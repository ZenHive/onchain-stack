defmodule Cartouche.RPC do
  @moduledoc """
  Shared JSON-RPC transport and typed Ethereum client.

  Single calls and batches use `config :cartouche, :ethereum_node` for the URL,
  `config :cartouche, Cartouche.RPC, [...]` for transport defaults, and
  `config :cartouche, :req_options, [...]` for global Req options. Per-call
  `:rpc_url` / `:ethereum_node` and `:req_options` override these defaults.
  A missing URL returns `{:error, {:missing_option, :ethereum_node}}`.
  The former `:onchain` batch transport configuration is no longer used.

  Both paths emit `[:onchain, :rpc, :request]` telemetry spans. Refusals now
  uniformly return `:method_not_found`, `:namespace_unavailable`, or `:unavailable`
  tags; other single-call error shapes remain unchanged. See `Onchain.RPC`'s
  node-capability refusal documentation for the live Alchemy provenance and
  message-sensitive meaning of -32600 and -32001.

  Local signing through `Cartouche.Signer` is the normal route for submitting
  transactions (`eth_sendRawTransaction`). The node-custody methods
  (`accounts/1`, `coinbase/1`, `fill_transaction/2`, `sign/3`,
  `sign_transaction/2`, `send_transaction/2`) exist for nodes that hold keys.
  The distinction is not key custody as such (`Cartouche.Signer.CloudKMS`
  already signs with a key cartouche does not hold) but which side constructs
  the transaction: those methods move envelope construction, nonce and fee
  policy, EIP-155 `v` derivation, and low-s normalization into the node.

  `sign/3` (`eth_sign`) takes a message, not a pre-computed digest: the node
  returns an EIP-191 signature over the data it is handed (`execution-apis`,
  `src/eth/sign.yaml`). The method is historically dangerous because early
  implementations signed the bytes verbatim, which let a caller pass a
  transaction hash and get it signed; most nodes ship it disabled today.
  """
  use Descripex, namespace: "/ethereum/rpc"
  use Cartouche.Hex

  import Cartouche.HTTP, only: [normalize_response: 1]
  import Cartouche.RPC.DSL, only: [defrpc: 3]
  import Cartouche.Wei, only: [to_wei: 1]

  alias Cartouche.Filter.Log, as: FilterLog
  alias Cartouche.RPC.Proof
  alias Cartouche.Signer.Default
  alias Cartouche.Transaction
  alias Cartouche.Transaction.Call
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2
  alias Cartouche.Transaction.V_2930
  alias Onchain.RPC.Helpers

  require Logger

  @rpc_request_event [:onchain, :rpc, :request]
  @batch_method "batch"
  @default_retry_max_retries 2
  @default_retry_backoff_ms 100
  @no_retry_max_retries 0
  # JSON-RPC 2.0 / observed hosted-provider refusal codes. Message patterns for
  # -32600 and -32001 are pinned from live Alchemy mainnet responses (2026-08-25).
  @jsonrpc_invalid_request -32_600
  @jsonrpc_method_not_found -32_601
  @jsonrpc_unable_to_complete -32_001

  # `r`/`s` decide whether a fill result is already signed; the full set is
  # shape-checked so a garbled value cannot pass as an unset field.
  @filled_signature_words ~w(r s)
  @filled_signature_fields ~w(v yParity r s)
  @hex_digits ~r/\A[0-9a-fA-F]+\z/

  # Canonical eth_getLogs filter keys. Unknown keys are rejected rather than
  # dropped. JSON-RPC camelCase string keys are normalized to these atoms;
  # when both forms are present, the atom wins. `:block_hash` is mutually
  # exclusive with `:from_block` / `:to_block` (execution-apis filter object).
  @allowed_log_filter_keys [:address, :topics, :from_block, :to_block, :block_hash]
  @camel_case_filter_aliases %{
    "fromBlock" => :from_block,
    "toBlock" => :to_block,
    "address" => :address,
    "topics" => :topics,
    "blockHash" => :block_hash
  }
  @log_filter_block_tags Helpers.block_tags()

  defmodule Configuration do
    @moduledoc """
    Deserialized `eth_config` fork configuration report defined by EIP-7910.

    Fields are nilable because clients may omit configuration added by newer
    revisions of the method.
    """

    alias __MODULE__.BlobSchedule
    alias __MODULE__.Fork
    alias Cartouche.Hex

    defmodule BlobSchedule do
      @moduledoc """
      Blob fee schedule active for one fork configuration.
      """

      @type t :: %__MODULE__{
              base_fee_update_fraction: non_neg_integer() | nil,
              max: non_neg_integer() | nil,
              target: non_neg_integer() | nil
            }

      defstruct [:base_fee_update_fraction, :max, :target]
    end

    defmodule Fork do
      @moduledoc """
      Chain parameters active at one fork boundary.
      """

      alias Cartouche.RPC.Configuration.BlobSchedule

      @type named_addresses :: %{optional(String.t()) => <<_::160>>}

      @type t :: %__MODULE__{
              activation_time: non_neg_integer() | nil,
              blob_schedule: BlobSchedule.t() | nil,
              chain_id: non_neg_integer() | nil,
              fork_id: <<_::32>> | nil,
              precompiles: named_addresses() | nil,
              system_contracts: named_addresses() | nil
            }

      defstruct [:activation_time, :blob_schedule, :chain_id, :fork_id, :precompiles, :system_contracts]
    end

    @type t :: %__MODULE__{
            current: Fork.t() | nil,
            next: Fork.t() | nil,
            last: Fork.t() | nil
          }

    defstruct [:current, :next, :last]

    @doc """
    Decodes an `eth_config` result while ignoring unknown fields.
    """
    @spec deserialize(map()) :: t()
    def deserialize(%{} = params) do
      %__MODULE__{
        current: deserialize_fork(params["current"]),
        next: deserialize_fork(params["next"]),
        last: deserialize_fork(params["last"])
      }
    end

    @spec deserialize_fork(map() | nil) :: Fork.t() | nil
    defp deserialize_fork(nil), do: nil

    defp deserialize_fork(%{} = params) do
      %Fork{
        activation_time: params["activationTime"],
        blob_schedule: deserialize_blob_schedule(params["blobSchedule"]),
        chain_id: decode_quantity(params["chainId"]),
        fork_id: decode_data(params["forkId"]),
        precompiles: decode_named_addresses(params["precompiles"]),
        system_contracts: decode_named_addresses(params["systemContracts"])
      }
    end

    @spec deserialize_blob_schedule(map() | nil) :: BlobSchedule.t() | nil
    defp deserialize_blob_schedule(nil), do: nil

    defp deserialize_blob_schedule(%{} = params) do
      %BlobSchedule{
        base_fee_update_fraction: params["baseFeeUpdateFraction"],
        max: params["max"],
        target: params["target"]
      }
    end

    @spec decode_quantity(String.t() | nil) :: non_neg_integer() | nil
    defp decode_quantity(nil), do: nil
    defp decode_quantity(quantity), do: Hex.decode_hex_number!(quantity)

    @spec decode_data(String.t() | nil) :: binary() | nil
    defp decode_data(nil), do: nil
    defp decode_data(data), do: Hex.decode_hex!(data)

    @spec decode_named_addresses(map() | nil) :: Fork.named_addresses() | nil
    defp decode_named_addresses(nil), do: nil

    defp decode_named_addresses(addresses) when is_map(addresses) do
      Map.new(addresses, fn {name, address} -> {name, Hex.decode_address!(address)} end)
    end
  end

  defmodule Capabilities do
    @moduledoc """
    Deserialized `eth_capabilities` report used to determine which historical
    resources a node can serve.
    """

    alias __MODULE__.DeleteStrategy
    alias __MODULE__.Head
    alias __MODULE__.Resource
    alias Cartouche.Hex

    defmodule Head do
      @moduledoc """
      Block at the head of the node's advertised capability range.
      """

      @type t :: %__MODULE__{number: non_neg_integer() | nil, hash: <<_::256>> | nil}
      defstruct [:number, :hash]
    end

    defmodule DeleteStrategy do
      @moduledoc """
      Resource-retention strategy advertised by the node.
      """

      @type t :: %__MODULE__{type: String.t() | nil, retention_blocks: non_neg_integer() | nil}
      defstruct [:type, :retention_blocks]
    end

    defmodule Resource do
      @moduledoc """
      Availability and retention details for one node resource.
      """

      alias Cartouche.RPC.Capabilities.DeleteStrategy

      @type t :: %__MODULE__{
              disabled: boolean() | nil,
              oldest_block: non_neg_integer() | nil,
              delete_strategy: DeleteStrategy.t() | nil
            }

      defstruct [:disabled, :oldest_block, :delete_strategy]
    end

    @type t :: %__MODULE__{
            head: Head.t() | nil,
            state: Resource.t() | nil,
            tx: Resource.t() | nil,
            logs: Resource.t() | nil,
            receipts: Resource.t() | nil,
            blocks: Resource.t() | nil,
            stateproofs: Resource.t() | nil
          }

    defstruct [:head, :state, :tx, :logs, :receipts, :blocks, :stateproofs]

    @doc """
    Decodes an `eth_capabilities` result while ignoring unknown fields.
    """
    @spec deserialize(map()) :: t()
    def deserialize(%{} = params) do
      %__MODULE__{
        head: deserialize_head(params["head"]),
        state: deserialize_resource(params["state"]),
        tx: deserialize_resource(params["tx"]),
        logs: deserialize_resource(params["logs"]),
        receipts: deserialize_resource(params["receipts"]),
        blocks: deserialize_resource(params["blocks"]),
        stateproofs: deserialize_resource(params["stateproofs"])
      }
    end

    @spec deserialize_head(map() | nil) :: Head.t() | nil
    defp deserialize_head(nil), do: nil

    defp deserialize_head(%{} = params) do
      %Head{number: decode_quantity(params["number"]), hash: decode_word(params["hash"])}
    end

    @spec deserialize_resource(map() | nil) :: Resource.t() | nil
    defp deserialize_resource(nil), do: nil

    defp deserialize_resource(%{} = params) do
      %Resource{
        disabled: params["disabled"],
        oldest_block: decode_quantity(params["oldestBlock"]),
        delete_strategy: deserialize_delete_strategy(params["deleteStrategy"])
      }
    end

    @spec deserialize_delete_strategy(map() | nil) :: DeleteStrategy.t() | nil
    defp deserialize_delete_strategy(nil), do: nil

    defp deserialize_delete_strategy(%{} = params) do
      %DeleteStrategy{
        type: params["type"],
        retention_blocks: decode_quantity(params["retentionBlocks"])
      }
    end

    @spec decode_quantity(String.t() | nil) :: non_neg_integer() | nil
    defp decode_quantity(nil), do: nil
    defp decode_quantity(quantity), do: Hex.decode_hex_number!(quantity)

    @spec decode_word(String.t() | nil) :: <<_::256>> | nil
    defp decode_word(nil), do: nil
    defp decode_word(word), do: Hex.decode_word!(word)
  end

  defmodule SyncStatus do
    @moduledoc """
    Progress object from `eth_syncing`.

    `execution-apis` v1.0.0-beta.7 defines `SyncingStatus` as one union:
    the boolean `false` when the node is not syncing, or this object.
    `false` is not a `t:t/0`. The three fields are the spec's quantity
    properties (`startingBlock`, `currentBlock`, `highestBlock`), decoded
    to integers. Fields the schema does not name are ignored, so a client
    snap-sync object still yields this struct.
    """

    alias Cartouche.Hex

    @enforce_keys [:starting_block, :current_block, :highest_block]
    defstruct [:starting_block, :current_block, :highest_block]

    @type t :: %__MODULE__{
            starting_block: non_neg_integer(),
            current_block: non_neg_integer(),
            highest_block: non_neg_integer()
          }

    @doc """
    Decodes the sync-progress object from the `eth_syncing` spec example shape.
    """
    @spec deserialize(map()) :: t()
    def deserialize(%{"startingBlock" => starting, "currentBlock" => current, "highestBlock" => highest})
        when is_binary(starting) and is_binary(current) and is_binary(highest) do
      %__MODULE__{
        starting_block: Hex.decode_hex_number!(starting),
        current_block: Hex.decode_hex_number!(current),
        highest_block: Hex.decode_hex_number!(highest)
      }
    end
  end

  @default_timeout Application.compile_env(:cartouche, :timeout, 30_000)

  @default_gas_price nil
  @default_base_fee nil
  @default_base_fee_buffer 1.20
  @default_gas_buffer 1.50

  @typedoc "Structured JSON-RPC error envelope returned by an Ethereum node or by local response validation."
  @type rpc_error :: %{
          required(:code) => integer(),
          required(:message) => String.t(),
          optional(:revert) => binary(),
          optional(:error_abi) => String.t(),
          optional(:error_params) => [term()],
          optional(:trace) => term()
        }

  @typedoc "Error returned when JSON encoding rejects the outbound request body."
  @type invalid_params_error :: {:invalid_params, Exception.t()}

  @typedoc "All values that can appear inside an `{:error, reason}` tuple returned by `send_rpc/3`."
  @type send_rpc_error :: rpc_error() | invalid_params_error() | Req.Response.t() | String.t() | {atom(), term()}

  @typedoc "Decoded `eth_createAccessList` result, retaining an optional execution error."
  @type access_list_result :: %{
          required(:access_list) => V_2930.access_list(),
          required(:gas_used) => non_neg_integer(),
          optional(:error) => String.t()
        }

  @spec headers([{String.t(), String.t()}]) :: [{String.t(), String.t()}]
  defp headers(extra_headers) do
    [
      {"Accept", "application/json"},
      {"Content-Type", "application/json"}
    ] ++ extra_headers
  end

  @doc false
  @spec get_body(String.t(), [term()], integer()) :: %{String.t() => term()}
  def get_body(method, params, id) do
    %{
      "jsonrpc" => "2.0",
      "method" => method,
      "params" => params,
      "id" => id
    }
  end

  # See https://blog.soliditylang.org/2021/04/21/custom-errors/
  @spec decode_error(binary(), [String.t()] | nil) :: :not_found | {:ok, String.t(), [term()] | nil}
  defp decode_error(data, errors) when is_list(errors) do
    all_errors = ["Panic(uint256)" | errors]

    case ABI.decode_error(data, all_errors) do
      {:ok, %{error: error_name, args: params}} -> classify_decoded_error(error_name, params, all_errors, data)
      {:error, _reason} -> :not_found
    end
  end

  defp decode_error(_, _errors), do: :not_found

  # From https://blog.soliditylang.org/2020/10/28/solidity-0.8.x-preview/
  @spec classify_decoded_error(String.t(), [term()], [String.t()], binary()) ::
          :not_found | {:ok, String.t(), [term()] | nil}
  defp classify_decoded_error("Panic", [0x00], _errors, _data), do: {:ok, "compiler inserted panic", nil}

  defp classify_decoded_error("Panic", [0x01], _errors, _data), do: {:ok, "assertion failure", nil}

  defp classify_decoded_error("Panic", [0x11], _errors, _data), do: {:ok, "arithmetic error: overflow or underflow", nil}

  defp classify_decoded_error("Panic", [0x12], _errors, _data), do: {:ok, "division or modulo by zero", nil}

  defp classify_decoded_error("Panic", [0x21], _errors, _data), do: {:ok, "failed to convert value to enum", nil}

  defp classify_decoded_error("Panic", [0x22], _errors, _data), do: {:ok, "incorrectly encoded storage byte array", nil}

  defp classify_decoded_error("Panic", [0x31], _errors, _data), do: {:ok, "popped from empty array", nil}

  defp classify_decoded_error("Panic", [0x32], _errors, _data), do: {:ok, "out-of-bounds array access", nil}
  defp classify_decoded_error("Panic", [0x41], _errors, _data), do: {:ok, "out of memory", nil}

  defp classify_decoded_error("Panic", [0x51], _errors, _data),
    do: {:ok, "called a zero-initialized variable of internal function type", nil}

  # `Error(string)` is compiler-defined, so it is never in the caller's `:errors`
  # list and must be labelled from its own selector. Matching it back against the
  # candidates instead would attribute a plain `require(x, "msg")` revert to
  # whichever error happened to be listed first.
  defp classify_decoded_error("Error", params, _errors, <<0x08, 0xC3, 0x79, 0xA0, _::binary>>),
    do: {:ok, "Error(string)", params}

  defp classify_decoded_error(error_name, params, errors, data) do
    case find_error_abi(error_name, errors, data) do
      {:ok, error_abi} -> {:ok, error_abi, params}
      :error -> :not_found
    end
  end

  @spec find_error_abi(String.t(), [String.t()], binary()) :: {:ok, String.t()} | :error
  defp find_error_abi(error_name, errors, data) do
    Enum.find_value(errors, :error, &match_error_abi(&1, error_name, data))
  end

  @spec match_error_abi(String.t(), String.t(), binary()) :: {:ok, String.t()} | nil
  defp match_error_abi(error, error_name, data) do
    with {:ok, %{error: ^error_name}} <- ABI.decode_error(data, [error]),
         true <- reverted_with?(data, error) do
      {:ok, error}
    else
      _ -> nil
    end
  end

  # True when `error`'s own selector is the one the revert data carries.
  # `ABI.decode_error/2` falls back to the compiler-defined `Error(string)` /
  # `Panic(uint256)` for *any* candidate list, so a bare name match would let a
  # built-in revert be reported under an unrelated caller-supplied ABI entry.
  @spec reverted_with?(binary(), String.t()) :: boolean()
  defp reverted_with?(data, error) do
    method_id = ABI.method_id(error)
    binary_part(data, 0, byte_size(method_id)) == method_id
  end

  @spec build_revert_data(binary(), [String.t()] | nil) :: map()
  defp build_revert_data(data_hex, errors) do
    case Hex.decode_hex(data_hex) do
      {:ok, data} ->
        Enum.into(decode_revert_error(data, errors), %{revert: data})

      _ ->
        %{}
    end
  end

  @spec decode_revert_error(binary(), [String.t()] | nil) :: map()
  defp decode_revert_error(data, errors) do
    case decode_error(data, errors) do
      {:ok, error_abi, error_params} when not is_nil(error_params) ->
        %{error_abi: error_abi, error_params: error_params}

      _ ->
        %{}
    end
  end

  @spec decode_response(binary(), integer(), [String.t()] | nil, String.t(), map()) ::
          {:ok, term()} | {:error, send_rpc_error()}
  defp decode_response(response, id, errors, method, body) do
    case Jason.decode(response) do
      {:ok, %{"jsonrpc" => "2.0", "result" => result, "id" => ^id}} ->
        {:ok, result}

      {:ok,
       %{
         "jsonrpc" => "2.0",
         "error" => %{
           "code" => 3 = code,
           "data" => data_hex,
           "message" => message
         },
         "id" => ^id
       }} ->
        extra_revert_data = build_revert_data(data_hex, errors)

        {:error, Map.merge(%{code: code, message: message}, extra_revert_data)}

      {:ok,
       %{
         "jsonrpc" => "2.0",
         "error" => %{
           "code" => code,
           "message" => message
         },
         "id" => ^id
       }} ->
        if code == -32_602 do
          Logger.warning(
            "[Cartouche][RPC][#{method}] Invalid JSON-PRC request \"#{code} #{message}\" from request `#{Jason.encode!(body)}`"
          )
        end

        {:error, %{code: code, message: message}}

      _ ->
        {:error, %{code: -999, message: "invalid JSON-RPC response"}}
    end
  end

  api(:send_rpc, "Send one Ethereum JSON-RPC request and optionally decode the result.",
    params: [
      method: [kind: :value, description: "JSON-RPC method name, such as `eth_getBalance` or `trace_call`."],
      params: [kind: :value, description: "Ordered JSON-RPC parameter list for the method."],
      opts: [
        kind: :value,
        default: [],
        description:
          "Keyword options for transport and decoding: `:rpc_url`, `:ethereum_node`, `:timeout`, `:headers`, `:retry`, `:verbose`, `:req_options`, `:decode`, `:errors`, and `:id`."
      ]
    ],
    opts: [
      decode: [
        kind: :value,
        default: nil,
        description:
          "`nil` for raw result, `:hex` for bytes, `:hex_unsigned` for integer quantities, or a decoder function."
      ],
      errors: [
        kind: :value,
        default: nil,
        description: "Optional Solidity custom error ABI strings used to decode revert data."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, decoded_result}` on JSON-RPC success, `{:error, reason}` for transport/RPC/decode failures, or `:invalid_hex` for invalid hex decoding."
    }
  )

  @doc """
  Simple RPC client for a JSON-RPC Ethereum node.

  ## Examples

      iex> Cartouche.RPC.send_rpc("net_version", [])
      {:ok, "3"}

      iex> use Cartouche.Hex
      iex> Cartouche.RPC.send_rpc("get_balance", ["0x407d73d8a49eeb85d32cf465507dd71d507100c1", "latest"], ethereum_node: "http://example.com")
      {:ok, "0x0234c8a3397aab58"}

      iex> match?({:error, {:invalid_params, %Jason.EncodeError{}}}, Cartouche.RPC.send_rpc(<<255>>, []))
      true

      iex> match?({:error, {:invalid_params, %Protocol.UndefinedError{}}}, Cartouche.RPC.send_rpc("net_version", [self()]))
      true

  ## Options

  Common options (other RPC wrappers forward `opts` here):

  - `:rpc_url` / `:ethereum_node` — node URL (`:rpc_url` takes precedence); falls back to `Application.get_env(:cartouche, :ethereum_node)`
  - `:retry` — opt-in `[max_retries: 2, backoff_ms: 100]`; only transport failures
    retry, before typed decoding. JSON-RPC application errors are final.
  - `:timeout` — Req `receive_timeout` in ms
  - `:headers` — extra request headers
  - `:verbose` — when `true`, decode failures log at `:error` instead of `:info`
  - `:req_options` — a keyword list merged into the `Req.request/1` options (highest
    precedence), exposing Req's whole pipeline (retries, redirects, a custom `finch:`
    pool, telemetry, proxies, plugs). A global default can be set with
    `config :cartouche, :req_options, [...]`. Tests stub the transport by passing
    `req_options: [plug: ...]` (or configuring `config :cartouche, Cartouche.RPC, plug: ...`).
  """
  @spec send_rpc(binary(), [term()], Keyword.t()) ::
          {:ok, term()} | {:error, send_rpc_error()} | :invalid_hex
  def send_rpc(method, params, opts \\ []) do
    :telemetry.span(@rpc_request_event, %{method: method}, fn ->
      result = method |> do_send_rpc(params, opts) |> classify_node_refusal()
      {result, rpc_request_stop_metadata(method, result)}
    end)
  end

  @spec do_send_rpc(String.t(), [term()], keyword()) :: {:ok, term()} | {:error, term()} | :invalid_hex
  defp do_send_rpc(method, params, opts) do
    id = Keyword.get_lazy(opts, :id, fn -> System.unique_integer([:positive]) end)
    body = get_body(method, params, id)

    with {:ok, encoded_body} <- encode_body(body),
         {:ok, %Req.Response{body: resp_body}} <- request(encoded_body, opts),
         {:ok, result} <- decode_response(resp_body, id, opts[:errors], method, body) do
      decode_result(opts[:decode], result, method, Keyword.get(opts, :verbose, false))
    end
  end

  api(:send_batch, "Send several Ethereum JSON-RPC requests as one array batch and return raw results in request order.",
    params: [
      requests: [kind: :value, description: "List of `{method, params}` tuples, sent in this order."],
      opts: [
        kind: :value,
        default: [],
        description:
          "Transport options, the same as `send_rpc/3`: `:rpc_url`, `:ethereum_node`, `:timeout`, `:headers`, `:retry`, and `:req_options`."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, results}` with one raw result per request in request order. `{:error, reason}` for a transport failure, a batch-level JSON-RPC error, or the first request that errored or has no response; recognised node refusals are tagged as in `send_rpc/3`."
    }
  )

  @doc "Sends a JSON-RPC array batch and returns raw results in request order. Uses the same options as `send_rpc/3`."
  @spec send_batch([{String.t(), [term()]}], keyword()) :: {:ok, [term()]} | {:error, term()}
  def send_batch(requests, opts \\ [])
  def send_batch([], _opts), do: {:ok, []}

  def send_batch(requests, opts) when is_list(requests) do
    :telemetry.span(@rpc_request_event, %{method: @batch_method}, fn ->
      result = do_batch(requests, opts)
      {result, rpc_request_stop_metadata(@batch_method, result)}
    end)
  end

  @spec request(binary(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  defp request(encoded_body, opts) do
    url = opts[:rpc_url] || opts[:ethereum_node] || Application.get_env(:cartouche, :ethereum_node)

    with {:ok, policy} <- normalize_retry_policy(opts[:retry]) do
      if is_binary(url) and url != "" do
        base = [
          method: :post,
          url: url,
          headers: headers(Keyword.get(opts, :headers, [])),
          body: encoded_body,
          receive_timeout: Keyword.get(opts, :timeout, @default_timeout),
          decode_body: false,
          retry: false
        ]

        request_opts = Cartouche.HTTP.req_options(__MODULE__, base, opts)
        retry_request(request_opts, policy)
      else
        {:error, {:missing_option, :ethereum_node}}
      end
    end
  end

  @spec retry_request(keyword(), %{max_retries: non_neg_integer(), backoff_ms: non_neg_integer()}) ::
          {:ok, Req.Response.t()} | {:error, term()}
  defp retry_request(opts, %{max_retries: remaining, backoff_ms: backoff} = policy) do
    result = Req.request(opts)

    if remaining > 0 and retryable_response?(result) do
      if backoff > 0, do: Process.sleep(backoff)
      retry_request(opts, %{policy | max_retries: remaining - 1})
    else
      normalize_response(result)
    end
  end

  @spec retryable_response?({:ok, Req.Response.t()} | {:error, term()}) :: boolean()
  defp retryable_response?({:error, _}), do: true

  defp retryable_response?({:ok, %Req.Response{status: status, body: body}}) when status < 200 or status >= 300 do
    # A gateway failure can be retried, but a JSON-RPC application error is final,
    # including providers that deliver it under HTTP 400 or 503.
    not match?({:ok, %{"error" => %{"code" => _}}}, Jason.decode(body))
  end

  defp retryable_response?({:ok, _}), do: false

  @spec rpc_request_stop_metadata(String.t(), {:ok, term()} | {:error, term()} | :invalid_hex) :: map()
  defp rpc_request_stop_metadata(method, {:ok, _}), do: %{method: method, status: :ok}

  defp rpc_request_stop_metadata(@batch_method, {:error, reason}), do: rpc_error_metadata(@batch_method, reason)

  defp rpc_request_stop_metadata(method, {:error, reason}) do
    error =
      case reason do
        {tag, _}
        when tag in [
               :rpc_error,
               :method_not_found,
               :namespace_unavailable,
               :unavailable,
               :invalid_retry_policy,
               :missing_option
             ] ->
          reason

        %{} = map ->
          {:rpc_error, Helpers.maybe_put_revert_data_hex(map)}

        other ->
          {:rpc_error, %{message: inspect(other)}}
      end

    rpc_error_metadata(method, error)
  end

  defp rpc_request_stop_metadata(method, :invalid_hex), do: rpc_error_metadata(method, :invalid_hex)

  @spec rpc_error_metadata(String.t(), term()) :: map()
  defp rpc_error_metadata(method, error), do: %{method: method, status: :error, error: error}

  @spec normalize_retry_policy(term()) ::
          {:ok, %{max_retries: non_neg_integer(), backoff_ms: non_neg_integer()}}
          | {:error, term()}
  defp normalize_retry_policy(retry) when retry in [nil, false] do
    {:ok, %{max_retries: @no_retry_max_retries, backoff_ms: @default_retry_backoff_ms}}
  end

  defp normalize_retry_policy(policy) when is_list(policy) do
    max_retries = Keyword.get(policy, :max_retries, @default_retry_max_retries)
    backoff_ms = Keyword.get(policy, :backoff_ms, @default_retry_backoff_ms)

    if valid_retry_policy?(max_retries, backoff_ms) do
      {:ok, %{max_retries: max_retries, backoff_ms: backoff_ms}}
    else
      {:error, {:invalid_retry_policy, policy}}
    end
  end

  defp normalize_retry_policy(policy), do: {:error, {:invalid_retry_policy, policy}}

  @spec valid_retry_policy?(term(), term()) :: boolean()
  defp valid_retry_policy?(max_retries, backoff_ms) do
    is_integer(max_retries) and max_retries >= 0 and is_integer(backoff_ms) and backoff_ms >= 0
  end

  # Classify distinguishable node-capability refusals. Unrecognized shapes,
  # including a `%Req.Response{}` whose body is not a JSON-RPC error, pass
  # through byte-identical. Alchemy answers method-not-found as HTTP 400 with a
  # JSON-RPC body (cartouche surfaces that as `%Req.Response{}` rather than
  # decoding it), so the body is unwrapped only when the result is classified.
  @spec classify_node_refusal({:ok, term()} | {:error, term()} | :invalid_hex) ::
          {:ok, term()} | {:error, term()} | :invalid_hex
  defp classify_node_refusal({:ok, _} = ok), do: ok

  defp classify_node_refusal({:error, {:rpc_error, map}} = err) when is_map(map) do
    classify_error_map(map, err)
  end

  defp classify_node_refusal({:error, map} = err) when is_map(map) do
    classify_error_map(map, err)
  end

  defp classify_node_refusal(other), do: other

  @spec classify_error_map(map(), {:error, term()}) :: {:error, term()}
  defp classify_error_map(map, err) do
    case jsonrpc_error_fields(map) do
      {:ok, code, message, fields} ->
        case refusal_tag(code, message) do
          nil -> err
          tag -> {:error, {tag, fields}}
        end

      :error ->
        err
    end
  end

  @spec jsonrpc_error_fields(map()) :: {:ok, integer(), String.t(), map()} | :error
  defp jsonrpc_error_fields(%{code: code, message: message} = map) when is_integer(code) and is_binary(message) do
    {:ok, code, message, map}
  end

  defp jsonrpc_error_fields(%Req.Response{body: body}) when is_binary(body) do
    decode_jsonrpc_error_body(body)
  end

  defp jsonrpc_error_fields(_), do: :error

  @spec decode_jsonrpc_error_body(binary()) :: {:ok, integer(), String.t(), map()} | :error
  defp decode_jsonrpc_error_body(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"code" => code, "message" => message} = error}}
      when is_integer(code) and is_binary(message) ->
        fields = maybe_put_error_field(%{code: code, message: message}, :data, Map.get(error, "data"))

        {:ok, code, message, fields}

      _ ->
        :error
    end
  end

  @spec refusal_tag(integer(), String.t()) :: atom() | nil
  defp refusal_tag(@jsonrpc_method_not_found, _message), do: :method_not_found

  defp refusal_tag(@jsonrpc_invalid_request, message) when is_binary(message) do
    cond do
      namespace_unavailable_message?(message) -> :namespace_unavailable
      method_not_found_message?(message) -> :method_not_found
      true -> nil
    end
  end

  defp refusal_tag(@jsonrpc_unable_to_complete, message) when is_binary(message) do
    if unable_to_complete_message?(message), do: :unavailable
  end

  defp refusal_tag(_code, _message), do: nil

  @spec namespace_unavailable_message?(String.t()) :: boolean()
  defp namespace_unavailable_message?(message) do
    down = String.downcase(message)
    String.contains?(down, "not available on the") and String.contains?(down, "tier")
  end

  @spec method_not_found_message?(String.t()) :: boolean()
  defp method_not_found_message?(message) do
    down = String.downcase(message)
    String.starts_with?(down, "unsupported method:") or String.contains?(down, "is not available")
  end

  @spec unable_to_complete_message?(String.t()) :: boolean()
  defp unable_to_complete_message?(message) do
    message |> String.downcase() |> String.contains?("unable to complete request")
  end

  @spec do_batch([{String.t(), [term()]}], keyword()) :: {:ok, [term()]} | {:error, term()}
  defp do_batch(requests, opts) do
    with {:ok, rpc_requests} <- build_batch_requests(requests),
         {:ok, encoded_body} <- encode_json(rpc_requests),
         {:ok, body} <- send_batch_request(encoded_body, opts) do
      decode_batch_body(body, Enum.map(rpc_requests, & &1["id"]))
    end
  end

  @spec build_batch_requests([{String.t(), [term()]}]) :: {:ok, [map()]} | {:error, term()}
  defp build_batch_requests(requests) do
    requests
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn
      {{method, params}, id}, {:ok, acc} when is_binary(method) and is_list(params) ->
        {:cont, {:ok, [Cartouche.RPC.get_body(method, params, id) | acc]}}

      {request, _id}, {:ok, _acc} ->
        {:halt, {:error, {:invalid_batch_request, request}}}
    end)
    |> case do
      {:ok, rpc_requests} -> {:ok, Enum.reverse(rpc_requests)}
      error -> error
    end
  end

  @spec encode_json(term()) :: {:ok, binary()} | {:error, term()}
  defp encode_json(term) do
    case Jason.encode(term) do
      {:ok, encoded} -> {:ok, encoded}
      {:error, reason} -> {:error, {:rpc_error, %{message: inspect(reason)}}}
    end
  end

  @spec send_batch_request(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  defp send_batch_request(encoded_body, opts) do
    case encoded_body |> request(opts) |> classify_node_refusal() do
      {:ok, %Req.Response{body: body}} ->
        {:ok, body}

      {:error, %Req.Response{body: body}} ->
        {:error, {:rpc_error, %{message: body}}}

      {:error, {tag, _}} = error
      when tag in [
             :method_not_found,
             :namespace_unavailable,
             :unavailable,
             :missing_option,
             :invalid_retry_policy
           ] ->
        error

      {:error, message} ->
        {:error, {:rpc_error, %{message: message}}}
    end
  end

  @spec decode_batch_body(binary(), [pos_integer()]) :: {:ok, [term()]} | {:error, term()}
  defp decode_batch_body(body, ids) do
    case Jason.decode(body) do
      {:ok, responses} when is_list(responses) ->
        decode_batch_responses(responses, ids)

      {:ok, %{"error" => error}} ->
        classify_node_refusal({:error, normalize_rpc_error(error)})

      {:ok, other} ->
        {:error, {:rpc_error, %{message: "unexpected batch response: #{inspect(other)}"}}}

      {:error, reason} ->
        {:error, {:rpc_error, %{message: inspect(reason)}}}
    end
  end

  @spec decode_batch_responses([term()], [pos_integer()]) :: {:ok, [term()]} | {:error, term()}
  defp decode_batch_responses(responses, ids) do
    responses_by_id =
      responses
      |> Enum.filter(&is_map/1)
      |> Map.new(&{&1["id"], &1})

    ids
    |> Enum.map(&Map.get(responses_by_id, &1))
    |> collect_batch_results()
  end

  @spec collect_batch_results([map() | nil]) :: {:ok, [term()]} | {:error, term()}
  defp collect_batch_results(responses) do
    responses
    |> Enum.reduce_while({:ok, []}, fn
      %{"result" => result}, {:ok, acc} ->
        {:cont, {:ok, [result | acc]}}

      %{"error" => error}, {:ok, _acc} ->
        {:halt, classify_node_refusal({:error, normalize_rpc_error(error)})}

      nil, {:ok, _acc} ->
        {:halt, {:error, {:rpc_error, %{message: "missing batch response"}}}}

      other, {:ok, _acc} ->
        {:halt, {:error, {:rpc_error, %{message: "unexpected batch item: #{inspect(other)}"}}}}
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  @spec normalize_rpc_error(term()) :: {:rpc_error, map()}
  defp normalize_rpc_error(%{} = error) do
    normalized =
      %{}
      |> maybe_put_error_field(:code, Map.get(error, "code"))
      |> maybe_put_error_field(:message, Map.get(error, "message"))
      |> maybe_put_error_field(:data, Map.get(error, "data"))
      |> maybe_put_revert_from_error_data()
      |> Helpers.maybe_put_revert_data_hex()

    {:rpc_error, normalized}
  end

  defp normalize_rpc_error(other), do: {:rpc_error, %{message: inspect(other)}}

  @spec maybe_put_error_field(map(), atom(), term()) :: map()
  defp maybe_put_error_field(map, _key, nil), do: map
  defp maybe_put_error_field(map, key, value), do: Map.put(map, key, value)

  @spec maybe_put_revert_from_error_data(map()) :: map()
  defp maybe_put_revert_from_error_data(%{code: 3, data: data} = map) when is_binary(data) do
    case Onchain.Hex.decode(data) do
      {:ok, revert} -> Map.put_new(map, :revert, revert)
      {:error, _reason} -> map
    end
  end

  defp maybe_put_revert_from_error_data(map), do: map

  @spec encode_body(map()) :: {:ok, binary()} | {:error, invalid_params_error()}
  defp encode_body(body) do
    {:ok, Jason.encode!(body)}
  rescue
    e in [Jason.EncodeError, Protocol.UndefinedError] ->
      {:error, {:invalid_params, e}}
  end

  @spec decode_result(nil | :hex | :hex_unsigned | (term() -> term()), term(), String.t(), boolean()) ::
          {:ok, term()} | {:error, String.t()} | :invalid_hex
  defp decode_result(nil, result, _method, _verbose), do: {:ok, result}

  defp decode_result(:hex, result, _method, _verbose), do: Hex.decode_hex(result)

  defp decode_result(:hex_unsigned, result, _method, _verbose) do
    with {:ok, bin} <- Hex.decode_hex(result), do: {:ok, :binary.decode_unsigned(bin)}
  end

  defp decode_result(f, result, method, verbose) when is_function(f) do
    {:ok, f.(result)}
  rescue
    # `f` is a caller-supplied decode function; it may raise any exception, so
    # the catch-all is correct here — every failure must surface as an
    # `{:error, _}` with the response logged, never crash the RPC call.
    # reach:disable-next-line bare_rescue
    e -> log_decode_error(e, method, result, verbose)
  end

  @spec log_decode_error(Exception.t(), String.t(), term(), boolean()) :: {:error, String.t()}
  defp log_decode_error(e, method, result, true) do
    Logger.error("[Cartouche][RPC][#{method}] Error decoding response. error=#{inspect(e)}, response=#{inspect(result)}")

    {:error, "failed to decode `#{method}` response: #{inspect(e)}"}
  end

  defp log_decode_error(e, method, _result, false) do
    Logger.info("[Cartouche][RPC][#{method}] Error decoding response: #{inspect(e)}")

    {:error, "failed to decode `#{method}` response: #{inspect(e)}"}
  end

  api(:get_nonce, "Fetch an account nonce at a block selector.",
    params: [
      account: [kind: :value, description: "20-byte Ethereum account address."],
      opts: [
        kind: :value,
        default: [],
        description:
          ~s{Keyword options including `:block_number` (`"latest"`, `"pending"`, integer, or hex quantity) and common `send_rpc/3` options.}
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, nonce}` as a non-negative integer decoded from `eth_getTransactionCount`, or `{:error, reason}`."
    }
  )

  @doc """
  RPC call to get account nonce.

  ## Examples

      iex> use Cartouche.Hex
      iex> Cartouche.RPC.get_nonce(~h[0x407d73d8a49eeb85d32cf465507dd71d507100c1])
      {:ok, 4}
  """
  @spec get_nonce(<<_::160>>, Keyword.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def get_nonce(account, opts \\ []) do
    block_number = opts |> Keyword.get(:block_number, "latest") |> normalize_block_param()

    send_rpc(
      "eth_getTransactionCount",
      [Hex.encode_big_hex(account), block_number],
      Keyword.put(opts, :decode, :hex_unsigned)
    )
  end

  api(:send_trx, "Submit a signed Ethereum transaction to the network.",
    params: [
      trx: [
        kind: :exchange_data,
        source: "Cartouche.Transaction.build_signed_trx/7 or Cartouche.Transaction.build_signed_trx_v2/9",
        description: "Signed legacy or EIP-1559 transaction struct with signature fields populated."
      ],
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, transaction_hash}` as 32 decoded bytes, or `{:error, reason}` from `eth_sendRawTransaction`."
    }
  )

  @doc """
  RPC call to send a raw transaction.

  ## Examples

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, signed_trx} = Cartouche.Transaction.build_signed_trx(<<1::160>>, 5, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, {50, :gwei}, 100_000, 0, chain_id: :goerli, signer: signer_proc)
      iex> {:ok, trx_id} = Cartouche.RPC.send_trx(signed_trx)
      iex> <<nonce::integer-size(8), gas_price::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, gas_price, gas_limit, to}
      {5, 50000000000, 100000, <<1::160>>}

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, signed_trx} = Cartouche.Transaction.build_signed_trx_v2(<<1::160>>, 5, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, {50, :gwei}, {10, :gwei}, 100_000, 0, [], chain_id: :goerli, signer: signer_proc)
      iex> {:ok, trx_id} = Cartouche.RPC.send_trx(signed_trx)
      iex> <<nonce::integer-size(8), max_priority_fee_per_gas::integer-size(64), max_fee_per_gas::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, max_priority_fee_per_gas, max_fee_per_gas, gas_limit, to}
      {5, 50000000000, 10000000000, 100000, <<1::160>>}
  """
  @spec send_trx(V1.t() | V2.t(), Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def send_trx(trx, opts \\ [])

  def send_trx(%V1{} = trx, opts) do
    send_rpc(
      "eth_sendRawTransaction",
      [Hex.encode_big_hex(V1.encode(trx))],
      Keyword.put(opts, :decode, :hex)
    )
  end

  def send_trx(%V2{signature_y_parity: v, signature_r: r, signature_s: s} = trx, opts)
      when not is_nil(v) and not is_nil(r) and not is_nil(s) do
    send_rpc(
      "eth_sendRawTransaction",
      [Hex.encode_big_hex(V2.encode(trx))],
      Keyword.put(opts, :decode, :hex)
    )
  end

  api(:call_trx, "Run `eth_call` against a transaction or call object without submitting it.",
    params: [
      trx: [
        kind: :value,
        description:
          "`Cartouche.Transaction.V1`, `Cartouche.Transaction.V2`, or `Cartouche.Transaction.Call` to simulate."
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          "Keyword options including optional `:from`, block selector `:block_number`, `:decode`, `:errors`, trace options, and transport options."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, bytes}` by default, another decoded shape when `:decode` is supplied, or `{:error, reason}` including decoded revert metadata."
    }
  )

  @doc ~S"""
  RPC call to call a transaction and preview results.

  ## Examples

      iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Cartouche.RPC.call_trx()
      {:ok, <<0x0c>>}

      iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
      iex> |> Cartouche.RPC.call_trx()
      {:ok, <<0x0d>>}

      iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Cartouche.RPC.call_trx(decode: :hex_unsigned)
      {:ok, 0x0c}

      iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Cartouche.RPC.call_trx()
      {:error, %{code: 3, message: "execution reverted", revert: <<61, 115, 139, 46>>}}

      iex> errors = ["Unauthorized()", "BadNonce()", "NotEnoughSigners()", "NotActiveWithdrawalAddress()", "NotActiveOperator()", "DuplicateSigners()"]
      iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Cartouche.RPC.call_trx(errors: errors)
      {:error, %{code: 3, message: "execution reverted", error_abi: "NotActiveOperator()", error_params: [], revert: <<61, 115, 139, 46>>}}

      iex> errors = ["Cool(uint256,string)"]
      iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<11::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Cartouche.RPC.call_trx(errors: errors)
      {:error, %{code: 3, message: "execution reverted", error_abi: "Cool(uint256,string)", error_params: [1, "cat"], revert: ABI.encode("Cool(uint256,string)", [1, "cat"])}}

      iex> errors = ["Cool(uint256,string)"]
      iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<12::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Cartouche.RPC.call_trx(errors: errors)
      {:error, %{code: 3, message: "execution reverted", revert: <<>>}}

      iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<13::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Cartouche.RPC.call_trx()
      {:error, %{code: -32602, message: "Failed to decode transaction"}}
  """
  @spec call_trx(V1.t() | V2.t() | Call.t(), Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def call_trx(trx, opts \\ []) do
    from = Keyword.get(opts, :from)
    block_number = opts |> Keyword.get(:block_number, "latest") |> normalize_block_param()
    errors = Keyword.get(opts, :errors, [])
    trace_reverts = Keyword.get(opts, :trace_reverts, false)
    debug_trace = Keyword.get(opts, :debug_trace, false)
    trace_opts = Keyword.get(opts, :trace_opts, [])

    trx_res =
      send_rpc(
        "eth_call",
        [to_call_params(trx, from), block_number],
        opts
        |> Keyword.put_new(:decode, :hex)
        |> Keyword.put_new(:errors, errors)
      )

    if trace_reverts do
      show_trace_revert(trx, trx_res, debug_trace, Keyword.merge(opts, trace_opts))
    else
      trx_res
    end
  end

  api(:create_access_list, "Generate an EIP-2930 access list for a transaction or call object.",
    params: [
      trx: [
        kind: :value,
        description: "`Cartouche.Transaction.V1`, `Cartouche.Transaction.V2`, or `Cartouche.Transaction.Call` to execute."
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          "Keyword options including optional `:from`, block selector `:block_number`, and common `send_rpc/3` options."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, %{access_list: [{address, storage_keys}], gas_used: gas, optional(:error) => message}}` with binary addresses and storage keys, or `{:error, reason}`."
    }
  )

  @doc ~S"""
  Generates the access list and gas used by a call at a block selector.

  A node may return an `:error` string alongside a usable access list when
  execution reverts; the field is retained in the successful result map.

  ## Examples

      iex> call = Cartouche.Transaction.Call.new(<<1::160>>, <<0, 1>>)
      iex> {:ok, %{access_list: [{address, [storage_key]}], gas_used: gas_used}} =
      ...>   Cartouche.RPC.create_access_list(call)
      iex> {address, storage_key, gas_used}
      {<<1::160>>, <<2::256>>, 26026}
  """
  @spec create_access_list(V1.t() | V2.t() | Call.t(), Keyword.t()) ::
          {:ok, access_list_result()} | {:error, term()}
  def create_access_list(trx, opts \\ []) do
    from = Keyword.get(opts, :from)
    block_number = opts |> Keyword.get(:block_number, "latest") |> normalize_block_param()

    send_rpc(
      "eth_createAccessList",
      [to_call_params(trx, from), block_number],
      Keyword.put(opts, :decode, &deserialize_access_list_result/1)
    )
  end

  @spec deserialize_access_list_result(map()) :: access_list_result()
  defp deserialize_access_list_result(%{"accessList" => access_list, "gasUsed" => gas_used} = params) do
    result = %{
      access_list: Cartouche.Transaction.JsonField.decode_access_list(access_list),
      gas_used: Hex.decode_hex_number!(gas_used)
    }

    case params do
      %{"error" => error} -> Map.put(result, :error, error)
      _ -> result
    end
  end

  api(:estimate_gas, "Estimate gas for a transaction or call object.",
    params: [
      trx: [
        kind: :value,
        description:
          "`Cartouche.Transaction.V1`, `Cartouche.Transaction.V2`, or `Cartouche.Transaction.Call` to estimate."
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          "Keyword options including optional `:from`, block selector `:block_number`, and common `send_rpc/3` options."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, gas_limit}` as a non-negative integer decoded from `eth_estimateGas`, or `{:error, reason}`."
    }
  )

  @doc """
  RPC call to call to estimate gas used by a given call.

  ## Examples

      iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> |> Cartouche.RPC.estimate_gas()
      {:ok, 0x0d}

      iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
      iex> |> Cartouche.RPC.estimate_gas()
      {:ok, 0xdd}

      iex> use Cartouche.Hex
      iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
      iex> |> Cartouche.RPC.estimate_gas()
      {:error, %{code: 3, message: "execution reverted: Dai/insufficient-balance", revert: ~h[0x08c379a0000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000184461692f696e73756666696369656e742d62616c616e63650000000000000000]}}
  """
  @spec estimate_gas(V1.t() | V2.t() | Call.t(), Keyword.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def estimate_gas(trx, opts \\ []) do
    from = Keyword.get(opts, :from)
    block_number = opts |> Keyword.get(:block_number, "latest") |> normalize_block_param()

    send_rpc(
      "eth_estimateGas",
      [to_call_params(trx, from), block_number],
      Keyword.put(opts, :decode, :hex_unsigned)
    )
  end

  defrpc(:eth_chain_id, "eth_chainId",
    decode: :hex_unsigned,
    summary: "Fetch the current Ethereum chain id.",
    returns_desc: "`{:ok, chain_id}` as a non-negative integer decoded from `eth_chainId`, or `{:error, reason}`.",
    doc: ~S"""
    RPC to get the current chain id.

    Docs: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_chainid

    ## Examples

        iex> Cartouche.RPC.eth_chain_id()
        {:ok, 0x22}
    """
  )

  api(:eth_config, "Fetch the node's EIP-7910 chain and fork configuration.",
    params: [
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, %Cartouche.RPC.Configuration{}}` decoded from `eth_config`, or `{:error, reason}`."
    }
  )

  @doc ~S"""
  Returns the current, next, and last configured Ethereum forks reported by the node.

  ## Examples

      iex> {:ok, config} = Cartouche.RPC.eth_config()
      iex> {config.current.chain_id, config.current.fork_id}
      {1, <<7, 201, 70, 46>>}
  """
  @spec eth_config(Keyword.t()) :: {:ok, Configuration.t()} | {:error, term()}
  def eth_config(opts \\ []) do
    send_rpc("eth_config", [], Keyword.put(opts, :decode, &Configuration.deserialize/1))
  end

  api(:eth_capabilities, "Fetch the node's effective historical-data capabilities.",
    params: [
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, %Cartouche.RPC.Capabilities{}}` decoded from `eth_capabilities`, or `{:error, reason}`."
    }
  )

  @doc ~S"""
  Returns the node's head and resource-retention capabilities.

  ## Examples

      iex> {:ok, capabilities} = Cartouche.RPC.eth_capabilities()
      iex> {capabilities.head.number, capabilities.blocks.oldest_block}
      {42, 0}
  """
  @spec eth_capabilities(Keyword.t()) :: {:ok, Capabilities.t()} | {:error, term()}
  def eth_capabilities(opts \\ []) do
    send_rpc("eth_capabilities", [], Keyword.put(opts, :decode, &Capabilities.deserialize/1))
  end

  defrpc(:get_code, "eth_getCode",
    encode: :big_hex,
    decode: :hex,
    summary: "Fetch contract bytecode at an address and block selector.",
    address_desc: "20-byte Ethereum contract or account address.",
    returns_desc: "`{:ok, bytecode}` decoded from `eth_getCode`, or `{:error, reason}`.",
    doc: ~S"""
    RPC call to get code for a contract at an address.

    ## Examples

        iex> Cartouche.RPC.get_code(<<1::160>>)
        {:ok, <<0x11, 0x22, 0x33>>}
    """
  )

  defrpc(:get_balance, "eth_getBalance",
    decode: :hex_unsigned,
    summary: "Fetch an account ETH balance at a block selector.",
    address_desc: "20-byte Ethereum account or contract address.",
    returns_desc: "`{:ok, wei_balance}` as a non-negative integer decoded from `eth_getBalance`, or `{:error, reason}`.",
    doc: ~S"""
    RPC to get an account's eth balance.

    Docs: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_getbalance

    ## Examples

        iex> Cartouche.RPC.get_balance(~h[0x0000000000000000000000000000000000000001])
        {:ok, 0x55}
    """
  )

  defrpc(:get_transaction_count, "eth_getTransactionCount",
    decode: :hex_unsigned,
    summary: "Fetch an account transaction count at a block selector.",
    address_desc: "20-byte Ethereum account address.",
    returns_desc:
      "`{:ok, nonce}` as a non-negative integer decoded from `eth_getTransactionCount`, or `{:error, reason}`.",
    doc: ~S"""
    RPC to get an account's transaction count (i.e. nonce)

    Docs: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_gettransactioncount

    ## Examples

        iex> Cartouche.RPC.get_transaction_count(~h[0x0000000000000000000000000000000000000001])
        {:ok, 0x4}
    """
  )

  defrpc(:eth_block_number, "eth_blockNumber",
    decode: :hex_unsigned,
    summary: "Fetch the current Ethereum block number.",
    returns_desc:
      "`{:ok, block_number}` as a non-negative integer decoded from `eth_blockNumber`, or `{:error, reason}`.",
    doc: ~S"""
    RPC to get the current block number.

    Docs: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_blocknumber

    ## Examples

        iex> Cartouche.RPC.eth_block_number()
        {:ok, 0x44}
    """
  )

  api(:eth_syncing, "Fetch the node's sync status.",
    params: [
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, false}` when the node is not syncing, `{:ok, %Cartouche.RPC.SyncStatus{}}` while it is, or `{:error, reason}`."
    }
  )

  @doc """
  Returns the node's sync status from `eth_syncing`.

  `execution-apis` v1.0.0-beta.7 (`src/eth/client.yaml`, schema `SyncingStatus`)
  defines one union: `false` when the node is not syncing, or a progress object
  whose quantity fields are `startingBlock`, `currentBlock`, and `highestBlock`.
  This decodes that union to `false` or `%Cartouche.RPC.SyncStatus{}`.

  ## Examples

      iex> Cartouche.RPC.eth_syncing()
      {:ok, false}
  """
  @spec eth_syncing(Keyword.t()) :: {:ok, false | SyncStatus.t()} | {:error, term()}
  def eth_syncing(opts \\ []) do
    send_rpc("eth_syncing", [], Keyword.put(opts, :decode, &decode_syncing/1))
  end

  api(:eth_get_block_transaction_count_by_hash, "Count transactions in the block with the given hash.",
    params: [
      block_hash: [kind: :value, description: "0x-prefixed 32-byte block hash."],
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, count}` as a non-negative integer, `{:ok, nil}` when the block is unknown, or `{:error, reason}`."
    }
  )

  @doc """
  Returns how many transactions are in the block identified by `block_hash`.

  Defined by `execution-apis` v1.0.0-beta.7 (`src/eth/block.yaml`,
  `eth_getBlockTransactionCountByHash`). The result is a hex quantity, or
  `null` when the node does not know the block.

  ## Examples

      iex> Cartouche.RPC.eth_get_block_transaction_count_by_hash("0x" <> String.duplicate("cd", 32))
      {:ok, 2}
  """
  @spec eth_get_block_transaction_count_by_hash(String.t(), Keyword.t()) ::
          {:ok, non_neg_integer() | nil} | {:error, term()}
  def eth_get_block_transaction_count_by_hash(block_hash, opts \\ []) do
    with {:ok, block_hash} <- ensure_block_hash(block_hash) do
      send_rpc(
        "eth_getBlockTransactionCountByHash",
        [block_hash],
        Keyword.put(opts, :decode, &decode_nullable_quantity/1)
      )
    end
  end

  api(:eth_get_block_transaction_count_by_number, "Count transactions in the block with the given number or tag.",
    params: [
      block: [kind: :value, description: "Non-negative block number, 0x quantity, or block tag."],
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, count}` as a non-negative integer, `{:ok, nil}` when the block is unknown, or `{:error, reason}`."
    }
  )

  @doc """
  Returns how many transactions are in the block identified by number or tag.

  Defined by `execution-apis` v1.0.0-beta.7 (`src/eth/block.yaml`,
  `eth_getBlockTransactionCountByNumber`). The result is a hex quantity, or
  `null` when the node does not know the block.

  ## Examples

      iex> Cartouche.RPC.eth_get_block_transaction_count_by_number("latest")
      {:ok, 2}
  """
  @spec eth_get_block_transaction_count_by_number(integer() | String.t(), Keyword.t()) ::
          {:ok, non_neg_integer() | nil} | {:error, term()}
  def eth_get_block_transaction_count_by_number(block, opts \\ []) do
    with {:ok, block} <- Helpers.normalize_block(block) do
      send_rpc(
        "eth_getBlockTransactionCountByNumber",
        [block],
        Keyword.put(opts, :decode, &decode_nullable_quantity/1)
      )
    end
  end

  api(:net_listening, "Ask whether the node is listening for network connections.",
    params: [
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, listening?}` from `net_listening`, or `{:error, reason}`. A node refusal is the shared `send_rpc/3` classification."
    }
  )

  @doc """
  Returns whether the node is listening for peer connections (`net_listening`).

  `net_listening` is not in any tagged `execution-apis` release. It landed on
  `main` after v1.0.0-beta.7 in commit `7c58b32` (#843, 2026-08-24). This
  wrapper does not make the method standard.

  Observed 2026-10-01 on the hosted lanes from the multi-endpoint seam: Alchemy
  (`ETHEREUM_ALCHEMY_URL`) and Infura (`ETHEREUM_INFURA_URL`) both answered
  HTTP 200 with JSON `true`. Neither lane refused the method.

  A refusing endpoint's JSON-RPC error is classified by `send_rpc/3`, not by a
  per-method probe. `-32601`, and `-32600` whose message says the method is
  unsupported or not available, become
  `{:error, {:method_not_found, map}}`. A plan-disabled namespace becomes
  `{:error, {:namespace_unavailable, map}}`. `-32001` whose message says the
  node is unable to complete the request becomes
  `{:error, {:unavailable, map}}`.

  ## Examples

      iex> Cartouche.RPC.net_listening()
      {:ok, true}
  """
  @spec net_listening(Keyword.t()) :: {:ok, boolean()} | {:error, term()}
  def net_listening(opts \\ []) do
    send_rpc("net_listening", [], Keyword.put(opts, :decode, &decode_boolean/1))
  end

  api(:net_peer_count, "Fetch the number of peers currently connected to the node.",
    params: [
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, peer_count}` decoded from `net_peerCount`, or `{:error, reason}`. Alchemy's refusal is `{:error, {:method_not_found, map}}`."
    }
  )

  @doc """
  Returns the node's connected peer count (`net_peerCount`).

  `net_peerCount` is not in any tagged `execution-apis` release. It landed on
  `main` after v1.0.0-beta.7 in commit `7c58b32` (#843, 2026-08-24). This
  wrapper does not make the method standard.

  Observed 2026-10-01 on Alchemy mainnet (`ETHEREUM_ALCHEMY_URL`), HTTP 400:

      {"code":-32600,"message":"net_peerCount is not available on the ETH_MAINNET. For more information see our docs: https://docs.alchemy.com/alchemy/documentation/apis/ethereum"}

  That refusal surfaces as
  `{:error, {:method_not_found, %{code: -32600, message: "net_peerCount is not available on the ETH_MAINNET. For more information see our docs: https://docs.alchemy.com/alchemy/documentation/apis/ethereum"}}}`.
  The same classification is `send_rpc/3`'s shared refusal tag. There is no
  separate capability probe. Infura answered a peer-count quantity on the same
  day; a hosted success is not evidence the method is standard.

  ## Examples

      iex> Cartouche.RPC.net_peer_count()
      {:ok, 2}
  """
  @spec net_peer_count(Keyword.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def net_peer_count(opts \\ []) do
    send_rpc("net_peerCount", [], Keyword.put(opts, :decode, :hex_unsigned))
  end

  api(:web3_client_version, "Fetch the node client version string.",
    params: [
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, client_version}` from `web3_clientVersion`, or `{:error, reason}`. A node refusal is the shared `send_rpc/3` classification."
    }
  )

  @doc """
  Returns the node client's version string (`web3_clientVersion`).

  `web3_clientVersion` is not in `execution-apis` at any tag or on `main`.
  EIP-1474 is the only definition.

  Observed 2026-10-01, HTTP 200, no JSON-RPC refusal. Alchemy
  (`ETHEREUM_ALCHEMY_URL`) returned
  `"reth/v2.5.2-5a6940e/x86_64-unknown-linux-gnu"`. Infura
  (`ETHEREUM_INFURA_URL`) returned
  `"Geth/v1.17.6-stable-3d84c6b2/linux-arm64/go1.27.1"`.

  A refusing endpoint's JSON-RPC error is classified by `send_rpc/3`, not by a
  per-method probe: `{:error, {:method_not_found, map}}`,
  `{:error, {:namespace_unavailable, map}}`, or
  `{:error, {:unavailable, map}}`.

  ## Examples

      iex> Cartouche.RPC.web3_client_version()
      {:ok, "TestClient/v1"}
  """
  @spec web3_client_version(Keyword.t()) :: {:ok, String.t()} | {:error, term()}
  def web3_client_version(opts \\ []) do
    send_rpc("web3_clientVersion", [], Keyword.put(opts, :decode, &decode_client_version/1))
  end

  @spec decode_syncing(term()) :: false | SyncStatus.t()
  defp decode_syncing(false), do: false

  defp decode_syncing(%{} = status) do
    SyncStatus.deserialize(status)
  end

  defp decode_syncing(other) do
    raise ArgumentError, "eth_syncing result must be false or a sync-status object, got: #{inspect(other)}"
  end

  @spec decode_nullable_quantity(term()) :: non_neg_integer() | nil
  defp decode_nullable_quantity(nil), do: nil

  defp decode_nullable_quantity(quantity) when is_binary(quantity), do: Hex.decode_hex_number!(quantity)

  defp decode_nullable_quantity(other) do
    raise ArgumentError, "expected a hex quantity or null, got: #{inspect(other)}"
  end

  @spec decode_boolean(term()) :: boolean()
  defp decode_boolean(value) when is_boolean(value), do: value

  defp decode_boolean(other) do
    raise ArgumentError, "expected a boolean, got: #{inspect(other)}"
  end

  @spec decode_client_version(term()) :: String.t()
  defp decode_client_version(value) when is_binary(value), do: value

  defp decode_client_version(other) do
    raise ArgumentError, "expected a client version string, got: #{inspect(other)}"
  end

  @spec ensure_block_hash(term()) :: {:ok, String.t()} | {:error, {:invalid_block_hash, term()}}
  defp ensure_block_hash(block_hash) do
    case Helpers.ensure_tx_hash(block_hash) do
      {:ok, hash} -> {:ok, hash}
      {:error, {:invalid_tx_hash, input}} -> {:error, {:invalid_block_hash, input}}
    end
  end

  api(:get_block_by_number, "Fetch a block by block number or block tag.",
    params: [
      block_number: [
        kind: :value,
        description: ~s(Block selector: integer block number, hex quantity string, `"latest"`, or `"pending"`.)
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          "Keyword options including `:include_transaction_details` and the common `send_rpc/3` transport options."
      ]
    ],
    opts: [
      include_transaction_details: [
        kind: :value,
        default: false,
        description: "When true, ask the node to include full transaction objects instead of only transaction hashes."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, %Cartouche.Block{}}` decoded by `Cartouche.Block.deserialize/1`, or `{:error, reason}`."
    }
  )

  @doc ~S"""
  RPC to get a block by its block number.

  Docs: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_getblockbynumber

  ## Examples

      iex> Cartouche.RPC.get_block_by_number(55)
      {:ok, %Cartouche.Block{
        difficulty: 0x4ea3f27bc,
        extra_data: ~h[0x476574682f4c5649562f76312e302e302f6c696e75782f676f312e342e32],
        gas_limit: 0x1388,
        gas_used: 0x0,
        hash: ~h[0xdc0818cf78f21a8e70579cb46a43643f78291264dda342ae31049421c82d21ae],
        logs_bloom: ~h[0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000],
        miner: ~h[0xbb7b8287f3f0a933474a79eae42cbca977791171],
        mix_hash: ~h[0x4fffe9ae21f1c9e15207b1f472d5bbdd68c9595d461666602f2be20daf5e7843],
        nonce: 0x689056015818adbe,
        number: 0x1b4,
        parent_hash: ~h[0xe99e022112df268087ea7eafaf4790497fd21dbeeb6bd7a1721df161a6657a54],
        receipts_root: ~h[0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421],
        sha3_uncles: ~h[0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347],
        size: 0x220,
        state_root: ~h[0xddc8b0234c2e0cad087c8b389aa7ef01f7d79b2570bccb77ce48648aa61c904d],
        timestamp: 0x55ba467c,
        total_difficulty: 0x78ed983323d,
        transactions: [],
        transactions_root: ~h[0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421],
        uncles: [],
        base_fee_per_gas: nil,
        withdrawals_root: nil,
        withdrawals: nil,
        parent_beacon_block_root: nil,
        blob_gas_used: nil,
        excess_blob_gas: nil
      }}

  ## Options

  - `:include_transaction_details` — when `true`, the node returns full transaction
    objects in `transactions`; when `false` (default), just hashes. Forwarded to
    `eth_getBlockByNumber` as the second wire param. Note: `Cartouche.Block.deserialize/1`
    currently returns `transactions: []` regardless — see ROADMAP Task 2066.

  Plus any option accepted by `send_rpc/3` (e.g. `:ethereum_node`, `:timeout`, `:req_options`).
  """
  @spec get_block_by_number(non_neg_integer() | String.t(), Keyword.t()) ::
          {:ok, Cartouche.Block.t()} | {:error, term()}
  def get_block_by_number(block_number, opts \\ []) do
    {include_transaction_details, opts} = Keyword.pop(opts, :include_transaction_details, false)

    send_rpc(
      "eth_getBlockByNumber",
      [normalize_block_param(block_number), include_transaction_details],
      Keyword.put(opts, :decode, &Cartouche.Block.deserialize/1)
    )
  end

  # Normalises a block-tag parameter for JSON-RPC: integers become lowercase
  # quantity strings (`"0x37"`); supported tag atoms become their wire strings;
  # strings (`"latest"`, `"0x37"`, etc.) pass through unchanged. Required
  # because `Jason.encode!/1` would otherwise serialise an integer as a bare
  # JSON number, which real Ethereum nodes reject with `-32602 Invalid params`.
  @spec normalize_block_param(integer() | binary() | :earliest | :latest | :pending | :safe | :finalized) :: String.t()
  defp normalize_block_param(n) when is_integer(n), do: Hex.encode_quantity(n)
  defp normalize_block_param(tag) when tag in [:earliest, :latest, :pending, :safe, :finalized], do: Atom.to_string(tag)
  defp normalize_block_param(s) when is_binary(s), do: s

  api(:get_block_by_hash, "Fetch a block by its 32-byte block hash.",
    params: [
      block_hash: [kind: :value, description: "32-byte block hash, encoded as Ethereum DATA for JSON-RPC."],
      opts: [
        kind: :value,
        default: [],
        description:
          "Keyword options including `:include_transaction_details` and the common `send_rpc/3` transport options."
      ]
    ],
    opts: [
      include_transaction_details: [
        kind: :value,
        default: false,
        description: "When true, ask the node to include full transaction objects instead of only transaction hashes."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, %Cartouche.Block{}}` decoded by `Cartouche.Block.deserialize/1`, or `{:error, reason}`."
    }
  )

  @doc ~S"""
  RPC to get a block by its block hash.

  Docs: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_getblockbyhash

  ## Examples

      iex> Cartouche.RPC.get_block_by_hash(~h[0xdc0818cf78f21a8e70579cb46a43643f78291264dda342ae31049421c82d21ae])
      {:ok, %Cartouche.Block{
        difficulty: 0x4ea3f27bc,
        extra_data: ~h[0x476574682f4c5649562f76312e302e302f6c696e75782f676f312e342e32],
        gas_limit: 0x1388,
        gas_used: 0x0,
        hash: ~h[0xdc0818cf78f21a8e70579cb46a43643f78291264dda342ae31049421c82d21ae],
        logs_bloom: ~h[0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000],
        miner: ~h[0xbb7b8287f3f0a933474a79eae42cbca977791171],
        mix_hash: ~h[0x4fffe9ae21f1c9e15207b1f472d5bbdd68c9595d461666602f2be20daf5e7843],
        nonce: 0x689056015818adbe,
        number: 0x1b4,
        parent_hash: ~h[0xe99e022112df268087ea7eafaf4790497fd21dbeeb6bd7a1721df161a6657a54],
        receipts_root: ~h[0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421],
        sha3_uncles: ~h[0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347],
        size: 0x220,
        state_root: ~h[0xddc8b0234c2e0cad087c8b389aa7ef01f7d79b2570bccb77ce48648aa61c904d],
        timestamp: 0x55ba467c,
        total_difficulty: 0x78ed983323d,
        transactions: [],
        transactions_root: ~h[0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421],
        uncles: [],
        base_fee_per_gas: nil,
        withdrawals_root: nil,
        withdrawals: nil,
        parent_beacon_block_root: nil,
        blob_gas_used: nil,
        excess_blob_gas: nil
      }}

  ## Options

  - `:include_transaction_details` — when `true`, the node returns full transaction
    objects in `transactions`; when `false` (default), just hashes. Forwarded to
    `eth_getBlockByHash` as the second wire param (real nodes reject single-param
    calls with `-32602 Invalid params`). Note: `Cartouche.Block.deserialize/1`
    currently returns `transactions: []` regardless — see ROADMAP Task 2066.

  Plus any option accepted by `send_rpc/3` (e.g. `:ethereum_node`, `:timeout`, `:req_options`).
  """
  @spec get_block_by_hash(binary(), Keyword.t()) ::
          {:ok, Cartouche.Block.t()} | {:error, term()}
  def get_block_by_hash(block_hash, opts \\ []) do
    {include_transaction_details, opts} = Keyword.pop(opts, :include_transaction_details, false)

    send_rpc(
      "eth_getBlockByHash",
      [to_hex(block_hash), include_transaction_details],
      Keyword.put(opts, :decode, &Cartouche.Block.deserialize/1)
    )
  end

  api(:get_trx_receipt, "Fetch and decode a transaction receipt by transaction hash.",
    params: [
      trx_id: [
        kind: :value,
        description: "Transaction hash as a 32-byte binary or a 0x-prefixed 66-character hex string."
      ],
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport and decode logging options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, %Cartouche.Receipt{}}`, `{:ok, nil}` when unavailable, or `{:error, reason}` when RPC or receipt decoding fails."
    }
  )

  @doc """
  RPC call to get a transaction receipt. Note, this will return {:ok, %Cartouche.Receipt{}} or {:ok, nil} if the
  receipt is not yet available.

  ## Examples

      iex> Cartouche.RPC.get_trx_receipt(~h[0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5])
      {:ok,
        %Cartouche.Receipt{
          transaction_hash: ~h[0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5],
          transaction_index: 0x66,
          block_hash: ~h[0xa957d47df264a31badc3ae823e10ac1d444b098d9b73d204c40426e57f47e8c3],
          block_number: 0xeff35f,
          from: ~h[0x6221a9c005f6e47eb398fd867784cacfdcfff4e7],
          to: ~h[0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2],
          cumulative_gas_used: 0xa12515,
          effective_gas_price: 0x5a9c688d4,
          gas_used: 0xb4c8,
          contract_address: nil,
          logs: [
            %Cartouche.Receipt.Log{
              log_index: 1,
              block_number: 0x01b4,
              block_hash: ~h[0xaa8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcfdf829c5a142f1fccd7d],
              transaction_hash: ~h[0xaadf829c5a142f1fccd7d8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcf],
              transaction_index: 0,
              address: ~h[0x16c5785ac562ff41e2dcfdf829c5a142f1fccd7d],
              data: ~h[0x0000000000000000000000000000000000000000000000000000000000000000],
              topics: [
                ~h[0x59ebeb90bc63057b6515673c3ecf9438e5058bca0f92585014eced636878c9a5]
              ]
            }
          ],
          logs_bloom: ~h[0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001],
          type: 0x02,
          status: 0x01,
        }
      }

      iex> Cartouche.RPC.get_trx_receipt("0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5")
      {:ok,
        %Cartouche.Receipt{
          transaction_hash: ~h[0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5],
          transaction_index: 0x66,
          block_hash: ~h[0xa957d47df264a31badc3ae823e10ac1d444b098d9b73d204c40426e57f47e8c3],
          block_number: 0xeff35f,
          from: ~h[0x6221a9c005f6e47eb398fd867784cacfdcfff4e7],
          to: ~h[0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2],
          cumulative_gas_used: 0xa12515,
          effective_gas_price: 0x5a9c688d4,
          gas_used: 0xb4c8,
          contract_address: nil,
          logs: [
            %Cartouche.Receipt.Log{
              log_index: 1,
              block_number: 0x01b4,
              block_hash: ~h[0xaa8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcfdf829c5a142f1fccd7d],
              transaction_hash: ~h[0xaadf829c5a142f1fccd7d8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcf],
              transaction_index: 0,
              address: ~h[0x16c5785ac562ff41e2dcfdf829c5a142f1fccd7d],
              data: ~h[0x0000000000000000000000000000000000000000000000000000000000000000],
              topics: [
                ~h[0x59ebeb90bc63057b6515673c3ecf9438e5058bca0f92585014eced636878c9a5]
              ]
            }
          ],
          logs_bloom: ~h[0x00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001],
          type: 0x02,
          status: 0x01,
        }
      }

      iex> Cartouche.RPC.get_trx_receipt("0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2")
      {:ok, %Cartouche.Receipt{
        transaction_hash: ~h[0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2],
        transaction_index: 0,
        block_hash: ~h[0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca],
        block_number: 10493428,
        from: ~h[0xb03d1100c68e58aa1895f8c1f230c0851ff41851],
        to: ~h[0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97],
        cumulative_gas_used: 222642,
        effective_gas_price: 1200000010,
        gas_used: 222642,
        contract_address: nil,
        logs: [
          %Cartouche.Receipt.Log{
            log_index: 0,
            block_number: 10493428,
            block_hash: ~h[0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca],
            transaction_hash: ~h[0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2],
            transaction_index: 0,
            address: ~h[0x9d8ec03e9ddb71f04da9db1e38837aaac1782a97],
            data: ~h[0x000000000000000000000000cb372382aa9a9e6f926714f4305afac4566f75380000000000000000000000000000000000000000000000000000000000000000],
            topics: [
              ~h[0x3ffe5de331422c5ec98e2d9ced07156f640bb51e235ef956e50263d4b28d3ae4],
              ~h[0x0000000000000000000000002326aba712500ae3114b664aeb51dba2c2fb416d],
              ~h[0x0000000000000000000000002326aba712500ae3114b664aeb51dba2c2fb416d]
            ]
          },
          %Cartouche.Receipt.Log{
            log_index: 1,
            block_number: 10493428,
            block_hash: ~h[0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca],
            transaction_hash: ~h[0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2],
            transaction_index: 0,
            address: ~h[0xcb372382aa9a9e6f926714f4305afac4566f7538],
            data: ~h[0x0000000000000000000000000000000000000000000000000000000000000000],
            topics: [
              ~h[0xe0d20d95fbbe7375f6edead77b5ce5c5b096e7dac85848c45c37a95eaf17fe62],
              ~h[0x0000000000000000000000009d8ec03e9ddb71f04da9db1e38837aaac1782a97],
              ~h[0x00000000000000000000000054f0a87eb5c8c8ba70243de1ac19e735b41b10a2],
              ~h[0x0000000000000000000000000000000000000000000000000000000000000000]
            ]
          },
          %Cartouche.Receipt.Log{
            log_index: 2,
            block_number: 10493428,
            block_hash: ~h[0x4bc3c26b1a599ced9876d9bf9a17c9bd58ec8b71a68e75335de7f2820e9336ca],
            transaction_hash: ~h[0xf9e69be4f1ae524854e14dc820c519d8f2b86e52c60e54448abf920d22fb6fe2],
            transaction_index: 0,
            address: ~h[0xcb372382aa9a9e6f926714f4305afac4566f7538],
            data: <<>>,
            topics: [
              ~h[0x0000000000000000000000000000000000000000000000000000000000000055]
            ]
          }
        ],
        logs_bloom: ~h[0x00800000000000000000000400000000000000000000000000000000000000000000000000000000000000000000002000200040000000000000000200001000000000000000000000000000000000000000000000000000000000000010000000008000020000004000000200000800000000000000000000220000000000000000000000000800000000000400000000000000000000000000000000000000000000040000000000008000008000000000000000000000000000000004000000800000000000004000000000000000000000000000000004080000000020000000000000000080000000000000000000000000000000000000000000000000],
        type: 0,
        status: 1
      }}

      iex> Cartouche.RPC.get_trx_receipt(<<1::256>>)
      {:error, "failed to decode `eth_getTransactionReceipt` response: %FunctionClauseError{module: Cartouche.Hex, function: :decode_hex_, arity: 1, kind: nil, args: nil, clauses: nil}"}

      iex> Cartouche.RPC.get_trx_receipt(<<1::256>>, verbose: true)
      {:error, "failed to decode `eth_getTransactionReceipt` response: %FunctionClauseError{module: Cartouche.Hex, function: :decode_hex_, arity: 1, kind: nil, args: nil, clauses: nil}"}

      iex> Cartouche.RPC.get_trx_receipt(<<2::256>>)
      {:ok, nil}
  """
  @spec get_trx_receipt(binary() | String.t(), Keyword.t()) ::
          {:ok, Cartouche.Receipt.t() | nil} | {:error, term()}
  def get_trx_receipt(trx_id, opts \\ [])

  def get_trx_receipt("0x" <> _ = trx_id, opts) when byte_size(trx_id) == 66,
    do: get_trx_receipt(Hex.from_hex!(trx_id), opts)

  def get_trx_receipt(<<_::256>> = trx_id, opts) do
    send_rpc(
      "eth_getTransactionReceipt",
      [Hex.encode_big_hex(trx_id)],
      Keyword.put(opts, :decode, fn
        nil ->
          nil

        receipt_params ->
          Cartouche.Receipt.deserialize(receipt_params)
      end)
    )
  end

  api(:eth_get_transaction_by_hash, "Fetch one transaction by hash (eth_getTransactionByHash).",
    params: [
      tx_hash: [kind: :value, description: "0x-prefixed 32-byte transaction hash."],
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, %Cartouche.Transaction.Info{}}`, `{:error, :not_found}` when the node returns null, or `{:error, reason}`."
    }
  )

  @doc """
  Returns the transaction identified by `tx_hash`.

  Defined by `execution-apis` v1.0.0-beta.7 (`src/eth/transaction.yaml`,
  `eth_getTransactionByHash`). The result is a `Cartouche.Transaction.Info`
  envelope: inclusion metadata plus the typed transaction from
  `Vn.from_json/1`. Block fields are `nil` when the transaction is pending.
  A null result is `{:error, :not_found}`.
  """
  @spec eth_get_transaction_by_hash(String.t(), Keyword.t()) ::
          {:ok, Transaction.Info.t()} | {:error, term()}
  def eth_get_transaction_by_hash(tx_hash, opts \\ []) do
    with {:ok, tx_hash} <- Helpers.ensure_tx_hash(tx_hash),
         {:ok, result} <- send_rpc("eth_getTransactionByHash", [tx_hash], opts) do
      decode_transaction_info(result)
    end
  end

  api(
    :eth_get_transaction_by_block_hash_and_index,
    "Fetch one transaction by block hash and position (eth_getTransactionByBlockHashAndIndex).",
    params: [
      block_hash: [kind: :value, description: "0x-prefixed 32-byte block hash."],
      transaction_index: [kind: :value, description: "Zero-based non-negative integer or 0x quantity."],
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, %Cartouche.Transaction.Info{}}`, `{:error, :not_found}` when the node returns null, or `{:error, reason}`."
    }
  )

  @doc """
  Returns the transaction at `transaction_index` in the block identified by `block_hash`.

  Defined by `execution-apis` v1.0.0-beta.7 (`src/eth/transaction.yaml`,
  `eth_getTransactionByBlockHashAndIndex`). Same envelope as
  `eth_get_transaction_by_hash/2`. A null result is `{:error, :not_found}`.
  """
  @spec eth_get_transaction_by_block_hash_and_index(String.t(), non_neg_integer() | String.t(), Keyword.t()) ::
          {:ok, Transaction.Info.t()} | {:error, term()}
  def eth_get_transaction_by_block_hash_and_index(block_hash, transaction_index, opts \\ []) do
    with {:ok, block_hash} <- ensure_block_hash(block_hash),
         {:ok, transaction_index} <- normalize_transaction_index(transaction_index),
         {:ok, result} <-
           send_rpc("eth_getTransactionByBlockHashAndIndex", [block_hash, transaction_index], opts) do
      decode_transaction_info(result)
    end
  end

  api(
    :eth_get_transaction_by_block_number_and_index,
    "Fetch one transaction by block number or tag and position (eth_getTransactionByBlockNumberAndIndex).",
    params: [
      block: [kind: :value, description: "Non-negative block number, 0x quantity, or block tag."],
      transaction_index: [kind: :value, description: "Zero-based non-negative integer or 0x quantity."],
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, %Cartouche.Transaction.Info{}}`, `{:error, :not_found}` when the node returns null, or `{:error, reason}`."
    }
  )

  @doc """
  Returns the transaction at `transaction_index` in the block identified by number or tag.

  Defined by `execution-apis` v1.0.0-beta.7 (`src/eth/transaction.yaml`,
  `eth_getTransactionByBlockNumberAndIndex`). Same envelope as
  `eth_get_transaction_by_hash/2`. A null result is `{:error, :not_found}`.
  """
  @spec eth_get_transaction_by_block_number_and_index(integer() | String.t(), non_neg_integer() | String.t(), Keyword.t()) ::
          {:ok, Transaction.Info.t()} | {:error, term()}
  def eth_get_transaction_by_block_number_and_index(block, transaction_index, opts \\ []) do
    with {:ok, block} <- Helpers.normalize_block(block),
         {:ok, transaction_index} <- normalize_transaction_index(transaction_index),
         {:ok, result} <-
           send_rpc("eth_getTransactionByBlockNumberAndIndex", [block, transaction_index], opts) do
      decode_transaction_info(result)
    end
  end

  api(:eth_get_block_receipts, "Fetch every receipt in a block (eth_getBlockReceipts).",
    params: [
      block: [
        kind: :value,
        description: "Block number, tag, or 0x-prefixed block hash."
      ],
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, [%Cartouche.Receipt{}]}` decoded by `Cartouche.Receipt.deserialize/1`, `{:ok, nil}` when the block is unknown, or `{:error, reason}`."
    }
  )

  @doc """
  Returns every receipt in the block identified by number, tag, or hash.

  Defined by `execution-apis` v1.0.0-beta.7 (`src/eth/block.yaml`,
  `eth_getBlockReceipts`). Each receipt is decoded by
  `Cartouche.Receipt.deserialize/1`, the same decoder as `get_trx_receipt/2`.
  A null result is `{:ok, nil}`.
  """
  @spec eth_get_block_receipts(integer() | String.t(), Keyword.t()) ::
          {:ok, [Cartouche.Receipt.t()] | nil} | {:error, term()}
  def eth_get_block_receipts(block, opts \\ []) do
    with {:ok, block} <- Helpers.normalize_block(block) do
      send_rpc(
        "eth_getBlockReceipts",
        [block],
        Keyword.put(opts, :decode, &decode_block_receipts/1)
      )
    end
  end

  # Null is an unknown hash or index, distinct from a pending transaction whose
  # block fields are nil. Decode after `send_rpc/3` so a malformed object stays
  # `{:error, reason}` instead of being wrapped by the transport decode callback.
  @spec decode_transaction_info(term()) :: {:ok, Transaction.Info.t()} | {:error, term()}
  defp decode_transaction_info(nil), do: {:error, :not_found}
  defp decode_transaction_info(%{} = transaction), do: Transaction.Info.decode(transaction)
  defp decode_transaction_info(other), do: {:error, {:unexpected_transaction, other}}

  @spec decode_block_receipts(term()) :: [Cartouche.Receipt.t()] | nil
  defp decode_block_receipts(nil), do: nil

  defp decode_block_receipts(receipts) when is_list(receipts) do
    Enum.map(receipts, &Cartouche.Receipt.deserialize/1)
  end

  defp decode_block_receipts(other) do
    raise ArgumentError, "eth_getBlockReceipts result must be a list or null, got: #{inspect(other)}"
  end

  @spec normalize_transaction_index(term()) ::
          {:ok, String.t()} | {:error, {:invalid_transaction_index, term()}}
  defp normalize_transaction_index(index) when is_integer(index) and index >= 0, do: {:ok, Hex.encode_quantity(index)}

  defp normalize_transaction_index("0x" <> _ = index) do
    if Onchain.Hex.valid?(index),
      do: {:ok, index},
      else: {:error, {:invalid_transaction_index, index}}
  end

  defp normalize_transaction_index(index), do: {:error, {:invalid_transaction_index, index}}

  api(:trace_trx, "Fetch parity-style traces for a transaction by transaction hash.",
    params: [
      trx_id: [
        kind: :value,
        description: "Transaction hash as a 32-byte binary or a 0x-prefixed 66-character hex string."
      ],
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, [%Cartouche.Trace{}]}` decoded by `Cartouche.Trace.deserialize_many/1`, or `{:error, reason}`."
    }
  )

  @doc """
  RPC call to get a transaction receipt

  ## Examples

      iex> Cartouche.RPC.trace_trx("0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5")
      {:ok,
        [
        %Cartouche.Trace{
          action: %Cartouche.Trace.Action{
            call_type: "call",
            from: ~h[0x83806d539d4ea1c140489a06660319c9a303f874],
            gas: 0x01a1f8,
            input: <<>>,
            to: ~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750],
            value: 0x7a16c911b4d00000,
          },
          block_hash: ~h[0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add],
          block_number: 3068185,
          gas_used: 0x2982,
          output: <<>>,
          subtraces: 2,
          trace_address: [~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750]],
          transaction_hash: ~h[0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3],
          transaction_position: 2,
          type: "call"
        },
        %Cartouche.Trace{
          action: %Cartouche.Trace.Action{
            call_type: "call",
            from: ~h[0x83806d539d4ea1c140489a06660319c9a303f874],
            gas: 0x01a1f8,
            input: <<>>,
            to: ~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750],
            value: 0x7a16c911b4d00000,
          },
          block_hash: ~h[0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add],
          block_number: 3068186,
          gas_used: 0x2982,
          output: <<>>,
          subtraces: 2,
          trace_address: [~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750]],
          transaction_hash: ~h[0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3],
          transaction_position: 2,
          type: "call"
        }
      ]}
  """
  @spec trace_trx(binary() | String.t(), Keyword.t()) ::
          {:ok, [Cartouche.Trace.t()]} | {:error, term()}
  def trace_trx(trx_id, opts \\ [])

  def trace_trx("0x" <> _ = trx_id, opts) when byte_size(trx_id) == 66, do: trace_trx(Hex.decode_hex!(trx_id), opts)

  def trace_trx(<<_::256>> = trx_id, opts) do
    send_rpc(
      "trace_transaction",
      [Hex.encode_big_hex(trx_id)],
      Keyword.put(opts, :decode, &Cartouche.Trace.deserialize_many/1)
    )
  end

  api(:trace_call, "Trace a transaction call speculatively with the parity trace API.",
    params: [
      trx: [
        kind: :value,
        description: "`Cartouche.Transaction.V1`, `Cartouche.Transaction.V2`, or `Cartouche.Transaction.Call` to trace."
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          ~s{Keyword options including optional `:from`, block selector `:block_number` (`"latest"`, `"pending"`, or integer), and transport options.}
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, %Cartouche.TraceCall{trace: [%Cartouche.Trace{}]}}` decoded by `Cartouche.TraceCall.deserialize/1`, or `{:error, reason}`."
    }
  )

  @doc """
  RPC to trace a transaction call speculatively.

  ## Examples

      iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      ...> |> Cartouche.RPC.trace_call()
      {:ok,
        %Cartouche.TraceCall{
          output: "",
          state_diff: nil,
          trace: [
            %Cartouche.Trace{
              action: %Cartouche.Trace.Action{
                call_type: "call",
                init: nil,
                from: <<0::160>>,
                gas: 499_978_072,
                input: ~h[0xd1692f56000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612000000000000000000000000142da9114e5a98e015aa95afca0585e84832a6120000000000000000000000000000000000000000000000000000000000000000],
                to: ~h[0x13172EE393713FBA9925A9A752341EBD31E8D9A7],
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: 492_166_471,
              error: "Reverted",
              output: "",
              result_code: nil,
              result_address: nil,
              subtraces: 1,
              trace_address: [],
              transaction_hash: nil,
              transaction_position: nil,
              type: "call"
            },
            %Cartouche.Trace{
              action: %Cartouche.Trace.Action{
                call_type: nil,
                init: ~h[0x60e03461009157601f6101ec38819003918201601f19168301916001600160401b038311848410176100965780849260609460405283398101031261009157610047816100ac565b906100606040610059602084016100ac565b92016100ac565b9060805260a05260c05260405161012b90816100c18239608051816088015260a051816045015260c0518160c60152f35b600080fd5b634e487b7160e01b600052604160045260246000fd5b51906001600160a01b03821682036100915756fe608060405260043610156013575b3660ba57005b6000803560e01c8063238ac9331460775763c34c08e51460325750600d565b34607457806003193601126074576040517f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03168152602090f35b80fd5b5034607457806003193601126074577f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03166080908152602090f35b600036818037808036817f00000000000000000000000000000000000000000000000000000000000000005af4903d918282803e60f357fd5bf3fea264697066735822122032b5603d6937ceb7a252e16379744d8545670ff4978c8d76c985d051dfcfe46c64736f6c6343000817003300000000000000000000000049e5d261e95f6a02505078bb339fecb210a0b634000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612],
                from: ~h[0x13172EE393713FBA9925A9A752341EBD31E8D9A7],
                gas: 492_133_529,
                input: nil,
                to: nil,
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: nil,
              error: "contract address collision",
              output: nil,
              result_code: nil,
              result_address: nil,
              subtraces: 0,
              trace_address: [0],
              transaction_hash: nil,
              transaction_position: nil,
              type: "create"
            }
          ],
          vm_trace: nil
        }
      }

      iex> Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
      ...> |> Cartouche.RPC.trace_call()
      {:ok,
        %Cartouche.TraceCall{
          output: "",
          state_diff: nil,
          trace: [
            %Cartouche.Trace{
              action: %Cartouche.Trace.Action{
                call_type: "call",
                init: nil,
                from: <<0::160>>,
                gas: 499_978_072,
                input: ~h[0xd1692f56000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612000000000000000000000000142da9114e5a98e015aa95afca0585e84832a6120000000000000000000000000000000000000000000000000000000000000000],
                to: ~h[0x13172EE393713FBA9925A9A752341EBD31E8D9A7],
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: 492_166_471,
              error: "Reverted",
              output: "",
              result_code: nil,
              result_address: nil,
              subtraces: 1,
              trace_address: [],
              transaction_hash: nil,
              transaction_position: nil,
              type: "call"
            },
            %Cartouche.Trace{
              action: %Cartouche.Trace.Action{
                call_type: nil,
                init: ~h[0x60e03461009157601f6101ec38819003918201601f19168301916001600160401b038311848410176100965780849260609460405283398101031261009157610047816100ac565b906100606040610059602084016100ac565b92016100ac565b9060805260a05260c05260405161012b90816100c18239608051816088015260a051816045015260c0518160c60152f35b600080fd5b634e487b7160e01b600052604160045260246000fd5b51906001600160a01b03821682036100915756fe608060405260043610156013575b3660ba57005b6000803560e01c8063238ac9331460775763c34c08e51460325750600d565b34607457806003193601126074576040517f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03168152602090f35b80fd5b5034607457806003193601126074577f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03166080908152602090f35b600036818037808036817f00000000000000000000000000000000000000000000000000000000000000005af4903d918282803e60f357fd5bf3fea264697066735822122032b5603d6937ceb7a252e16379744d8545670ff4978c8d76c985d051dfcfe46c64736f6c6343000817003300000000000000000000000049e5d261e95f6a02505078bb339fecb210a0b634000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612],
                from: ~h[0x13172EE393713FBA9925A9A752341EBD31E8D9A7],
                gas: 492_133_529,
                input: nil,
                to: nil,
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: nil,
              error: "contract address collision",
              output: nil,
              result_code: nil,
              result_address: nil,
              subtraces: 0,
              trace_address: [0],
              transaction_hash: nil,
              transaction_position: nil,
              type: "create"
            }
          ],
          vm_trace: nil
        }
      }
  """
  @spec trace_call(V1.t() | V2.t() | Call.t(), Keyword.t()) ::
          {:ok, Cartouche.TraceCall.t()} | {:error, term()}
  def trace_call(trx, opts \\ []) do
    from = Keyword.get(opts, :from)
    block_number = opts |> Keyword.get(:block_number, "latest") |> normalize_block_param()

    send_rpc(
      "trace_call",
      [to_call_params(trx, from), ["trace"], block_number],
      Keyword.put(opts, :decode, &Cartouche.TraceCall.deserialize/1)
    )
  end

  api(:trace_call_many, "Trace multiple transaction calls speculatively with the parity trace API.",
    params: [
      trxs: [
        kind: :value,
        description:
          "List of transaction structs, call structs, or `{trx, from}` pairs; per-item `from` overrides the shared `:from` option."
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          ~s{Keyword options including optional shared `:from`, block selector `:block_number` (`"latest"`, `"pending"`, or integer), and transport options.}
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, [%Cartouche.TraceCall{}]}` decoded by `Cartouche.TraceCall.deserialize_many/1`, or `{:error, reason}`."
    }
  )

  @doc """
  RPC to trace many transaction calls speculatively.

  ## Examples

      iex> t1 = Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      iex> t2 = Cartouche.Transaction.V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [<<2::160>>, <<3::160>>], :goerli)
      iex> Cartouche.RPC.trace_call_many([t1, t2])
      {:ok, [
        %Cartouche.TraceCall{
          output: "",
          state_diff: nil,
          trace: [
            %Cartouche.Trace{
              action: %Cartouche.Trace.Action{
                call_type: "call",
                init: nil,
                from: <<0::160>>,
                gas: 499_978_072,
                input: ~h[0xd1692f56000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612000000000000000000000000142da9114e5a98e015aa95afca0585e84832a6120000000000000000000000000000000000000000000000000000000000000000],
                to: ~h[0x13172EE393713FBA9925A9A752341EBD31E8D9A7],
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: 492_166_471,
              error: "Reverted",
              output: "",
              result_code: nil,
              result_address: nil,
              subtraces: 1,
              trace_address: [],
              transaction_hash: nil,
              transaction_position: nil,
              type: "call"
            },
            %Cartouche.Trace{
              action: %Cartouche.Trace.Action{
                call_type: nil,
                init: ~h[0x60e03461009157601f6101ec38819003918201601f19168301916001600160401b038311848410176100965780849260609460405283398101031261009157610047816100ac565b906100606040610059602084016100ac565b92016100ac565b9060805260a05260c05260405161012b90816100c18239608051816088015260a051816045015260c0518160c60152f35b600080fd5b634e487b7160e01b600052604160045260246000fd5b51906001600160a01b03821682036100915756fe608060405260043610156013575b3660ba57005b6000803560e01c8063238ac9331460775763c34c08e51460325750600d565b34607457806003193601126074576040517f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03168152602090f35b80fd5b5034607457806003193601126074577f00000000000000000000000000000000000000000000000000000000000000006001600160a01b03166080908152602090f35b600036818037808036817f00000000000000000000000000000000000000000000000000000000000000005af4903d918282803e60f357fd5bf3fea264697066735822122032b5603d6937ceb7a252e16379744d8545670ff4978c8d76c985d051dfcfe46c64736f6c6343000817003300000000000000000000000049e5d261e95f6a02505078bb339fecb210a0b634000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612000000000000000000000000142da9114e5a98e015aa95afca0585e84832a612],
                from: ~h[0x13172EE393713FBA9925A9A752341EBD31E8D9A7],
                gas: 492_133_529,
                input: nil,
                to: nil,
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: nil,
              error: "contract address collision",
              output: nil,
              result_code: nil,
              result_address: nil,
              subtraces: 0,
              trace_address: [0],
              transaction_hash: nil,
              transaction_position: nil,
              type: "create"
            }
          ],
          vm_trace: nil
        },
        %Cartouche.TraceCall{
          output: ~h[0x00000000000000000000000079EDBC4F3A6AA2266CD469CC544501743BE8B078],
          state_diff: nil,
          trace: [
            %Cartouche.Trace{
              action: %Cartouche.Trace.Action{
                call_type: "call",
                init: nil,
                from: <<0::160>>,
                gas: 499_945_916,
                input: ~h[0xd6d38d3f0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000081a60808060405234610016576107fe908161001c8239f35b600080fdfe6040608081526004908136101561001557600080fd5b600091823560e01c80630c0a769b146102eb57806350a4548914610255578063c3da3590146100fc5763f1afb11f1461004d57600080fd5b8291346100f85760803660031901126100f857610068610389565b61007061039f565b6100786103b5565b6001600160a01b03908116929091606435918390610097848288610482565b1693843b156100f457879460649386928851998a978896634232cd6360e01b88521690860152602485015260448401525af19081156100eb57506100d85750f35b6100e1906103fc565b6100e85780f35b80fd5b513d84823e3d90fd5b8780fd5b5050fd5b503461025157606036600319011261025157610116610389565b67ffffffffffffffff929060243584811161024d5761013890369085016103cb565b9190946044359081116102495761015290369086016103cb565b9590928681036102395791958793926001600160a01b0380891693909290865b83811061017d578780f35b6101a88561019461018f848887610448565b61046e565b168c6101a184878c610448565b3591610482565b6101b661018f828685610448565b6101c182858a610448565b3590873b15610235578a51631e573fb760e31b81526001600160a01b03909116818d019081526020810192909252908990829081906040010381838b5af1801561022b57908991610217575b5050600101610172565b610220906103fc565b6100f457873861020d565b8a513d8b823e3d90fd5b8980fd5b845163b4fa3fb360e01b81528690fd5b8680fd5b8580fd5b8280fd5b50346102515760a03660031901126102515761026f610389565b9161027861039f565b6102806103b5565b906001600160a01b039060643582811691908290036102e6578288971693843b156100f457879460849385879389519a8b988997639032317760e01b895216908701521660248501526044840152833560648401525af19081156100eb57506100d85750f35b600080fd5b5090346102515760603660031901126102515782610307610389565b61030f61039f565b604435916001600160a01b03906103298482858516610482565b1690813b15610385578451631e573fb760e31b81526001600160a01b039091169581019586526020860192909252909384919082908490829060400103925af19081156100eb5750610379575080f35b610382906103fc565b80f35b8380fd5b600435906001600160a01b03821682036102e657565b602435906001600160a01b03821682036102e657565b604435906001600160a01b03821682036102e657565b9181601f840112156102e65782359167ffffffffffffffff83116102e6576020808501948460051b0101116102e657565b67ffffffffffffffff811161041057604052565b634e487b7160e01b600052604160045260246000fd5b90601f8019910116810190811067ffffffffffffffff82111761041057604052565b91908110156104585760051b0190565b634e487b7160e01b600052603260045260246000fd5b356001600160a01b03811681036102e65790565b60405163095ea7b360e01b602082018181526001600160a01b0385166024840152604480840196909652948252949390926104be606485610426565b83516000926001600160a01b039291858416918591829182855af1906104e26105a4565b82610572575b5081610567575b50156104ff575b50505050509050565b60405196602088015216602486015280604486015260448552608085019085821067ffffffffffffffff8311176105535750610548939461054391604052826105fc565b6105fc565b8038808080806104f6565b634e487b7160e01b81526041600452602490fd5b90503b1515386104ef565b8051919250811591821561058a575b505090386104e8565b61059d92506020809183010191016105e4565b3880610581565b3d156105df573d9067ffffffffffffffff821161041057604051916105d3601f8201601f191660200184610426565b82523d6000602084013e565b606090565b908160209103126102e6575180151581036102e65790565b60408051908101916001600160a01b031667ffffffffffffffff8311828410176104105761066c926040526000806020958685527f5361666545524332303a206c6f772d6c6576656c2063616c6c206661696c656487860152868151910182855af16106666105a4565b916106f4565b8051908282159283156106dc575b505050156106855750565b6084906040519062461bcd60e51b82526004820152602a60248201527f5361666545524332303a204552433230206f7065726174696f6e20646964206e6044820152691bdd081cdd58d8d9595960b21b6064820152fd5b6106ec93508201810191016105e4565b38828161067a565b919290156107565750815115610708575090565b3b156107115790565b60405162461bcd60e51b815260206004820152601d60248201527f416464726573733a2063616c6c20746f206e6f6e2d636f6e74726163740000006044820152606490fd5b8251909150156107695750805190602001fd5b6040519062461bcd60e51b82528160208060048301528251908160248401526000935b8285106107af575050604492506000838284010152601f80199101168101030190fd5b848101820151868601604401529381019385935061078c56fea264697066735822122065151e6cccce6828ff0901f46ab142cb8aa214fc37379817e3635a556dd638a564736f6c63430008170033000000000000],
                to: ~h[0x2926631647877E9A84BB7E3A0821D643BF8D63C0],
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: 4298,
              error: nil,
              output: ~h[0x00000000000000000000000079EDBC4F3A6AA2266CD469CC544501743BE8B078],
              result_code: nil,
              result_address: nil,
              subtraces: 0,
              trace_address: [],
              transaction_hash: nil,
              transaction_position: nil,
              type: "call"
            }
          ],
          vm_trace: nil
        },
        %Cartouche.TraceCall{
          output: <<130, 180, 41, 0>>,
          state_diff: nil,
          trace: [
            %Cartouche.Trace{
              action: %Cartouche.Trace.Action{
                call_type: "call",
                init: nil,
                from: <<0::160>>,
                gas: 499_977_072,
                input: ~h[0xdd560874000000000000000000000000000000000000000000000000000000000000000400000000000000000000000079edbc4f3a6aa2266cd469cc544501743be8b078000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000640c0a769b000000000000000000000000aec1f48e02cfb822be958b68c7957156eb3f0b6e0000000000000000000000001c7d4b196cb0c7b01d743fbc6116a902379c723800000000000000000000000000000000000000000000000000000000000f429000000000000000000000000000000000000000000000000000000000],
                to: ~h[0x6E995746B61C48C5BDF58FC788B1AEA08DFB7E43],
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: 4202,
              error: "Reverted",
              output: ~h[0x82B42900],
              result_code: nil,
              result_address: nil,
              subtraces: 1,
              trace_address: [],
              transaction_hash: nil,
              transaction_position: nil,
              type: "call"
            },
            %Cartouche.Trace{
              action: %Cartouche.Trace.Action{
                call_type: "delegatecall",
                init: nil,
                from: ~h[0x6E995746B61C48C5BDF58FC788B1AEA08DFB7E43],
                gas: 492_162_171,
                input: ~h[0xdd560874000000000000000000000000000000000000000000000000000000000000000400000000000000000000000079edbc4f3a6aa2266cd469cc544501743be8b078000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000640c0a769b000000000000000000000000aec1f48e02cfb822be958b68c7957156eb3f0b6e0000000000000000000000001c7d4b196cb0c7b01d743fbc6116a902379c723800000000000000000000000000000000000000000000000000000000000f429000000000000000000000000000000000000000000000000000000000],
                to: ~h[0x49E5D261E95F6A02505078BB339FECB210A0B634],
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: 1362,
              error: "Reverted",
              output: <<130, 180, 41, 0>>,
              result_code: nil,
              result_address: nil,
              subtraces: 1,
              trace_address: [0],
              transaction_hash: nil,
              transaction_position: nil,
              type: "call"
            },
            %Cartouche.Trace{
              action: %Cartouche.Trace.Action{
                call_type: "staticcall",
                init: nil,
                from: ~h[0x6E995746B61C48C5BDF58FC788B1AEA08DFB7E43],
                gas: 484_471_386,
                input: ~h[0xC34C08E5],
                to: ~h[0x6E995746B61C48C5BDF58FC788B1AEA08DFB7E43],
                value: 0
              },
              block_hash: nil,
              block_number: nil,
              gas_used: 190,
              error: nil,
              output: ~h[0x000000000000000000000000142DA9114E5A98E015AA95AFCA0585E84832A612],
              result_code: nil,
              result_address: nil,
              subtraces: 0,
              trace_address: [0, 0],
              transaction_hash: nil,
              transaction_position: nil,
              type: "call"
            }
          ],
          vm_trace: nil
        }
      ]}
  """
  @spec trace_call_many([V1.t() | V2.t() | Call.t() | {V1.t() | V2.t() | Call.t(), <<_::160>> | nil}], Keyword.t()) ::
          {:ok, [Cartouche.TraceCall.t()]} | {:error, term()}
  def trace_call_many(trxs, opts \\ []) do
    from = Keyword.get(opts, :from)
    block_number = opts |> Keyword.get(:block_number, "latest") |> normalize_block_param()

    send_rpc(
      "trace_callMany",
      [
        Enum.map(
          trxs,
          fn
            {trx, from} -> [to_call_params(trx, from), ["trace"]]
            trx -> [to_call_params(trx, from), ["trace"]]
          end
        ),
        block_number
      ],
      Keyword.put(opts, :decode, &Cartouche.TraceCall.deserialize_many/1)
    )
  end

  api(:debug_trace_call, "Trace a transaction call speculatively with the debug trace API.",
    params: [
      trx: [
        kind: :value,
        description: "`Cartouche.Transaction.V1`, `Cartouche.Transaction.V2`, or `Cartouche.Transaction.Call` to trace."
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          ~s{Keyword options including optional `:from`, block selector `:block_number` (`"latest"`, `"pending"`, or integer), and transport options.}
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, %Cartouche.DebugTrace{struct_logs: [%Cartouche.DebugTrace.StructLog{}]}}` decoded by `Cartouche.DebugTrace.deserialize/1`, or `{:error, reason}`."
    }
  )

  @doc """
  RPC to trace a transaction call speculatively via debug API.

  ## Examples

      iex> Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      ...> |> Cartouche.RPC.debug_trace_call()
      {:ok,
        %Cartouche.DebugTrace{
        failed: false,
        gas: 24034,
        return_value: ~h[0x0000000000000000000000000000000000000000000000000858898f93629000],
        struct_logs: [
          %Cartouche.DebugTrace.StructLog{
            depth: 1,
            gas: 599978568,
            gas_cost: 3,
            op: :PUSH1,
            pc: 0,
            stack: []
          },
          %Cartouche.DebugTrace.StructLog{
            depth: 1,
            gas: 599978565,
            gas_cost: 3,
            op: :PUSH1,
            pc: 2,
            stack: [~h[0x80]]
          },
          %Cartouche.DebugTrace.StructLog{
            depth: 1,
            gas: 599978562,
            gas_cost: 12,
            op: :MSTORE,
            pc: 4,
            stack: [~h[0x80], ~h[0x40]]
          }
        ]
      }}
  """
  @spec debug_trace_call(V1.t() | V2.t() | Call.t(), Keyword.t()) ::
          {:ok, Cartouche.DebugTrace.t()} | {:error, term()}
  def debug_trace_call(trx, opts \\ []) do
    from = Keyword.get(opts, :from)
    block_number = opts |> Keyword.get(:block_number, "latest") |> normalize_block_param()

    send_rpc(
      "debug_traceCall",
      [to_call_params(trx, from), block_number],
      Keyword.put(opts, :decode, &Cartouche.DebugTrace.deserialize/1)
    )
  end

  defrpc(:gas_price, "eth_gasPrice",
    decode: :hex_unsigned,
    summary: "Fetch the current legacy gas price.",
    returns_desc: "`{:ok, wei_per_gas}` decoded from `eth_gasPrice`, or `{:error, reason}`.",
    doc: ~S"""
    RPC call to call to get the current gas price.

    ## Examples

        iex> Cartouche.RPC.gas_price()
        {:ok, 1000000000}
    """
  )

  api(:eth_get_storage_at, "Read a 32-byte contract storage word.",
    params: [
      address: [kind: :value, description: "Hex address or 20-byte binary."],
      slot: [kind: :value, description: "Hex storage position, up to 32 bytes."],
      opts: [kind: :value, default: [], description: "Options: :block and send_rpc/3 transport options."]
    ],
    returns: %{type: :ok_error_tuple, description: "32-byte binary or an error."}
  )

  @doc """
  Reads a 32-byte storage word via `eth_getStorageAt` (execution-apis v1.0.0-beta.7).

  Accepts a hex slot of up to 32 bytes, including leading zeroes. `:block` selects
  a block number or tag (default `"latest"`). Returns raw bytes.

  Observed 2026-10-01: Alchemy mainnet and the archive node returned DAI slot 1
  at block 18,000,000; Alchemy also returned zero at block 1 (before deployment).
  This does not establish an unlimited history guarantee. Verbatim responses
  and refusals are recorded in `docs/state-read-portability.md`.
  """
  @spec eth_get_storage_at(String.t() | binary(), String.t(), keyword()) ::
          {:ok, <<_::256>>} | {:error, term()}
  def eth_get_storage_at(address, slot, opts \\ []) do
    with {:ok, address} <- Helpers.ensure_hex_address(address),
         {:ok, slot} <- normalize_storage_slot(slot),
         {:ok, block} <- Helpers.normalize_block(Keyword.get(opts, :block, "latest")) do
      send_rpc("eth_getStorageAt", [address, slot, block], Keyword.put(opts, :decode, &Hex.decode_word!/1))
    end
  end

  api(:eth_get_proof, "Fetch an EIP-1186 account and storage proof.",
    params: [
      address: [kind: :value, description: "Hex address or 20-byte binary."],
      storage_keys: [kind: :value, description: "List of hex storage keys of up to 32 bytes."],
      opts: [kind: :value, default: [], description: "Options: :block and send_rpc/3 transport options."]
    ],
    returns: %{type: :ok_error_tuple, description: "Cartouche.RPC.Proof struct or an error."}
  )

  @doc """
  Fetches an EIP-1186 account and storage proof as `Cartouche.RPC.Proof`.

  Defined by execution-apis v1.0.0-beta.7. Keys are hex strings of 1 to 64
  digits, left-padded to 32 bytes on the wire;
  `:block` selects a block number or tag (default `"latest"`). Quantities decode
  to integers and addresses, hashes and proof nodes to bytes. No local Merkle
  verification is performed.

  Observed 2026-10-01: Alchemy mainnet served DAI proofs at latest, block
  18,000,000 and block 1 (before deployment, with empty storage proof nodes).
  The archive node served latest but refused both historical blocks with
  `-32602`, `"distance to target block exceeds maximum proof window"`.
  Availability is endpoint-specific; node refusals propagate unchanged.
  See `docs/state-read-portability.md` for verbatim evidence.
  """
  @spec eth_get_proof(String.t() | binary(), [String.t()], keyword()) ::
          {:ok, Proof.t()} | {:error, term()}
  def eth_get_proof(address, storage_keys, opts \\ []) do
    with {:ok, address} <- Helpers.ensure_hex_address(address),
         {:ok, keys} <- validate_storage_keys(storage_keys),
         {:ok, block} <- Helpers.normalize_block(Keyword.get(opts, :block, "latest")) do
      send_rpc("eth_getProof", [address, keys, block], Keyword.put(opts, :decode, &Proof.deserialize/1))
    end
  end

  @spec normalize_storage_slot(term()) :: {:ok, String.t()} | {:error, {:invalid_slot, term()}}
  defp normalize_storage_slot("0x" <> digits = slot) when byte_size(digits) in 1..64 do
    if Regex.match?(@hex_digits, digits), do: {:ok, String.downcase(slot)}, else: {:error, {:invalid_slot, slot}}
  end

  defp normalize_storage_slot(slot), do: {:error, {:invalid_slot, slot}}

  @spec validate_storage_keys(term()) ::
          {:ok, [String.t()]}
          | {:error, {:invalid_storage_keys, term()} | {:invalid_storage_key, term()}}
  defp validate_storage_keys(keys) when is_list(keys) do
    keys
    |> Enum.reduce_while({:ok, []}, fn key, {:ok, acc} ->
      case normalize_storage_slot(key) do
        {:ok, "0x" <> digits} -> {:cont, {:ok, ["0x" <> String.pad_leading(digits, 64, "0") | acc]}}
        {:error, _} -> {:halt, {:error, {:invalid_storage_key, key}}}
      end
    end)
    |> case do
      {:ok, keys} -> {:ok, Enum.reverse(keys)}
      error -> error
    end
  end

  defp validate_storage_keys(keys), do: {:error, {:invalid_storage_keys, keys}}

  api(:base_fee, "Fetch the EIP-1559 base fee per gas for the next block.",
    params: [opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]],
    returns: %{type: :ok_error_tuple, description: "`{:ok, wei_per_gas}` or `{:error, reason}`."}
  )

  @doc """
  Returns the next block's base fee in wei via `eth_feeHistory(1, "latest", [])`.

  The final `baseFeePerGas` entry is the next block's fee, as specified in
  execution-apis v1.0.0-beta.7. This avoids hosted endpoints' differing handling
  of the `pending` block tag. Uses the shared fee-history decoder and transport;
  node errors propagate unchanged. An incomplete fee window returns
  `{:error, :invalid_base_fee_history}`.

  `eth_baseFee` landed on execution-apis `main` on 2026-06-15, but is in no
  tagged release (latest verified: v1.0.0-beta.7). Alchemy and Infura mainnet
  refused it in live probes on 2026-10-01; see `docs/base-fee-portability.md`.
  """
  @spec base_fee(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def base_fee(opts \\ []) do
    opts = Keyword.merge(opts, block_count: "0x1", newest_block: "latest", reward_percentiles: [])

    case fee_history(opts) do
      {:ok, %Cartouche.FeeHistory{base_fee_per_gas: [_current, next]}} -> {:ok, next}
      {:ok, %Cartouche.FeeHistory{}} -> {:error, :invalid_base_fee_history}
      {:error, reason} -> {:error, reason}
    end
  end

  defrpc(:blob_base_fee, "eth_blobBaseFee",
    decode: :hex_unsigned,
    summary: "Fetch the current base fee per blob gas.",
    returns_desc: "`{:ok, wei_per_blob_gas}` decoded from `eth_blobBaseFee`, or the node's unchanged `{:error, reason}`.",
    doc: ~S"""
    RPC call to get the current base fee per blob gas.

    ## Examples

        iex> Cartouche.RPC.blob_base_fee()
        {:ok, 42}
    """
  )

  defrpc(:max_priority_fee_per_gas, "eth_maxPriorityFeePerGas",
    decode: :hex_unsigned,
    summary: "Fetch the current max priority fee per gas.",
    returns_desc: "`{:ok, max_priority_fee_per_gas}` decoded from `eth_maxPriorityFeePerGas`, or `{:error, reason}`.",
    doc: ~S"""
    RPC call to call to get the current max priority fee per gas.

    ## Examples

        iex> Cartouche.RPC.max_priority_fee_per_gas()
        {:ok, 1000000001}
    """
  )

  api(:fee_history, "Fetch and decode EIP-1559 fee history data.",
    params: [
      opts: [
        kind: :value,
        default: [],
        description:
          ~s{Keyword options including `:block_count`, `:newest_block` (`"latest"`, `"pending"`, integer, or hex quantity), `:reward_percentiles`, and transport options.}
      ]
    ],
    opts: [
      block_count: [kind: :value, default: 1, description: "Number of blocks to request in the fee history window."],
      newest_block: [kind: :value, default: "latest", description: "Newest block selector for the requested fee window."],
      reward_percentiles: [
        kind: :value,
        default: [],
        description: "Reward percentile list forwarded to `eth_feeHistory`."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, %Cartouche.FeeHistory{}}` decoded by `Cartouche.FeeHistory.deserialize/1`, or `{:error, reason}`."
    }
  )

  @doc """
  RPC call to call to get the Eip-1559 fee history data.

  ## Examples

      iex> Cartouche.RPC.fee_history()
      {:ok, %Cartouche.FeeHistory{
        base_fee_per_gas: [20566340803, 20460504186, 19629790325, 19239635811, 19090900440, 19048391846],
        gas_used_ratio: [0.4794155666666667, 0.3375966, 0.42049746666666665, 0.4690773, 0.49109343333333333],
        oldest_block: 16607861,
        reward: [[1000000000, 1000000000, 1500000000], [1000000000, 1000000000, 2000000000], [1000000000, 1000000000, 1000000000], [780000000, 1000000000, 2000000000], [1000000000, 1000000000, 1500000000]]
      }}
  """
  @spec fee_history(Keyword.t()) :: {:ok, Cartouche.FeeHistory.t()} | {:error, term()}
  def fee_history(opts \\ []) do
    block_count = Keyword.get(opts, :block_count, 1)
    newest_block = opts |> Keyword.get(:newest_block, "latest") |> normalize_block_param()
    reward_percentiles = Keyword.get(opts, :reward_percentiles, [])

    send_rpc(
      "eth_feeHistory",
      [block_count, newest_block, reward_percentiles],
      Keyword.put(opts, :decode, &Cartouche.FeeHistory.deserialize/1)
    )
  end

  api(:prepare_trx, "Prepare and sign a transaction for later submission.",
    params: [
      contract: [kind: :value, description: "20-byte destination contract address."],
      call_data: [
        kind: :value,
        description: "Raw calldata bytes or `{function_signature, args}` ABI call data tuple."
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          "Keyword transaction assembly options, including signer, value, gas, nonce, verification, transaction type, trace, and transport options."
      ]
    ],
    opts: [
      nonce: [
        kind: :exchange_data,
        source: "Cartouche.RPC.get_transaction_count/2",
        description: "Optional account nonce; fetched from the signer address when omitted."
      ],
      gas_limit: [
        kind: :exchange_data,
        source: "Cartouche.RPC.estimate_gas/2",
        description: "Optional gas limit; estimated and buffered when omitted."
      ],
      gas_price: [
        kind: :exchange_data,
        source: "Cartouche.RPC.gas_price/1",
        description: "Optional legacy gas price; fetched and buffered for V1 transactions when omitted."
      ],
      base_fee: [
        kind: :exchange_data,
        source: "Cartouche.RPC.fee_history/1",
        description: "Optional EIP-1559 base fee; derived from fee history when omitted for V2 transactions."
      ],
      priority_fee: [
        kind: :exchange_data,
        source: "Cartouche.RPC.max_priority_fee_per_gas/1",
        description: "Optional EIP-1559 priority fee; fetched when omitted for V2 transactions."
      ],
      signer: [
        kind: :value,
        default: Default,
        description: "Signer process used to address and sign the transaction."
      ],
      verify: [
        kind: :value,
        default: true,
        description: "When true, preview the call before finalizing gas and signature."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, %Cartouche.Transaction.V1{} | %Cartouche.Transaction.V2{}}` or `{:error, reason}`."
    },
    composes_with: [:get_nonce, :estimate_gas, :fee_history, :gas_price, :max_priority_fee_per_gas]
  )

  @doc """
  Helper function to work with other Cartouche modules to get a nonce, sign a transction, and prepare it to be submitted on-chain.

  If you need higher-level functionality, like manual nonce tracking, you may want to use the more granular function calls.

  Options:
    * `gas_price` - Set the gas price for a v1 (non-Eip1559) transaction, if nil, comes from `eth_gasPrice` (default `nil`) [note: only compatible with V1 transaction]
    * `base_fee` - Set the base price for the transaction, if nil, will use base gas price from `eth_feeHistory` (default `nil`) [note: only compatible with V2 transactions]
    * `base_fee_buffer` - Buffer for the gas price or base fee when estimating gas price. Ingored if `gas_price` (for v1) or `base_fee` (for v2) is specified directly (default: 1.2 = 120%)
    * `priority_fee` - Additional gas to send as a priority fee. (default: `{0, :gwei}`) [note: only compatible with V2 transactions]
    * `gas_limit` - Set the gas limit for the transaction (default: calls `eth_estimateGas`)
    * `gas_buffer` - Buffer if estimating gas limit (default: 1.5 = 150%)
    * `value` - Value to provide with transaction in wei (default: 0)
    * `nonce` - Nonce to send with transaction. (default: lookup via `eth_transactionCount`)
    * `verify` - Verify the function is likely to succeed (default: true)
    * `trx_type` - :v1 for V1 (pre-EIP-1559 transactions), :v2 for V2 (EIP-1559) transactions, and `nil` for auto-detect.

    Note: if we don't `verify`, then `estimateGas` will likely fail if the transaction were to fail.
          To prevent this, `gas_limit` should always be supplied when `verify` is set to false.

  ## Examples
      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, trx} = Cartouche.RPC.prepare_trx(<<1::160>>, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, gas_price: {50, :gwei}, nonce: 10, value: 0, signer: signer_proc)
      iex> %{trx|v: nil, r: nil, s: nil}
      %Cartouche.Transaction.V1{
        nonce: 10,
        gas_price: 50000000000,
        gas_limit: 20,
        to: <<1::160>>,
        value: 0,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>
      }

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, trx} = Cartouche.RPC.prepare_trx(<<1::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, signer: signer_proc)
      iex> %{trx|v: nil, r: nil, s: nil}
      %Cartouche.Transaction.V1{
        nonce: 4,
        gas_price: 50000000000,
        gas_limit: 100000,
        to: <<1::160>>,
        value: 0,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>
      }

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, trx} = Cartouche.RPC.prepare_trx(<<1::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, signer: signer_proc)
      iex> %{trx|v: nil, r: nil, s: nil}
      %Cartouche.Transaction.V1{
        nonce: 10,
        gas_price: 50000000000,
        gas_limit: 100000,
        to: <<1::160>>,
        value: 0,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>
      }

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> Cartouche.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, signer: signer_proc)
      {:error, %{code: 3, message: "execution reverted", revert: <<61, 115, 139, 46>>}}

      iex> # Set gas price directly
      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, trx} = Cartouche.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, verify: false, signer: signer_proc)
      iex> %{trx|v: nil, r: nil, s: nil}
      %Cartouche.Transaction.V1{
        nonce: 10,
        gas_price: 50000000000,
        gas_limit: 100000,
        to: <<10::160>>,
        value: 0,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>
      }

      iex> # Default gas price v1
      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, trx} = Cartouche.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_limit: 100_000, trx_type: :v1, value: 0, nonce: 10, verify: false, signer: signer_proc)
      iex> %{trx|v: nil, r: nil, s: nil}
      %Cartouche.Transaction.V1{
        nonce: 10,
        gas_price: 1200000000,
        gas_limit: 100000,
        to: <<10::160>>,
        value: 0,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>
      }

      iex> # Default gas price v2
      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, trx} = Cartouche.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_limit: 100_000, trx_type: :v2, value: 0, nonce: 10, verify: false, signer: signer_proc)
      iex> %{trx|signature_y_parity: nil, signature_r: nil, signature_s: nil}
      %Cartouche.Transaction.V2{
        chain_id: 5,
        nonce: 10,
        gas_limit: 100000,
        destination: <<10::160>>,
        amount: 0,
        max_fee_per_gas: 25679608965,
        max_priority_fee_per_gas: 1000000001,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>,
        access_list: []
      }

      iex> # Default gas price (trx_type: nil)
      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, trx} = Cartouche.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_limit: 100_000, value: 0, nonce: 10, verify: false, signer: signer_proc)
      iex> %{trx|signature_y_parity: nil, signature_r: nil, signature_s: nil}
      %Cartouche.Transaction.V2{
        chain_id: 5,
        nonce: 10,
        gas_limit: 100000,
        destination: <<10::160>>,
        amount: 0,
        max_fee_per_gas: 25679608965,
        max_priority_fee_per_gas: 1000000001,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>,
        access_list: []
      }

      iex> # Set priority fee (v2)
      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, trx} = Cartouche.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, priority_fee: {3, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, verify: false, signer: signer_proc)
      iex> %{trx|signature_y_parity: nil, signature_r: nil, signature_s: nil}
      %Cartouche.Transaction.V2{
        chain_id: 5,
        nonce: 10,
        gas_limit: 100000,
        destination: <<10::160>>,
        amount: 0,
        max_fee_per_gas: 27679608964,
        max_priority_fee_per_gas: 3000000000,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>,
        access_list: []
      }

      iex> # Set base fee and priority fee (v2)
      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, trx} = Cartouche.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, base_fee: {1, :gwei}, priority_fee: {3, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, verify: false, signer: signer_proc)
      iex> %{trx|signature_y_parity: nil, signature_r: nil, signature_s: nil}
      %Cartouche.Transaction.V2{
        chain_id: 5,
        nonce: 10,
        gas_limit: 100000,
        destination: <<10::160>>,
        amount: 0,
        max_fee_per_gas: 4000000000,
        max_priority_fee_per_gas: 3000000000,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>,
        access_list: []
      }

      iex> # Sets chain id
      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, trx} = Cartouche.RPC.prepare_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, base_fee: {1, :gwei}, priority_fee: {3, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, verify: false, signer: signer_proc, chain_id: 99)
      iex> %{trx|signature_y_parity: nil, signature_r: nil, signature_s: nil}
      %Cartouche.Transaction.V2{
        chain_id: 99,
        nonce: 10,
        gas_limit: 100000,
        destination: <<10::160>>,
        amount: 0,
        max_fee_per_gas: 4000000000,
        max_priority_fee_per_gas: 3000000000,
        data: <<162, 145, 173, 214, 0::248, 50, 0::248, 1>>,
        access_list: []
      }
  """
  @spec prepare_trx(<<_::160>>, binary() | {String.t(), [term()]}, Keyword.t()) ::
          {:ok, V1.t() | V2.t()} | {:error, term()}
  def prepare_trx(contract, call_data, opts \\ []) do
    with {:ok, trx, _send_opts} <- prepare_trx_(contract, call_data, opts) do
      {:ok, trx}
    end
  end

  @doc false
  @spec prepare_trx_(<<_::160>>, binary() | {String.t(), [term()]}, Keyword.t()) ::
          {:ok, V1.t() | V2.t(), Keyword.t()} | {:error, term()}
  defp prepare_trx_(contract, call_data, opts) do
    {trx_type, opts} = Keyword.pop(opts, :trx_type, nil)
    {gas_price_user, opts} = Keyword.pop(opts, :gas_price, @default_gas_price)
    {base_fee_user, opts} = Keyword.pop(opts, :base_fee, @default_base_fee)
    {base_fee_buffer, opts} = Keyword.pop(opts, :base_fee_buffer, @default_base_fee_buffer)
    {priority_fee_user, opts} = Keyword.pop(opts, :priority_fee, nil)
    {gas_limit, opts} = Keyword.pop(opts, :gas_limit)
    {gas_buffer, opts} = Keyword.pop(opts, :gas_buffer, @default_gas_buffer)
    {value, opts} = Keyword.pop(opts, :value, 0)
    {nonce, opts} = Keyword.pop(opts, :nonce)
    {verify, opts} = Keyword.pop(opts, :verify, true)
    {access_list, opts} = Keyword.pop(opts, :access_list, [])
    {signer, opts} = Keyword.pop(opts, :signer, Default)
    {trace_reverts, opts} = Keyword.pop(opts, :trace_reverts, false)
    {debug_trace, opts} = Keyword.pop(opts, :debug_trace, false)
    {trace_opts, opts} = Keyword.pop(opts, :trace_opts, [])

    signer_address = Cartouche.Signer.address(signer)
    chain_id = Keyword.get_lazy(opts, :chain_id, fn -> Cartouche.Signer.chain_id(signer) end)
    send_opts = Keyword.put_new(opts, :from, signer_address)

    # Determine the type of the transaction based on the gas inputs. This is complicated because
    # a) we don't want the user to specify what they want since it would break earlier clients,
    # and b) it should be obvious on the inputs, e.g. `gas_price` implies a V1 transaction,
    # while `base_fee` or `priority_fee` imply a V2 transaction, and c) we want to default
    # users to V2 transactions if nothing is specified.
    trx_type_result =
      case {trx_type, gas_price_user, base_fee_user, priority_fee_user} do
        # v1 specified
        {:v1, nil, nil, nil} ->
          v1_gas_parameters(nil, base_fee_buffer, send_opts)

        # surmise :v1 since gas_price is set but not v2 gas parameters
        {nil, gas_price, nil, nil} when not is_nil(gas_price) ->
          v1_gas_parameters(gas_price, base_fee_buffer, send_opts)

        # any valid :v2 combination
        {ty, nil, user_base_fee, user_priority_fee} when ty in [nil, :v2] ->
          v2_gas_parameters(user_base_fee, user_priority_fee, base_fee_buffer, send_opts)

        _ ->
          raise "mismatched transaction type and gas price settings"
      end

    estimate_and_verify = fn trx ->
      do_estimate_and_verify(trx, %{
        verify: verify,
        gas_limit: gas_limit,
        gas_buffer: gas_buffer,
        trace_reverts: trace_reverts,
        debug_trace: debug_trace,
        opts: opts,
        trace_opts: trace_opts
      })
    end

    with {:ok, trx_type} <- trx_type_result,
         {:ok, nonce} <-
           if(is_nil(nonce), do: get_nonce(signer_address, opts), else: {:ok, nonce}),
         {:ok, trx} <-
           (case trx_type do
              {:v1, gas_price} ->
                Transaction.build_signed_trx(
                  contract,
                  nonce,
                  call_data,
                  gas_price,
                  gas_limit,
                  value,
                  signer: signer,
                  chain_id: chain_id,
                  callback: estimate_and_verify
                )

              {:v2, max_fee_per_gas, max_priority_fee_per_gas} ->
                Transaction.build_signed_trx_v2(
                  contract,
                  nonce,
                  call_data,
                  max_priority_fee_per_gas,
                  max_fee_per_gas,
                  gas_limit,
                  value,
                  access_list,
                  signer: signer,
                  chain_id: chain_id,
                  callback: estimate_and_verify
                )
            end) do
      {:ok, trx, send_opts}
    end
  end

  @spec resolve_gas_limit(nil | non_neg_integer(), V1.t() | V2.t(), Keyword.t(), number()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp resolve_gas_limit(nil, trx, opts, gas_buffer) do
    with {:ok, limit} <- estimate_gas(trx, opts), do: {:ok, ceil(limit * gas_buffer)}
  end

  defp resolve_gas_limit(els, _trx, _opts, _gas_buffer), do: {:ok, els}

  @spec maybe_trace_revert(
          V1.t() | V2.t(),
          {:ok, term()} | {:error, term()},
          boolean(),
          boolean(),
          Keyword.t(),
          Keyword.t()
        ) ::
          {:ok, term()} | {:error, term()}
  defp maybe_trace_revert(trx, trx_res, true, debug_trace, opts, trace_opts),
    do: show_trace_revert(trx, trx_res, debug_trace, Keyword.merge(opts, trace_opts))

  defp maybe_trace_revert(_trx, trx_res, false, _debug_trace, _opts, _trace_opts), do: trx_res

  @spec do_estimate_and_verify(V1.t() | V2.t(), map()) :: {:ok, V1.t() | V2.t()} | {:error, term()}
  defp do_estimate_and_verify(trx, %{
         verify: verify,
         gas_limit: gas_limit,
         gas_buffer: gas_buffer,
         trace_reverts: trace_reverts,
         debug_trace: debug_trace,
         opts: opts,
         trace_opts: trace_opts
       }) do
    with {:ok, _} <- if(verify, do: call_trx(trx, opts), else: {:ok, nil}),
         {:ok, resolved} <- resolve_gas_limit(gas_limit, trx, opts, gas_buffer) do
      {:ok, %{trx | gas_limit: resolved}}
    else
      trx_res -> maybe_trace_revert(trx, trx_res, trace_reverts, debug_trace, opts, trace_opts)
    end
  end

  api(:execute_trx, "Prepare, sign, and submit a transaction to the Ethereum network.",
    params: [
      contract: [kind: :value, description: "20-byte destination contract address."],
      call_data: [
        kind: :value,
        description: "Raw calldata bytes or `{function_signature, args}` ABI call data tuple."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Same transaction assembly, signing, trace, and transport options accepted by `prepare_trx/3`."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, transaction_hash}` with the submitted transaction hash bytes, or `{:error, reason}`."
    },
    composes_with: [:prepare_trx, :send_trx]
  )

  @doc """
  Helper function to work with other Cartouche modules to get a nonce, sign a transction, and transmit it to the network.

  If you need higher-level functionality, like manual nonce tracking, you may want to use the more granular function calls.

  Options:
    * `gas_price` - Set the base gas for the transaction, overrides all other gas prices listed below (default `nil`) [note: only compatible with V1 transaction]
    * `base_fee` - Set the base price for the transaction, if nil, will use base gas price from `eth_gasPrice` call (default `nil`) [note: only compatible with V2 transactions]
    * `base_fee_buffer` - Buffer for the gas price when estimating gas (default: 1.2 = 120%) [note: only compatible with V2 transactions]
    * `priority_fee` - Additional gas to send as a priority fee. (default: `{0, :gwei}`) [note: only compatible with V2 transactions]
    * `gas_limit` - Set the gas limit for the transaction (default: calls `eth_estimateGas`)
    * `gas_buffer` - Buffer if estimating gas limit (default: 1.5 = 150%)
    * `value` - Value to provide with transaction in wei (default: 0)
    * `nonce` - Nonce to send with transaction. (default: lookup via `eth_transactionCount`)
    * `verify` - Verify the function is likely to succeed (default: true)
    * `trx_type` - :v1 for V1 (pre-EIP-1559 transactions), :v2 for V2 (EIP-1559) transactions, and `nil` for auto-detect.

    Note: if we don't `verify`, then `estimateGas` will likely fail if the transaction were to fail.
          To prevent this, `gas_limit` should always be supplied when `verify` is set to false.

  ## Examples
      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, trx_id} = Cartouche.RPC.execute_trx(<<1::160>>, {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]}, gas_price: {50, :gwei}, value: 0, signer: signer_proc)
      iex> <<nonce::integer-size(8), gas_price::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, gas_price, gas_limit, to}
      {4, 50000000000, 20, <<1::160>>}

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> Cartouche.RPC.execute_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, gas_price: {50, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, signer: signer_proc)
      {:error, %{code: 3, message: "execution reverted", revert: <<61, 115, 139, 46>>}}

      iex> # Set base fee and priority fee (v2)
      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, trx_id} = Cartouche.RPC.execute_trx(<<10::160>>, {"baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned]}, base_fee: {1, :gwei}, priority_fee: {3, :gwei}, gas_limit: 100_000, value: 0, nonce: 10, verify: false, signer: signer_proc)
      iex> <<nonce::integer-size(8), max_priority_fee_per_gas::integer-size(64), max_fee_per_gas::integer-size(64), gas_limit::integer-size(24), to::binary>> = trx_id
      iex> {nonce, max_priority_fee_per_gas, max_fee_per_gas, gas_limit, to}
      {10, 3000000000, 4000000000, 100000, <<10::160>>}
  """
  @spec execute_trx(<<_::160>>, binary() | {String.t(), [term()]}, Keyword.t()) ::
          {:ok, binary()} | {:error, term()}
  def execute_trx(contract, call_data, opts \\ []) do
    with {:ok, trx, send_opts} <- prepare_trx_(contract, call_data, opts) do
      send_trx(trx, send_opts)
    end
  end

  api(:new_block_filter, "Create a node-side filter that records new block hashes.",
    params: [
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, filter_id}` as the node's hex filter identifier, or `{:error, reason}`."
    }
  )

  @doc """
  RPC call to create a new block filter.

  ## Examples

      iex> Cartouche.RPC.new_block_filter()
      {:ok, "0xb10cf11e"}
  """
  @spec new_block_filter(Keyword.t()) :: {:ok, String.t()} | {:error, term()}
  def new_block_filter(opts \\ []) do
    send_rpc("eth_newBlockFilter", [], opts)
  end

  api(:new_pending_transaction_filter, "Create a node-side filter that records new pending transaction hashes.",
    params: [
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, filter_id}` as the node's hex filter identifier, or `{:error, reason}`."
    }
  )

  @doc """
  RPC call to create a new pending-transaction filter.

  ## Examples

      iex> Cartouche.RPC.new_pending_transaction_filter()
      {:ok, "0xpend1ng"}
  """
  @spec new_pending_transaction_filter(Keyword.t()) :: {:ok, String.t()} | {:error, term()}
  def new_pending_transaction_filter(opts \\ []) do
    send_rpc("eth_newPendingTransactionFilter", [], opts)
  end

  api(:eth_get_logs, "Fetch event logs matching a stateless filter (eth_getLogs).",
    params: [
      filter: [
        kind: :value,
        description:
          "Filter map. Atom keys: :address (one address or a list; 0x hex or 20-byte binary), " <>
            ":topics (list), :from_block and :to_block (integer, block tag, or 0x quantity), " <>
            ":block_hash (32-byte 0x hex). Canonical JSON-RPC camelCase string keys " <>
            ~s{("fromBlock", "toBlock", "address", "topics", "blockHash") are aliases. } <>
            "If both an atom key and its alias are present, the atom wins. :block_hash is " <>
            "mutually exclusive with :from_block / :to_block."
      ],
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, [%Cartouche.Filter.Log{}]}` decoded by `Cartouche.Filter.Log.decode_logs/1`, " <>
          "or `{:error, reason}`. Unknown keys are `{:invalid_filter_key, key}`; bad values are " <>
          "`{:invalid_filter, {field, value}}`; combining :block_hash with a block range is " <>
          "`{:invalid_filter, {:block_hash_mutually_exclusive, present}}`."
    }
  )

  @doc """
  Stateless `eth_getLogs` query.

  Accepts the execution-apis filter object: a block range (`fromBlock` /
  `toBlock`) or a mutually exclusive `blockHash`, plus optional `address` and
  `topics`. Logs are decoded with `Cartouche.Filter.Log`, the same decoder
  `Cartouche.Filter` and `get_filter_logs/2` use. That decoder expects the
  mined-log fields (block hash, block number, and transaction hash present).

  ## Examples

      iex> {:ok, [log]} = Cartouche.RPC.eth_get_logs(%{from_block: 16, to_block: 16})
      iex> log.block_number
      16
  """
  @spec eth_get_logs(map(), Keyword.t()) :: {:ok, [FilterLog.t()]} | {:error, term()}
  def eth_get_logs(filter, opts \\ []) when is_map(filter) do
    normalized = normalize_filter_keys(filter)

    with :ok <- validate_log_filter_keys(normalized),
         {:ok, rpc_filter} <- build_log_filter(normalized) do
      send_rpc("eth_getLogs", [rpc_filter], Keyword.put(opts, :decode, &FilterLog.decode_logs/1))
    end
  end

  api(:get_filter_logs, "Return every log matching a log filter, not only changes since the last poll.",
    params: [
      filter_id: [kind: :value, description: "Hex filter identifier returned by `eth_newFilter`."],
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, [%Cartouche.Filter.Log{}]}` decoded from `eth_getFilterLogs`, or `{:error, reason}`."
    }
  )

  @doc """
  RPC call to fetch the full log backlog for a filter.

  ## Examples

      iex> {:ok, [log]} = Cartouche.RPC.get_filter_logs("0xf11735")
      iex> log.address
      <<181, 165, 242, 38, 148, 53, 44, 21, 176, 3, 35, 132, 74, 213, 69, 171, 178, 177, 16, 40>>
  """
  @spec get_filter_logs(String.t(), Keyword.t()) :: {:ok, [FilterLog.t()]} | {:error, term()}
  def get_filter_logs(filter_id, opts \\ []) do
    send_rpc("eth_getFilterLogs", [filter_id], Keyword.put(opts, :decode, &FilterLog.decode_logs/1))
  end

  api(:accounts, "List addresses the node manages.",
    params: [
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, addresses}` as 20-byte binaries decoded from `eth_accounts`, or `{:error, reason}`."
    }
  )

  @doc """
  RPC call to list accounts the node holds keys for.

  ## Examples

      iex> Cartouche.RPC.accounts()
      {:ok, [<<64, 125, 115, 216, 164, 158, 235, 133, 211, 44, 244, 101, 80, 125, 215, 29, 80, 113, 0, 193>>]}
  """
  @spec accounts(Keyword.t()) :: {:ok, [<<_::160>>]} | {:error, term()}
  def accounts(opts \\ []) do
    send_rpc("eth_accounts", [], Keyword.put(opts, :decode, &decode_addresses/1))
  end

  api(:coinbase, "Return the node's coinbase (fee recipient) address.",
    params: [
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, address}` as a 20-byte binary decoded from `eth_coinbase`, or `{:error, reason}`."
    }
  )

  @doc """
  RPC call to get the node's coinbase address.

  ## Examples

      iex> Cartouche.RPC.coinbase()
      {:ok, <<254, 59, 85, 126, 143, 182, 43, 137, 244, 145, 107, 114, 27, 229, 92, 235, 130, 141, 189, 115>>}
  """
  @spec coinbase(Keyword.t()) :: {:ok, <<_::160>>} | {:error, term()}
  def coinbase(opts \\ []) do
    send_rpc("eth_coinbase", [], Keyword.put(opts, :decode, &Hex.decode_address!/1))
  end

  api(:fill_transaction, "Ask the node to populate missing nonce, gas, and fee fields without signing.",
    params: [
      trx: [
        kind: :value,
        description: "`Cartouche.Transaction.V1`, `Cartouche.Transaction.V2`, or `Cartouche.Transaction.Call` to fill."
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          "Keyword options including optional `:from`, optional `:chain_id` (the chain id geth " <>
            "omits from an unsigned legacy result; refused when it disagrees with the one the " <>
            "response names), and common `send_rpc/3` transport options."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, transaction}` deserialized into cartouche's transaction representation, or `{:error, reason}`."
    }
  )

  @doc """
  RPC call to fill missing transaction fields via `eth_fillTransaction`.

  The node populates nonce, gas, and fee fields and returns the completed
  unsigned transaction. Spec-conforming nodes return a `FillTransactionResult`
  carrying only `tx`; geth returns a `{raw, tx}` pair. Both shapes decode into a
  `Cartouche.Transaction` struct.

  Decoding prefers the `tx` object `execution-apis` requires over geth's
  additional `raw` field, because `raw` serializes an unsigned transaction in
  the signed wire format and so cannot be told apart from a signed one.

  A typed envelope's unsigned form is `nil` signature fields; a legacy one keeps
  the chain id in `v` with `r`/`s` zero.

  Legacy fills need a chain id, which `Cartouche.Transaction.V1` holds in `v`
  until a signature replaces it. geth omits `chainId` from an unsigned legacy
  result; pass `chain_id:` to supply it. Without it — from either side — the
  call errors rather than return a transaction that would sign to the wrong
  address, and so does a `chain_id:` that disagrees with the one the response
  names: `Cartouche.Signer` takes the chain id from its caller rather than from
  the struct, so a disagreement signs a digest the encoded payload does not
  match.

  ## Examples

      iex> {:ok, trx} =
      ...>   Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
      ...>   |> Cartouche.RPC.fill_transaction()
      iex> trx.nonce
      1
  """
  @spec fill_transaction(V1.t() | V2.t() | Call.t(), Keyword.t()) :: {:ok, struct()} | {:error, term()}
  def fill_transaction(trx, opts \\ []) do
    from = Keyword.get(opts, :from)
    chain_id = Keyword.get(opts, :chain_id)

    send_rpc(
      "eth_fillTransaction",
      [to_transaction_params(trx, from)],
      Keyword.put(opts, :decode, &decode_filled_transaction(&1, chain_id))
    )
  end

  api(:sign, "Ask the node to sign a message under EIP-191 with a managed account (`eth_sign`).",
    params: [
      account: [kind: :value, description: "20-byte account address the node must hold a key for."],
      message: [kind: :value, description: "Message bytes the node signs under EIP-191; not a pre-computed digest."],
      opts: [kind: :value, default: [], description: "Common `send_rpc/3` transport options."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, signature}` as decoded bytes from `eth_sign`, or the node's `{:error, reason}`."
    }
  )

  @doc """
  RPC call to `eth_sign`.

  The node signs `message` with a managed account and returns an EIP-191
  signature over it — `message` is the data to be signed, not a digest the
  node signs verbatim. Most nodes disable this method; when they do, the
  node's error is returned unchanged.

  ## Examples

      iex> {:ok, signature} = Cartouche.RPC.sign(<<1::160>>, "hello")
      iex> byte_size(signature)
      65
  """
  @spec sign(<<_::160>>, binary(), Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def sign(account, message, opts \\ []) do
    send_rpc(
      "eth_sign",
      [Hex.encode_big_hex(account), Hex.encode_big_hex(message)],
      Keyword.put(opts, :decode, :hex)
    )
  end

  api(:sign_transaction, "Ask the node to sign a transaction with a managed account.",
    params: [
      trx: [
        kind: :value,
        description: "`Cartouche.Transaction.V1`, `Cartouche.Transaction.V2`, or `Cartouche.Transaction.Call` to sign."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Keyword options including optional `:from` and common `send_rpc/3` transport options."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, transaction}` decoded from the node's raw signed transaction via `Cartouche.Transaction.decode/1`, or `{:error, reason}`."
    }
  )

  @doc """
  RPC call to `eth_signTransaction`.

  The node signs with its keystore and returns a raw transaction, which is
  decoded through `Cartouche.Transaction.decode/1`.

  ## Examples

      iex> {:ok, trx} =
      ...>   Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
      ...>   |> Cartouche.RPC.sign_transaction()
      iex> trx.nonce
      1
  """
  @spec sign_transaction(V1.t() | V2.t() | Call.t(), Keyword.t()) :: {:ok, struct()} | {:error, term()}
  def sign_transaction(trx, opts \\ []) do
    from = Keyword.get(opts, :from)

    send_rpc(
      "eth_signTransaction",
      [to_transaction_params(trx, from)],
      Keyword.put(opts, :decode, &decode_signed_transaction/1)
    )
  end

  api(:send_transaction, "Ask the node to sign and broadcast a transaction with a managed account.",
    params: [
      trx: [
        kind: :value,
        description: "`Cartouche.Transaction.V1`, `Cartouche.Transaction.V2`, or `Cartouche.Transaction.Call` to submit."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Keyword options including optional `:from` and common `send_rpc/3` transport options."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, transaction_hash}` as 32 decoded bytes from `eth_sendTransaction`, or `{:error, reason}`."
    }
  )

  @doc """
  RPC call to `eth_sendTransaction`.

  ## Examples

      iex> {:ok, hash} =
      ...>   Cartouche.Transaction.V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      ...>   |> Cartouche.RPC.send_transaction()
      iex> Base.encode16(hash, case: :lower)
      "abababababababababababababababababababababababababababababababab"
  """
  @spec send_transaction(V1.t() | V2.t() | Call.t(), Keyword.t()) :: {:ok, binary()} | {:error, term()}
  def send_transaction(trx, opts \\ []) do
    from = Keyword.get(opts, :from)

    send_rpc(
      "eth_sendTransaction",
      [to_transaction_params(trx, from)],
      Keyword.put(opts, :decode, :hex)
    )
  end

  # Rewrites canonical JSON-RPC camelCase string keys to their atom equivalents.
  # Other string keys pass through and fail `validate_log_filter_keys/1`.
  # Atom keys take precedence when both forms are present.
  @spec normalize_filter_keys(map()) :: map()
  defp normalize_filter_keys(filter) do
    Enum.reduce(@camel_case_filter_aliases, filter, fn {string_key, atom_key}, acc ->
      case Map.pop(acc, string_key) do
        {nil, acc} -> acc
        {value, acc} -> Map.put_new(acc, atom_key, value)
      end
    end)
  end

  @spec validate_log_filter_keys(map()) :: :ok | {:error, {:invalid_filter_key, term()}}
  defp validate_log_filter_keys(filter) do
    case Map.keys(filter) -- @allowed_log_filter_keys do
      [] -> :ok
      [unknown | _] -> {:error, {:invalid_filter_key, unknown}}
    end
  end

  @spec build_log_filter(map()) :: {:ok, map()} | {:error, term()}
  defp build_log_filter(filter) do
    with :ok <- check_block_hash_exclusivity(filter),
         {:ok, result} <- put_filter_address(%{}, filter),
         {:ok, result} <- put_filter_topics(result, filter),
         {:ok, result} <- put_filter_block_hash(result, filter),
         {:ok, result} <- put_block_param(result, "fromBlock", :fromBlock, Map.get(filter, :from_block)) do
      put_block_param(result, "toBlock", :toBlock, Map.get(filter, :to_block))
    end
  end

  @spec check_block_hash_exclusivity(map()) ::
          :ok | {:error, {:invalid_filter, {:block_hash_mutually_exclusive, [atom()]}}}
  defp check_block_hash_exclusivity(filter) do
    if Map.has_key?(filter, :block_hash) do
      case Enum.filter([:from_block, :to_block], &Map.has_key?(filter, &1)) do
        [] -> :ok
        conflicts -> {:error, {:invalid_filter, {:block_hash_mutually_exclusive, [:block_hash | conflicts]}}}
      end
    else
      :ok
    end
  end

  @spec put_filter_address(map(), map()) :: {:ok, map()} | {:error, term()}
  defp put_filter_address(result, filter) do
    case Map.get(filter, :address) do
      nil ->
        {:ok, result}

      addresses when is_list(addresses) ->
        with {:ok, hexes} <- encode_filter_addresses(addresses), do: {:ok, Map.put(result, "address", hexes)}

      addr ->
        with {:ok, hex} <- Helpers.ensure_hex_address(addr), do: {:ok, Map.put(result, "address", hex)}
    end
  end

  @spec encode_filter_addresses([term()]) :: {:ok, [String.t()]} | {:error, term()}
  defp encode_filter_addresses(addresses), do: encode_filter_addresses(addresses, [])

  @spec encode_filter_addresses([term()], [String.t()]) :: {:ok, [String.t()]} | {:error, term()}
  defp encode_filter_addresses([], acc), do: {:ok, Enum.reverse(acc)}

  defp encode_filter_addresses([addr | rest], acc) do
    with {:ok, hex} <- Helpers.ensure_hex_address(addr) do
      encode_filter_addresses(rest, [hex | acc])
    end
  end

  @spec put_filter_block_hash(map(), map()) :: {:ok, map()} | {:error, term()}
  defp put_filter_block_hash(result, filter) do
    case Map.get(filter, :block_hash) do
      nil ->
        {:ok, result}

      hash ->
        case Helpers.ensure_tx_hash(hash) do
          {:ok, valid_hash} -> {:ok, Map.put(result, "blockHash", valid_hash)}
          {:error, _} -> {:error, {:invalid_filter, {:blockHash, hash}}}
        end
    end
  end

  @spec put_filter_topics(map(), map()) :: {:ok, map()} | {:error, term()}
  defp put_filter_topics(result, filter) do
    case Map.get(filter, :topics) do
      nil -> {:ok, result}
      topics when is_list(topics) -> {:ok, Map.put(result, "topics", topics)}
      other -> {:error, {:invalid_filter, {:topics, other}}}
    end
  end

  @spec put_block_param(map(), String.t(), atom(), term()) :: {:ok, map()} | {:error, term()}
  defp put_block_param(result, _key, _error_label, nil), do: {:ok, result}

  defp put_block_param(result, key, _error_label, n) when is_integer(n) and n >= 0,
    do: {:ok, Map.put(result, key, Onchain.Hex.from_integer(n))}

  defp put_block_param(result, key, _error_label, tag) when tag in @log_filter_block_tags,
    do: {:ok, Map.put(result, key, tag)}

  defp put_block_param(result, key, error_label, "0x" <> _ = hex) do
    if Onchain.Hex.valid?(hex),
      do: {:ok, Map.put(result, key, hex)},
      else: {:error, {:invalid_filter, {error_label, hex}}}
  end

  defp put_block_param(_result, _key, error_label, other), do: {:error, {:invalid_filter, {error_label, other}}}

  @spec decode_addresses(list()) :: [<<_::160>>]
  defp decode_addresses(addresses) when is_list(addresses), do: Enum.map(addresses, &Hex.decode_address!/1)

  # `tx` wins over `raw`, which inverts the precedence `eth_signTransaction`
  # uses below. `eth_fillTransaction` returns an *unsigned* transaction, and
  # geth serializes that into `raw` using the canonical *signed* wire format
  # with a zero signature — a legacy body ending `[0, 0, 0]` rather than
  # EIP-155's `[chain_id, 0, 0]`, and a typed body carrying its zero-valued
  # V/R/S rather than the short signing preimage. Nothing in those bytes
  # distinguishes "unsigned" from "signed with zeros", so a caller who signs
  # the re-encoded result gets a signature that recovers to the wrong address.
  # `tx` is the field `execution-apis` actually requires, and it says which
  # fields the node left unset, so it is the trustworthy one.
  @spec decode_filled_transaction(map(), atom() | integer() | nil) :: struct()
  defp decode_filled_transaction(%{"tx" => tx}, chain_id) when is_map(tx),
    do: deserialize_unsigned_rpc_transaction(tx, chain_id)

  defp decode_filled_transaction(%{"raw" => raw}, _chain_id) when is_binary(raw),
    do: raw |> decode_raw_transaction!() |> assert_unsigned_raw!()

  defp decode_filled_transaction(%{} = params, _chain_id) do
    raise ArgumentError,
          "eth_fillTransaction returned neither a `tx` object nor a `raw` field " <>
            "(keys: #{inspect(Map.keys(params))})"
  end

  # Reached only when the node sent `raw` without the `tx` object that would say
  # what it means. `eth_fillTransaction` returns an *unsigned* transaction, so
  # the fallback must yield an envelope that is unsigned in cartouche's own
  # representation — the only shape `encode/1` re-emits as the bytes a caller
  # signs. Legacy means `[chain_id, 0, 0]` with a real chain id; typed means
  # `nil` signature fields, which only a short signing-preimage body decodes to.
  # Everything else is refused: geth's all-zero canonical serialization (whose
  # signing payload is not recoverable from those bytes), an already-signed
  # transaction, or a malformed mix. Re-encoding any of them would hash
  # different bytes than were signed, and the signature would recover to an
  # address that never signed anything.
  @spec assert_unsigned_raw!(struct()) :: struct()
  defp assert_unsigned_raw!(%V1{v: v, r: 0, s: 0} = transaction) when is_integer(v) and v > 0, do: transaction

  defp assert_unsigned_raw!(%{signature_y_parity: nil, signature_r: nil, signature_s: nil} = transaction), do: transaction

  defp assert_unsigned_raw!(transaction) do
    raise ArgumentError,
          "eth_fillTransaction returned a `raw` transaction that is not unambiguously unsigned, " <>
            "and no `tx` object to interpret it (#{inspect(transaction.__struct__)}). A node " <>
            "answering per `execution-apis` sends `tx`; geth's `raw` serializes an unsigned fill " <>
            "in the signed wire format, whose signing payload cannot be recovered from those bytes"
  end

  @spec decode_signed_transaction(map() | String.t()) :: struct()
  defp decode_signed_transaction(%{"raw" => raw}) when is_binary(raw), do: decode_raw_transaction!(raw)
  defp decode_signed_transaction(%{"tx" => tx}) when is_map(tx), do: deserialize_rpc_transaction(tx)
  defp decode_signed_transaction(raw) when is_binary(raw), do: decode_raw_transaction!(raw)

  defp decode_signed_transaction(%{} = params) do
    raise ArgumentError,
          "eth_signTransaction returned neither a `raw` nor a `tx` field (keys: #{inspect(Map.keys(params))})"
  end

  @spec decode_raw_transaction!(String.t()) :: struct()
  defp decode_raw_transaction!(raw) do
    case raw |> Hex.decode_hex!() |> Transaction.decode() do
      {:ok, trx} -> trx
      {:error, reason} -> raise ArgumentError, "invalid transaction payload: #{inspect(reason)}"
    end
  end

  @spec deserialize_rpc_transaction(map()) :: struct()
  defp deserialize_rpc_transaction(%{} = params) do
    case params["type"] do
      nil -> V1.from_json(params)
      "0x0" -> V1.from_json(params)
      "0x1" -> V_2930.from_json(params)
      "0x2" -> V2.from_json(params)
      "0x3" -> Transaction.V3.from_json(params)
      "0x4" -> Transaction.V4.from_json(params)
      other -> raise ArgumentError, "unsupported transaction envelope type #{inspect(other)}"
    end
  end

  # A fill result is unsigned, but geth still emits the signature keys with zero
  # values, so "key present" cannot mean "signed" — only a non-zero `r`/`s` can.
  # `v`/`yParity` are deliberately not consulted: a legitimately signed typed
  # transaction may carry `yParity: "0x0"`, and an unsigned legacy one carries
  # the chain id in `v`.
  @spec deserialize_unsigned_rpc_transaction(map(), atom() | integer() | nil) :: struct()
  defp deserialize_unsigned_rpc_transaction(%{} = params, chain_id) do
    validate_signature_quantities!(params)

    case Enum.filter(@filled_signature_words, &match?({:ok, value} when value != 0, quantity(params[&1]))) do
      [] ->
        params
        |> put_unsigned_signature_fields(chain_id)
        |> deserialize_rpc_transaction()
        |> clear_typed_signature()

      signature_words ->
        raise ArgumentError,
              "eth_fillTransaction returned a signed `tx` object " <>
                "(non-zero: #{inspect(signature_words)})"
    end
  end

  # A typed envelope keeps `chain_id` in its own field, so its unsigned form is
  # the signature fields set to `nil` — which `V2.encode/1` and its siblings
  # already emit as the payload a caller signs. The placeholders here only exist
  # to get past `from_json/1`, which stays strict for `eth_getBlockBy*`.
  @spec put_unsigned_signature_fields(map(), atom() | integer() | nil) :: map()
  defp put_unsigned_signature_fields(%{"type" => type} = params, _chain_id) when type not in [nil, "0x0"],
    do: Map.merge(params, %{"yParity" => "0x0", "r" => "0x0", "s" => "0x0"})

  # A legacy envelope has no `chain_id` field: `V1` carries the chain id in `v`
  # until a signature overwrites it, which is exactly the `[chain_id, 0, 0]`
  # signature triple EIP-155 defines for the payload a caller signs. Writing a
  # placeholder there instead would make `V1.encode/1` emit `[0, 0, 0]`, and a
  # signature over that payload recovers to the wrong address.
  defp put_unsigned_signature_fields(%{} = params, chain_id) do
    id = legacy_chain_id(params["chainId"], chain_id, params)
    Map.merge(params, %{"v" => Hex.encode_short_hex(id), "r" => "0x0", "s" => "0x0"})
  end

  # geth omits `chainId` from a legacy fill result — `newRPCTransaction` emits it
  # only for a replay-protected (already signed) transaction — so the caller's
  # `:chain_id` option is the fallback. Neither present is a hard error: guessing
  # from application config would sign for whatever network happened to be
  # configured. Chain id 0 is refused too, because `Cartouche.Signer` maps it to
  # a pre-EIP-155 `v` of 27/28 while `V1.encode/1` always emits nine fields, and
  # the two halves would disagree about what was signed.
  #
  # When both name a chain id and they disagree, neither wins. Silently taking
  # the response would hand back an envelope carrying the node's chain id to a
  # caller who just said which chain it means to sign for — and `Cartouche.Signer`
  # takes that chain id from the caller, not from this struct, so the EIP-155
  # digest signed and the `[chain_id, 0, 0]` payload encoded would disagree and
  # the signature would recover to an address that never signed it. That is the
  # same wrong-address hazard the `raw` and malformed-`chainId` refusals exist
  # for, so it is refused the same way.
  @spec legacy_chain_id(term(), atom() | integer() | nil, map()) :: pos_integer()
  defp legacy_chain_id(response_chain_id, opt_chain_id, params) do
    case {quantity_chain_id(response_chain_id), option_chain_id(opt_chain_id)} do
      {nil, nil} -> raise ArgumentError, missing_chain_id_message(params)
      {nil, option} -> option
      {response, nil} -> response
      {id, id} -> id
      {response, option} -> raise ArgumentError, conflicting_chain_id_message(response, option)
    end
  end

  # `Cartouche.Chain.parse_id/1` passes every integer through, so the option
  # needs the same positivity check the node's `chainId` gets — otherwise
  # `chain_id: 0` would reach `v` and defeat the refusal above. The message
  # blames the caller rather than the response, because that is where a bad
  # value came from.
  @spec option_chain_id(atom() | integer() | nil) :: pos_integer() | nil
  defp option_chain_id(nil), do: nil

  defp option_chain_id(chain_id) do
    case chain_id |> parse_option_chain_id() |> quantity() do
      {:ok, id} when id > 0 ->
        id

      _zero_or_invalid ->
        raise ArgumentError,
              "`chain_id:` must be a positive chain id, got #{inspect(chain_id)}. Chain id 0 is " <>
                "not signable here: `Cartouche.Signer` would sign it pre-EIP-155 while " <>
                "`V1.encode/1` emits the nine-field body"
    end
  end

  # `Cartouche.Chain.parse_id/1` is `Map.fetch!/2` for atoms, so an unknown chain
  # atom escapes as a `KeyError` before the check above can name the option that
  # carried it — the caller is told the response failed to decode. Funnel it into
  # the same refusal instead: `quantity/1` reads `:unknown_chain` as malformed.
  @spec parse_option_chain_id(atom() | integer()) :: term()
  defp parse_option_chain_id(chain_id) do
    Cartouche.Chain.parse_id(chain_id)
  rescue
    KeyError -> :unknown_chain
  end

  # A garbled signature word must not read as "unsigned" — the placeholders below
  # would overwrite it, and the caller would sign a transaction built from a
  # response cartouche never actually understood. `v` and `yParity` are checked
  # for shape here even though only `r`/`s` decide signedness.
  @spec validate_signature_quantities!(map()) :: :ok
  defp validate_signature_quantities!(params) do
    case Enum.filter(@filled_signature_fields, &(quantity(params[&1]) == :malformed)) do
      [] ->
        :ok

      malformed ->
        raise ArgumentError,
              "eth_fillTransaction returned a `tx` object with malformed signature quantities " <>
                "(#{inspect(malformed)})"
    end
  end

  # Reads a JSON `QUANTITY`. Nothing is silently coerced: anything that is
  # neither a `0x`-prefixed hex string nor a non-negative integer comes back
  # `:malformed` so the caller can refuse it, rather than collapsing to a zero
  # that would read as an unset field.
  @spec quantity(term()) :: {:ok, non_neg_integer()} | :absent | :malformed
  defp quantity(nil), do: :absent
  defp quantity(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp quantity("0x" <> digits) when byte_size(digits) > 0 do
    if String.match?(digits, @hex_digits), do: {:ok, String.to_integer(digits, 16)}, else: :malformed
  end

  defp quantity(_value), do: :malformed

  @spec quantity_chain_id(term()) :: pos_integer() | nil
  defp quantity_chain_id(value) do
    case quantity(value) do
      {:ok, id} when id > 0 -> id
      :malformed -> raise ArgumentError, "eth_fillTransaction returned a malformed `chainId` (#{inspect(value)})"
      _zero_or_absent -> nil
    end
  end

  @spec conflicting_chain_id_message(pos_integer(), pos_integer()) :: String.t()
  defp conflicting_chain_id_message(response, option) do
    "eth_fillTransaction returned `chainId` #{response} but `chain_id:` was #{option}. Neither " <>
      "is picked: `Cartouche.Transaction.V1` would carry the node's chain id in `v` while " <>
      "`Cartouche.Signer` signs the EIP-155 digest for the caller's, and the signature would " <>
      "recover to an address that never signed it. Pass the chain id the node is on, or none"
  end

  @spec missing_chain_id_message(map()) :: String.t()
  defp missing_chain_id_message(params) do
    "eth_fillTransaction returned an unsigned legacy `tx` object with no usable `chainId` " <>
      "(keys: #{inspect(Map.keys(params))}). `Cartouche.Transaction.V1` holds the chain id in " <>
      "`v` until it is signed, so the EIP-155 signing payload cannot be reconstructed without " <>
      "it — pass `chain_id:` to `fill_transaction/2`"
  end

  # Only the typed envelopes need clearing: the legacy placeholders above are
  # already the representation `V1` uses for an unsigned transaction.
  @spec clear_typed_signature(V1.t() | V_2930.t() | V2.t() | Transaction.V3.t() | Transaction.V4.t()) ::
          V1.t() | V_2930.t() | V2.t() | Transaction.V3.t() | Transaction.V4.t()
  defp clear_typed_signature(%V1{} = transaction), do: transaction

  defp clear_typed_signature(%{signature_y_parity: _, signature_r: _, signature_s: _} = transaction) do
    %{transaction | signature_y_parity: nil, signature_r: nil, signature_s: nil}
  end

  @spec to_transaction_params(V1.t() | V2.t() | Call.t(), <<_::160>> | nil) :: map()
  defp to_transaction_params(%V1{} = trx, from) do
    trx
    |> to_call_params(from)
    |> Map.put(:nonce, Hex.encode_short_hex(trx.nonce))
  end

  # `to_call_params/2` serializes what `eth_call` needs, which omits the fields
  # that only matter once the node *signs* an envelope: without `type` the node
  # picks its own envelope kind, and without `accessList` a non-empty access
  # list is silently dropped from the transaction the caller asked it to sign.
  defp to_transaction_params(%V2{} = trx, from) do
    trx
    |> to_call_params(from)
    |> Map.put(:nonce, Hex.encode_short_hex(trx.nonce))
    |> Map.put(:type, "0x2")
    |> put_chain_id(trx.chain_id)
    |> Map.put(:accessList, encode_access_list(trx.access_list))
  end

  defp to_transaction_params(%Call{} = call, from), do: to_call_params(call, from)

  # `chainId` is optional in `GenericTransaction` but is not nullable, so omit
  # the key rather than sending an explicit JSON `null`.
  @spec put_chain_id(map(), non_neg_integer() | nil) :: map()
  defp put_chain_id(params, nil), do: params
  defp put_chain_id(params, chain_id), do: Map.put(params, :chainId, encode_quantity(chain_id))

  # `uint` per `execution-apis` `src/schemas/base-types.yaml`: lowercase, no
  # leading zeros. `Hex.encode_short_hex/1` strips leading zeros but emits
  # uppercase, which the pattern rejects.
  @spec encode_quantity(non_neg_integer()) :: String.t()
  defp encode_quantity(value) when is_integer(value) and value >= 0,
    do: "0x" <> String.downcase(Integer.to_string(value, 16))

  # `AccessList` per `execution-apis` `src/schemas/transaction.yaml`: a list of
  # `{address, storageKeys}` objects. `address` and `hash32` are both
  # lowercase-only patterns, so this uses `encode_hex/1`, not the uppercase
  # `encode_big_hex/1` the rest of this module reaches for.
  @spec encode_access_list(V2.access_list() | nil) :: [map()]
  defp encode_access_list(nil), do: []

  defp encode_access_list(entries) when is_list(entries) do
    Enum.map(entries, fn {address, storage_keys} ->
      %{address: Hex.encode_hex(address), storageKeys: Enum.map(storage_keys, &Hex.encode_hex/1)}
    end)
  end

  @doc false
  @spec to_call_params(V1.t() | V2.t() | Call.t(), <<_::160>> | nil) :: map()
  def to_call_params(%V1{} = trx, from) do
    %{
      from: nil_map(from, &Hex.encode_big_hex/1),
      to: nil_map(trx.to, &Hex.encode_big_hex/1),
      gasPrice: nil_map(trx.gas_price, &Hex.encode_short_hex/1),
      gas: nil_map(trx.gas_limit, &Hex.encode_short_hex/1),
      value: nil_map(trx.value, &Hex.encode_short_hex/1),
      # DATA type: bytes-preserving (big_hex), not QUANTITY (short_hex which strips
      # leading zeros and emits "0x0" for empty calldata — rejected by real nodes).
      # See V2's data encoding for the correct pattern.
      data: nil_map(trx.data, &Hex.encode_big_hex/1)
    }
  end

  def to_call_params(%V2{} = trx, from) do
    %{
      from: nil_map(from, &Hex.encode_big_hex/1),
      to: nil_map(trx.destination, &Hex.encode_big_hex/1),
      maxPriorityFeePerGas: nil_map(trx.max_priority_fee_per_gas, &Hex.encode_short_hex/1),
      maxFeePerGas: nil_map(trx.max_fee_per_gas, &Hex.encode_short_hex/1),
      gas: nil_map(trx.gas_limit, &Hex.encode_short_hex/1),
      value: nil_map(trx.amount, &Hex.encode_short_hex/1),
      data: nil_map(trx.data, &Hex.encode_big_hex/1)
    }
  end

  def to_call_params(%Call{} = call, from) do
    %{
      from: nil_map(call.from || from, &Hex.encode_big_hex/1),
      to: Hex.encode_big_hex(call.destination),
      gas: nil_map(call.gas, &Hex.encode_short_hex/1),
      value: nil_map(call.value, &Hex.encode_short_hex/1),
      data: Hex.encode_big_hex(call.data)
    }
  end

  @spec v1_gas_parameters(nil | number() | {number(), atom()}, number(), Keyword.t()) ::
          {:ok, {:v1, non_neg_integer()}} | {:error, term()}
  defp v1_gas_parameters(user_gas_price, buffer, rpc_opts) do
    gas_price_result =
      if is_nil(user_gas_price) do
        gas_price(rpc_opts)
      else
        {:ok, to_wei(user_gas_price)}
      end

    buffer_multiplier = if is_nil(user_gas_price), do: buffer, else: 1

    with {:ok, gas_price} <- gas_price_result do
      {:ok, {:v1, ceil(gas_price * buffer_multiplier)}}
    end
  end

  @spec v2_gas_parameters(
          nil | number() | {number(), atom()},
          nil | number() | {number(), atom()},
          number(),
          Keyword.t()
        ) :: {:ok, {:v2, non_neg_integer(), non_neg_integer()}} | {:error, term()}
  defp v2_gas_parameters(user_base_fee, user_priority_fee, buffer, rpc_opts) do
    base_fee_result =
      if is_nil(user_base_fee) do
        get_fee_history_base_fee(rpc_opts)
      else
        {:ok, to_wei(user_base_fee)}
      end

    max_priority_fee_per_gas_result =
      if is_nil(user_priority_fee) do
        max_priority_fee_per_gas(rpc_opts)
      else
        {:ok, to_wei(user_priority_fee)}
      end

    buffer_multiplier = if is_nil(user_base_fee), do: buffer, else: 1

    with {:ok, base_fee} <- base_fee_result,
         {:ok, max_priority_fee_per_gas} <- max_priority_fee_per_gas_result do
      {:ok, {:v2, ceil(base_fee * buffer_multiplier + max_priority_fee_per_gas), max_priority_fee_per_gas}}
    end
  end

  @spec get_fee_history_base_fee(Keyword.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  defp get_fee_history_base_fee(rpc_opts) do
    case fee_history(rpc_opts) do
      {:ok, %Cartouche.FeeHistory{base_fee_per_gas: [fee_history_base_fee | _]}} ->
        {:ok, fee_history_base_fee}

      {:ok, _} ->
        {:error, "missing fee history"}

      err ->
        err
    end
  end

  @spec nil_map(nil | term(), (term() -> term())) :: term() | nil
  defp nil_map(nil, _), do: nil
  defp nil_map(x, fun), do: fun.(x)

  @spec show_trace_revert(V1.t() | V2.t(), {:error, map()}, boolean(), Keyword.t()) :: {:error, map()}
  defp show_trace_revert(trx, trx_res, debug_trace, opts) do
    with {:error, %{code: 3, message: "execution reverted" <> _} = error} <- trx_res do
      {tracer, label} =
        if debug_trace,
          do: {&debug_trace_call/2, "debug_traceCall"},
          else: {&trace_call/2, "trace_call"}

      apply_trace(tracer, label, trx, opts, error, trx_res)
    end
  end

  @spec apply_trace(
          (V1.t() | V2.t(), Keyword.t() -> {:ok, term()} | {:error, term()}),
          String.t(),
          V1.t() | V2.t(),
          Keyword.t(),
          map(),
          {:error, map()}
        ) :: {:error, map()}
  defp apply_trace(tracer, label, trx, opts, error, trx_res) do
    case tracer.(trx, opts) do
      {:ok, trace} ->
        {:error, Map.put(error, :trace, trace)}

      err ->
        Logger.error("Failed to trace revert by `#{label}`: #{inspect(err)}")
        trx_res
    end
  end
end
