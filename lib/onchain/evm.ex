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
  | Invalid address input | `{:error, {:invalid_address, input}}` |
  | Invalid hex data input | `{:error, {:invalid_data, input}}` |

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

  import Onchain.RPC.Helpers, only: [ensure_hex_address: 1, ensure_hex_data: 1]

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
          # TODO: Support string block tags ("latest", "finalized") — requires RPC resolution before NIF call
          block: non_neg_integer(),
          from: String.t() | binary(),
          value: String.t(),
          gas_limit: non_neg_integer(),
          state_overrides: state_overrides()
        ]

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
        description: "Options: :rpc_url (required), :block, :from, :value, :gas_limit, :state_overrides"
      ]
    ],
    returns: %{
      type: "{:ok, hex_string} | {:error, term}",
      description: "Raw 0x-prefixed hex output, compatible with ABI.decode_response/2"
    }
  )

  @spec simulate_call(String.t() | binary(), String.t(), sim_opts()) ::
          {:ok, String.t()} | {:error, term()}
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
  def simulate_call!(address, data, opts \\ []) do
    case simulate_call(address, data, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "simulate_call failed: #{inspect(reason)}"
    end
  end

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
        description: "Options: :rpc_url (required), :block, :from, :value, :gas_limit, :state_overrides"
      ]
    ],
    returns: %{
      type: "{:ok, tx_result()} | {:error, term}",
      description: "Transaction result with :success, :gas_used, :output, :logs"
    }
  )

  @spec simulate_transaction(String.t() | binary(), String.t(), sim_opts()) ::
          {:ok, tx_result()} | {:error, term()}
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
  def simulate_transaction!(address, data, opts \\ []) do
    case simulate_transaction(address, data, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "simulate_transaction failed: #{inspect(reason)}"
    end
  end

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
        description: "Options: :rpc_url (required), :block, :from, :gas_limit, :state_overrides"
      ]
    ],
    returns: %{
      type: "{:ok, [tx_result()]} | {:error, term}",
      description: "List of transaction results, one per call"
    }
  )

  @spec simulate_batch([{String.t() | binary(), String.t()}], sim_opts()) ::
          {:ok, [tx_result()]} | {:error, term()}
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
  def simulate_batch!(calls, opts \\ []) do
    case simulate_batch(calls, opts) do
      {:ok, results} -> results
      {:error, reason} -> raise "simulate_batch failed: #{inspect(reason)}"
    end
  end

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
  defp build_call_params(address, data, opts) do
    with {:ok, hex_addr} <- ensure_hex_address(address),
         {:ok, hex_data} <- ensure_hex_data(data),
         {:ok, rpc_url} <- require_rpc_url(opts),
         {:ok, base} <- maybe_put_block(%{"rpc_url" => rpc_url, "to" => hex_addr, "data" => hex_data}, opts),
         {:ok, params} <- maybe_put_from(base, opts) do
      params =
        params
        |> maybe_put_value(opts)
        |> maybe_put_gas_limit(opts)
        |> maybe_put_state_overrides(opts)

      {:ok, params}
    end
  end

  @doc false
  # Validates batch calls and builds the params map for NIF batch simulation.
  defp build_batch_params(calls, opts) do
    with {:ok, rpc_url} <- require_rpc_url(opts),
         {:ok, validated_calls} <- validate_calls(calls),
         {:ok, base} <- maybe_put_block(%{"rpc_url" => rpc_url, "calls" => validated_calls}, opts),
         {:ok, params} <- maybe_put_from(base, opts) do
      params =
        params
        |> maybe_put_gas_limit(opts)
        |> maybe_put_state_overrides(opts)

      {:ok, params}
    end
  end

  @doc false
  # Validates each {address, data} tuple in a batch call list.
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
  # Extracts and requires the :rpc_url option.
  defp require_rpc_url(opts) do
    case Keyword.get(opts, :rpc_url) do
      nil -> {:error, {:evm_error, "rpc_url option is required"}}
      url when is_binary(url) -> {:ok, url}
      other -> {:error, {:evm_error, "rpc_url must be a string, got: #{inspect(other)}"}}
    end
  end

  @doc false
  defp maybe_put_block(params, opts) do
    case Keyword.get(opts, :block) do
      nil -> {:ok, params}
      n when is_integer(n) and n >= 0 -> {:ok, Map.put(params, "block_number", n)}
      other -> {:error, {:invalid_block, other}}
    end
  end

  @doc false
  # Validates and adds the :from address to params. Returns error for invalid addresses.
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
  defp maybe_put_value(params, opts) do
    case Keyword.get(opts, :value) do
      nil -> params
      val when is_binary(val) -> Map.put(params, "value", val)
      _other -> params
    end
  end

  @doc false
  defp maybe_put_gas_limit(params, opts) do
    case Keyword.get(opts, :gas_limit) do
      nil -> params
      gl when is_integer(gl) and gl > 0 -> Map.put(params, "gas_limit", gl)
      _other -> params
    end
  end

  @doc false
  defp maybe_put_state_overrides(params, opts) do
    case Keyword.get(opts, :state_overrides) do
      nil -> params
      overrides when is_map(overrides) -> Map.put(params, "state_overrides", overrides)
      _other -> params
    end
  end
end
