defmodule Cartouche.Block do
  @moduledoc ~S"""
  Represents a block from the Ethereum JSON-RPC endpoint.

  Defined here: https://ethereum.org/en/developers/docs/apis/json-rpc/#eth_getblockbyhash

  Fields are nullable when they belong to a hard-fork upgrade and may be
  absent on pre-upgrade blocks: `base_fee_per_gas` (London, EIP-1559),
  `withdrawals_root` / `withdrawals` (Shanghai, EIP-4895), and
  `parent_beacon_block_root` / `blob_gas_used` / `excess_blob_gas`
  (Cancun, EIP-4788 + EIP-4844). `mix_hash` is present pre-Merge as the
  PoW mix hash and post-Merge as PREVRANDAO (EIP-4399).
  """

  use Descripex, namespace: "/ethereum/block"
  use Cartouche.Hex

  alias Cartouche.Hex
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2
  alias Cartouche.Transaction.V3
  alias Cartouche.Transaction.V4
  alias Cartouche.Transaction.V_2930

  defmodule Withdrawal do
    @moduledoc """
    A validator withdrawal entry from a post-Shanghai block (EIP-4895).

    Embedded in `Cartouche.Block.t().withdrawals` when the block is
    post-Shanghai (block ≥ 17,034,870 on mainnet).
    """

    use Descripex, namespace: "/ethereum/block/withdrawal"

    @type t :: %__MODULE__{
            # QUANTITY - the index of the withdrawal in the validator pool.
            index: integer(),
            # QUANTITY - the index of the validator that produced the withdrawal.
            validator_index: integer(),
            # DATA, 20 Bytes - the recipient address of the withdrawal.
            address: <<_::160>>,
            # QUANTITY - the withdrawal amount, in gwei.
            amount: integer()
          }

    defstruct [:index, :validator_index, :address, :amount]

    api(:deserialize, "Decode a validator withdrawal entry from an Ethereum block JSON-RPC object.",
      params: [
        params: [
          kind: :exchange_data,
          source: "Cartouche.RPC.get_block_by_number/2 or Cartouche.RPC.get_block_by_hash/2",
          description:
            "Map with `index`, `validatorIndex`, `address`, and `amount` hex fields from a post-Shanghai block withdrawal."
        ]
      ],
      returns: %{
        type: :block_withdrawal,
        description:
          "%Cartouche.Block.Withdrawal{} with integer indices, a 20-byte recipient address, and amount in gwei."
      }
    )

    @doc ~S"""
    Deserializes a withdrawal object from JSON-RPC.

    ## Examples

        iex> use Cartouche.Hex
        iex> %{
        ...>   "index" => "0x4d8f7d",
        ...>   "validatorIndex" => "0xc8a5f",
        ...>   "address" => "0x1f9090aae28b8a3dceadf281b0f12828e676c326",
        ...>   "amount" => "0x111c8c2"
        ...> }
        ...> |> Cartouche.Block.Withdrawal.deserialize()
        %Cartouche.Block.Withdrawal{
          index: 0x4d8f7d,
          validator_index: 0xc8a5f,
          address: ~h[0x1f9090aae28b8a3dceadf281b0f12828e676c326],
          amount: 0x111c8c2
        }
    """
    @spec deserialize(map()) :: t() | no_return()
    def deserialize(%{} = params) do
      %__MODULE__{
        index: Hex.decode_hex_number!(params["index"]),
        validator_index: Hex.decode_hex_number!(params["validatorIndex"]),
        address: Hex.decode_address!(params["address"]),
        amount: Hex.decode_hex_number!(params["amount"])
      }
    end
  end

  defstruct [
    :number,
    :hash,
    :parent_hash,
    :nonce,
    :sha3_uncles,
    :logs_bloom,
    :transactions_root,
    :state_root,
    :receipts_root,
    :miner,
    :difficulty,
    :total_difficulty,
    :extra_data,
    :size,
    :gas_limit,
    :gas_used,
    :timestamp,
    :transactions,
    :uncles,
    # Pre-Merge: PoW mix hash; post-Merge: PREVRANDAO (EIP-4399).
    :mix_hash,
    # London (EIP-1559).
    :base_fee_per_gas,
    # Shanghai (EIP-4895).
    :withdrawals_root,
    :withdrawals,
    # Cancun (EIP-4788).
    :parent_beacon_block_root,
    # Cancun (EIP-4844).
    :blob_gas_used,
    :excess_blob_gas,
    :requests_hash
  ]

  @type t :: %__MODULE__{
          # number: QUANTITY - the block number. null when its pending block.
          number: integer() | nil,
          # hash: DATA, 32 Bytes - hash of the block. null when its pending block.
          hash: <<_::256>> | nil,
          # parentHash: DATA, 32 Bytes - hash of the parent block.
          parent_hash: <<_::256>> | nil,
          # nonce: DATA, 8 Bytes - hash of the generated proof-of-work. null when its pending block.
          nonce: integer() | nil,
          # sha3Uncles: DATA, 32 Bytes - SHA3 of the uncles data in the block.
          sha3_uncles: <<_::256>>,
          # logsBloom: DATA, 256 Bytes - the bloom filter for the logs of the block. null when its pending block.
          logs_bloom: <<_::1024>> | nil,
          # transactionsRoot: DATA, 32 Bytes - the root of the transaction trie of the block.
          transactions_root: <<_::256>>,
          # stateRoot: DATA, 32 Bytes - the root of the final state trie of the block.
          state_root: <<_::256>>,
          # receiptsRoot: DATA, 32 Bytes - the root of the receipts trie of the block.
          receipts_root: <<_::256>>,
          # miner: DATA, 20 Bytes - the address of the beneficiary to whom the mining rewards were given.
          miner: <<_::160>>,
          # difficulty: QUANTITY - integer of the difficulty for this block.
          difficulty: integer(),
          # totalDifficulty: QUANTITY - integer of the total difficulty of the chain until this block.
          total_difficulty: integer(),
          # extraData: DATA - the "extra data" field of this block.
          extra_data: binary(),
          # size: QUANTITY - integer the size of this block in bytes.
          size: integer(),
          # gasLimit: QUANTITY - the maximum gas allowed in this block.
          gas_limit: integer(),
          # gasUsed: QUANTITY - the total used gas by all transactions in this block.
          gas_used: integer(),
          # timestamp: QUANTITY - the unix timestamp for when the block was collated.
          timestamp: integer(),
          # transactions: Array - Array of transaction objects (when the
          # node was queried with `:include_transaction_details, true`), or
          # 0x-prefixed 32-byte transaction hash strings (default). Per-element
          # dispatch is robust to mixed-shape lists; full-shape elements are
          # decoded into the matching Vn struct via each module's `from_json/1`.
          transactions: [
            String.t()
            | V1.t()
            | V_2930.t()
            | V2.t()
            | V3.t()
            | V4.t()
          ],
          # uncles: Array - Array of uncle hashes.
          uncles: [<<_::256>>],
          # mixHash: DATA, 32 Bytes - pre-Merge PoW mix hash; post-Merge PREVRANDAO (EIP-4399).
          mix_hash: <<_::256>> | nil,
          # baseFeePerGas: QUANTITY - the base fee per gas. London+ (EIP-1559); nil pre-London.
          base_fee_per_gas: integer() | nil,
          # withdrawalsRoot: DATA, 32 Bytes - root of the withdrawal trie. Shanghai+ (EIP-4895); nil pre-Shanghai.
          withdrawals_root: <<_::256>> | nil,
          # withdrawals: Array - validator withdrawals. Shanghai+ (EIP-4895); nil pre-Shanghai.
          withdrawals: [Withdrawal.t()] | nil,
          # parentBeaconBlockRoot: DATA, 32 Bytes - parent beacon block root. Cancun+ (EIP-4788); nil pre-Cancun.
          parent_beacon_block_root: <<_::256>> | nil,
          # blobGasUsed: QUANTITY - blob gas used in this block. Cancun+ (EIP-4844); nil pre-Cancun.
          blob_gas_used: integer() | nil,
          # excessBlobGas: QUANTITY - excess blob gas. Cancun+ (EIP-4844); nil pre-Cancun.
          excess_blob_gas: integer() | nil,
          requests_hash: <<_::256>> | nil
        }

  api(:deserialize, "Decode an Ethereum block JSON-RPC object into a Cartouche.Block struct.",
    params: [
      params: [
        kind: :exchange_data,
        source: "Cartouche.RPC.get_block_by_number/2 or Cartouche.RPC.get_block_by_hash/2",
        description:
          "Block response map containing DATA hex strings, QUANTITY hex strings, transactions, uncles, and optional fork-tier fields."
      ]
    ],
    returns: %{
      type: :ethereum_block,
      description:
        "%Cartouche.Block{} with decoded hashes, addresses, quantities, uncle hashes, and optional nested Cartouche.Block.Withdrawal entries."
    }
  )

  @doc ~S"""
  Deserializes a block object from JSON-RPC.

  ## Examples

      iex> %{
      ...>   "difficulty" => "0x4ea3f27bc",
      ...>   "extraData" => "0x476574682f4c5649562f76312e302e302f6c696e75782f676f312e342e32",
      ...>   "gasLimit" => "0x1388",
      ...>   "gasUsed" => "0x0",
      ...>   "hash" => "0xdc0818cf78f21a8e70579cb46a43643f78291264dda342ae31049421c82d21ae",
      ...>   "logsBloom" => "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
      ...>   "miner" => "0xbb7b8287f3f0a933474a79eae42cbca977791171",
      ...>   "mixHash" => "0x4fffe9ae21f1c9e15207b1f472d5bbdd68c9595d461666602f2be20daf5e7843",
      ...>   "nonce" => "0x689056015818adbe",
      ...>   "number" => "0x1b4",
      ...>   "parentHash" => "0xe99e022112df268087ea7eafaf4790497fd21dbeeb6bd7a1721df161a6657a54",
      ...>   "receiptsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
      ...>   "sha3Uncles" => "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
      ...>   "size" => "0x220",
      ...>   "stateRoot" => "0xddc8b0234c2e0cad087c8b389aa7ef01f7d79b2570bccb77ce48648aa61c904d",
      ...>   "timestamp" => "0x55ba467c",
      ...>   "totalDifficulty" => "0x78ed983323d",
      ...>   "transactions" => [],
      ...>   "transactionsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
      ...>   "uncles" => []
      ...> }
      ...> |> Cartouche.Block.deserialize()
      %Cartouche.Block{
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
      }

  Post-Cancun block with all fork-tier fields populated:

      iex> %{
      ...>   "number" => "0x1312d00",
      ...>   "hash" => "0xd24fd73f794058a3807db926d8898c6481e902b7edb91ce0d479d6760f276183",
      ...>   "parentHash" => "0xb390d63aac03bbef75de888d16bd56b91c9291c2a7e38d36ac24731351522bd1",
      ...>   "nonce" => "0x0000000000000000",
      ...>   "sha3Uncles" => "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
      ...>   "logsBloom" => "0x" <> String.duplicate("00", 256),
      ...>   "transactionsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
      ...>   "stateRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
      ...>   "receiptsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
      ...>   "miner" => "0x95222290dd7278aa3ddd389cc1e1d165cc4bafe5",
      ...>   "difficulty" => "0x0",
      ...>   "totalDifficulty" => "0xc70d815d562d3cfa955",
      ...>   "extraData" => "0x",
      ...>   "size" => "0x220",
      ...>   "gasLimit" => "0x1c9c380",
      ...>   "gasUsed" => "0xa9371c",
      ...>   "timestamp" => "0x665ba27f",
      ...>   "transactions" => [],
      ...>   "uncles" => [],
      ...>   "mixHash" => "0x4fffe9ae21f1c9e15207b1f472d5bbdd68c9595d461666602f2be20daf5e7843",
      ...>   "baseFeePerGas" => "0x6f4f8d96",
      ...>   "withdrawalsRoot" => "0x9d56fa5a08e21cd3ff7f8b6f5b6cb6f5b6cb6f5b6cb6f5b6cb6f5b6cb6f5b6cb",
      ...>   "withdrawals" => [
      ...>     %{
      ...>       "index" => "0x4d8f7d",
      ...>       "validatorIndex" => "0xc8a5f",
      ...>       "address" => "0x1f9090aae28b8a3dceadf281b0f12828e676c326",
      ...>       "amount" => "0x111c8c2"
      ...>     }
      ...>   ],
      ...>   "parentBeaconBlockRoot" => "0xb390d63aac03bbef75de888d16bd56b91c9291c2a7e38d36ac24731351522bd1",
      ...>   "blobGasUsed" => "0x80000",
      ...>   "excessBlobGas" => "0x4a0000"
      ...> }
      ...> |> Cartouche.Block.deserialize()
      ...> |> Map.take([:number, :base_fee_per_gas, :withdrawals, :parent_beacon_block_root, :blob_gas_used, :excess_blob_gas])
      %{
        number: 20_000_000,
        base_fee_per_gas: 0x6f4f8d96,
        withdrawals: [
          %Cartouche.Block.Withdrawal{
            index: 0x4d8f7d,
            validator_index: 0xc8a5f,
            address: ~h[0x1f9090aae28b8a3dceadf281b0f12828e676c326],
            amount: 0x111c8c2
          }
        ],
        parent_beacon_block_root: ~h[0xb390d63aac03bbef75de888d16bd56b91c9291c2a7e38d36ac24731351522bd1],
        blob_gas_used: 0x80000,
        excess_blob_gas: 0x4a0000
      }
  """
  @spec deserialize(map() | nil) :: t() | nil
  def deserialize(nil), do: nil

  def deserialize(params) when is_map(params) do
    %__MODULE__{
      number: map(get_in(params, ["number"]), &Hex.decode_hex_number!/1),
      hash: map(get_in(params, ["hash"]), &Hex.decode_word!/1),
      parent_hash: map(get_in(params, ["parentHash"]), &Hex.decode_word!/1),
      nonce: map(get_in(params, ["nonce"]), &Hex.decode_hex_number!/1),
      sha3_uncles: map(get_in(params, ["sha3Uncles"]), &Hex.decode_word!/1),
      logs_bloom:
        map(get_in(params, ["logsBloom"]), fn hex ->
          Hex.decode_sized!(hex, 256, "invalid logs bloom")
        end),
      transactions_root: map(get_in(params, ["transactionsRoot"]), &Hex.decode_word!/1),
      state_root: map(get_in(params, ["stateRoot"]), &Hex.decode_word!/1),
      receipts_root: map(get_in(params, ["receiptsRoot"]), &Hex.decode_word!/1),
      miner: map(get_in(params, ["miner"]), &Hex.decode_address!/1),
      difficulty: map(get_in(params, ["difficulty"]), &Hex.decode_hex_number!/1),
      total_difficulty: map(get_in(params, ["totalDifficulty"]), &Hex.decode_hex_number!/1),
      extra_data: map(get_in(params, ["extraData"]), &Hex.decode_hex!/1),
      size: map(get_in(params, ["size"]), &Hex.decode_hex_number!/1),
      gas_limit: map(get_in(params, ["gasLimit"]), &Hex.decode_hex_number!/1),
      gas_used: map(get_in(params, ["gasUsed"]), &Hex.decode_hex_number!/1),
      timestamp: map(get_in(params, ["timestamp"]), &Hex.decode_hex_number!/1),
      transactions: map(get_in(params, ["transactions"]), fn txs -> Enum.map(txs, &deserialize_transaction/1) end),
      uncles: map(get_in(params, ["uncles"]), fn uncles -> Enum.map(uncles, &Hex.decode_word!/1) end),
      mix_hash: map(get_in(params, ["mixHash"]), &Hex.decode_word!/1),
      base_fee_per_gas: map(get_in(params, ["baseFeePerGas"]), &Hex.decode_hex_number!/1),
      withdrawals_root: map(get_in(params, ["withdrawalsRoot"]), &Hex.decode_word!/1),
      withdrawals: map(get_in(params, ["withdrawals"]), fn ws -> Enum.map(ws, &Withdrawal.deserialize/1) end),
      parent_beacon_block_root: map(get_in(params, ["parentBeaconBlockRoot"]), &Hex.decode_word!/1),
      blob_gas_used: map(get_in(params, ["blobGasUsed"]), &Hex.decode_hex_number!/1),
      excess_blob_gas: map(get_in(params, ["excessBlobGas"]), &Hex.decode_hex_number!/1),
      requests_hash: map(params["requestsHash"], &Hex.decode_word!/1)
    }
  end

  @spec map(nil | term(), (term() -> term())) :: term() | nil
  defp map(x, f) do
    if is_nil(x), do: nil, else: f.(x)
  end

  # Per-element dispatch for `params["transactions"]`. The list is
  # heterogeneous in shape per the JSON-RPC wire contract:
  #
  #   * `is_binary(elem)` — `eth_getBlockBy*` was called without
  #     `:include_transaction_details, true` (or with `false`); the node
  #     returned 0x-prefixed transaction hashes. We preserve them as
  #     `String.t()` rather than decoding to `<<_::256>>` to keep the
  #     wire shape addressable for downstream callers (display, logging,
  #     direct comparison against API responses).
  #
  #   * `is_map(elem)` — `:include_transaction_details, true` was set;
  #     the element is a full transaction JSON object. Dispatch by the
  #     `"type"` field per EIP-2718, falling back to V1 when `"type"` is
  #     `"0x0"`, `nil`, or absent (some nodes still omit the field on
  #     pre-Berlin payloads).
  #
  # We dispatch per element rather than per block to be robust to nodes
  # (e.g. some Erigon configurations) that may return mixed-shape lists.
  @spec deserialize_transaction(String.t() | map()) ::
          String.t()
          | V1.t()
          | V_2930.t()
          | V2.t()
          | V3.t()
          | V4.t()
  defp deserialize_transaction(hash) when is_binary(hash) do
    _ = Hex.decode_word!(hash)
    hash
  end

  defp deserialize_transaction(%{} = params) do
    case Cartouche.Transaction.from_json_module(params["type"]) do
      {:ok, module} ->
        module.from_json(params)

      {:error, {:unknown_transaction_type, other}} ->
        raise ArgumentError,
              "unsupported transaction envelope type #{inspect(other)} in block JSON"
    end
  end

  api(:get_by_number, "Fetch and parse a block by number or tag.",
    params: [
      block_id: [
        kind: :value,
        description: ~s{Block number (integer) or tag string ("latest", "finalized", etc.)}
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, Cartouche.Block.t()} | {:error, term}",
      description: "Full block struct with integer quantities and binary hashes"
    }
  )

  @spec get_by_number(integer() | String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def get_by_number(block_id, opts \\ []) do
    with {:ok, block} <- Cartouche.RPC.get_block_by_number(block_id, opts) do
      summarize_block(block)
    end
  end

  # --- get_by_number! ---

  api(:get_by_number!, "Fetch and parse a block by number or tag. Raises on error.",
    params: [
      block_id: [kind: :value, description: "Block number (integer) or tag string"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: :map, description: "Full decoded block struct"}
  )

  @spec get_by_number!(integer() | String.t(), keyword()) :: t()
  def get_by_number!(block_id, opts \\ []) do
    case get_by_number(block_id, opts) do
      {:ok, block} -> block
      {:error, reason} -> raise "get_by_number failed: #{inspect(reason)}"
    end
  end

  # --- find_by_timestamp ---

  api(:find_by_timestamp, "Binary search for the highest block with timestamp ≤ target.",
    params: [
      target_timestamp: [kind: :value, description: "Unix timestamp (seconds) to search for"],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :rpc_url, :timeout, :floor (block number integer), :ceil (block number integer)"
      ]
    ],
    returns: %{
      type: "{:ok, Cartouche.Block.t()} | {:error, term}",
      description: "Full block struct with highest timestamp ≤ target"
    }
  )

  @spec find_by_timestamp(non_neg_integer(), keyword()) :: {:ok, t()} | {:error, term()}
  def find_by_timestamp(target_timestamp, opts \\ [])

  def find_by_timestamp(target_timestamp, _opts) when not is_integer(target_timestamp) do
    {:error, {:invalid_timestamp, target_timestamp}}
  end

  def find_by_timestamp(target_timestamp, _opts) when target_timestamp < 0 do
    {:error, {:invalid_timestamp, target_timestamp}}
  end

  def find_by_timestamp(target_timestamp, opts) do
    rpc_opts = Keyword.drop(opts, [:floor, :ceil])

    with {:ok, floor_block} <- resolve_floor(Keyword.get(opts, :floor), rpc_opts),
         {:ok, ceil_block} <- resolve_ceil(Keyword.get(opts, :ceil), rpc_opts) do
      cond do
        floor_block.timestamp == target_timestamp ->
          {:ok, floor_block}

        floor_block.timestamp > target_timestamp ->
          {:error, {:timestamp_before_floor, target_timestamp}}

        ceil_block.timestamp <= target_timestamp ->
          # Target is at or after the ceiling — return ceil as best known block
          {:ok, ceil_block}

        true ->
          binary_search(
            floor_block.number + 1,
            ceil_block.number,
            floor_block,
            target_timestamp,
            rpc_opts
          )
      end
    end
  end

  # --- find_by_timestamp! ---

  api(:find_by_timestamp!, "Binary search for block ≤ target timestamp. Raises on error.",
    params: [
      target_timestamp: [kind: :value, description: "Unix timestamp (seconds)"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :floor, :ceil"]
    ],
    returns: %{type: :map, description: "Full decoded block struct"}
  )

  @spec find_by_timestamp!(non_neg_integer(), keyword()) :: t()
  def find_by_timestamp!(target_timestamp, opts \\ []) do
    case find_by_timestamp(target_timestamp, opts) do
      {:ok, block} -> block
      {:error, reason} -> raise "find_by_timestamp failed: #{inspect(reason)}"
    end
  end

  # --- Private helpers ---

  @doc false
  # Resolves the floor block: fetch genesis (block 0) if no floor provided.
  @spec resolve_floor(non_neg_integer() | nil, keyword()) :: {:ok, t()} | {:error, term()}
  defp resolve_floor(nil, rpc_opts), do: get_by_number(0, rpc_opts)
  defp resolve_floor(block_num, rpc_opts), do: get_by_number(block_num, rpc_opts)

  @doc false
  # Resolves the ceiling block: fetch "finalized" if no ceil provided.
  # "finalized" avoids reorg issues (same strategy as blockwatch).
  @spec resolve_ceil(non_neg_integer() | nil, keyword()) :: {:ok, t()} | {:error, term()}
  defp resolve_ceil(nil, rpc_opts), do: get_by_number("finalized", rpc_opts)
  defp resolve_ceil(block_num, rpc_opts), do: get_by_number(block_num, rpc_opts)

  @doc false
  # Binary search for the highest block with timestamp <= target.
  #
  # Invariants:
  #   - floor: lowest block number that might have timestamp <= target
  #   - ceil: block number whose timestamp is always > target (exclusive upper bound)
  #   - best: highest block seen so far with timestamp <= target
  #
  # Ported from blockwatch's do_get_block_number_from_timestamp/5.
  @spec binary_search(
          non_neg_integer(),
          non_neg_integer(),
          map(),
          non_neg_integer(),
          keyword()
        ) :: {:ok, t()} | {:error, term()}
  defp binary_search(floor, ceil, best, _target, _rpc_opts) when floor >= ceil do
    {:ok, best}
  end

  defp binary_search(floor, ceil, best, target, rpc_opts) do
    mid = div(ceil - floor, 2) + floor

    case get_by_number(mid, rpc_opts) do
      {:ok, block} ->
        cond do
          block.timestamp == target ->
            {:ok, block}

          block.timestamp < target ->
            binary_search(mid + 1, ceil, block, target, rpc_opts)

          true ->
            binary_search(floor, mid, best, target, rpc_opts)
        end

      {:error, _} = error ->
        error
    end
  end

  @doc false
  # RPC blocks are decoded in Cartouche.RPC; pending blocks have number: nil.
  @spec summarize_block(map() | nil) :: {:ok, t()} | {:error, term()}
  defp summarize_block(nil), do: {:error, :block_not_found}

  defp summarize_block(%{number: nil}), do: {:error, :pending_block}

  defp summarize_block(%__MODULE__{number: n, timestamp: ts} = block) when is_integer(n) and is_integer(ts) do
    {:ok, block}
  end

  defp summarize_block(_), do: {:error, :invalid_block}
end
