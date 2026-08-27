defmodule Onchain.DEX.Router.Pool do
  @moduledoc """
  A single DEX liquidity pool descriptor consumed by `Onchain.DEX.Router`.

  Two protocols are supported:

  - `:uniswap_v2` — constant-product pools. Output is computed analytically in
    pure Elixir from `:reserve0`/`:reserve1` (no RPC needed for the math). Fetch
    reserves once via `getReserves()` and populate the struct.
  - `:uniswap_v3` — concentrated-liquidity pools. Output is obtained from the
    on-chain QuoterV2 contract via `eth_call` (exact tick-crossing simulation);
    `:reserve0`/`:reserve1` are ignored.

  `:fee_bps` is the pool fee in **true basis points** (30 = 0.30%). For v3 it is
  converted to the uint24 fee tier the quoter expects (`fee_bps * 100`, so
  30 bps → 3000).
  """

  @enforce_keys [:protocol, :address, :token0, :token1, :fee_bps]
  defstruct [:protocol, :address, :token0, :token1, :fee_bps, :reserve0, :reserve1]

  @type t :: %__MODULE__{
          protocol: :uniswap_v2 | :uniswap_v3,
          address: String.t() | binary(),
          token0: String.t() | binary(),
          token1: String.t() | binary(),
          fee_bps: non_neg_integer(),
          reserve0: non_neg_integer() | nil,
          reserve1: non_neg_integer() | nil
        }
end

defmodule Onchain.DEX.Router.Route do
  @moduledoc """
  The result of an `Onchain.DEX.Router.route/5` query: the output-maximizing
  path through a candidate pool set.

  - `:path` — token addresses (normalized lowercase hex) from input to output.
  - `:pools` — pool addresses (normalized lowercase hex), one per hop.
  - `:amount_in` / `:amount_out` — raw integer amounts (caller normalizes with
    `Onchain.Decimal`).
  - `:hops` — number of pool hops (`length(pools)`).
  """

  @enforce_keys [:path, :pools, :amount_in, :amount_out, :hops]
  defstruct [:path, :pools, :amount_in, :amount_out, :hops]

  @type t :: %__MODULE__{
          path: [String.t()],
          pools: [String.t()],
          amount_in: non_neg_integer(),
          amount_out: non_neg_integer(),
          hops: non_neg_integer()
        }
end

