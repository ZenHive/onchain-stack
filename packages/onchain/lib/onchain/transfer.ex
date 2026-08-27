defmodule Onchain.Transfer do
  @moduledoc """
  Transfer event parser for ERC-20, ERC-721, and ERC-1155 token standards.

  Parses raw Ethereum logs into normalized `%Transfer{}` structs — the "follow
  the money" primitive for wallet analytics. Every token movement on Ethereum
  emits a Transfer event; this module decodes all three standards.

  ## Does

  - Parse raw log maps into `%Transfer{}` structs (`parse_log/1`, `parse_logs/1`)
  - Fetch and parse transfer logs in one call (`fetch/2`)
  - Expose topic hashes for filter building (`transfer_topics/0`)

  ## Does Not

  - Index or store transfers (see rexex for durable indexing)
  - Track balances over time (compose with `Onchain.ERC20` for snapshots)
  - Handle non-standard transfer events (custom names, non-indexed params)

  ## Token Standard Detection

  ERC-20 and ERC-721 share the same `Transfer(address,address,uint256)` topic hash.
  Distinguished by topic count:

  - **3 topics** `[topic0, from, to]` + value in `data` → ERC-20
  - **4 topics** `[topic0, from, to, tokenId]` + empty/no data → ERC-721

  ERC-1155 uses separate `TransferSingle` and `TransferBatch` signatures.

  ## Error Format

  - Non-transfer log: `{:error, {:unknown_event, :not_a_transfer}}`
  - Decode errors: propagated from `Onchain.Log.decode_event/2`

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `parse_log/1` | Single raw log → Transfer struct(s) |
  | `parse_log!/1` | Same, raises on error |
  | `parse_logs/1` | List of raw logs → Transfer structs (skips non-Transfer) |
  | `parse_logs!/1` | Same, raises on error |
  | `fetch/2` | `eth_get_logs` + `parse_logs` convenience |
  | `fetch!/2` | Same, raises on error |
  | `transfer_topics/0` | The 3 topic0 hashes for filter building |
  """

  use Descripex, namespace: "/transfer"

  alias Onchain.Address
  alias Onchain.Hex
  alias Onchain.Log
  alias Onchain.RPC

  require Logger

  # --- Event signatures ---

  # ERC-20: Transfer(address indexed from, address indexed to, uint256 value)
  # ERC-721: Transfer(address indexed from, address indexed to, uint256 indexed tokenId)
  # Both share the same canonical signature and topic hash.
  @transfer_sig "Transfer(address indexed from, address indexed to, uint256 value)"
  @transfer_721_sig "Transfer(address indexed from, address indexed to, uint256 indexed tokenId)"

  # ERC-1155: TransferSingle(operator, from, to, id, value)
  @transfer_single_sig "TransferSingle(address indexed operator, address indexed from, " <>
                         "address indexed to, uint256 id, uint256 value)"

  # ERC-1155: TransferBatch(operator, from, to, ids[], values[])
  @transfer_batch_sig "TransferBatch(address indexed operator, address indexed from, " <>
                        "address indexed to, uint256[] ids, uint256[] values)"

  # Precomputed topic hashes (compile-time)
  @transfer_topic Hex.encode(Cartouche.Hash.keccak("Transfer(address,address,uint256)"))
  @transfer_single_topic Hex.encode(Cartouche.Hash.keccak("TransferSingle(address,address,address,uint256,uint256)"))
  @transfer_batch_topic Hex.encode(Cartouche.Hash.keccak("TransferBatch(address,address,address,uint256[],uint256[])"))

  # --- Struct ---

  @enforce_keys [:from, :to, :token, :token_standard, :block_number, :transaction_hash, :log_index]

  defstruct [
    :from,
    :to,
    :token,
    :token_standard,
    :amount,
    :token_id,
    :operator,
    :block_number,
    :transaction_hash,
    :log_index
  ]

  @type t :: %__MODULE__{
          from: String.t(),
          to: String.t(),
          token: String.t(),
          token_standard: :erc20 | :erc721 | :erc1155,
          amount: non_neg_integer() | nil,
          token_id: non_neg_integer() | nil,
          operator: String.t() | nil,
          block_number: non_neg_integer(),
          transaction_hash: String.t(),
          log_index: non_neg_integer()
        }

  # --- transfer_topics ---

  api(:transfer_topics, "Returns the 3 topic0 hashes for ERC-20/721/1155 Transfer events.",
    params: [],
    returns: %{
      type: "[String.t()]",
      description: "List of 0x-prefixed keccak256 hashes: [Transfer, TransferSingle, TransferBatch]"
    }
  )

  @spec transfer_topics() :: [String.t()]
  def transfer_topics, do: [@transfer_topic, @transfer_single_topic, @transfer_batch_topic]

  # --- parse_log ---

  api(:parse_log, "Parse a single raw log map into Transfer struct(s).",
    params: [
      log: [
        kind: :value,
        description: "Raw log map with :topics, :data, :address, :block_number, :transaction_hash, :log_index"
      ]
    ],
    returns: %{
      type: "{:ok, t()} | {:ok, [t()]} | {:error, term}",
      description: "Single struct for ERC-20/721/1155-Single, list for 1155-Batch"
    }
  )

  @spec parse_log(map()) :: {:ok, t()} | {:ok, [t()]} | {:error, term()}

  # ERC-20: 3 topics [topic0, from, to] + value in data
  def parse_log(%{topics: [topic0, _, _]} = log) when topic0 == @transfer_topic do
    do_parse_erc20(log)
  end

  # ERC-721: 4 topics [topic0, from, to, tokenId] with Transfer topic
  def parse_log(%{topics: [topic0, _, _, _]} = log) when topic0 == @transfer_topic do
    do_parse_erc721(log)
  end

  # ERC-1155 TransferSingle: 4 topics [topic0, operator, from, to] + (id, value) in data
  def parse_log(%{topics: [topic0, _, _, _]} = log) when topic0 == @transfer_single_topic do
    do_parse_erc1155_single(log)
  end

  # ERC-1155 TransferBatch: 4 topics [topic0, operator, from, to] + (ids[], values[]) in data
  def parse_log(%{topics: [topic0, _, _, _]} = log) when topic0 == @transfer_batch_topic do
    do_parse_erc1155_batch(log)
  end

  def parse_log(_), do: {:error, {:unknown_event, :not_a_transfer}}

  # --- parse_log! ---

  api(:parse_log!, "Parse a single raw log map into Transfer struct(s). Raises on error.",
    params: [
      log: [kind: :value, description: "Raw log map (see parse_log/1)"]
    ],
    returns: %{type: "t() | [t()]", description: "Transfer struct(s)"}
  )

  @spec parse_log!(map()) :: t() | [t()]
  def parse_log!(log) do
    case parse_log(log) do
      {:ok, result} -> result
      {:error, reason} -> raise "parse_log failed: #{inspect(reason)}"
    end
  end

  # --- parse_logs ---

  api(:parse_logs, "Parse a list of raw logs, skipping non-Transfer events.",
    params: [
      logs: [kind: :value, description: "List of raw log maps from eth_get_logs"]
    ],
    returns: %{
      type: "{:ok, [t()]}",
      description: "Flat list of Transfer structs (batches expanded, non-transfers skipped)"
    }
  )

  @spec parse_logs([map()]) :: {:ok, [t()]}
  def parse_logs(logs) when is_list(logs) do
    transfers =
      Enum.flat_map(logs, fn log ->
        case parse_log(log) do
          {:ok, list} when is_list(list) ->
            list

          {:ok, single} ->
            [single]

          # reach:disable-next-line false_success_error -- skipping non-Transfer logs is this function's contract
          {:error, {:unknown_event, _}} ->
            []

          {:error, reason} ->
            Logger.warning("Transfer parse error (skipped): #{inspect(reason)}")
            []
        end
      end)

    {:ok, transfers}
  end

  # --- parse_logs! ---

  api(:parse_logs!, "Parse a list of raw logs, skipping non-Transfer events. Raises on error.",
    params: [
      logs: [kind: :value, description: "List of raw log maps"]
    ],
    returns: %{type: "[t()]", description: "Flat list of Transfer structs"}
  )

  @spec parse_logs!([map()]) :: [t()]
  def parse_logs!(logs) do
    {:ok, result} = parse_logs(logs)
    result
  end

  # --- fetch ---

  api(:fetch, "Fetch transfer logs from chain and parse into structs.",
    params: [
      filter: [
        kind: :value,
        description:
          "Filter map for eth_get_logs (e.g. %{from_block: 18_000_000, to_block: 18_000_100, address: \"0x...\"})"
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, [t()]} | {:error, term}",
      description: "Parsed transfer structs from matching logs"
    }
  )

  @spec fetch(map(), keyword()) :: {:ok, [t()]} | {:error, term()}
  def fetch(filter, opts \\ []) do
    # Wrap topics list in an outer list for eth_getLogs OR semantics at position 0:
    # [[topicA, topicB, topicC]] means "match topicA OR topicB OR topicC as topic0"
    filter = Map.put_new(filter, :topics, [transfer_topics()])

    with {:ok, logs} <- RPC.eth_get_logs(filter, opts) do
      parse_logs(logs)
    end
  end

  # --- fetch! ---

  api(:fetch!, "Fetch transfer logs from chain and parse into structs. Raises on error.",
    params: [
      filter: [kind: :value, description: "Filter map (see fetch/2)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: "[t()]", description: "Parsed transfer structs"}
  )

  @spec fetch!(map(), keyword()) :: [t()]
  def fetch!(filter, opts \\ []) do
    case fetch(filter, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "fetch failed: #{inspect(reason)}"
    end
  end

  # --- Private parsers ---

  @doc false
  # Parses an ERC-20 Transfer log: 3 topics + uint256 value in data.
  @spec do_parse_erc20(map()) :: {:ok, t()} | {:error, term()}
  defp do_parse_erc20(log) do
    with {:ok, decoded} <- Log.decode_event(log, @transfer_sig) do
      build_transfer(decoded, log, :erc20)
    end
  end

  @doc false
  # Parses an ERC-721 Transfer log: 4 topics (from, to, tokenId all indexed).
  @spec do_parse_erc721(map()) :: {:ok, t()} | {:error, term()}
  defp do_parse_erc721(log) do
    with {:ok, decoded} <- Log.decode_event(log, @transfer_721_sig),
         {:ok, transfer} <- build_transfer(decoded, log, :erc721) do
      {:ok, %{transfer | token_id: decoded.tokenId, amount: nil}}
    end
  end

  @doc false
  # Parses an ERC-1155 TransferSingle log: 4 topics + (uint256, uint256) in data.
  @spec do_parse_erc1155_single(map()) :: {:ok, t()} | {:error, term()}
  defp do_parse_erc1155_single(log) do
    with {:ok, decoded} <- Log.decode_event(log, @transfer_single_sig),
         {:ok, transfer} <- build_transfer(decoded, log, :erc1155) do
      {:ok,
       %{
         transfer
         | operator: ensure_checksum(decoded.operator),
           token_id: decoded.id,
           amount: decoded.value
       }}
    end
  end

  @doc false
  # Parses an ERC-1155 TransferBatch log: 4 topics + (uint256[], uint256[]) in data.
  # Expands into one struct per (id, value) pair. All share the same log_index.
  @spec do_parse_erc1155_batch(map()) :: {:ok, [t()]} | {:error, term()}
  defp do_parse_erc1155_batch(log) do
    with {:ok, decoded} <- Log.decode_event(log, @transfer_batch_sig),
         {:ok, base} <- build_transfer(decoded, log, :erc1155) do
      operator = ensure_checksum(decoded.operator)

      transfers =
        decoded.ids
        |> Enum.zip(decoded.values)
        |> Enum.map(fn {id, value} ->
          %{base | operator: operator, token_id: id, amount: value}
        end)

      {:ok, transfers}
    end
  end

  @doc false
  # Builds a base %Transfer{} from decoded params and raw log metadata.
  # Returns {:ok, struct} | {:error, term} to propagate address validation errors.
  @spec build_transfer(map(), map(), :erc20 | :erc721 | :erc1155) ::
          {:ok, t()} | {:error, term()}
  defp build_transfer(decoded, log, standard) do
    with {:ok, from} <- Address.checksum(decoded.from),
         {:ok, to} <- Address.checksum(decoded.to),
         {:ok, token} <- Address.checksum(log.address) do
      {:ok,
       %__MODULE__{
         from: from,
         to: to,
         token: token,
         token_standard: standard,
         amount: if(standard == :erc20, do: decoded[:value]),
         token_id: nil,
         operator: nil,
         block_number: log.block_number,
         transaction_hash: log.transaction_hash,
         log_index: log.log_index
       }}
    end
  end

  @doc false
  # Checksums an address, handling both 20-byte binary and hex string formats.
  # Used for optional fields (operator) where we already validated core addresses in build_transfer.
  @spec ensure_checksum(String.t() | binary()) :: String.t()
  defp ensure_checksum(addr) when is_binary(addr) and byte_size(addr) == 20 do
    Address.checksum!(addr)
  end

  defp ensure_checksum(<<"0x", _rest::binary-size(40)>> = addr), do: Address.checksum!(addr)

  defp ensure_checksum(<<hex::binary-size(40)>>), do: Address.checksum!("0x" <> hex)
end
