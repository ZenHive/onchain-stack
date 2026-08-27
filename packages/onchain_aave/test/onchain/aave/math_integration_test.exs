defmodule Onchain.Aave.Math.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.Math
  alias Onchain.ABI
  alias Onchain.RPC

  @moduletag :integration

  describe "getUserAccountData math" do
    test "to_usd and to_health_factor produce sane values for live position" do
      user = "0xF380B8F1e63e2BEd7CA329CA1FdDbC39B52cC0d3"
      {:ok, user_bin} = Onchain.Address.validate(user)
      {:ok, pool_addr} = Contracts.address(:pool)
      {:ok, calldata} = ABI.encode_call("getUserAccountData(address)", [user_bin])
      {:ok, hex_result} = RPC.eth_call(pool_addr, calldata, Onchain.RPCCase.rpc_opts!())

      {:ok, [collateral, debt, _available, _liq_threshold, _ltv, health_factor]} =
        ABI.decode_response("(uint256,uint256,uint256,uint256,uint256,uint256)", hex_result)

      collateral_usd = Math.to_usd(collateral)
      debt_usd = Math.to_usd(debt)
      hf = Math.to_health_factor(health_factor)

      # Collateral and debt should be positive Decimals
      assert Decimal.gt?(collateral_usd, Decimal.new(0)),
             "Expected collateral > 0, got #{collateral_usd}"

      assert Decimal.gt?(debt_usd, Decimal.new(0)),
             "Expected debt > 0, got #{debt_usd}"

      # Health factor should be > 1 (not liquidatable) and < 100 (sane range)
      assert Decimal.gt?(hf, Decimal.new(1)),
             "Expected health factor > 1, got #{hf}"

      assert Decimal.lt?(hf, Decimal.new(100)),
             "Expected health factor < 100, got #{hf}"
    end
  end

  describe "oracle price math" do
    test "getAssetPrice for WETH returns reasonable USD price" do
      # WETH address on Ethereum mainnet
      weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
      {:ok, weth_bin} = Onchain.Address.validate(weth)
      {:ok, oracle_addr} = Contracts.address(:oracle)
      {:ok, calldata} = ABI.encode_call("getAssetPrice(address)", [weth_bin])
      {:ok, hex_result} = RPC.eth_call(oracle_addr, calldata, Onchain.RPCCase.rpc_opts!())
      {:ok, [raw_price]} = ABI.decode_response("(uint256)", hex_result)

      price = Math.to_usd(raw_price)

      # ETH price should be between $100 and $100,000
      assert Decimal.gt?(price, Decimal.new(100)),
             "Expected ETH price > $100, got $#{price}"

      assert Decimal.lt?(price, Decimal.new(100_000)),
             "Expected ETH price < $100,000, got $#{price}"
    end
  end
end