defmodule Onchain.DEX.Router do
  @moduledoc """
  Optimal DEX swap-path routing across liquidity pools (Uniswap v2/v3-style).

  Given an input token, output token, amount, and a candidate pool set, returns
  the path that maximizes output — direct or multi-hop.

  ## Approach: pure-Elixir analytic routing + on-chain v3 quoting (chosen)

  The task scoped three candidate approaches, all of which were **rejected**:

  | Approach | Rejected because |
  |----------|------------------|
  | (a) Rust routing libs via `onchain_evm` | `onchain_evm` *depends on* `onchain`. Routing here would invert the dependency graph, and `onchain`'s charter is **pure Elixir, no native deps**. |
  | (b) Elixir + revm local simulation | revm is a Rust NIF (lives in `onchain_evm`). Same dependency inversion + native-dep violation. |
  | (c) QuickBEAM + Uniswap v3 SDK | QuickBEAM is a Zig NIF (lives in `onchain_js`). Same inversion; also ships a full JS runtime to quote a swap. |

  All three pull a native dependency `onchain` cannot take and invert the
  dependency graph (`onchain_evm`/`onchain_js` build *on top of* `onchain`). The
  chosen fourth approach keeps routing in the pure-Elixir layer where it belongs:

  - **Uniswap v2-style pools** — output computed analytically from reserves with
    the canonical constant-product formula (`amount_out_v2/4`). Pure, fast,
    unit-testable, no RPC.
  - **Uniswap v3-style pools** — output obtained from the on-chain **QuoterV2**
    contract via `eth_call` (`quoteExactInputSingle`), which simulates tick
    crossings exactly. An `eth_call` read is squarely `onchain`'s wheelhouse and
    avoids a fragile single-tick approximation that would silently mis-rank
    large trades.

  Path enumeration is a pure graph walk over the pool set (tokens as nodes, pools
  as edges); for a fixed token path the per-hop output-maximizing pool is chosen
  greedily, which is globally optimal because each pool's output is monotonic in
  its input.

  ## Limitations

  - **No split routing.** A single best path is returned; the amount is not split
    across pools (production aggregators do — out of scope for this prototype).
  - v3 hops require `opts[:rpc_url]` (and reach the mainnet QuoterV2 by default;
    override with `opts[:quoter]`). v2 hops need no RPC.

  ## Sources

  - Uniswap v2 `getAmountOut`: `Uniswap/v2-periphery` `UniswapV2Library.sol`.
  - QuoterV2 `0x61fFE014bA17989E743c5F6cB21bF9697530B21e` and
    `quoteExactInputSingle` ABI: `Uniswap/v3-periphery` `IQuoterV2.sol`,
    Uniswap Ethereum deployments docs.

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `route/5` | Optimal path for a token pair across a candidate pool set |
  | `quote_pool/4` | Output of a single pool hop (v2 analytic / v3 on-chain quote) |
  | `amount_out_v2/4` | Pure constant-product output for one v2 hop |
  """

  use Descripex, namespace: "/dex/router"

  alias Onchain.Address
  alias Onchain.Contract
  alias Onchain.DEX.Router.Pool
  alias Onchain.DEX.Router.Route

  # Uniswap v3 QuoterV2 on Ethereum mainnet.
  @quoter_v2_mainnet "0x61fFE014bA17989E743c5F6cB21bF9697530B21e"
  @quoter_signature "quoteExactInputSingle((address,address,uint256,uint24,uint160))"
  @quoter_return "(uint256,uint160,uint32,uint256)"
  @default_max_hops 3
  @fee_denominator 10_000

  # --- route ---

  api(:route, "Find the output-maximizing swap path across a candidate pool set.",
    params: [
      token_in: [kind: :value, description: "Input token address (0x hex or 20-byte binary)"],
      token_out: [kind: :value, description: "Output token address (0x hex or 20-byte binary)"],
      amount_in: [kind: :value, description: "Raw input amount (integer, token base units)"],
      pools: [
        kind: :value,
        description: "List of %Onchain.DEX.Router.Pool{} candidates to route through"
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :rpc_url (v3 hops), :quoter, :max_hops (default 3), :timeout, :block"
      ]
    ],
    returns: %{
      type: "{:ok, %Onchain.DEX.Router.Route{}} | {:error, term()}",
      description: "Optimal route with path, per-hop pools, and output amount",
      example: "{:ok, %Onchain.DEX.Router.Route{amount_out: 90}}"
    }
  )

  @spec route(
          String.t() | binary(),
          String.t() | binary(),
          non_neg_integer(),
          [Pool.t()],
          keyword()
        ) :: {:ok, Route.t()} | {:error, term()}
  def route(token_in, token_out, amount_in, pools, opts \\ [])

  def route(_token_in, _token_out, amount_in, _pools, _opts) when not (is_integer(amount_in) and amount_in > 0) do
    {:error, {:invalid_amount, amount_in}}
  end

  def route(token_in, token_out, amount_in, pools, opts) when is_list(pools) do
    max_hops = Keyword.get(opts, :max_hops, @default_max_hops)

    with {:ok, from} <- Address.normalize(token_in),
         {:ok, to} <- Address.normalize(token_out),
         :ok <- distinct_tokens(from, to),
         {:ok, edges} <- build_edges(pools) do
      from
      |> token_paths(to, edges, max_hops)
      |> best_route(amount_in, edges, opts)
    end
  end

  # --- quote_pool ---

  api(:quote_pool, "Quote the output of a single pool hop for a given input token.",
    params: [
      pool: [kind: :value, description: "%Onchain.DEX.Router.Pool{} to quote against"],
      token_in: [kind: :value, description: "Input token of this hop (0x hex or 20-byte binary)"],
      amount_in: [kind: :value, description: "Raw input amount (integer)"],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :rpc_url (v3), :quoter, :timeout, :block"
      ]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Raw output amount of the swap through this pool",
      example: "90"
    }
  )

  @spec quote_pool(Pool.t(), String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def quote_pool(%Pool{} = pool, token_in, amount_in, opts \\ []) do
    with {:ok, in_hex} <- Address.normalize(token_in),
         {:ok, out_hex} <- other_token(pool, in_hex) do
      do_quote(pool, in_hex, out_hex, amount_in, opts)
    end
  end

  # --- amount_out_v2 ---

  api(:amount_out_v2, "Constant-product (Uniswap v2) output for one hop. Pure math.",
    params: [
      amount_in: [kind: :value, description: "Raw input amount (integer > 0)"],
      reserve_in: [kind: :value, description: "Reserve of the input token (integer > 0)"],
      reserve_out: [kind: :value, description: "Reserve of the output token (integer > 0)"],
      fee_bps: [kind: :value, description: "Pool fee in basis points (30 = 0.30%)"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Raw output amount via x*y=k with fee deducted",
      example: "90"
    }
  )

  @doc """
  Constant-product output for a single Uniswap v2-style hop.

  Implements the canonical `getAmountOut`:
  `amount_out = (amount_in * f * reserve_out) / (reserve_in * 10000 + amount_in * f)`
  where `f = 10000 - fee_bps`. Source: `UniswapV2Library.sol` (997/1000 = 0.3%).

  ## Examples

      iex> Onchain.DEX.Router.amount_out_v2(100, 1000, 1000, 30)
      {:ok, 90}

      iex> Onchain.DEX.Router.amount_out_v2(0, 1000, 1000, 30)
      {:error, :insufficient_input_amount}

      iex> Onchain.DEX.Router.amount_out_v2(100, 0, 1000, 30)
      {:error, :insufficient_liquidity}
  """
  @spec amount_out_v2(integer(), integer(), integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def amount_out_v2(amount_in, _reserve_in, _reserve_out, _fee_bps) when amount_in <= 0 do
    {:error, :insufficient_input_amount}
  end

  def amount_out_v2(_amount_in, reserve_in, reserve_out, _fee_bps) when reserve_in <= 0 or reserve_out <= 0 do
    {:error, :insufficient_liquidity}
  end

  def amount_out_v2(_amount_in, _reserve_in, _reserve_out, fee_bps) when fee_bps < 0 or fee_bps >= @fee_denominator do
    {:error, {:invalid_fee_bps, fee_bps}}
  end

  def amount_out_v2(amount_in, reserve_in, reserve_out, fee_bps) do
    amount_in_with_fee = amount_in * (@fee_denominator - fee_bps)
    numerator = amount_in_with_fee * reserve_out
    denominator = reserve_in * @fee_denominator + amount_in_with_fee
    {:ok, div(numerator, denominator)}
  end

  # --- private: quoting ---

  @spec do_quote(Pool.t(), String.t(), String.t(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp do_quote(%Pool{protocol: :uniswap_v2} = pool, in_hex, _out_hex, amount_in, _opts) do
    with {:ok, {reserve_in, reserve_out}} <- v2_reserves(pool, in_hex) do
      amount_out_v2(amount_in, reserve_in, reserve_out, pool.fee_bps)
    end
  end

  defp do_quote(%Pool{protocol: :uniswap_v3} = pool, in_hex, out_hex, amount_in, opts) do
    quoter = Keyword.get(opts, :quoter, @quoter_v2_mainnet)
    fee_uint24 = pool.fee_bps * 100

    with {:ok, in_bin} <- Address.validate(in_hex),
         {:ok, out_bin} <- Address.validate(out_hex),
         params = {in_bin, out_bin, amount_in, fee_uint24, 0},
         {:ok, [amount_out | _]} <-
           Contract.call(quoter, @quoter_signature, [params], @quoter_return, opts) do
      {:ok, amount_out}
    end
  end

  # Resolves (reserve_in, reserve_out) for a v2 pool given the input token.
  @spec v2_reserves(Pool.t(), String.t()) ::
          {:ok, {non_neg_integer(), non_neg_integer()}} | {:error, term()}
  defp v2_reserves(%Pool{reserve0: r0, reserve1: r1}, _in_hex) when is_nil(r0) or is_nil(r1) do
    {:error, :missing_reserves}
  end

  defp v2_reserves(%Pool{token0: t0, reserve0: r0, reserve1: r1} = pool, in_hex) do
    cond do
      Address.equal?(t0, in_hex) -> {:ok, {r0, r1}}
      Address.equal?(pool.token1, in_hex) -> {:ok, {r1, r0}}
      true -> {:error, {:token_not_in_pool, in_hex}}
    end
  end

  # Returns the token on the other side of a pool from `token_hex`.
  @spec other_token(Pool.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defp other_token(%Pool{token0: t0, token1: t1}, token_hex) do
    cond do
      Address.equal?(t0, token_hex) -> Address.normalize(t1)
      Address.equal?(t1, token_hex) -> Address.normalize(t0)
      true -> {:error, {:token_not_in_pool, token_hex}}
    end
  end

  # --- private: path enumeration + evaluation ---

  # Pre-normalizes pools into {pool, token_a_hex, token_b_hex} edges.
  @spec build_edges([Pool.t()]) :: {:ok, [{Pool.t(), String.t(), String.t()}]} | {:error, term()}
  defp build_edges(pools) do
    pools
    |> Enum.reduce_while({:ok, []}, fn pool, {:ok, acc} ->
      with %Pool{} <- pool,
           {:ok, a} <- Address.normalize(pool.token0),
           {:ok, b} <- Address.normalize(pool.token1) do
        {:cont, {:ok, [{pool, a, b} | acc]}}
      else
        {:error, _} = err -> {:halt, err}
        other -> {:halt, {:error, {:invalid_pool, other}}}
      end
    end)
    |> case do
      {:ok, edges} -> {:ok, Enum.reverse(edges)}
      err -> err
    end
  end

  # Enumerates all simple token paths from `from` to `to` with <= max_hops edges.
  @spec token_paths(String.t(), String.t(), [{Pool.t(), String.t(), String.t()}], pos_integer()) ::
          [[String.t()]]
  defp token_paths(from, to, edges, max_hops) do
    expand([from], from, to, edges, max_hops)
  end

  @spec expand([String.t()], String.t(), String.t(), [{Pool.t(), String.t(), String.t()}], integer()) ::
          [[String.t()]]
  defp expand(visited, current, target, _edges, _max_hops) when current == target do
    case visited do
      [_, _ | _] -> [Enum.reverse(visited)]
      _ -> []
    end
  end

  defp expand(visited, _current, _target, _edges, max_hops) when length(visited) > max_hops do
    []
  end

  defp expand(visited, current, target, edges, max_hops) do
    edges
    |> neighbors(current)
    |> Enum.reject(&(&1 in visited))
    |> Enum.flat_map(fn next -> expand([next | visited], next, target, edges, max_hops) end)
  end

  # All tokens directly reachable from `token` via one edge.
  @spec neighbors([{Pool.t(), String.t(), String.t()}], String.t()) :: [String.t()]
  defp neighbors(edges, token) do
    edges
    |> Enum.flat_map(fn
      {_pool, ^token, b} -> [b]
      {_pool, a, ^token} -> [a]
      _ -> []
    end)
    |> Enum.uniq()
  end

  # Evaluates every candidate token path and returns the max-output route.
  @spec best_route([[String.t()]], non_neg_integer(), [{Pool.t(), String.t(), String.t()}], keyword()) ::
          {:ok, Route.t()} | {:error, term()}
  defp best_route([], _amount_in, _edges, _opts), do: {:error, :no_route}

  defp best_route(paths, amount_in, edges, opts) do
    paths
    |> Enum.map(&evaluate_path(&1, amount_in, edges, opts))
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, route} -> route end)
    |> case do
      [] -> {:error, :no_route}
      routes -> {:ok, Enum.max_by(routes, & &1.amount_out)}
    end
  end

  # Walks a single token path, greedily choosing the best pool per hop.
  @spec evaluate_path([String.t()], non_neg_integer(), [{Pool.t(), String.t(), String.t()}], keyword()) ::
          {:ok, Route.t()} | {:error, term()}
  defp evaluate_path(path, amount_in, edges, opts) do
    path
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce_while({:ok, {amount_in, []}}, fn [a, b], {:ok, {running, pool_acc}} ->
      case best_hop(a, b, running, edges, opts) do
        {:ok, {pool_addr, out}} -> {:cont, {:ok, {out, [pool_addr | pool_acc]}}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, {amount_out, pool_acc}} ->
        pools = Enum.reverse(pool_acc)

        {:ok,
         %Route{
           path: path,
           pools: pools,
           amount_in: amount_in,
           amount_out: amount_out,
           hops: length(pools)
         }}

      err ->
        err
    end
  end

  # Among all pools connecting a->b, picks the one with the highest output.
  @spec best_hop(String.t(), String.t(), non_neg_integer(), [{Pool.t(), String.t(), String.t()}], keyword()) ::
          {:ok, {String.t(), non_neg_integer()}} | {:error, term()}
  defp best_hop(a, b, amount_in, edges, opts) do
    edges
    |> pools_for_pair(a, b)
    |> Enum.flat_map(fn pool ->
      case quote_pool(pool, a, amount_in, opts) do
        {:ok, out} when out > 0 ->
          case Address.normalize(pool.address) do
            {:ok, addr} -> [{addr, out}]
            _ -> []
          end

        _ ->
          []
      end
    end)
    |> case do
      [] -> {:error, {:no_pool_for_pair, a, b}}
      quotes -> {:ok, Enum.max_by(quotes, fn {_addr, out} -> out end)}
    end
  end

  # Pools whose token pair is exactly {a, b} (unordered).
  @spec pools_for_pair([{Pool.t(), String.t(), String.t()}], String.t(), String.t()) :: [Pool.t()]
  defp pools_for_pair(edges, a, b) do
    edges
    |> Enum.filter(fn {_pool, x, y} ->
      (x == a and y == b) or (x == b and y == a)
    end)
    |> Enum.map(fn {pool, _x, _y} -> pool end)
  end

  @spec distinct_tokens(String.t(), String.t()) :: :ok | {:error, :identical_tokens}
  defp distinct_tokens(from, to) do
    if from == to, do: {:error, :identical_tokens}, else: :ok
  end
end
