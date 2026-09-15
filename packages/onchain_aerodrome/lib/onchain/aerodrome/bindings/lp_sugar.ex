defmodule Onchain.Aerodrome.Bindings.LpSugar do
  @moduledoc """
  Positional bindings for the deployed Base LpSugar read surface.

  Options are forwarded to `Onchain.RPC.eth_call/3`. `:network` selects the
  contract registry (default `:base`); configure a Base endpoint through
  `:rpc_url` or the core RPC configuration. Pin `:block` across an enumeration
  for a consistent snapshot; historical blocks require an archive-capable
  endpoint. RPC and decode errors propagate as tagged tuples, never as
  successful partial enumerations.

  Elixir names use snake_case (for example `for_swaps/3` calls `forSwaps`).
  """

  alias Onchain.ABI
  alias Onchain.Address
  alias Onchain.Aerodrome.Bindings.Abi
  alias Onchain.Aerodrome.Contracts
  alias Onchain.Aerodrome.Types.Lp
  alias Onchain.Aerodrome.Types.Position
  alias Onchain.Aerodrome.Types.Swap
  alias Onchain.Aerodrome.Types.Token
  alias Onchain.RPC

  @doc "Returns the size of the unfiltered global pool index space."
  @spec count(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def count(opts \\ []) do
    with {:ok, [count]} <- call("count", [], opts), do: {:ok, count}
  end

  @doc """
  Reads one `all(uint256,uint256,uint256)` page as pool structs.

  `offset` walks the unfiltered global pool index space; enumeration ends only
  at `count/1`, never on a short or empty page. `filter` is an opaque
  non-negative integer passthrough: its semantics are undocumented upstream,
  and fixture drift detection is the only available verification.
  """
  @spec all(pos_integer(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, [Lp.t()]} | {:error, term()}
  def all(limit, offset, filter, opts \\ []) do
    rows("all", [limit, offset, filter], Lp, opts)
  end

  @doc """
  Enumerates pools sequentially until offset reaches the initial `count/1`.

  Options include `:limit` (default 500, at most `Contracts.constants().max_lps`)
  plus RPC options. Short and empty filtered pages do not terminate the scan.
  A 500-pool call returns about 1.1 MB and works on public Base and Alchemy;
  the endpoint must permit that per-call gas and response size. A refusal is
  returned unchanged, without silently lowering the limit or using multicall.
  """
  @spec all_pages(non_neg_integer(), keyword()) :: {:ok, [Lp.t()]} | {:error, term()}
  def all_pages(filter \\ 0, opts \\ []) do
    {limit, rpc_opts} = Keyword.pop(opts, :limit, Contracts.constants().max_lps)

    if is_integer(limit) and limit > 0 and limit <= Contracts.constants().max_lps do
      with {:ok, count} <- count(rpc_opts) do
        paginate(count, limit, &all(limit, &1, filter, rpc_opts))
      end
    else
      {:error, {:invalid_limit, limit}}
    end
  end

  @doc """
  Reads a `forSwaps` page. Offset scans the global pool index, not returned
  swap rows; skipped pools can make any page short. Walk to `count/1` to finish.
  """
  @spec for_swaps(pos_integer(), non_neg_integer(), keyword()) ::
          {:ok, [Swap.t()]} | {:error, term()}
  def for_swaps(limit, offset, opts \\ []) do
    rows("forSwaps", [limit, offset], Swap, opts)
  end

  @doc """
  Reads positions for an account. Offset scans the global pool index, not
  returned positions; walk to `count/1` even after short or empty pages.
  """
  @spec positions(pos_integer(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, [Position.t()]} | {:error, term()}
  def positions(limit, offset, account, opts \\ []) do
    with {:ok, account} <- Address.validate(account) do
      rows("positions", [limit, offset, account], Position, opts)
    end
  end

  @doc """
  Reads `positionsByFactory` for an account and factory. Offset scans that
  factory's pool index space, not returned positions. Enumerate through the
  factory's full pool count; a short or empty page is not terminal.
  """
  @spec positions_by_factory(
          pos_integer(),
          non_neg_integer(),
          String.t() | binary(),
          String.t() | binary(),
          keyword()
        ) :: {:ok, [Position.t()]} | {:error, term()}
  def positions_by_factory(limit, offset, account, factory, opts \\ []) do
    with {:ok, account} <- Address.validate(account),
         {:ok, factory} <- Address.validate(factory) do
      rows("positionsByFactory", [limit, offset, account, factory], Position, opts)
    end
  end

  @doc """
  Reads `positionsUnstakedConcentrated` for an account. Offset scans the
  account's owned position-NFT index space, not returned live positions.
  Enumerate the full scanned NFT space across the legacy position managers
  (managers supporting `userPositions` are handled by `positions/4`). Skipped
  NFTs mean short or empty pages are not terminal. Pool `count/1` is not the
  bound for this scan.
  """
  @spec positions_unstaked_concentrated(
          pos_integer(),
          non_neg_integer(),
          String.t() | binary(),
          keyword()
        ) :: {:ok, [Position.t()]} | {:error, term()}
  def positions_unstaked_concentrated(limit, offset, account, opts \\ []) do
    with {:ok, account} <- Address.validate(account) do
      rows("positionsUnstakedConcentrated", [limit, offset, account], Position, opts)
    end
  end

  @doc """
  Reads token metadata and account balances, including the supplied token addresses.
  Offset scans the underlying pool index space, not the deduplicated returned
  token rows. Walk the full scanned pool space to `count/1`; neither a short
  page nor its token-row count determines the next offset.
  """
  @spec tokens(pos_integer(), non_neg_integer(), String.t() | binary(), [String.t() | binary()], keyword()) ::
          {:ok, [Token.t()]} | {:error, term()}
  def tokens(limit, offset, account, addresses, opts \\ []) do
    with {:ok, account} <- Address.validate(account),
         {:ok, addresses} <- validate_addresses(addresses) do
      rows("tokens", [limit, offset, account, addresses], Token, opts)
    end
  end

  @doc "Returns `almEstimateAmounts`' three integer amounts in ABI order; this read has no offset."
  @spec alm_estimate_amounts(String.t() | binary(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, {non_neg_integer(), non_neg_integer(), non_neg_integer()}} | {:error, term()}
  def alm_estimate_amounts(alm, amount0, amount1, opts \\ []) do
    with {:ok, alm} <- Address.validate(alm),
         {:ok, [[used0, used1, liquidity]]} <- call("almEstimateAmounts", [alm, amount0, amount1], opts) do
      {:ok, {used0, used1, liquidity}}
    end
  end

  @doc """
  Collects sequential pages over a caller-supplied scanned index count.

  Calls `fetch_page.(offset)` starting at zero and advances by `limit` until
  offset reaches or exceeds `count`, regardless of returned row counts. Pass
  the bound for the function's actual scanned space (pool count or NFT count),
  and use the same limit and pinned block in the callback. Errors discard the
  partial result. `all_pages/2` obtains the pool count automatically.
  """
  @spec paginate(non_neg_integer(), pos_integer(), (non_neg_integer() -> {:ok, [item]} | {:error, term()})) ::
          {:ok, [item]} | {:error, term()}
        when item: term()
  def paginate(count, limit, fetch_page)
      when is_integer(count) and count >= 0 and is_integer(limit) and limit > 0 and is_function(fetch_page, 1) do
    collect_pages(0, count, limit, fetch_page, [])
  end

  defp collect_pages(offset, count, _limit, _fetch_page, pages) when offset >= count do
    {:ok, pages |> Enum.reverse() |> Enum.concat()}
  end

  defp collect_pages(offset, count, limit, fetch_page, pages) do
    with {:ok, rows} <- fetch_page.(offset) do
      collect_pages(offset + limit, count, limit, fetch_page, [rows | pages])
    end
  end

  defp rows(function, args, module, opts) do
    with {:ok, [rows]} <- call(function, args, opts) do
      {:ok, Enum.map(rows, &module.from_raw/1)}
    end
  end

  defp call(function, args, opts) do
    opts = Keyword.put_new(opts, :network, :base)

    with {:ok, address} <- Contracts.address(:lp_sugar, opts),
         {:ok, signature} <- Abi.signature("lp_sugar.json", function),
         {:ok, return_type} <- Abi.return_type("lp_sugar.json", function),
         {:ok, calldata} <- ABI.encode_call(signature, args),
         {:ok, response} <- RPC.eth_call(address, calldata, opts) do
      ABI.decode_response(return_type, response)
    end
  end

  defp validate_addresses(addresses) do
    addresses
    |> Enum.reduce_while({:ok, []}, fn address, {:ok, acc} ->
      case Address.validate(address) do
        {:ok, address} -> {:cont, {:ok, [address | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, addresses} -> {:ok, Enum.reverse(addresses)}
      error -> error
    end
  end
end
