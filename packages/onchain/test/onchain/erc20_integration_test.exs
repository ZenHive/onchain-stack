defmodule Onchain.ERC20.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.ERC20

  @moduletag :integration

  # USDC on Ethereum mainnet
  @usdc_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

  # Circle's treasury — holds large USDC balance
  @usdc_holder "0x55FE002aefF02F77364de339a1292923A15844B8"

  # WETH on Ethereum mainnet
  @weth_address "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

  defp rpc_opts do
    [rpc_url: Onchain.RPCCase.rpc_url!()]
  end

  describe "decimals/2" do
    test "returns 6 for USDC" do
      assert {:ok, 6} = ERC20.decimals(@usdc_address, rpc_opts())
    end
  end

  describe "decimals!/2" do
    test "returns 6 for USDC" do
      assert 6 = ERC20.decimals!(@usdc_address, rpc_opts())
    end
  end

  describe "symbol/2" do
    test "returns USDC for USDC token" do
      assert {:ok, "USDC"} = ERC20.symbol(@usdc_address, rpc_opts())
    end
  end

  describe "symbol!/2" do
    test "returns USDC for USDC token" do
      assert "USDC" = ERC20.symbol!(@usdc_address, rpc_opts())
    end
  end

  describe "balance_of/3" do
    test "returns positive balance for Circle treasury" do
      assert {:ok, balance} = ERC20.balance_of(@usdc_address, @usdc_holder, rpc_opts())
      assert is_integer(balance)
      assert balance > 0, "Expected Circle treasury to have USDC balance > 0, got #{balance}"
    end
  end

  describe "balance_of!/3" do
    test "returns balance directly" do
      balance = ERC20.balance_of!(@usdc_address, @usdc_holder, rpc_opts())
      assert is_integer(balance)
      assert balance > 0
    end
  end

  describe "allowance/4" do
    test "returns integer allowance for two addresses" do
      assert {:ok, allowance} =
               ERC20.allowance(@usdc_address, @usdc_holder, @usdc_address, rpc_opts())

      assert is_integer(allowance)
      assert allowance >= 0
    end
  end

  describe "allowance!/4" do
    test "returns allowance directly" do
      allowance = ERC20.allowance!(@usdc_address, @usdc_holder, @usdc_address, rpc_opts())
      assert is_integer(allowance)
      assert allowance >= 0
    end
  end

  describe "total_supply/2" do
    test "returns positive supply for WETH" do
      assert {:ok, supply} = ERC20.total_supply(@weth_address, rpc_opts())
      assert is_integer(supply)
      assert supply > 0
    end
  end

  describe "total_supply!/2" do
    test "returns positive supply for WETH" do
      supply = ERC20.total_supply!(@weth_address, rpc_opts())
      assert is_integer(supply)
      assert supply > 0
    end
  end
end
