defmodule Onchain.DEX.RouterTest do
  use ExUnit.Case, async: true

  alias Onchain.DEX.Router
  alias Onchain.DEX.Router.Pool
  alias Onchain.DEX.Router.Route

  doctest Router

  # Distinct, valid 20-byte addresses for synthetic pools.
  @weth "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  @usdc "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @dai "0x6B175474E89094C44Da98b954EedeAC495271d0F"
  @usdt "0xdAC17F958D2ee523a2206206994597C13D831ec7"

  defp v2_pool(addr, t0, t1, r0, r1, fee_bps \\ 30) do
    %Pool{
      protocol: :uniswap_v2,
      address: addr,
      token0: t0,
      token1: t1,
      reserve0: r0,
      reserve1: r1,
      fee_bps: fee_bps
    }
  end

  describe "amount_out_v2/4" do
    test "matches canonical Uniswap v2 getAmountOut" do
      # (100 * 997 * 1000) / (1000 * 1000 + 100 * 997) = 99_700_000 / 1_099_700 = 90
      assert {:ok, 90} = Router.amount_out_v2(100, 1000, 1000, 30)
    end

    test "fee_bps of 0 gives the no-fee constant-product result" do
      # (100 * 1000) / (1000 + 100) = 100_000 / 1100 = 90
      assert {:ok, 90} = Router.amount_out_v2(100, 1000, 1000, 0)
    end

    test "larger reserves reduce price impact" do
      {:ok, small} = Router.amount_out_v2(1_000, 10_000, 10_000, 30)
      {:ok, large} = Router.amount_out_v2(1_000, 1_000_000, 1_000_000, 30)
      assert large > small
    end

    test "output is monotonic in input" do
      {:ok, less} = Router.amount_out_v2(100, 1_000_000, 1_000_000, 30)
      {:ok, more} = Router.amount_out_v2(200, 1_000_000, 1_000_000, 30)
      assert more > less
    end

    test "rejects non-positive input" do
      assert {:error, :insufficient_input_amount} = Router.amount_out_v2(0, 1000, 1000, 30)
      assert {:error, :insufficient_input_amount} = Router.amount_out_v2(-5, 1000, 1000, 30)
    end

    test "rejects empty reserves" do
      assert {:error, :insufficient_liquidity} = Router.amount_out_v2(100, 0, 1000, 30)
      assert {:error, :insufficient_liquidity} = Router.amount_out_v2(100, 1000, 0, 30)
    end

    test "rejects out-of-range fee" do
      assert {:error, {:invalid_fee_bps, 10_000}} = Router.amount_out_v2(100, 1000, 1000, 10_000)
      assert {:error, {:invalid_fee_bps, -1}} = Router.amount_out_v2(100, 1000, 1000, -1)
    end
  end

  describe "quote_pool/4 (v2)" do
    test "quotes in token0 -> token1 direction" do
      pool = v2_pool("0x1111111111111111111111111111111111111111", @usdc, @weth, 1_000_000, 2_000_000)
      assert {:ok, out} = Router.quote_pool(pool, @usdc, 1000)
      assert out > 0
    end

    test "quotes in token1 -> token0 direction (reserves swapped)" do
      pool = v2_pool("0x1111111111111111111111111111111111111111", @usdc, @weth, 1_000_000, 2_000_000)
      {:ok, forward} = Router.quote_pool(pool, @usdc, 1000)
      {:ok, backward} = Router.quote_pool(pool, @weth, 1000)
      # Output side has 2x the reserves going forward, so forward yields more.
      assert forward > backward
    end

    test "errors when the input token is not in the pool" do
      pool = v2_pool("0x1111111111111111111111111111111111111111", @usdc, @weth, 1_000_000, 2_000_000)
      assert {:error, {:token_not_in_pool, _}} = Router.quote_pool(pool, @dai, 1000)
    end

    test "errors when v2 reserves are missing" do
      pool = %Pool{
        protocol: :uniswap_v2,
        address: "0x1111111111111111111111111111111111111111",
        token0: @usdc,
        token1: @weth,
        fee_bps: 30
      }

      assert {:error, :missing_reserves} = Router.quote_pool(pool, @usdc, 1000)
    end
  end

  describe "route/5 — path selection" do
    test "routes a direct single-pool swap" do
      pools = [
        v2_pool("0xAAaAAaA0000000000000000000000000000000A1", @usdc, @weth, 1_000_000, 1_000_000)
      ]

      assert {:ok, %Route{} = route} = Router.route(@usdc, @weth, 1000, pools)
      assert route.hops == 1
      assert route.amount_in == 1000
      assert route.amount_out > 0
      assert [_pool] = route.pools
      assert [from, to] = route.path
      assert Onchain.Address.equal?(from, @usdc)
      assert Onchain.Address.equal?(to, @weth)
    end

    test "picks the higher-output pool among two direct candidates" do
      shallow = v2_pool("0xAAaAAaA0000000000000000000000000000000A1", @usdc, @weth, 10_000, 10_000)
      deep = v2_pool("0xBBbBbBb0000000000000000000000000000000B2", @usdc, @weth, 10_000, 1_000_000)

      assert {:ok, route} = Router.route(@usdc, @weth, 1000, [shallow, deep])
      # Deep pool has far more @weth out-reserve, so it wins.
      assert Onchain.Address.equal?(hd(route.pools), deep.address)
    end

    test "finds a two-hop path when no direct pool exists" do
      pools = [
        v2_pool("0xAAaAAaA0000000000000000000000000000000A1", @usdc, @dai, 1_000_000, 1_000_000),
        v2_pool("0xBBbBbBb0000000000000000000000000000000B2", @dai, @weth, 1_000_000, 1_000_000)
      ]

      assert {:ok, route} = Router.route(@usdc, @weth, 1000, pools)
      assert route.hops == 2
      assert [_, _] = route.pools
      assert [a, b, c] = route.path
      assert Onchain.Address.equal?(a, @usdc)
      assert Onchain.Address.equal?(b, @dai)
      assert Onchain.Address.equal?(c, @weth)
    end

    test "prefers the multi-hop path when it yields more than the direct pool" do
      # Direct USDC/WETH is shallow; the USDC->DAI->WETH route is deep.
      direct = v2_pool("0xAAaAAaA0000000000000000000000000000000A1", @usdc, @weth, 10_000, 10_000)
      hop1 = v2_pool("0xBBbBbBb0000000000000000000000000000000B2", @usdc, @dai, 100_000_000, 100_000_000)
      hop2 = v2_pool("0xCCcCcCc0000000000000000000000000000000C3", @dai, @weth, 100_000_000, 100_000_000)

      assert {:ok, route} = Router.route(@usdc, @weth, 1000, [direct, hop1, hop2])
      assert route.hops == 2
    end

    test "respects max_hops" do
      pools = [
        v2_pool("0xAAaAAaA0000000000000000000000000000000A1", @usdc, @dai, 1_000_000, 1_000_000),
        v2_pool("0xBBbBbBb0000000000000000000000000000000B2", @dai, @usdt, 1_000_000, 1_000_000),
        v2_pool("0xCCcCcCc0000000000000000000000000000000C3", @usdt, @weth, 1_000_000, 1_000_000)
      ]

      # 3-hop path needs max_hops >= 3; capping at 2 yields no route.
      assert {:error, :no_route} = Router.route(@usdc, @weth, 1000, pools, max_hops: 2)
      assert {:ok, route} = Router.route(@usdc, @weth, 1000, pools, max_hops: 3)
      assert route.hops == 3
    end

    test "returns :no_route when the pair is unreachable" do
      pools = [
        v2_pool("0xAAaAAaA0000000000000000000000000000000A1", @usdc, @dai, 1_000_000, 1_000_000)
      ]

      assert {:error, :no_route} = Router.route(@usdc, @weth, 1000, pools)
    end

    test "rejects identical input and output tokens" do
      pools = [
        v2_pool("0xAAaAAaA0000000000000000000000000000000A1", @usdc, @weth, 1_000_000, 1_000_000)
      ]

      assert {:error, :identical_tokens} = Router.route(@usdc, @usdc, 1000, pools)
    end

    test "rejects non-positive amount" do
      pools = [
        v2_pool("0xAAaAAaA0000000000000000000000000000000A1", @usdc, @weth, 1_000_000, 1_000_000)
      ]

      assert {:error, {:invalid_amount, 0}} = Router.route(@usdc, @weth, 0, pools)
    end

    test "propagates an invalid token address" do
      pools = [
        v2_pool("0xAAaAAaA0000000000000000000000000000000A1", @usdc, @weth, 1_000_000, 1_000_000)
      ]

      assert {:error, {:invalid_address, _}} = Router.route("0xnothex", @weth, 1000, pools)
    end

    test "propagates an invalid pool token address" do
      bad = v2_pool("0xAAaAAaA0000000000000000000000000000000A1", "0xbad", @weth, 1_000_000, 1_000_000)
      assert {:error, {:invalid_address, _}} = Router.route(@usdc, @weth, 1000, [bad])
    end
  end
end
