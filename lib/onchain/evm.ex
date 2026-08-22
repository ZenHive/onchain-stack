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
  | Invalid batch calls | `{:error, {:invalid_calls, input}}` |
  | Invalid RPC URL | `{:error, {:invalid_rpc_url, reason}}` |
  | Invalid block option | `{:error, {:invalid_block, input}}` |
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

  ## Batch Partial Failure

  `simulate_batch/2` is resilient by design: one reverting call does not abort the
  batch. The outer `{:ok, results}` therefore signals only that the fork itself was
  built and every call was executed — **not** that every call succeeded. A reverted
  call appears in the list as `%{success: false, output: "0x", ...}`, in position,
  and later calls still observe the state it left behind.

  Check `:success` per element; never treat `{:ok, _}` as "all calls succeeded":

      {:ok, results} = Onchain.EVM.simulate_batch(calls, rpc_url: url)
      Enum.filter(results, & &1.success == false)

  Only `simulate_call/3` and `simulate_transaction/3` surface a revert as
  `{:error, {:evm_revert, data}}`; the batch path deliberately does not.
  """

  use Descripex, namespace: "/evm"
  use Rustler, otp_app: :onchain_evm, crate: "onchain_evm"

  import Onchain.BangHelper, only: [defbang: 1]

  alias Onchain.EVM.Params

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
          | {:invalid_calls, term()}
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
    with {:ok, params} <- Params.build_call_params(address, data, opts) do
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
    with {:ok, params} <- Params.build_call_params(address, data, opts) do
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
    with {:ok, params} <- Params.build_batch_params(calls, opts) do
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
  @spec nif_simulate_call(map()) :: {:ok, String.t()} | {:error, evm_error()}
  def nif_simulate_call(_params), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  @spec nif_simulate_transaction(map()) :: {:ok, tx_result()} | {:error, evm_error()}
  def nif_simulate_transaction(_params), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  @spec nif_simulate_batch(map()) :: {:ok, [tx_result()]} | {:error, evm_error()}
  def nif_simulate_batch(_params), do: :erlang.nif_error(:nif_not_loaded)
end
