defmodule Onchain.EVM.Params do
  @moduledoc false
  # Pure-Elixir input validation and NIF-param assembly for `Onchain.EVM`.
  #
  # Lives in its own module (no `use Rustler`) so test coverage can instrument
  # it. The sibling `Onchain.EVM` carries the revm NIF, whose `on_load` is
  # incompatible with cover's beam recompilation; keeping the validation logic
  # out of that module lets the coverage gate measure it — and makes the
  # param-building directly unit-testable without a live RPC.

  import Onchain.RPC.Helpers, only: [ensure_hex_address: 1, ensure_hex_data: 1, normalize_block: 1]

  alias Onchain.EVM

  @block_tags ~w(latest finalized pending earliest safe)

  # u64::MAX — the NIF decodes timeout_ms, block_number, and gas_limit as u64.
  # Anything above this overflows the decoder and surfaces as a bare
  # {:evm_error, "invalid param type: …"} instead of the documented tagged contract.
  @u64_max 0xFFFF_FFFF_FFFF_FFFF

  # U256::MAX — the NIF parses :value as alloy_primitives::U256.
  @u256_max Integer.pow(2, 256) - 1

  @doc false
  # Validates address and data, then builds the params map for NIF calls.
  @spec build_call_params(String.t() | binary(), String.t(), EVM.sim_opts()) ::
          {:ok, map()} | {:error, EVM.validation_error()}
  def build_call_params(address, data, opts) do
    with {:ok, hex_addr} <- ensure_hex_address(address),
         {:ok, hex_data} <- ensure_hex_data(data),
         {:ok, rpc_url} <- require_rpc_url(opts),
         {:ok, base} <- maybe_put_block(%{"rpc_url" => rpc_url, "to" => hex_addr, "data" => hex_data}, opts),
         {:ok, params} <- maybe_put_from(base, opts),
         {:ok, params} <- maybe_put_value(params, opts),
         {:ok, params} <- maybe_put_gas_limit(params, opts),
         {:ok, params} <- maybe_put_timeout_ms(params, opts) do
      maybe_put_state_overrides(params, opts)
    end
  end

  @doc false
  # Validates batch calls and builds the params map for NIF batch simulation.
  @spec build_batch_params([{String.t() | binary(), String.t()}], EVM.sim_opts()) ::
          {:ok, map()} | {:error, EVM.validation_error()}
  def build_batch_params(calls, opts) do
    with {:ok, rpc_url} <- require_rpc_url(opts),
         {:ok, validated_calls} <- validate_calls(calls),
         {:ok, base} <- maybe_put_block(%{"rpc_url" => rpc_url, "calls" => validated_calls}, opts),
         {:ok, params} <- maybe_put_from(base, opts),
         {:ok, params} <- maybe_put_gas_limit(params, opts),
         {:ok, params} <- maybe_put_timeout_ms(params, opts) do
      maybe_put_state_overrides(params, opts)
    end
  end

  @doc false
  # Validates each {address, data} tuple in a batch call list.
  @spec validate_calls(term()) ::
          {:ok, [{String.t(), String.t()}]}
          | {:error, {:invalid_address, term()} | {:invalid_data, term()} | {:invalid_calls, term()}}
  defp validate_calls(calls) when is_list(calls) do
    calls
    |> Enum.reduce_while({:ok, []}, &validate_call_entry/2)
    |> case do
      {:ok, validated} -> {:ok, Enum.reverse(validated)}
      error -> error
    end
  end

  defp validate_calls(other), do: {:error, {:invalid_calls, other}}

  @spec validate_call_entry(term(), {:ok, [{String.t(), String.t()}]}) ::
          {:cont, {:ok, [{String.t(), String.t()}]}}
          | {:halt, {:error, {:invalid_address, term()} | {:invalid_data, term()} | {:invalid_calls, term()}}}
  defp validate_call_entry({addr, data}, {:ok, acc}) do
    with {:ok, hex_addr} <- ensure_hex_address(addr),
         {:ok, hex_data} <- ensure_hex_data(data) do
      {:cont, {:ok, [{hex_addr, hex_data} | acc]}}
    else
      error -> {:halt, error}
    end
  end

  defp validate_call_entry(other, _acc), do: {:halt, {:error, {:invalid_calls, other}}}

  @doc false
  # Extracts, requires, and validates the :rpc_url option.
  # Rejects missing, empty, whitespace-only, and non-HTTP(S) URLs.
  @spec require_rpc_url(EVM.sim_opts()) ::
          {:ok, String.t()} | {:error, {:invalid_rpc_url, EVM.rpc_url_reason()}}
  defp require_rpc_url(opts) do
    case Keyword.get(opts, :rpc_url) do
      nil ->
        {:error, {:invalid_rpc_url, :missing}}

      url when is_binary(url) ->
        validate_rpc_url(url)

      other ->
        {:error, {:invalid_rpc_url, {:not_a_string, other}}}
    end
  end

  @doc false
  @spec validate_rpc_url(String.t()) ::
          {:ok, String.t()}
          | {:error, {:invalid_rpc_url, :empty | {:invalid_scheme, String.t()} | {:missing_host, String.t()}}}
  defp validate_rpc_url(url) do
    trimmed = String.trim(url)

    if trimmed == "" do
      {:error, {:invalid_rpc_url, :empty}}
    else
      validate_parsed_rpc_url(trimmed)
    end
  end

  @spec validate_parsed_rpc_url(String.t()) ::
          {:ok, String.t()}
          | {:error, {:invalid_rpc_url, {:invalid_scheme, String.t()} | {:missing_host, String.t()}}}
  defp validate_parsed_rpc_url(trimmed) do
    case URI.new(trimmed) do
      {:ok, %URI{scheme: scheme}} when scheme not in ["http", "https"] ->
        {:error, {:invalid_rpc_url, {:invalid_scheme, trimmed}}}

      {:ok, %URI{host: nil}} ->
        {:error, {:invalid_rpc_url, {:missing_host, trimmed}}}

      {:ok, %URI{host: ""}} ->
        {:error, {:invalid_rpc_url, {:missing_host, trimmed}}}

      {:ok, %URI{}} ->
        {:ok, trimmed}

      # URI.new/1 returns {:error, part} only for `<`/`>` characters. We
      # intentionally fold that into :invalid_scheme (pinned by the "malformed
      # URI characters" test) rather than exposing a separate :malformed_uri tag.
      {:error, _part} ->
        {:error, {:invalid_rpc_url, {:invalid_scheme, trimmed}}}
    end
  end

  @doc false
  # Validates block input and adds either "block_number" (u64) or "block_tag" (string) to params.
  # The NIF handles both via resolve_block_id — tag strings are resolved natively by Alloy.
  @spec maybe_put_block(map(), EVM.sim_opts()) :: {:ok, map()} | {:error, {:invalid_block, term()}}
  defp maybe_put_block(params, opts) do
    case Keyword.fetch(opts, :block) do
      :error ->
        {:ok, params}

      {:ok, tag} when tag in @block_tags ->
        {:ok, Map.put(params, "block_tag", tag)}

      {:ok, n} when is_integer(n) and n >= 0 and n <= @u64_max ->
        {:ok, Map.put(params, "block_number", n)}

      {:ok, "0x" <> _ = hex} ->
        parse_hex_block(params, hex)

      {:ok, other} ->
        {:error, {:invalid_block, other}}
    end
  end

  @doc false
  # Validates hex format and parses to integer for the NIF's u64 block_number param.
  @spec parse_hex_block(map(), String.t()) :: {:ok, map()} | {:error, {:invalid_block, term()}}
  defp parse_hex_block(params, "0x" <> rest = hex) do
    case normalize_block(hex) do
      {:ok, _} ->
        case Integer.parse(rest, 16) do
          {n, ""} when n <= @u64_max -> {:ok, Map.put(params, "block_number", n)}
          _ -> {:error, {:invalid_block, hex}}
        end

      {:error, _} = err ->
        err
    end
  end

  @doc false
  # Validates and adds the :from address to params. Returns error for invalid addresses.
  @spec maybe_put_from(map(), EVM.sim_opts()) :: {:ok, map()} | {:error, {:invalid_address, term()}}
  defp maybe_put_from(params, opts) do
    case Keyword.fetch(opts, :from) do
      :error ->
        {:ok, params}

      {:ok, from} ->
        case ensure_hex_address(from) do
          {:ok, hex} -> {:ok, Map.put(params, "from", hex)}
          {:error, _} -> {:error, {:invalid_address, from}}
        end
    end
  end

  @doc false
  # Validates and adds :value (must be a 0x-prefixed U256 hex quantity) to params.
  @spec maybe_put_value(map(), EVM.sim_opts()) :: {:ok, map()} | {:error, {:invalid_value, term()}}
  defp maybe_put_value(params, opts) do
    case Keyword.fetch(opts, :value) do
      :error ->
        {:ok, params}

      {:ok, val} ->
        case parse_u256_hex(val) do
          {:ok, hex} -> {:ok, Map.put(params, "value", hex)}
          :error -> {:error, {:invalid_value, val}}
        end
    end
  end

  @spec parse_u256_hex(term()) :: {:ok, String.t()} | :error
  defp parse_u256_hex("0x" <> rest = hex) do
    if Onchain.Hex.valid?(hex) do
      case Integer.parse(rest, 16) do
        {n, ""} when n <= @u256_max -> {:ok, hex}
        _ -> :error
      end
    else
      :error
    end
  end

  defp parse_u256_hex(_), do: :error

  @doc false
  # Validates and adds :gas_limit (must be a positive integer) to params.
  @spec maybe_put_gas_limit(map(), EVM.sim_opts()) :: {:ok, map()} | {:error, {:invalid_gas_limit, term()}}
  defp maybe_put_gas_limit(params, opts) do
    case Keyword.fetch(opts, :gas_limit) do
      :error -> {:ok, params}
      {:ok, gl} when is_integer(gl) and gl > 0 and gl <= @u64_max -> {:ok, Map.put(params, "gas_limit", gl)}
      {:ok, other} -> {:error, {:invalid_gas_limit, other}}
    end
  end

  @doc false
  # Validates and adds :state_overrides (nested string maps, address keys) to params.
  @spec maybe_put_state_overrides(map(), EVM.sim_opts()) ::
          {:ok, map()} | {:error, {:invalid_state_overrides, term()}}
  defp maybe_put_state_overrides(params, opts) do
    case Keyword.fetch(opts, :state_overrides) do
      :error -> {:ok, params}
      {:ok, overrides} -> put_state_overrides(params, overrides)
    end
  end

  @spec put_state_overrides(map(), term()) :: {:ok, map()} | {:error, {:invalid_state_overrides, term()}}
  defp put_state_overrides(params, overrides) when is_map(overrides) do
    if valid_state_overrides?(overrides) do
      {:ok, Map.put(params, "state_overrides", overrides)}
    else
      {:error, {:invalid_state_overrides, overrides}}
    end
  end

  defp put_state_overrides(_params, other), do: {:error, {:invalid_state_overrides, other}}

  @spec valid_state_overrides?(map()) :: boolean()
  defp valid_state_overrides?(overrides) do
    Enum.all?(overrides, &valid_override_entry?/1)
  end

  @spec valid_override_entry?(term()) :: boolean()
  defp valid_override_entry?({"0x" <> _ = addr, fields}) when is_map(fields) do
    match?({:ok, _}, ensure_hex_address(addr)) and valid_override_fields?(fields)
  end

  defp valid_override_entry?(_), do: false

  @spec valid_override_fields?(map()) :: boolean()
  defp valid_override_fields?(fields) do
    Enum.all?(fields, fn {key, value} ->
      is_binary(key) and String.valid?(key) and is_binary(value) and String.valid?(value)
    end)
  end

  @doc false
  # Validates and adds :timeout_ms (must be a positive integer ≤ u64::MAX) to params.
  # Caps each individual RPC request, not aggregate simulation time. NIF default is 30s.
  @spec maybe_put_timeout_ms(map(), EVM.sim_opts()) :: {:ok, map()} | {:error, {:invalid_timeout_ms, term()}}
  defp maybe_put_timeout_ms(params, opts) do
    case Keyword.fetch(opts, :timeout_ms) do
      :error -> {:ok, params}
      {:ok, ms} when is_integer(ms) and ms > 0 and ms <= @u64_max -> {:ok, Map.put(params, "timeout_ms", ms)}
      {:ok, other} -> {:error, {:invalid_timeout_ms, other}}
    end
  end
end
