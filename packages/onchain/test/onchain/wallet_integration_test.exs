defmodule Onchain.WalletIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Wallet

  @moduletag :integration

  # WETH contract on mainnet
  @weth_address "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

  # Vitalik's address — well-known EOA
  @eoa_address "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"

  # EOAs can gain code via EIP-7702 delegation; query at historical block
  @historical_block 20_000_000

  defp rpc_opts, do: [rpc_url: Onchain.RPCCase.rpc_url!()]

  describe "classify/2" do
    test "returns :contract for known contract (WETH)" do
      assert {:ok, :contract} = Wallet.classify(@weth_address, rpc_opts())
    end

    test "returns :eoa for known EOA" do
      opts = Keyword.put(rpc_opts(), :block, @historical_block)
      assert {:ok, :eoa} = Wallet.classify(@eoa_address, opts)
    end
  end

  describe "classify!/2" do
    test "returns atom directly" do
      assert :contract == Wallet.classify!(@weth_address, rpc_opts())
      opts = Keyword.put(rpc_opts(), :block, @historical_block)
      assert :eoa == Wallet.classify!(@eoa_address, opts)
    end
  end

  describe "balance/2" do
    test "returns balance for known address" do
      assert {:ok, balance} = Wallet.balance(@weth_address, rpc_opts())
      assert is_integer(balance)
      assert balance >= 0
    end
  end

  describe "balance!/2" do
    test "returns balance directly" do
      balance = Wallet.balance!(@weth_address, rpc_opts())
      assert is_integer(balance)
      assert balance >= 0
    end
  end
end
