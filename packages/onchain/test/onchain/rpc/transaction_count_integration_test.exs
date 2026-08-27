defmodule Onchain.RPC.TransactionCountIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.RPC

  @moduletag :integration

  # Vitalik's address — guaranteed to have many transactions
  @vitalik "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
  # Zero address — no transactions sent from it
  @zero_address "0x0000000000000000000000000000000000000000"

  defp rpc_opts, do: [rpc_url: Onchain.RPCCase.rpc_url!()]

  describe "get_transaction_count/2" do
    test "returns positive count for active address" do
      assert {:ok, count} = RPC.get_transaction_count(@vitalik, rpc_opts())
      assert is_integer(count)
      assert count > 0
    end

    test "returns zero for zero address" do
      assert {:ok, 0} = RPC.get_transaction_count(@zero_address, rpc_opts())
    end

    test "block option works (historical count <= latest count)" do
      {:ok, latest_count} = RPC.get_transaction_count(@vitalik, rpc_opts())

      # Check nonce at a historical block (block 15M, well before present)
      historical_block = 15_000_000
      opts = Keyword.put(rpc_opts(), :block, historical_block)
      {:ok, historical_count} = RPC.get_transaction_count(@vitalik, opts)

      assert is_integer(historical_count)
      assert historical_count <= latest_count
      assert historical_count > 0
    end

    test "accepts 20-byte binary address" do
      {:ok, binary_addr} = Onchain.Address.validate(@vitalik)
      assert {:ok, count} = RPC.get_transaction_count(binary_addr, rpc_opts())
      assert is_integer(count)
      assert count > 0
    end
  end

  describe "get_transaction_count!/2" do
    test "returns count directly" do
      count = RPC.get_transaction_count!(@vitalik, rpc_opts())
      assert is_integer(count)
      assert count > 0
    end
  end
end
