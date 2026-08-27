defmodule Onchain.DEX.Router.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Contract
  alias Onchain.DEX.Router
  alias Onchain.DEX.Router.Pool
  alias Onchain.DEX.Router.Route

  @moduletag :integration

  # USDC on Ethereum mainnet (6 decimals)
  @usdc "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  # WETH on Ethereum mainnet (18 decimals)
  @weth "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

  # Uniswap v2 USDC/WETH pair (token0 = USDC, token1 = WETH)
  @v2_pair "0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc"
  # Uniswap v3 USDC/WETH 0.05% (5 bps) pool
  @v3_pool "0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640"

  # 1000 USDC in base units
  @amount_in 1_000_000_000

  defp rpc_opts, do: [rpc_url: Onchain.RPCCase.rpc_url!()]

  # Fetches live reserves and builds a v2 Pool struct.
  defp live_v2_pool(opts) do
    {:ok, [r0, r1, _ts]} =
      Contract.call(@v2_pair, "getReserves()", [], "(uint112,uint112,uint32)", opts)

    %Pool{
      protocol: :uniswap_v2,
      address: @v2_pair,
      token0: @usdc,
      token1: @weth,
      reserve0: r0,
      reserve1: r1,
      fee_bps: 30
    }
  end

  defp v3_pool do
    %Pool{
      protocol: :uniswap_v3,
      address: @v3_pool,
      token0: @usdc,
      token1: @weth,
      fee_bps: 5
    }
  end

  describe "route/5 against real mainnet pools" do
    test "routes 1000 USDC -> WETH through the live v2 pair" do
      opts = rpc_opts()
      pools = [live_v2_pool(opts)]

      assert {:ok, %Route{} = route} = Router.route(@usdc, @weth, @amount_in, pools, opts)
      assert route.hops == 1
      assert route.amount_out > 0
      # ~1000 USDC should buy well under 1 WETH but a non-trivial amount of wei.
      assert route.amount_out > 100_000_000_000_000
    end

    test "quotes the v3 pool via the on-chain QuoterV2" do
      opts = rpc_opts()

      assert {:ok, out} = Router.quote_pool(v3_pool(), @usdc, @amount_in, opts)
      assert out > 0
      assert out > 100_000_000_000_000
    end

    test "picks the better of v2 and v3 USDC/WETH pools" do
      opts = rpc_opts()
      pools = [live_v2_pool(opts), v3_pool()]

      assert {:ok, %Route{} = route} = Router.route(@usdc, @weth, @amount_in, pools, opts)
      assert route.hops == 1

      # Independently quote each and confirm the router chose the max.
      {:ok, v2_out} = Router.quote_pool(live_v2_pool(opts), @usdc, @amount_in, opts)
      {:ok, v3_out} = Router.quote_pool(v3_pool(), @usdc, @amount_in, opts)

      assert route.amount_out == max(v2_out, v3_out)

      winner = if v2_out >= v3_out, do: @v2_pair, else: @v3_pool
      assert Onchain.Address.equal?(hd(route.pools), winner)
    end
  end
end
