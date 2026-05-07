defmodule Onchain.EVM do
  @moduledoc """
  Local EVM simulation powered by revm via Rustler NIF.

  Simulates contract execution locally by forking mainnet state from any RPC
  endpoint. Zero gas cost, zero latency compared to on-chain execution.

  ## Core Use Cases

  - Run hundreds of "what if" scenarios (supply X, borrow Y, price drops Z%)
  - Test liquidation thresholds without on-chain risk
  - Estimate gas usage for transactions before sending
  - Validate contract interactions with state overrides

  ## Error Format

  | Source | Error Shape |
  |--------|-------------|
  | EVM execution reverted | `{:error, {:evm_revert, revert_data_hex}}` |
  | EVM execution error | `{:error, {:evm_error, reason}}` |
  | Fork/RPC connection error | `{:error, {:fork_error, reason}}` |
  | RPC request timeout | `{:error, {:timeout, reason}}` |
  | Invalid address input | `{:error, {:invalid_address, input}}` |
  | Invalid hex data input | `{:error, {:invalid_data, input}}` |
  | Invalid RPC URL | `{:error, {:invalid_rpc_url, reason}}` |
  | Invalid value option | `{:error, {:invalid_value, input}}` |
  | Invalid gas_limit option | `{:error, {:invalid_gas_limit, input}}` |
  | Invalid timeout_ms option | `{:error, {:invalid_timeout_ms, input}}` |
  | Invalid state_overrides option | `{:error, {:invalid_state_overrides, input}}` |

  ## Timeouts

  Each NIF call configures a `reqwest::Client` with a per-RPC-request timeout.
  Default is 30 seconds (sufficient for archive-node reads). Pass `:timeout_ms`
  to override. Note this caps each individual RPC request, not the aggregate
  simulation time — a single `simulate_transaction` may issue many RPC reads
  for accounts and storage slots.

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `simulate_call/3` | Read-only call simulation → raw hex output |
  | `simulate_call!/3` | Same, raises on error |
  | `simulate_transaction/3` | Full tx simulation → success, gas, output, logs |
  | `simulate_transaction!/3` | Same, raises on error |
  | `simulate_batch/2` | Batch calls on shared fork → list of results |
  | `simulate_batch!/2` | Same, raises on error |
  """

  use Descripex, namespace: "/evm"
  use Rustler, otp_app: :onchain_evm, crate: "onchain_evm"

  import Onchain.BangHelper, only: [defbang: 1]
  import Onchain.RPC.Helpers, only: [ensure_hex_address: 1, ensure_hex_data: 1, normalize_block: 1]

  # --- Types ---

  @typedoc "EVM log entry from transaction simulation."
  @type log_entry :: %{
          address: String.t(),
          topics: [String.t()],
          data: String.t()
        }

  @typedoc "Transaction simulation result with gas usage and logs."
  @type tx_result :: %{
          success: boolean(),
          gas_used: non_neg_integer(),
          output: String.t(),
          logs: [log_entry()]
        }

  @typedoc """
  State overrides to apply before simulation.

  Keys are 0x-prefixed address strings. Values are maps with **string keys**:
  `"balance"` (hex string), `"nonce"` (string of integer), `"code"` (hex string),
  `"storage"` (JSON string of slot→value map).

  All keys and values must be strings — the NIF decodes them as `HashMap<String, String>`.

      %{
        "0xAddress..." => %{
          "balance" => "0xDE0B6B3A7640000",
          "nonce" => "5",
          "code" => "0x6080...",
          "storage" => ~s({"0x0": "0x1"})
        }
      }
  """
  @type state_overrides :: %{
          optional(String.t()) => %{
            optional(String.t()) => String.t()
          }
        }

  @typedoc "Options for EVM simulation functions."
  @type sim_opts :: [
          rpc_url: String.t(),
          block: non_neg_integer() | String.t(),
          from: String.t() | binary(),
          value: String.t(),
          gas_limit: non_neg_integer(),
          timeout_ms: pos_integer(),
          state_overrides: state_overrides()
        ]

  # --- Error Types ---

  @typedoc "RPC URL validation sub-reasons."
  @type rpc_url_reason ::
          :missing
          | :empty
          | {:not_a_string, term()}
          | {:invalid_scheme, String.t()}
          | {:missing_host, String.t()}

  @typedoc "Validation errors from Elixir-side input checks."
  @type validation_error ::
          {:invalid_rpc_url, rpc_url_reason()}
          | {:invalid_address, term()}
          | {:invalid_data, term()}
          | {:invalid_block, term()}
          | {:invalid_value, term()}
          | {:invalid_gas_limit, term()}
          | {:invalid_timeout_ms, term()}
          | {:invalid_state_overrides, term()}

  @typedoc "Errors from the Rust NIF during EVM execution."
  @type nif_error ::
          {:evm_revert, String.t()}
          | {:evm_error, String.t()}
          | {:fork_error, String.t()}
          | {:timeout, String.t()}

  @typedoc "All possible errors from EVM simulation functions."
  @type evm_error :: validation_error() | nif_error()

  # --- simulate_call ---

  api(
    :simulate_call,
    "Simulate a read-only contract call locally using a forked EVM state.",
    params: [
      address: [
        kind: :value,
        description: "Contract address as 0x hex string or 20-byte binary"
      ],
      data: [
        kind: :value,
        description: "0x-prefixed hex-encoded calldata (from ABI.encode_call)"
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :rpc_url (required), :block, :from, :value, :gas_limit, :timeout_ms, :state_overrides"
      ]
    ],
    returns: %{
      type: "{:ok, hex_string} | {:error, evm_error()}",
      description: "Raw 0x-prefixed hex output, compatible with ABI.decode_response/2"
    }
  )

  @spec simulate_call(String.t() | binary(), String.t(), sim_opts()) ::
          {:ok, String.t()} | {:error, evm_error()}
  def simulate_call(address, data, opts \\ []) do
    with {:ok, params} <- build_call_params(address, data, opts) do
      nif_simulate_call(params)
    end
  end

  # --- simulate_call! ---

  api(:simulate_call!, "Simulate a read-only contract call. Raises on error.",
    params: [
      address: [kind: :value, description: "Contract address"],
      data: [kind: :value, description: "0x-prefixed hex-encoded calldata"],
      opts: [kind: :value, default: [], description: "Simulation options"]
    ],
    returns: %{type: :string, description: "Raw 0x-prefixed hex output"}
  )

  @spec simulate_call!(String.t() | binary(), String.t(), sim_opts()) :: String.t()
  defbang(simulate_call!(address, data, opts \\ []))

  # --- simulate_transaction ---

  api(
    :simulate_transaction,
    "Simulate a full transaction locally, returning gas usage, output, and logs.",
    params: [
      address: [
        kind: :value,
        description: "Contract address as 0x hex string or 20-byte binary"
      ],
      data: [
        kind: :value,
        description: "0x-prefixed hex-encoded calldata"
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :rpc_url (required), :block, :from, :value, :gas_limit, :timeout_ms, :state_overrides"
      ]
    ],
    returns: %{
      type: "{:ok, tx_result()} | {:error, evm_error()}",
      description: "Transaction result with :success, :gas_used, :output, :logs"
    }
  )

  @spec simulate_transaction(String.t() | binary(), String.t(), sim_opts()) ::
          {:ok, tx_result()} | {:error, evm_error()}
  def simulate_transaction(address, data, opts \\ []) do
    with {:ok, params} <- build_call_params(address, data, opts) do
      nif_simulate_transaction(params)
    end
  end

  # --- simulate_transaction! ---

  api(:simulate_transaction!, "Simulate a full transaction. Raises on error.",
    params: [
      address: [kind: :value, description: "Contract address"],
      data: [kind: :value, description: "0x-prefixed hex-encoded calldata"],
      opts: [kind: :value, default: [], description: "Simulation options"]
    ],
    returns: %{type: "tx_result()", description: "Transaction result map"}
  )

  @spec simulate_transaction!(String.t() | binary(), String.t(), sim_opts()) :: tx_result()
  defbang(simulate_transaction!(address, data, opts \\ []))

  # --- simulate_batch ---

  api(
    :simulate_batch,
    "Simulate multiple calls on a single forked EVM state.",
    params: [
      calls: [
        kind: :value,
        description: "List of {address, data} tuples — each address as 0x hex, data as 0x hex calldata"
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :rpc_url (required), :block, :from, :gas_limit, :timeout_ms, :state_overrides"
      ]
    ],
    returns: %{
      type: "{:ok, [tx_result()]} | {:error, evm_error()}",
      description: "List of transaction results, one per call"
    }
  )

  @spec simulate_batch([{String.t() | binary(), String.t()}], sim_opts()) ::
          {:ok, [tx_result()]} | {:error, evm_error()}
  def simulate_batch(calls, opts \\ []) do
    with {:ok, params} <- build_batch_params(calls, opts) do
      nif_simulate_batch(params)
    end
  end

  # --- simulate_batch! ---

  api(:simulate_batch!, "Simulate multiple calls on a shared fork. Raises on error.",
    params: [
      calls: [kind: :value, description: "List of {address, data} tuples"],
      opts: [kind: :value, default: [], description: "Simulation options"]
    ],
    returns: %{type: "[tx_result()]", description: "List of transaction results"}
  )

  @spec simulate_batch!([{String.t() | binary(), String.t()}], sim_opts()) :: [tx_result()]
  defbang(simulate_batch!(calls, opts \\ []))

  # --- NIF stubs (public for Rustler, prefixed to avoid clash with API functions) ---

  @doc false
  def nif_simulate_call(_params), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def nif_simulate_transaction(_params), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def nif_simulate_batch(_params), do: :erlang.nif_error(:nif_not_loaded)

  # --- Input validation & param building ---

  @doc false
  # Validates address and data, then builds the params map for NIF calls.
  @spec build_call_params(String.t() | binary(), String.t(), sim_opts()) ::
          {:ok, map()} | {:error, validation_error()}
  defp build_call_params(address, data, opts) do
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
  @spec build_batch_params([{String.t() | binary(), String.t()}], sim_opts()) ::
          {:ok, map()} | {:error, validation_error()}
  defp build_batch_params(calls, opts) do
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
  @spec validate_calls([{String.t() | binary(), String.t()}]) ::
          {:ok, [{String.t(), String.t()}]} | {:error, {:invalid_address, term()} | {:invalid_data, term()}}
  defp validate_calls(calls) do
    calls
    |> Enum.reduce_while({:ok, []}, fn {addr, data}, {:ok, acc} ->
      with {:ok, hex_addr} <- ensure_hex_address(addr),
           {:ok, hex_data} <- ensure_hex_data(data) do
        {:cont, {:ok, [{hex_addr, hex_data} | acc]}}
      else
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, validated} -> {:ok, Enum.reverse(validated)}
      error -> error
    end
  end

  @doc false
  # Extracts, requires, and validates the :rpc_url option.
  # Rejects missing, empty, whitespace-only, and non-HTTP(S) URLs.
  @spec require_rpc_url(sim_opts()) :: {:ok, String.t()} | {:error, {:invalid_rpc_url, rpc_url_reason()}}
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

      {:ok, %URI{host: host}} when is_nil(host) or host == "" ->
        {:error, {:invalid_rpc_url, {:missing_host, trimmed}}}

      {:ok, %URI{}} ->
        {:ok, trimmed}

      # TODO: URI.new/1 returns {:error, part} only for `<`/`>` characters.
      # We fold that into :invalid_scheme; consider a dedicated :malformed_uri tag.
      {:error, _part} ->
        {:error, {:invalid_rpc_url, {:invalid_scheme, trimmed}}}
    end
  end

  @block_tags ~w(latest finalized pending earliest safe)

  @doc false
  # Validates block input and adds either "block_number" (u64) or "block_tag" (string) to params.
  # The NIF handles both via resolve_block_id — tag strings are resolved natively by Alloy.
  @spec maybe_put_block(map(), sim_opts()) :: {:ok, map()} | {:error, {:invalid_block, term()}}
  defp maybe_put_block(params, opts) do
    case Keyword.get(opts, :block) do
      nil ->
        {:ok, params}

      tag when tag in @block_tags ->
        {:ok, Map.put(params, "block_tag", tag)}

      n when is_integer(n) and n >= 0 ->
        {:ok, Map.put(params, "block_number", n)}

      "0x" <> _ = hex ->
        parse_hex_block(params, hex)

      other ->
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
          {n, ""} -> {:ok, Map.put(params, "block_number", n)}
          _ -> {:error, {:invalid_block, hex}}
        end

      {:error, _} = err ->
        err
    end
  end

  @doc false
  # Validates and adds the :from address to params. Returns error for invalid addresses.
  @spec maybe_put_from(map(), sim_opts()) :: {:ok, map()} | {:error, {:invalid_address, term()}}
  defp maybe_put_from(params, opts) do
    case Keyword.get(opts, :from) do
      nil ->
        {:ok, params}

      from ->
        case ensure_hex_address(from) do
          {:ok, hex} -> {:ok, Map.put(params, "from", hex)}
          {:error, _} -> {:error, {:invalid_address, from}}
        end
    end
  end

  @doc false
  # Validates and adds :value (must be a hex string) to params.
  @spec maybe_put_value(map(), sim_opts()) :: {:ok, map()} | {:error, {:invalid_value, term()}}
  defp maybe_put_value(params, opts) do
    case Keyword.get(opts, :value) do
      nil -> {:ok, params}
      val when is_binary(val) -> {:ok, Map.put(params, "value", val)}
      other -> {:error, {:invalid_value, other}}
    end
  end

  @doc false
  # Validates and adds :gas_limit (must be a positive integer) to params.
  @spec maybe_put_gas_limit(map(), sim_opts()) :: {:ok, map()} | {:error, {:invalid_gas_limit, term()}}
  defp maybe_put_gas_limit(params, opts) do
    case Keyword.get(opts, :gas_limit) do
      nil -> {:ok, params}
      gl when is_integer(gl) and gl > 0 -> {:ok, Map.put(params, "gas_limit", gl)}
      other -> {:error, {:invalid_gas_limit, other}}
    end
  end

  @doc false
  # Validates and adds :state_overrides (must be a map) to params.
  @spec maybe_put_state_overrides(map(), sim_opts()) :: {:ok, map()} | {:error, {:invalid_state_overrides, term()}}
  defp maybe_put_state_overrides(params, opts) do
    case Keyword.get(opts, :state_overrides) do
      nil -> {:ok, params}
      overrides when is_map(overrides) -> {:ok, Map.put(params, "state_overrides", overrides)}
      other -> {:error, {:invalid_state_overrides, other}}
    end
  end

  # u64::MAX — the NIF decodes timeout_ms as u64. Anything above this overflows
  # the decoder and surfaces as a bare {:evm_error, "invalid param type: timeout_ms"}
  # instead of the documented {:invalid_timeout_ms, _} contract.
  @timeout_ms_max 0xFFFF_FFFF_FFFF_FFFF

  @doc false
  # Validates and adds :timeout_ms (must be a positive integer ≤ u64::MAX) to params.
  # Caps each individual RPC request, not aggregate simulation time. NIF default is 30s.
  @spec maybe_put_timeout_ms(map(), sim_opts()) :: {:ok, map()} | {:error, {:invalid_timeout_ms, term()}}
  defp maybe_put_timeout_ms(params, opts) do
    case Keyword.get(opts, :timeout_ms) do
      nil -> {:ok, params}
      ms when is_integer(ms) and ms > 0 and ms <= @timeout_ms_max -> {:ok, Map.put(params, "timeout_ms", ms)}
      other -> {:error, {:invalid_timeout_ms, other}}
    end
  end
end
