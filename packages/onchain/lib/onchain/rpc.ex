defmodule Onchain.RPC do
  @moduledoc """
  Ethereum JSON-RPC wrapper using cartouche's RPC client.

  Provides a curated API for common Ethereum RPC methods with consistent
  error tuples and option handling. All functions accept `:rpc_url`,
  `:timeout`, and `:block` options. Single RPC calls also accept an opt-in
  `:retry` policy. Omit `:retry` to preserve the underlying
  `Cartouche.RPC.send_rpc/3` single-attempt behavior. Pass
  `retry: [max_retries: 2, backoff_ms: 100]` to retry RPC/network errors before
  returning the final normalized error.

  ## Telemetry

  Every single-call RPC (`do_rpc/3`, all named wrappers, and `call/3`) plus
  `batch/2` is wrapped in `:telemetry.span/3` under the event prefix
  `[:onchain, :rpc, :request]` — emitting `:start`, `:stop`, and `:exception`
  events. Start metadata is `%{method: method}`; stop metadata is
  `%{method: method, status: :ok}` on success or
  `%{method: method, status: :error, error: reason}` on a returned error tuple
  (`method` is `"batch"` for `batch/2`). Attach a handler to measure latency or
  count failures per method.

  ## Error Format

  - Address validation: `{:error, {:invalid_address, input}}`
  - Data validation: `{:error, {:invalid_data, input}}`
  - Block validation: `{:error, {:invalid_block, input}}`
  - Block hash validation: `{:error, {:invalid_block_hash, input}}`
  - Tx hash validation: `{:error, {:invalid_tx_hash, input}}` (must be 32 bytes)
  - Transaction index validation: `{:error, {:invalid_transaction_index, input}}`
  - RPC/network errors: `{:error, {:rpc_error, map}}`
  - Method the node does not implement: `{:error, {:method_not_found, map}}`
  - Namespace disabled on the provider plan: `{:error, {:namespace_unavailable, map}}`
  - Node could not complete the request: `{:error, {:unavailable, map}}`

  For RPC errors, the map always has at least a `:message` key. JSON-RPC error
  responses from the node include `:code`; network/transport errors are wrapped
  with `inspect/1` as the message.

  ### Node-capability refusals

  A weaker node than this repo's archive endpoint routinely refuses a call for
  one of three reasons: the method is not implemented, the provider has disabled
  that namespace on the current plan, or the node cannot complete the request
  (historical state pruned, method the gateway does not route, transient
  overload). Classification runs once on the shared `do_rpc/3` result path and
  again on `batch/2`'s decode path (both item-level and top-level batch errors),
  so a codegen'd wrapper, a hand-written wrapper, `call/3` and a batched call
  apply the same rules to the same wire response.

  The classifier is uniform; the provider's wire response is not. Verified live
  on Alchemy mainnet 2026-08-25: historical `eth_feeHistory` at block 20_000_000
  answers `-32001 "Unable to complete request at this time."` as a single call
  (classified `{:unavailable, map}`), but the byte-identical request inside a
  JSON-RPC array batch answers `-32000 "Internal error"` — alone or alongside a
  healthy call — which stays `{:rpc_error, map}`. That is not a gap in the
  classifier: `-32000 "Internal error"` is indistinguishable from a genuine
  internal failure, and tagging it would invent a distinction the node does not
  make. Batching can therefore downgrade a classifiable refusal to an
  unclassifiable one; when a caller needs the capability signal, issue that
  probe as a single call. Unrecognized codes keep `{:error, {:rpc_error, map}}`
  unchanged — the classifier names distinguishable cases, it does not guess.

  Each classified map retains the observed `:code` and `:message` (and `:data`
  when the node sent it). Branch on the tag; inspect the map when you need the
  wire detail.

  - `{:error, {:method_not_found, map}}` — this node does not implement the
    method. The reliable standard signal is JSON-RPC `-32601` ("Method not
    found"). Hosted providers often misuse `-32600` ("Invalid Request") instead:
    Alchemy mainnet answers `-32600` `"Unsupported method: <method> on ETH_MAINNET"`
    and `-32600` `"eth_baseFee is not available on the ETH_MAINNET..."`. Those
    two message shapes are pinned from live responses; a bare `-32600` without
    them still passes through as `{:rpc_error, map}`, because other nodes use
    that code for genuinely malformed requests. Callers should pick a portable
    construction (see `base_fee/1`) or a different method.

  - `{:error, {:namespace_unavailable, map}}` — the method exists but this
    provider plan has disabled the namespace. Observed on Alchemy mainnet as
    `-32600` `"<method> is not available on the Free tier - upgrade to Pay As
    You Go, or Enterprise for access."` for `trace_*` and `debug_*`. Callers
    should use a plan that serves the namespace, or avoid it.

  - `{:error, {:unavailable, map}}` — the node refused to complete a request it
    otherwise accepts. Observed on Alchemy mainnet as HTTP 503 / `-32001`
    `"Unable to complete request at this time."` for `eth_feeHistory` at block
    20_000_000, while `eth_feeHistory` at `"latest"` succeeds on the same URL.
    The identical wire error is also returned for some unimplemented methods
    (`erigon_getHeaderByNumber`), so this is **not** a unique pruned-history
    signal — treat it as "this node cannot serve this request". Callers that
    need historical state should retry against an archive endpoint.

  Codes the classifier does not name, including `-32602` ("Invalid params" —
  also what reth answers for `eth_getStorageValues` with empty params, which is
  indistinguishable from a genuine bad-params error), reach the caller as
  `{:error, {:rpc_error, map}}` exactly as before.

  ### Revert errors (`code: 3`)

  When `eth_call` reverts, the node returns a JSON-RPC error with `code: 3`. The
  inner map is widened with extra fields populated by cartouche
  (see `t:Cartouche.RPC.rpc_error/0`) plus `:data` mirrored by Onchain
  (enriched internally by the Onchain.RPC.Helpers module):

  - `:revert` — the raw revert-data binary (present on `code: 3` when the node
    returned a `data` field; absent if the node omitted it). Use this for
    selector inspection or pass to ABI libraries that accept binaries.
  - `:data` — the same payload as a lowercase `0x`-prefixed hex string. Mirrored
    from `:revert` whenever the latter is set so callers can pipe it straight
    into `Onchain.ABI.decode_error/2` (which expects 0x hex, not raw bytes).
  - `:error_abi` — the matching custom-error signature `String.t()` from the
    `:errors` opt (e.g. `"InsufficientBalance(uint256,uint256)"`). Only present
    when the caller passed `errors:` AND the revert payload's selector matches
    one of those signatures (or a Solidity 0.8.x `Panic` variant — those decode
    to a human-readable string like `"arithmetic error: overflow or underflow"`).
  - `:error_params` — the decoded argument list for `:error_abi` (e.g.
    `[1_000, 500]` for `InsufficientBalance(1000, 500)`). Empty list `[]` for
    nullary errors. Same population rule as `:error_abi`.

  Pattern matches:

      # Revert without :errors opt — decode out-of-band via the hex :data mirror
      {:error, {:rpc_error, %{code: 3, data: hex_data}}} = result
      {:ok, %{error: signature, args: args}} =
        Onchain.ABI.decode_error(hex_data, ["InsufficientBalance(uint256,uint256)"])

      # Revert with matching :errors opt — already decoded inline
      {:error,
       {:rpc_error,
        %{code: 3, error_abi: "InsufficientBalance(uint256,uint256)", error_params: [1000, 500]}}} =
        result

  Existing `{:error, {:rpc_error, %{code:, message:}}}` matches still work — the
  revert fields are additive on the inner map.

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `eth_call/3` | Read-only contract call → raw hex response |
  | `eth_call!/3` | Same, raises on error |
  | `eth_send_raw_transaction/2` | Broadcast signed tx → tx hash |
  | `eth_send_raw_transaction!/2` | Same, raises on error |
  | `get_balance/2` | Account ETH balance in wei |
  | `get_balance!/2` | Same, raises on error |
  | `block_number/1` | Current block height |
  | `block_number!/1` | Same, raises on error |
  | `syncing/1` | Node sync status (`false` or sync-status map) |
  | `syncing!/1` | Same, raises on error |
  | `get_block_by_number/2` | Fetch block by number or tag → atom-keyed decoded map (same conventions as `get_transaction_by_hash`) |
  | `get_block_by_number!/2` | Same, raises on error |
  | `get_block_receipts/2` | Fetch every receipt in a block → parsed receipt maps |
  | `get_block_receipts!/2` | Same, raises on error |
  | `get_block_transaction_count_by_hash/2` | Transaction count for a block hash |
  | `get_block_transaction_count_by_hash!/2` | Same, raises on error |
  | `get_block_transaction_count_by_number/2` | Transaction count for a block number or tag |
  | `get_block_transaction_count_by_number!/2` | Same, raises on error |
  | `get_transaction_by_block_hash_and_index/3` | Fetch one transaction by block hash and position |
  | `get_transaction_by_block_hash_and_index!/3` | Same, raises on error |
  | `get_transaction_by_block_number_and_index/3` | Fetch one transaction by block number/tag and position |
  | `get_transaction_by_block_number_and_index!/3` | Same, raises on error |
  | `get_block_access_list/2` | Fetch an EIP-7928 block access list |
  | `get_block_access_list!/2` | Same, raises on error |
  | `chain_id/1` | Network chain ID |
  | `chain_id!/1` | Same, raises on error |
  | `eth_get_logs/2` | Fetch event logs by filter |
  | `eth_get_logs!/2` | Same, raises on error |
  | `get_transaction_receipt/2` | Transaction receipt by hash |
  | `get_transaction_receipt!/2` | Same, raises on error |
  | `get_transaction_count/2` | Account nonce (tx count) |
  | `get_transaction_count!/2` | Same, raises on error |
  | `eth_get_code/2` | Contract bytecode (or "0x" for EOAs) |
  | `eth_get_code!/2` | Same, raises on error |
  | `get_transaction_by_hash/2` | Full transaction details by hash |
  | `get_transaction_by_hash!/2` | Same, raises on error |
  | `call/3` | Generic JSON-RPC passthrough — any method, raw result |
  | `call!/3` | Same, raises on error |
  | `batch/2` | Generic JSON-RPC array batch — one HTTP round-trip for many raw calls |
  | `fee_history/2` | EIP-1559 fee history (`eth_feeHistory`) → `Cartouche.FeeHistory.t()` |
  | `fee_history!/2` | Same, raises on error |
  | `get_proof/3` | Account + storage Merkle proofs (`eth_getProof`) |
  | `get_proof!/3` | Same, raises on error |
  """

  use Descripex, namespace: "/rpc"

  import Onchain.RPC.Codegen
  import Onchain.RPC.Helpers, except: [do_rpc: 3]

  alias Onchain.RPC.Helpers

  @rpc_request_event [:onchain, :rpc, :request]
  @batch_method "batch"
  @content_type_json {"Content-Type", "application/json"}
  @default_ethereum_node "https://mainnet.infura.io"
  @default_retry_max_retries 2
  @default_retry_backoff_ms 100
  @no_retry_max_retries 0
  @no_backoff_ms 0
  # JSON-RPC 2.0 / observed hosted-provider refusal codes. Message patterns for
  # -32600 and -32001 are pinned from live Alchemy mainnet responses (2026-08-25).
  @jsonrpc_invalid_request -32_600
  @jsonrpc_method_not_found -32_601
  @jsonrpc_unable_to_complete -32_001

  # --- eth_call ---

  api(:eth_call, "Execute a read-only contract call (eth_call).",
    params: [
      address: [kind: :value, description: "Contract address as 0x hex string or 20-byte binary"],
      data: [kind: :value, description: "0x-prefixed hex-encoded calldata (from ABI.encode_call)"],
      opts: [
        kind: :value,
        default: [],
        description:
          ~s|Options: :rpc_url, :timeout, :block, :errors. :errors is a list of Solidity custom-error signatures (e.g. ["InsufficientBalance(uint256,uint256)"]). When the call reverts with matching revert data, the error map carries decoded :error_abi + :error_params alongside the always-present :revert binary. See @moduledoc "Error Format" for the full shape and pattern-match examples.|
      ]
    ],
    returns: %{
      type: "{:ok, hex_string} | {:error, term}",
      description: "Raw 0x-prefixed hex response from the contract",
      example: "0x000000000000000000000000000000000000000000000000000000000000002a"
    }
  )

  @doc """
  Execute a read-only contract call (`eth_call`).

  ## Options

  - `:rpc_url` — node URL (overrides `Application.get_env(:cartouche, :ethereum_node)`)
  - `:timeout` — request timeout in ms (default 30_000)
  - `:block` — block number / tag / 0x hex (default `"latest"`)
  - `:errors` — list of Solidity custom-error signatures, e.g.
    `["InsufficientBalance(uint256,uint256)", "Unauthorized()"]`. When the call
    reverts with matching revert data, the error map carries decoded
    `:error_abi` + `:error_params` alongside the raw `:revert` binary and its
    hex mirror `:data`.

  ## Revert handling

  On `code: 3` reverts the inner map widens — see the module's "Error Format"
  section. Quick pattern-match shape:

      case Onchain.RPC.eth_call(token, calldata, errors: ["InsufficientBalance(uint256,uint256)"]) do
        {:ok, hex_result} ->
          # Decode hex_result with Onchain.ABI.decode_response/2
          :ok

        {:error, {:rpc_error, %{code: 3, error_abi: "InsufficientBalance(uint256,uint256)", error_params: [requested, available]}}} ->
          {:insufficient, requested, available}

        {:error, {:rpc_error, %{code: 3, data: hex_data}}} ->
          # Custom error not in :errors list (or :errors omitted) — fall back
          # to the hex-mirrored revert payload and decode out-of-band.
          # `Onchain.ABI.decode_error/2` expects 0x hex, which is exactly :data.
          Onchain.ABI.decode_error(hex_data, ["MyError(uint256)"])

        {:error, {:rpc_error, %{message: msg}}} ->
          {:rpc, msg}
      end
  """
  @spec eth_call(String.t() | binary(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def eth_call(address, data, opts \\ []) do
    with {:ok, hex_addr} <- ensure_hex_address(address),
         {:ok, hex_data} <- ensure_hex_data(data),
         {:ok, block} <- normalize_block(Keyword.get(opts, :block, "latest")) do
      call_params = %{"to" => hex_addr, "data" => hex_data}

      do_rpc("eth_call", [call_params, block], to_rpc_opts(opts))
    end
  end

  # --- eth_call! ---

  api(:eth_call!, "Execute a read-only contract call. Raises on error.",
    params: [
      address: [kind: :value, description: "Contract address as 0x hex string or 20-byte binary"],
      data: [kind: :value, description: "0x-prefixed hex-encoded calldata"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :string, description: "Raw 0x-prefixed hex response"}
  )

  @spec eth_call!(String.t() | binary(), String.t(), keyword()) :: String.t()
  def eth_call!(address, data, opts \\ []) do
    case eth_call(address, data, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "eth_call failed: #{inspect(reason)}"
    end
  end

  # --- eth_estimate_gas ---

  api(:eth_estimate_gas, "Estimate the gas a transaction would consume.",
    params: [
      tx_params: [
        kind: :value,
        description:
          "Transaction-params map with atom keys. Recognized: :from, :to, :data, :value, :gas, :gas_price, :max_fee_per_gas, :max_priority_fee_per_gas, :access_list. Absent keys are omitted from the call object."
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Estimated gas units as an integer"
    }
  )

  @spec eth_estimate_gas(map(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def eth_estimate_gas(tx_params, opts \\ []) when is_map(tx_params) do
    with {:ok, call_object} <- build_estimate_gas_params(tx_params),
         {:ok, block} <- normalize_block(Keyword.get(opts, :block, "latest")) do
      do_rpc(
        "eth_estimateGas",
        [call_object, block],
        Keyword.put(to_rpc_opts(opts), :decode, :hex_unsigned)
      )
    end
  end

  # --- eth_estimate_gas! ---

  api(:eth_estimate_gas!, "Estimate the gas a transaction would consume. Raises on error.",
    params: [
      tx_params: [
        kind: :value,
        description: "Transaction-params map with atom keys (see eth_estimate_gas/2)"
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :integer, description: "Estimated gas units"}
  )

  @spec eth_estimate_gas!(map(), keyword()) :: non_neg_integer()
  def eth_estimate_gas!(tx_params, opts \\ []) do
    case eth_estimate_gas(tx_params, opts) do
      {:ok, gas} -> gas
      {:error, reason} -> raise "eth_estimate_gas failed: #{inspect(reason)}"
    end
  end

  # --- eth_send_raw_transaction ---

  api(:eth_send_raw_transaction, "Broadcast a signed transaction.",
    params: [
      data: [kind: :value, description: "0x-prefixed hex-encoded signed transaction"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, tx_hash} | {:error, term}",
      description: "Transaction hash as 0x hex string",
      example: "0xabc123..."
    }
  )

  @spec eth_send_raw_transaction(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defrpc(:eth_send_raw_transaction, method: "eth_sendRawTransaction", arg: :data)

  # --- eth_send_raw_transaction! ---

  api(:eth_send_raw_transaction!, "Broadcast a signed transaction. Raises on error.",
    params: [
      data: [kind: :value, description: "0x-prefixed hex-encoded signed transaction"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: :string, description: "Transaction hash as 0x hex string"}
  )

  @spec eth_send_raw_transaction!(String.t(), keyword()) :: String.t()
  defrpc_bang(:eth_send_raw_transaction, args: [:data])

  # --- get_balance ---

  api(:get_balance, "Get the ETH balance of an address in wei.",
    params: [
      address: [kind: :value, description: "Account address as 0x hex string or 20-byte binary"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer} | {:error, term}",
      description: "Balance in wei"
    }
  )

  @spec get_balance(String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defrpc(:get_balance, method: "eth_getBalance", arg: :address, decode: :hex_unsigned)

  # --- get_balance! ---

  api(:get_balance!, "Get the ETH balance of an address in wei. Raises on error.",
    params: [
      address: [kind: :value, description: "Account address as 0x hex string or 20-byte binary"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :non_neg_integer, description: "Balance in wei"}
  )

  @spec get_balance!(String.t() | binary(), keyword()) :: non_neg_integer()
  defrpc_bang(:get_balance, args: [:address])

  # --- block_number ---

  api(:block_number, "Get the current block height.",
    params: [
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer} | {:error, term}",
      description: "Current block number"
    }
  )

  @spec block_number(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  defrpc(:block_number, method: "eth_blockNumber", decode: :hex_unsigned)

  # --- block_number! ---

  api(:block_number!, "Get the current block height. Raises on error.",
    params: [
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: :non_neg_integer, description: "Current block number"}
  )

  @spec block_number!(keyword()) :: non_neg_integer()
  defrpc_bang(:block_number)

  # --- syncing ---

  api(:syncing, "Get the node's sync status (eth_syncing).",
    params: [
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, false | map} | {:error, term}",
      description:
        "`false` when the node is fully synced; otherwise a raw sync-status map with hex-encoded fields (`startingBlock`, `currentBlock`, `highestBlock`, sometimes snap-sync fields). Field shape varies by client — caller decodes."
    }
  )

  @spec syncing(keyword()) :: {:ok, false | map()} | {:error, term()}
  defrpc(:syncing, method: "eth_syncing")

  # --- syncing! ---

  api(:syncing!, "Get the node's sync status. Raises on error.",
    params: [
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: "false | map", description: "`false` when synced, sync-status map otherwise"}
  )

  @spec syncing!(keyword()) :: false | map()
  defrpc_bang(:syncing)

  # --- get_block_by_number ---

  api(:get_block_by_number, "Fetch a block by number or tag (eth_getBlockByNumber).",
    params: [
      block_id: [
        kind: :value,
        description:
          ~s{Block number (integer) or tag string ("latest", "finalized", "pending", "earliest", "safe", or "0x..." hex)}
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, map | nil} | {:error, term}",
      description:
        "Decoded block map (atom keys): quantities as integers, miner checksummed, " <>
          "blooms/hashes/roots/extra_data as 0x hex; transactions are tx hashes or decoded maps if full txs requested",
      example: ~s(%{number: 20_000_000, timestamp: 1_717_281_407, hash: "0x...", transactions: ["0x...", ...]})
    }
  )

  @block_tags Helpers.block_tags()

  # Canonical log-filter keys accepted by eth_get_logs/2.
  # Unknown keys are rejected loudly rather than silently dropped (Task 56).
  # Canonical JSON-RPC string keys ("fromBlock"/"toBlock"/"address"/"topics"/"blockHash")
  # are normalized to atoms before validation (Task 60).
  # `:block_hash` is mutually exclusive with `:from_block`/`:to_block` per EIP-1474 (Task 61).
  @allowed_log_filter_keys [:address, :topics, :from_block, :to_block, :block_hash]

  # JSON-RPC camelCase string keys → canonical atom keys. Used by
  # normalize_filter_keys/1 to accept JSON-RPC-style filter shapes (Task 60).
  @camel_case_filter_aliases %{
    "fromBlock" => :from_block,
    "toBlock" => :to_block,
    "address" => :address,
    "topics" => :topics,
    "blockHash" => :block_hash
  }

  @spec get_block_by_number(integer() | String.t(), keyword()) ::
          {:ok, map() | nil} | {:error, term()}
  def get_block_by_number(block_id, opts \\ [])

  def get_block_by_number(block_id, opts) when is_integer(block_id) and block_id >= 0 do
    hex = Onchain.Hex.from_integer(block_id)

    "eth_getBlockByNumber"
    |> do_rpc([hex, false], to_rpc_opts(opts))
    |> decode_get_block_result()
  end

  def get_block_by_number(tag, opts) when tag in @block_tags do
    "eth_getBlockByNumber"
    |> do_rpc([tag, false], to_rpc_opts(opts))
    |> decode_get_block_result()
  end

  def get_block_by_number("0x" <> _ = hex_num, opts) do
    if Onchain.Hex.valid?(hex_num) do
      "eth_getBlockByNumber"
      |> do_rpc([hex_num, false], to_rpc_opts(opts))
      |> decode_get_block_result()
    else
      {:error, {:invalid_block_id, hex_num}}
    end
  end

  def get_block_by_number(block_id, _opts), do: {:error, {:invalid_block_id, block_id}}

  # --- get_block_by_number! ---

  api(:get_block_by_number!, "Fetch a block by number or tag. Raises on error.",
    params: [
      block_id: [
        kind: :value,
        description: "Block number (integer) or tag string"
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: "map | nil", description: "Decoded atom-keyed block map"}
  )

  @spec get_block_by_number!(integer() | String.t(), keyword()) :: map() | nil
  def get_block_by_number!(block_id, opts \\ []) do
    case get_block_by_number(block_id, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "get_block_by_number failed: #{inspect(reason)}"
    end
  end

  # --- block-level reads ---

  api(:get_block_receipts, "Fetch every receipt in a block (eth_getBlockReceipts).",
    params: [
      block: [
        kind: :value,
        description: "Block number, tag, or 0x-prefixed 32-byte block hash"
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, [map] | nil} | {:error, term}",
      description: "Parsed receipt maps matching get_transaction_receipt/2, or nil when the block is unknown"
    }
  )

  @spec get_block_receipts(integer() | String.t(), keyword()) ::
          {:ok, [map()] | nil} | {:error, term()}
  defrpc(:get_block_receipts,
    method: "eth_getBlockReceipts",
    arg: :block,
    decode: :receipt_list
  )

  api(:get_block_receipts!, "Fetch every receipt in a block. Raises on error.",
    params: [
      block: [kind: :value, description: "Block number, tag, or 0x-prefixed 32-byte block hash"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: "[map] | nil", description: "Parsed receipt maps or nil"}
  )

  @spec get_block_receipts!(integer() | String.t(), keyword()) :: [map()] | nil
  defrpc_bang(:get_block_receipts, args: [:block])

  api(
    :get_block_transaction_count_by_hash,
    "Get a block's transaction count by hash (eth_getBlockTransactionCountByHash).",
    params: [
      block_hash: [kind: :value, description: "0x-prefixed 32-byte block hash"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer | nil} | {:error, term}",
      description: "Transaction count, or nil when the block is unknown"
    }
  )

  @spec get_block_transaction_count_by_hash(String.t(), keyword()) ::
          {:ok, non_neg_integer() | nil} | {:error, term()}
  defrpc(:get_block_transaction_count_by_hash,
    method: "eth_getBlockTransactionCountByHash",
    arg: :block_hash,
    decode: :nullable_hex_unsigned
  )

  api(
    :get_block_transaction_count_by_hash!,
    "Get a block's transaction count by hash. Raises on error.",
    params: [
      block_hash: [kind: :value, description: "0x-prefixed 32-byte block hash"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: "non_neg_integer | nil", description: "Transaction count or nil"}
  )

  @spec get_block_transaction_count_by_hash!(String.t(), keyword()) ::
          non_neg_integer() | nil
  defrpc_bang(:get_block_transaction_count_by_hash, args: [:block_hash])

  api(
    :get_block_transaction_count_by_number,
    "Get a block's transaction count by number or tag (eth_getBlockTransactionCountByNumber).",
    params: [
      block: [kind: :value, description: "Block number, tag, or 0x-prefixed quantity"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer | nil} | {:error, term}",
      description: "Transaction count, or nil when the block is unknown"
    }
  )

  @spec get_block_transaction_count_by_number(integer() | String.t(), keyword()) ::
          {:ok, non_neg_integer() | nil} | {:error, term()}
  defrpc(:get_block_transaction_count_by_number,
    method: "eth_getBlockTransactionCountByNumber",
    arg: :block,
    decode: :nullable_hex_unsigned
  )

  api(
    :get_block_transaction_count_by_number!,
    "Get a block's transaction count by number or tag. Raises on error.",
    params: [
      block: [kind: :value, description: "Block number, tag, or 0x-prefixed quantity"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: "non_neg_integer | nil", description: "Transaction count or nil"}
  )

  @spec get_block_transaction_count_by_number!(integer() | String.t(), keyword()) ::
          non_neg_integer() | nil
  defrpc_bang(:get_block_transaction_count_by_number, args: [:block])

  api(
    :get_transaction_by_block_hash_and_index,
    "Fetch a transaction by block hash and position (eth_getTransactionByBlockHashAndIndex).",
    params: [
      block_hash: [kind: :value, description: "0x-prefixed 32-byte block hash"],
      transaction_index: [kind: :value, description: "Zero-based non-negative integer or 0x quantity"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, map | nil} | {:error, term}",
      description: "Parsed transaction map, or nil when the block or index is unknown"
    }
  )

  @spec get_transaction_by_block_hash_and_index(String.t(), non_neg_integer() | String.t(), keyword()) ::
          {:ok, map() | nil} | {:error, term()}
  defrpc(:get_transaction_by_block_hash_and_index,
    method: "eth_getTransactionByBlockHashAndIndex",
    arg: :block_hash_and_index,
    decode: :transaction
  )

  api(
    :get_transaction_by_block_hash_and_index!,
    "Fetch a transaction by block hash and position. Raises on error.",
    params: [
      block_hash: [kind: :value, description: "0x-prefixed 32-byte block hash"],
      transaction_index: [kind: :value, description: "Zero-based non-negative integer or 0x quantity"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: "map | nil", description: "Parsed transaction map or nil"}
  )

  @spec get_transaction_by_block_hash_and_index!(
          String.t(),
          non_neg_integer() | String.t(),
          keyword()
        ) :: map() | nil
  defrpc_bang(:get_transaction_by_block_hash_and_index, args: [:block_hash, :transaction_index])

  api(
    :get_transaction_by_block_number_and_index,
    "Fetch a transaction by block number/tag and position (eth_getTransactionByBlockNumberAndIndex).",
    params: [
      block: [kind: :value, description: "Block number, tag, or 0x-prefixed quantity"],
      transaction_index: [kind: :value, description: "Zero-based non-negative integer or 0x quantity"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, map | nil} | {:error, term}",
      description: "Parsed transaction map, or nil when the block or index is unknown"
    }
  )

  @spec get_transaction_by_block_number_and_index(
          integer() | String.t(),
          non_neg_integer() | String.t(),
          keyword()
        ) :: {:ok, map() | nil} | {:error, term()}
  defrpc(:get_transaction_by_block_number_and_index,
    method: "eth_getTransactionByBlockNumberAndIndex",
    arg: :block_and_index,
    decode: :transaction
  )

  api(
    :get_transaction_by_block_number_and_index!,
    "Fetch a transaction by block number/tag and position. Raises on error.",
    params: [
      block: [kind: :value, description: "Block number, tag, or 0x-prefixed quantity"],
      transaction_index: [kind: :value, description: "Zero-based non-negative integer or 0x quantity"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: "map | nil", description: "Parsed transaction map or nil"}
  )

  @spec get_transaction_by_block_number_and_index!(
          integer() | String.t(),
          non_neg_integer() | String.t(),
          keyword()
        ) :: map() | nil
  defrpc_bang(:get_transaction_by_block_number_and_index, args: [:block, :transaction_index])

  api(:get_block_access_list, "Fetch an EIP-7928 block access list (eth_getBlockAccessList).",
    params: [
      block: [
        kind: :value,
        description: "Block number, tag, or 0x-prefixed 32-byte block hash"
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, [map] | nil} | {:error, term}",
      description: "Raw camelCase EIP-7928 account-access entries, or nil when unavailable"
    }
  )

  @spec get_block_access_list(integer() | String.t(), keyword()) ::
          {:ok, [map()] | nil} | {:error, term()}
  defrpc(:get_block_access_list,
    method: "eth_getBlockAccessList",
    arg: :block,
    decode: :block_access_list
  )

  api(:get_block_access_list!, "Fetch an EIP-7928 block access list. Raises on error.",
    params: [
      block: [kind: :value, description: "Block number, tag, or 0x-prefixed 32-byte block hash"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: "[map] | nil", description: "Raw camelCase account-access entries or nil"}
  )

  @spec get_block_access_list!(integer() | String.t(), keyword()) :: [map()] | nil
  defrpc_bang(:get_block_access_list, args: [:block])

  # --- chain_id ---

  api(:chain_id, "Get the network chain ID.",
    params: [
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer} | {:error, term}",
      description: "Chain ID (1 = mainnet, 11155111 = sepolia, etc.)"
    }
  )

  @spec chain_id(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  defrpc(:chain_id, method: "eth_chainId", decode: :hex_unsigned)

  # --- chain_id! ---

  api(:chain_id!, "Get the network chain ID. Raises on error.",
    params: [
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: :non_neg_integer, description: "Chain ID integer"}
  )

  @spec chain_id!(keyword()) :: non_neg_integer()
  defrpc_bang(:chain_id)

  # --- get_transaction_receipt ---

  api(:get_transaction_receipt, "Get a transaction receipt by hash (eth_getTransactionReceipt).",
    params: [
      tx_hash: [kind: :value, description: "0x-prefixed hex transaction hash"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, map | nil} | {:error, term}",
      description: "Parsed receipt map, or nil if the transaction is pending/unknown"
    }
  )

  @spec get_transaction_receipt(String.t(), keyword()) :: {:ok, map() | nil} | {:error, term()}
  def get_transaction_receipt(tx_hash, opts \\ []) do
    with {:ok, _hex} <- ensure_tx_hash(tx_hash) do
      case do_rpc("eth_getTransactionReceipt", [tx_hash], to_rpc_opts(opts)) do
        {:ok, nil} -> {:ok, nil}
        {:ok, receipt} when is_map(receipt) -> {:ok, parse_receipt(receipt)}
        error -> error
      end
    end
  end

  # --- get_transaction_receipt! ---

  api(:get_transaction_receipt!, "Get a transaction receipt by hash. Raises on error.",
    params: [
      tx_hash: [kind: :value, description: "0x-prefixed hex transaction hash"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: "map | nil", description: "Parsed receipt map or nil"}
  )

  @spec get_transaction_receipt!(String.t(), keyword()) :: map() | nil
  def get_transaction_receipt!(tx_hash, opts \\ []) do
    case get_transaction_receipt(tx_hash, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "get_transaction_receipt failed: #{inspect(reason)}"
    end
  end

  # --- get_transaction_count ---

  api(:get_transaction_count, "Get the transaction count (nonce) of an address.",
    params: [
      address: [kind: :value, description: "Account address as 0x hex string or 20-byte binary"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer} | {:error, term}",
      description: "Transaction count (nonce)"
    }
  )

  @spec get_transaction_count(String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defrpc(:get_transaction_count,
    method: "eth_getTransactionCount",
    arg: :address,
    decode: :hex_unsigned
  )

  # --- get_transaction_count! ---

  api(
    :get_transaction_count!,
    "Get the transaction count (nonce) of an address. Raises on error.",
    params: [
      address: [kind: :value, description: "Account address as 0x hex string or 20-byte binary"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :non_neg_integer, description: "Transaction count (nonce)"}
  )

  @spec get_transaction_count!(String.t() | binary(), keyword()) :: non_neg_integer()
  defrpc_bang(:get_transaction_count, args: [:address])

  # --- eth_get_code ---

  api(:eth_get_code, "Fetch contract bytecode at an address (eth_getCode).",
    params: [
      address: [kind: :value, description: "Account address as 0x hex string or 20-byte binary"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, hex_string} | {:error, term}",
      description: "0x-prefixed bytecode hex string, or \"0x\" for EOA addresses",
      example: ~s("0x" for EOAs, "0x6080604052..." for contracts)
    }
  )

  @spec eth_get_code(String.t() | binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  defrpc(:eth_get_code, method: "eth_getCode", arg: :address)

  # --- eth_get_code! ---

  api(:eth_get_code!, "Fetch contract bytecode at an address. Raises on error.",
    params: [
      address: [kind: :value, description: "Account address as 0x hex string or 20-byte binary"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :string, description: "0x-prefixed bytecode hex string"}
  )

  @spec eth_get_code!(String.t() | binary(), keyword()) :: String.t()
  defrpc_bang(:eth_get_code, args: [:address])

  # --- get_transaction_by_hash ---

  api(
    :get_transaction_by_hash,
    "Get full transaction details by hash (eth_getTransactionByHash).",
    params: [
      tx_hash: [kind: :value, description: "0x-prefixed hex transaction hash"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, map | nil} | {:error, term}",
      description: "Parsed transaction map, or nil if the transaction is unknown"
    }
  )

  @spec get_transaction_by_hash(String.t(), keyword()) :: {:ok, map() | nil} | {:error, term()}
  def get_transaction_by_hash(tx_hash, opts \\ []) do
    with {:ok, _hex} <- ensure_tx_hash(tx_hash) do
      case do_rpc("eth_getTransactionByHash", [tx_hash], to_rpc_opts(opts)) do
        {:ok, nil} -> {:ok, nil}
        {:ok, tx} when is_map(tx) -> {:ok, parse_transaction_map(tx)}
        error -> error
      end
    end
  end

  # --- get_transaction_by_hash! ---

  api(:get_transaction_by_hash!, "Get full transaction details by hash. Raises on error.",
    params: [
      tx_hash: [kind: :value, description: "0x-prefixed hex transaction hash"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: "map | nil", description: "Parsed transaction map or nil"}
  )

  @spec get_transaction_by_hash!(String.t(), keyword()) :: map() | nil
  def get_transaction_by_hash!(tx_hash, opts \\ []) do
    case get_transaction_by_hash(tx_hash, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "get_transaction_by_hash failed: #{inspect(reason)}"
    end
  end

  # --- eth_get_logs ---

  api(:eth_get_logs, "Fetch event logs matching a filter (eth_getLogs).",
    params: [
      filter: [
        kind: :value,
        description:
          ~s|Filter map. Atom keys: :address (hex string), :topics (list), :from_block (integer or tag), :to_block (integer or tag), :block_hash (32-byte hex). Canonical JSON-RPC camelCase string keys ("fromBlock", "toBlock", "address", "topics", "blockHash") are accepted as aliases. If both an atom key and its camelCase alias are present, the atom key wins (the alias value is silently dropped). :block_hash is mutually exclusive with :from_block / :to_block per EIP-1474. Unknown keys return {:error, {:invalid_filter_key, key}}.|
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, [log_map]} | {:error, term}",
      description:
        "List of log maps with keys: address, topics, data, block_number, transaction_hash, log_index, transaction_index, removed. Errors: {:invalid_filter_key, key} for unknown filter keys; {:invalid_filter, {field, value}} for bad values; {:invalid_filter, {:block_hash_mutually_exclusive, present}} when :block_hash is combined with :from_block / :to_block."
    }
  )

  @spec eth_get_logs(map(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def eth_get_logs(filter, opts \\ []) when is_map(filter) do
    normalized = normalize_filter_keys(filter)

    with :ok <- validate_log_filter_keys(normalized),
         {:ok, rpc_filter} <- build_log_filter(normalized) do
      case do_rpc("eth_getLogs", [rpc_filter], to_rpc_opts(opts)) do
        {:ok, logs} when is_list(logs) ->
          {:ok, Enum.map(logs, &parse_log/1)}

        {:ok, other} ->
          {:error, {:rpc_error, %{message: "unexpected response: #{inspect(other)}"}}}

        error ->
          error
      end
    end
  end

  # Rewrites canonical JSON-RPC camelCase string keys to their atom equivalents.
  # Other string keys pass through unchanged (and trip validate_log_filter_keys/1).
  # Atom keys take precedence on conflict (e.g. both :from_block and "fromBlock" set).
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

  # --- eth_get_logs! ---

  api(:eth_get_logs!, "Fetch event logs matching a filter. Raises on error.",
    params: [
      filter: [kind: :value, description: "Filter map (see eth_get_logs/2)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: "[log_map]", description: "List of parsed log maps"}
  )

  @spec eth_get_logs!(map(), keyword()) :: [map()]
  def eth_get_logs!(filter, opts \\ []) do
    case eth_get_logs(filter, opts) do
      {:ok, logs} -> logs
      {:error, reason} -> raise "eth_get_logs failed: #{inspect(reason)}"
    end
  end

  # --- call (generic JSON-RPC passthrough) ---

  api(:call, "Generic JSON-RPC passthrough — invoke any method not covered by a named wrapper.",
    params: [
      method: [
        kind: :value,
        description:
          ~s|JSON-RPC method name, e.g. "eth_getStorageAt", "debug_traceTransaction", "trace_call", "eth_feeHistory"|
      ],
      params: [
        kind: :value,
        description: "List of params for the method, in the order the JSON-RPC spec requires"
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, term} | {:error, term}",
      description:
        "Raw decoded JSON result (no further decoding — caller knows what they asked for) or wrapped error tuple"
    }
  )

  @spec call(String.t(), [term()], keyword()) :: {:ok, term()} | {:error, term()}
  def call(method, params, opts \\ []) when is_binary(method) and is_list(params) do
    do_rpc(method, params, to_rpc_opts(opts))
  end

  # --- call! ---

  api(:call!, "Generic JSON-RPC passthrough. Raises on error.",
    params: [
      method: [kind: :value, description: "JSON-RPC method name"],
      params: [kind: :value, description: "List of params for the method"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: :term, description: "Raw decoded JSON result"}
  )

  @spec call!(String.t(), [term()], keyword()) :: term()
  def call!(method, params, opts \\ []) do
    case call(method, params, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "RPC #{method} failed: #{inspect(reason)}"
    end
  end

  # --- batch (generic JSON-RPC array batch) ---

  api(:batch, "Generic JSON-RPC array batch — invoke many methods in one HTTP request.",
    params: [
      requests: [
        kind: :value,
        description:
          ~s|List of {method, params} tuples, e.g. [{"eth_blockNumber", []}, {"eth_chainId", []}]. Results are returned in the same order as requests even if the node responds out of order.|
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, [term]} | {:error, term}",
      description:
        "Raw decoded JSON results in request order, or a wrapped RPC/transport error. If any response item is a JSON-RPC error, the batch returns that error."
    }
  )

  @doc """
  Invoke many raw JSON-RPC calls in one HTTP request.

  Each request is a `{method, params}` tuple. Results are returned in request
  order even when the node returns the JSON-RPC response array out of order.
  """
  @spec batch([{String.t(), [term()]}], keyword()) :: {:ok, [term()]} | {:error, term()}
  def batch(requests, opts \\ [])

  def batch([], _opts), do: {:ok, []}

  def batch(requests, opts) when is_list(requests) do
    :telemetry.span(@rpc_request_event, %{method: @batch_method}, fn ->
      result = do_batch(requests, to_rpc_opts(opts))
      {result, rpc_request_stop_metadata(@batch_method, result)}
    end)
  end

  # --- fee_history (eth_feeHistory) ---

  api(
    :fee_history,
    "Fetch base-fee history and per-block priority-fee percentiles (eth_feeHistory).",
    params: [
      block_count: [
        kind: :value,
        description: "Number of recent blocks to query, 1..1024 (EIP-1474 cap)"
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          "Options: :newest_block (default \"latest\"), :reward_percentiles (default [50] — list of ints 0..100, monotonically non-decreasing), :rpc_url, :timeout"
      ]
    ],
    returns: %{
      type: "{:ok, Cartouche.FeeHistory.t()} | {:error, term}",
      description:
        "Deserialized fee history struct: oldest_block, base_fee_per_gas (block_count + 1 entries), gas_used_ratio, reward (block_count rows × length(reward_percentiles) cols)"
    }
  )

  @spec fee_history(pos_integer(), keyword()) ::
          {:ok, Cartouche.FeeHistory.t()} | {:error, term()}
  def fee_history(block_count, opts \\ []) do
    percentiles = Keyword.get(opts, :reward_percentiles, [50])

    with {:ok, hex_count} <- ensure_block_count(block_count),
         {:ok, newest} <- normalize_block(Keyword.get(opts, :newest_block, "latest")),
         :ok <- ensure_reward_percentiles(percentiles),
         {:ok, raw} <-
           do_rpc("eth_feeHistory", [hex_count, newest, percentiles], to_rpc_opts(opts)) do
      {:ok, Cartouche.FeeHistory.deserialize(raw)}
    end
  end

  # --- fee_history! ---

  api(:fee_history!, "Fetch fee history. Raises on error.",
    params: [
      block_count: [kind: :value, description: "Number of recent blocks to query, 1..1024"],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :newest_block, :reward_percentiles, :rpc_url, :timeout"
      ]
    ],
    returns: %{type: "Cartouche.FeeHistory.t()", description: "Deserialized fee history struct"}
  )

  @spec fee_history!(pos_integer(), keyword()) :: Cartouche.FeeHistory.t()
  def fee_history!(block_count, opts \\ []) do
    case fee_history(block_count, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "fee_history failed: #{inspect(reason)}"
    end
  end

  # --- get_proof ---

  api(:get_proof, "Fetch Merkle proof for an account and storage slots (eth_getProof).",
    params: [
      address: [kind: :value, description: "Account address as 0x hex string or 20-byte binary"],
      storage_keys: [
        kind: :value,
        description: "List of 0x-prefixed 32-byte hex storage slot keys (may be empty for account-only proofs)"
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, map} | {:error, term}",
      description:
        "Atom-keyed proof map: address (checksummed), balance (integer wei), nonce (integer), code_hash (0x hex), storage_hash (0x hex), account_proof ([0x hex]), storage_proof ([%{key, value, proof}])"
    }
  )

  @spec get_proof(String.t() | binary(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def get_proof(address, storage_keys, opts \\ []) do
    with {:ok, hex_addr} <- ensure_hex_address(address),
         {:ok, normalized_keys} <- validate_storage_keys(storage_keys),
         {:ok, block} <- normalize_block(Keyword.get(opts, :block, "latest")),
         {:ok, raw} <-
           do_rpc("eth_getProof", [hex_addr, normalized_keys, block], to_rpc_opts(opts)) do
      {:ok, parse_proof(raw)}
    end
  end

  # --- get_proof! ---

  api(:get_proof!, "Fetch Merkle proof for an account and storage slots. Raises on error.",
    params: [
      address: [kind: :value, description: "Account address as 0x hex string or 20-byte binary"],
      storage_keys: [
        kind: :value,
        description: "List of 0x-prefixed 32-byte hex storage slot keys (may be empty for account-only proofs)"
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: "map", description: "Atom-keyed proof map (see get_proof/3)"}
  )

  @spec get_proof!(String.t() | binary(), [String.t()], keyword()) :: map()
  def get_proof!(address, storage_keys, opts \\ []) do
    case get_proof(address, storage_keys, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "get_proof failed: #{inspect(reason)}"
    end
  end

  # --- base_fee ---

  # NOTE (portability): cartouche 0.8.0 exposes `Cartouche.RPC.base_fee/1`, which calls the
  # `eth_baseFee` JSON-RPC method. That method is an Erigon extension — it is absent from the
  # vendored OpenRPC spec, and hosted providers reject it (Alchemy mainnet answers
  # `-32600 "eth_baseFee is not available on the ETH_MAINNET"`). Wrapping it directly would
  # give this library a fee read that works on the maintainers' node and fails for consumers
  # on the most common hosted endpoints. We therefore read the value from the pending block
  # header instead, which every EIP-1559 node serves. Verified equivalent against reth
  # v2.5.1 in a single batch request: `eth_baseFee` == pending `baseFeePerGas` == 71_739_926,
  # while `latest` was 68_871_658 — so the pending header, not the latest one, carries
  # `eth_baseFee`'s "next block" semantics.

  api(:base_fee, "Get the EIP-1559 base fee per gas for the next block.",
    params: [
      opts: [
        kind: :value,
        default: [],
        description:
          ~s{Options: :block (default "pending" — the next block's base fee; pass "latest" for the most recent mined block), :rpc_url, :timeout}
      ]
    ],
    returns: %{
      type: "{:ok, non_neg_integer | nil} | {:error, term}",
      description:
        "Base fee per gas in wei, or nil for a pre-EIP-1559 block. Read from the block header, so it works on any EIP-1559 node rather than only those implementing Erigon's eth_baseFee.",
      example: "71_739_926"
    }
  )

  @spec base_fee(keyword()) :: {:ok, non_neg_integer() | nil} | {:error, term()}
  def base_fee(opts \\ []) do
    {block, rpc_opts} = Keyword.pop(opts, :block, "pending")

    case get_block_by_number(block, rpc_opts) do
      {:ok, nil} -> {:error, {:block_not_found, block}}
      {:ok, %{base_fee_per_gas: base_fee}} -> {:ok, base_fee}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- base_fee! ---

  api(:base_fee!, "Get the base fee per gas for the next block. Raises on error.",
    params: [
      opts: [kind: :value, default: [], description: "Options: :block, :rpc_url, :timeout"]
    ],
    returns: %{type: "non_neg_integer | nil", description: "Base fee per gas in wei"}
  )

  @spec base_fee!(keyword()) :: non_neg_integer() | nil
  def base_fee!(opts \\ []) do
    case base_fee(opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "base_fee failed: #{inspect(reason)}"
    end
  end

  # --- blob_base_fee ---

  api(:blob_base_fee, "Get the current base fee per blob gas (eth_blobBaseFee).",
    params: [
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer} | {:error, term}",
      description: "EIP-4844 base fee per blob gas in wei",
      example: "3_936_408"
    }
  )

  @spec blob_base_fee(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  defrpc(:blob_base_fee, method: "eth_blobBaseFee", decode: :hex_unsigned)

  # --- blob_base_fee! ---

  api(:blob_base_fee!, "Get the current base fee per blob gas. Raises on error.",
    params: [
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: :non_neg_integer, description: "Base fee per blob gas in wei"}
  )

  @spec blob_base_fee!(keyword()) :: non_neg_integer()
  defrpc_bang(:blob_base_fee)

  # --- Private helpers ---

  @spec do_rpc(String.t(), list(), keyword()) :: {:ok, term()} | {:error, term()}
  defp do_rpc(method, params, opts) do
    :telemetry.span(@rpc_request_event, %{method: method}, fn ->
      result = method |> do_rpc_with_retry(params, opts) |> classify_node_refusal()
      {result, rpc_request_stop_metadata(method, result)}
    end)
  end

  @spec do_rpc_with_retry(String.t(), list(), keyword()) :: {:ok, term()} | {:error, term()}
  defp do_rpc_with_retry(method, params, opts) do
    {retry, rpc_opts} = Keyword.pop(opts, :retry)

    case normalize_retry_policy(retry) do
      {:ok, policy} -> retry_rpc(method, params, rpc_opts, policy)
      {:error, reason} -> {:error, reason}
    end
  end

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

  @spec retry_rpc(String.t(), list(), keyword(), map()) :: {:ok, term()} | {:error, term()}
  defp retry_rpc(method, params, opts, %{max_retries: max_retries, backoff_ms: backoff_ms}) do
    case Helpers.do_rpc(method, params, opts) do
      {:error, _} = err ->
        if max_retries > @no_retry_max_retries and retryable_rpc_error?(err) do
          sleep_before_retry(backoff_ms)
          retry_rpc(method, params, opts, %{max_retries: max_retries - 1, backoff_ms: backoff_ms})
        else
          err
        end

      result ->
        result
    end
  end

  # JSON-RPC application errors (node responded with a code) are final; retry transport failures only.
  @spec retryable_rpc_error?({:error, {:rpc_error, map()}}) :: boolean()
  defp retryable_rpc_error?({:error, {:rpc_error, %{code: _}}}), do: false
  defp retryable_rpc_error?({:error, {:rpc_error, _}}), do: true

  # Classify distinguishable node-capability refusals. Unrecognized shapes,
  # including a `%Req.Response{}` whose body is not a JSON-RPC error, pass
  # through byte-identical. Alchemy answers method-not-found as HTTP 400 with a
  # JSON-RPC body (cartouche surfaces that as `%Req.Response{}` rather than
  # decoding it), so the body is unwrapped only when the result is classified.
  @spec classify_node_refusal({:ok, term()} | {:error, term()}) :: {:ok, term()} | {:error, term()}
  defp classify_node_refusal({:ok, _} = ok), do: ok

  defp classify_node_refusal({:error, {:rpc_error, map}} = err) when is_map(map) do
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

  defp classify_node_refusal(other), do: other

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

  @spec sleep_before_retry(non_neg_integer()) :: :ok
  defp sleep_before_retry(@no_backoff_ms), do: :ok
  defp sleep_before_retry(backoff_ms), do: Process.sleep(backoff_ms)

  defp rpc_request_stop_metadata(method, {:ok, _result}), do: %{method: method, status: :ok}

  defp rpc_request_stop_metadata(method, {:error, reason}) do
    %{method: method, status: :error, error: reason}
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

  # Single-call RPC flows through Cartouche.RPC.send_rpc/3 (cartouche's Req
  # transport); only this batch POST builds its own request. retry: false keeps
  # the no-retry contract (onchain's opt-in retry wraps the whole call), and the
  # :onchain transport seam (Onchain.HTTP.req_options/3) replaces the removed
  # :cartouche, :client / :finch_name config.
  @spec send_batch_request(binary(), keyword()) :: {:ok, binary()} | {:error, term()}
  defp send_batch_request(encoded_body, opts) do
    base = [
      method: :post,
      url: ethereum_node(opts),
      headers: [@content_type_json],
      body: encoded_body,
      receive_timeout: Keyword.fetch!(opts, :timeout),
      decode_body: false,
      retry: false
    ]

    __MODULE__
    |> Onchain.HTTP.req_options(base, opts)
    |> Req.request()
    |> Cartouche.HTTP.normalize_response()
    |> case do
      {:ok, %Req.Response{body: body}} -> {:ok, body}
      {:error, %Req.Response{body: body}} -> {:error, {:rpc_error, %{message: body}}}
      {:error, message} -> {:error, {:rpc_error, %{message: message}}}
    end
  end

  @spec ethereum_node(keyword()) :: String.t()
  defp ethereum_node(opts) do
    Keyword.get(opts, :ethereum_node) ||
      Application.get_env(:cartouche, :ethereum_node, @default_ethereum_node)
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

  @doc false
  # Builds the eth_estimateGas call object from an atom-keyed tx-params map.
  # Addresses use big-hex (lowercased 0x-40-hex); :data uses big-hex (bytes-preserving,
  # even-length — never quantity, which strips leading zeros and is rejected by nodes);
  # integer quantities (value/gas/fees) use quantity hex. Absent keys are omitted.
  @spec build_estimate_gas_params(map()) :: {:ok, map()} | {:error, term()}
  defp build_estimate_gas_params(tx_params) do
    with {:ok, result} <- put_estimate_address(%{}, "from", Map.get(tx_params, :from)),
         {:ok, result} <- put_estimate_address(result, "to", Map.get(tx_params, :to)),
         {:ok, result} <- put_estimate_data(result, Map.get(tx_params, :data)),
         {:ok, result} <- put_estimate_quantity(result, "value", Map.get(tx_params, :value)),
         {:ok, result} <- put_estimate_quantity(result, "gas", Map.get(tx_params, :gas)),
         {:ok, result} <- put_estimate_quantity(result, "gasPrice", Map.get(tx_params, :gas_price)),
         {:ok, result} <-
           put_estimate_quantity(result, "maxFeePerGas", Map.get(tx_params, :max_fee_per_gas)),
         {:ok, result} <-
           put_estimate_quantity(
             result,
             "maxPriorityFeePerGas",
             Map.get(tx_params, :max_priority_fee_per_gas)
           ) do
      put_estimate_access_list(result, Map.get(tx_params, :access_list))
    end
  end

  @spec put_estimate_address(map(), String.t(), term()) :: {:ok, map()} | {:error, term()}
  defp put_estimate_address(result, _key, nil), do: {:ok, result}

  defp put_estimate_address(result, key, addr) do
    with {:ok, hex} <- ensure_hex_address(addr), do: {:ok, Map.put(result, key, hex)}
  end

  @spec put_estimate_data(map(), term()) :: {:ok, map()} | {:error, term()}
  defp put_estimate_data(result, nil), do: {:ok, result}

  defp put_estimate_data(result, data) do
    with {:ok, hex} <- ensure_hex_data(data), do: {:ok, Map.put(result, "data", hex)}
  end

  @spec put_estimate_quantity(map(), String.t(), term()) ::
          {:ok, map()} | {:error, term()}
  defp put_estimate_quantity(result, _key, nil), do: {:ok, result}

  defp put_estimate_quantity(result, key, n) when is_integer(n) and n >= 0 do
    {:ok, Map.put(result, key, Onchain.Hex.from_integer(n))}
  end

  defp put_estimate_quantity(_result, key, other), do: {:error, {:invalid_quantity, key, other}}

  # Serializes an EIP-2930 access list into the eth_estimateGas call object as
  # [%{"address" => 0xhex, "storageKeys" => [0xhex, ...]}]. Accepts the cartouche
  # canonical shape [{<<_::160>>, [<<_::256>>]}] (binary address + binary storage
  # keys) and 0x-hex-string forms. An empty/absent list is omitted; a malformed
  # entry returns an error rather than crashing.
  @spec put_estimate_access_list(map(), term()) :: {:ok, map()} | {:error, term()}
  defp put_estimate_access_list(result, nil), do: {:ok, result}
  defp put_estimate_access_list(result, []), do: {:ok, result}

  defp put_estimate_access_list(result, entries) when is_list(entries) do
    with {:ok, serialized} <- serialize_access_list(entries, []) do
      {:ok, Map.put(result, "accessList", serialized)}
    end
  end

  defp put_estimate_access_list(_result, other), do: {:error, {:invalid_access_list, other}}

  @spec serialize_access_list([term()], list()) :: {:ok, list()} | {:error, term()}
  defp serialize_access_list([], acc), do: {:ok, Enum.reverse(acc)}

  defp serialize_access_list([{address, storage_keys} | rest], acc) when is_list(storage_keys) do
    with {:ok, addr_hex} <- ensure_hex_address(address),
         {:ok, key_hexes} <- serialize_storage_keys(storage_keys, []) do
      entry = %{"address" => addr_hex, "storageKeys" => key_hexes}
      serialize_access_list(rest, [entry | acc])
    end
  end

  defp serialize_access_list([entry | _rest], _acc), do: {:error, {:invalid_access_list_entry, entry}}

  @spec serialize_storage_keys([term()], list()) :: {:ok, list()} | {:error, term()}
  defp serialize_storage_keys([], acc), do: {:ok, Enum.reverse(acc)}

  # 0x-string clause first: a "0x"-prefixed value is a binary, so it must be matched
  # before the raw-32-byte-binary clause to avoid double-encoding a 32-byte hex string.
  defp serialize_storage_keys(["0x" <> _ = key | rest], acc) do
    with {:ok, hex} <- ensure_hex_data(key), do: serialize_storage_keys(rest, [hex | acc])
  end

  defp serialize_storage_keys([key | rest], acc) when is_binary(key) and byte_size(key) == 32 do
    serialize_storage_keys(rest, [Onchain.Hex.encode(key) | acc])
  end

  defp serialize_storage_keys([key | _rest], _acc), do: {:error, {:invalid_storage_key, key}}

  @doc false
  # Builds a JSON-RPC filter object from an Elixir map.
  # Per EIP-1474: when :block_hash is present, :from_block / :to_block are
  # mutually exclusive — the spec rejects the combination at the JSON-RPC layer.
  @spec build_log_filter(map()) :: {:ok, map()} | {:error, term()}
  defp build_log_filter(filter) do
    with :ok <- check_block_hash_exclusivity(filter),
         {:ok, result} <- put_filter_address(%{}, filter),
         {:ok, result} <- put_filter_topics(result, filter),
         {:ok, result} <- put_filter_block_hash(result, filter),
         {:ok, result} <-
           put_block_param(result, "fromBlock", :fromBlock, Map.get(filter, :from_block)) do
      put_block_param(result, "toBlock", :toBlock, Map.get(filter, :to_block))
    end
  end

  @doc false
  @spec check_block_hash_exclusivity(map()) ::
          :ok | {:error, {:invalid_filter, {:block_hash_mutually_exclusive, [atom()]}}}
  defp check_block_hash_exclusivity(filter) do
    if Map.has_key?(filter, :block_hash) do
      conflicts = Enum.filter([:from_block, :to_block], &Map.has_key?(filter, &1))

      case conflicts do
        [] ->
          :ok

        _ ->
          {:error, {:invalid_filter, {:block_hash_mutually_exclusive, [:block_hash | conflicts]}}}
      end
    else
      :ok
    end
  end

  @doc false
  @spec put_filter_address(map(), map()) :: {:ok, map()} | {:error, term()}
  defp put_filter_address(result, filter) do
    case Map.get(filter, :address) do
      nil ->
        {:ok, result}

      addr ->
        with {:ok, hex} <- ensure_hex_address(addr), do: {:ok, Map.put(result, "address", hex)}
    end
  end

  @doc false
  @spec put_filter_block_hash(map(), map()) :: {:ok, map()} | {:error, term()}
  defp put_filter_block_hash(result, filter) do
    case Map.get(filter, :block_hash) do
      nil ->
        {:ok, result}

      hash ->
        case ensure_tx_hash(hash) do
          {:ok, valid_hash} -> {:ok, Map.put(result, "blockHash", valid_hash)}
          {:error, _} -> {:error, {:invalid_filter, {:blockHash, hash}}}
        end
    end
  end

  @doc false
  @spec put_filter_topics(map(), map()) :: {:ok, map()} | {:error, term()}
  defp put_filter_topics(result, filter) do
    case Map.get(filter, :topics) do
      nil -> {:ok, result}
      topics when is_list(topics) -> {:ok, Map.put(result, "topics", topics)}
      other -> {:error, {:invalid_filter, {:topics, other}}}
    end
  end

  @doc false
  # Converts a block identifier to hex for the filter.
  # `error_label` is an atom used in error tuples (e.g. :fromBlock, :toBlock).
  @spec put_block_param(map(), String.t(), atom(), term()) :: {:ok, map()} | {:error, term()}
  defp put_block_param(result, _key, _error_label, nil), do: {:ok, result}

  defp put_block_param(result, key, _error_label, n) when is_integer(n) and n >= 0,
    do: {:ok, Map.put(result, key, Onchain.Hex.from_integer(n))}

  defp put_block_param(result, key, _error_label, tag) when tag in @block_tags, do: {:ok, Map.put(result, key, tag)}

  defp put_block_param(result, key, error_label, "0x" <> _ = hex) do
    if Onchain.Hex.valid?(hex),
      do: {:ok, Map.put(result, key, hex)},
      else: {:error, {:invalid_filter, {error_label, hex}}}
  end

  defp put_block_param(_result, _key, error_label, other), do: {:error, {:invalid_filter, {error_label, other}}}

  @doc false
  @spec ensure_block_hash(term()) :: {:ok, String.t()} | {:error, term()}
  defp ensure_block_hash(block_hash) do
    case ensure_tx_hash(block_hash) do
      {:ok, hash} -> {:ok, hash}
      {:error, {:invalid_tx_hash, input}} -> {:error, {:invalid_block_hash, input}}
    end
  end

  @doc false
  @spec normalize_transaction_index(term()) :: {:ok, String.t()} | {:error, term()}
  defp normalize_transaction_index(index) when is_integer(index) and index >= 0,
    do: {:ok, Onchain.Hex.from_integer(index)}

  defp normalize_transaction_index("0x" <> _ = index) do
    if Onchain.Hex.valid?(index),
      do: {:ok, index},
      else: {:error, {:invalid_transaction_index, index}}
  end

  defp normalize_transaction_index(index), do: {:error, {:invalid_transaction_index, index}}

  @doc false
  @spec decode_nullable_quantity_result({:ok, term()} | {:error, term()}) ::
          {:ok, non_neg_integer() | nil} | {:error, term()}
  defp decode_nullable_quantity_result({:ok, nil}), do: {:ok, nil}

  defp decode_nullable_quantity_result({:ok, quantity}) when is_binary(quantity) do
    case Onchain.Hex.to_integer(quantity) do
      {:ok, count} -> {:ok, count}
      {:error, _reason} -> unexpected_rpc_result("block transaction count", quantity)
    end
  end

  defp decode_nullable_quantity_result({:ok, result}), do: unexpected_rpc_result("block transaction count", result)

  defp decode_nullable_quantity_result({:error, _reason} = error), do: error

  @doc false
  @spec decode_receipt_list_result({:ok, term()} | {:error, term()}) ::
          {:ok, [map()] | nil} | {:error, term()}
  defp decode_receipt_list_result({:ok, nil}), do: {:ok, nil}

  defp decode_receipt_list_result({:ok, receipts}) when is_list(receipts) do
    if Enum.all?(receipts, &is_map/1),
      do: {:ok, Enum.map(receipts, &parse_receipt/1)},
      else: unexpected_rpc_result("block receipts", receipts)
  end

  defp decode_receipt_list_result({:ok, result}), do: unexpected_rpc_result("block receipts", result)
  defp decode_receipt_list_result({:error, _reason} = error), do: error

  @doc false
  @spec decode_transaction_result({:ok, term()} | {:error, term()}) ::
          {:ok, map() | nil} | {:error, term()}
  defp decode_transaction_result({:ok, nil}), do: {:ok, nil}

  defp decode_transaction_result({:ok, transaction}) when is_map(transaction),
    do: {:ok, parse_transaction_map(transaction)}

  defp decode_transaction_result({:ok, result}), do: unexpected_rpc_result("block transaction", result)
  defp decode_transaction_result({:error, _reason} = error), do: error

  @doc false
  @spec decode_block_access_list_result({:ok, term()} | {:error, term()}) ::
          {:ok, [map()] | nil} | {:error, term()}
  defp decode_block_access_list_result({:ok, nil}), do: {:ok, nil}

  defp decode_block_access_list_result({:ok, entries}) when is_list(entries) do
    if Enum.all?(entries, &is_map/1),
      do: {:ok, entries},
      else: unexpected_rpc_result("block access list", entries)
  end

  defp decode_block_access_list_result({:ok, result}), do: unexpected_rpc_result("block access list", result)

  defp decode_block_access_list_result({:error, _reason} = error), do: error

  @spec unexpected_rpc_result(String.t(), term()) :: {:error, {:rpc_error, map()}}
  defp unexpected_rpc_result(label, result) do
    {:error, {:rpc_error, %{message: "unexpected #{label} response: #{inspect(result)}"}}}
  end

  @doc false
  # Parses a raw transaction receipt map from the RPC response into atom-keyed map.
  @spec parse_receipt(map()) :: map()
  defp parse_receipt(receipt) when is_map(receipt) do
    %{
      transaction_hash: receipt["transactionHash"],
      transaction_index: parse_hex_integer(receipt["transactionIndex"]),
      block_hash: receipt["blockHash"],
      block_number: parse_hex_integer(receipt["blockNumber"]),
      from: parse_address(receipt["from"]),
      to: parse_address(receipt["to"]),
      cumulative_gas_used: parse_hex_integer(receipt["cumulativeGasUsed"]),
      gas_used: parse_hex_integer(receipt["gasUsed"]),
      effective_gas_price: parse_hex_integer(receipt["effectiveGasPrice"]),
      status: parse_hex_integer(receipt["status"]),
      contract_address: parse_address(receipt["contractAddress"]),
      logs: Enum.map(receipt["logs"] || [], &parse_log/1),
      type: parse_hex_integer(receipt["type"])
    }
  end

  defp decode_get_block_result({:ok, nil}), do: {:ok, nil}

  defp decode_get_block_result({:ok, block}) when is_map(block) do
    case parse_block_response(block) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} = error -> error
    end
  end

  defp decode_get_block_result(other), do: other

  @doc false
  # Validates that storage_keys is a list of 32-byte 0x-hex strings, normalizing each.
  @spec validate_storage_keys(term()) :: {:ok, [String.t()]} | {:error, term()}
  defp validate_storage_keys(keys) when is_list(keys) do
    result =
      Enum.reduce_while(keys, {:ok, []}, fn key, {:ok, acc} ->
        case ensure_storage_key(key) do
          {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
          {:error, _} = err -> {:halt, err}
        end
      end)

    case result do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      err -> err
    end
  end

  defp validate_storage_keys(other), do: {:error, {:invalid_storage_keys, other}}

  @doc false
  # Parses a raw eth_getProof response into an atom-keyed map.
  @spec parse_proof(map()) :: map()
  defp parse_proof(proof) when is_map(proof) do
    %{
      address: parse_address(proof["address"]),
      balance: parse_hex_integer(proof["balance"]),
      nonce: parse_hex_integer(proof["nonce"]),
      code_hash: proof["codeHash"],
      storage_hash: proof["storageHash"],
      account_proof: proof["accountProof"] || [],
      storage_proof: Enum.map(proof["storageProof"] || [], &parse_storage_proof_entry/1)
    }
  end

  @doc false
  @spec parse_storage_proof_entry(map()) :: map()
  defp parse_storage_proof_entry(entry) when is_map(entry) do
    %{
      key: entry["key"],
      value: entry["value"],
      proof: entry["proof"] || []
    }
  end
end
