defmodule Onchain.Block do
  @moduledoc """
  Ethereum block fetching and timestamp-based block search.

  Provides parsed block data (native integers instead of hex strings) and a
  binary search algorithm for finding the block closest to a target timestamp.

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `get_by_number/2` | Fetch and parse a block by number or tag |
  | `get_by_number!/2` | Same, raises on error |
  | `find_by_timestamp/2` | Binary search for block ≤ target timestamp |
  | `find_by_timestamp!/2` | Same, raises on error |

  ## Return Shape

  All functions return a plain map with native types:

      %{number: 20_000_000, timestamp: 1_717_281_407, hash: "0xd24f..."}

  ## Algorithm

  `find_by_timestamp/2` performs a binary search between a floor and ceiling
  block. It fetches the midpoint block, compares its timestamp to the target,
  and recurses into the appropriate half. Returns the highest block with
  `timestamp <= target`. Ported from blockwatch's `BlockFromTimestamp`.
  """

  use Descripex, namespace: "/block"

  # --- get_by_number ---

  api(:get_by_number, "Fetch and parse a block by number or tag.",
    params: [
      block_id: [
        kind: :value,
        description: ~s{Block number (integer) or tag string ("latest", "finalized", etc.)}
      ],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{
      type: "{:ok, map} | {:error, term}",
      description: "Parsed block with native types",
      example: ~s(%{number: 20_000_000, timestamp: 1_717_281_407, hash: "0xd24f..."})
    }
  )

  @spec get_by_number(integer() | String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_by_number(block_id, opts \\ []) do
    with {:ok, block} <- Onchain.RPC.get_block_by_number(block_id, opts) do
      summarize_block(block)
    end
  end

  # --- get_by_number! ---

  api(:get_by_number!, "Fetch and parse a block by number or tag. Raises on error.",
    params: [
      block_id: [kind: :value, description: "Block number (integer) or tag string"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout"]
    ],
    returns: %{type: :map, description: "Parsed block map"}
  )

  @spec get_by_number!(integer() | String.t(), keyword()) :: map()
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
      type: "{:ok, map} | {:error, term}",
      description: "Block with highest timestamp ≤ target",
      example: ~s(%{number: 20_000_000, timestamp: 1_717_281_407, hash: "0xd24f..."})
    }
  )

  @spec find_by_timestamp(non_neg_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def find_by_timestamp(target_timestamp, opts \\ [])

  def find_by_timestamp(target_timestamp, _opts) when not is_integer(target_timestamp) do
    {:error, {:invalid_timestamp, target_timestamp}}
  end

  def find_by_timestamp(target_timestamp, _opts) when target_timestamp < 0 do
    {:error, {:invalid_timestamp, target_timestamp}}
  end

  def find_by_timestamp(target_timestamp, opts) do
    rpc_opts = Keyword.take(opts, [:rpc_url, :timeout])

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
    returns: %{type: :map, description: "Parsed block map"}
  )

  @spec find_by_timestamp!(non_neg_integer(), keyword()) :: map()
  def find_by_timestamp!(target_timestamp, opts \\ []) do
    case find_by_timestamp(target_timestamp, opts) do
      {:ok, block} -> block
      {:error, reason} -> raise "find_by_timestamp failed: #{inspect(reason)}"
    end
  end

  # --- Private helpers ---

  @doc false
  # Resolves the floor block: fetch genesis (block 0) if no floor provided.
  @spec resolve_floor(non_neg_integer() | nil, keyword()) :: {:ok, map()} | {:error, term()}
  defp resolve_floor(nil, rpc_opts), do: get_by_number(0, rpc_opts)
  defp resolve_floor(block_num, rpc_opts), do: get_by_number(block_num, rpc_opts)

  @doc false
  # Resolves the ceiling block: fetch "finalized" if no ceil provided.
  # "finalized" avoids reorg issues (same strategy as blockwatch).
  @spec resolve_ceil(non_neg_integer() | nil, keyword()) :: {:ok, map()} | {:error, term()}
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
        ) :: {:ok, map()} | {:error, term()}
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
  # RPC blocks are decoded in Onchain.RPC; pending blocks have number: nil.
  @spec summarize_block(map() | nil) :: {:ok, map()} | {:error, term()}
  defp summarize_block(nil), do: {:error, :block_not_found}

  defp summarize_block(%{number: nil}), do: {:error, :pending_block}

  defp summarize_block(%{number: n, timestamp: ts, hash: h}) when is_integer(n) and is_integer(ts) do
    {:ok, %{number: n, timestamp: ts, hash: h}}
  end

  defp summarize_block(_), do: {:error, :invalid_block}
end
