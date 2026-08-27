defmodule Onchain.RPC.ReceiptIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.RPC

  @moduletag :integration

  # Known mainnet block guaranteed to have transactions
  @test_block 20_000_000

  defp rpc_opts, do: [rpc_url: Onchain.RPCCase.rpc_url!()]

  describe "get_transaction_receipt/2" do
    test "fetches receipt from a known block's first transaction" do
      {:ok, block} = RPC.get_block_by_number(@test_block, rpc_opts())
      tx_hashes = block.transactions

      assert tx_hashes != [],
             "Expected block #{@test_block} to have transactions"

      tx_hash = hd(tx_hashes)
      assert {:ok, receipt} = RPC.get_transaction_receipt(tx_hash, rpc_opts())
      assert receipt

      # Verify all parsed fields
      assert is_binary(receipt.transaction_hash)
      assert String.starts_with?(receipt.transaction_hash, "0x")
      assert is_integer(receipt.transaction_index)
      assert is_binary(receipt.block_hash)
      assert String.starts_with?(receipt.block_hash, "0x")
      assert is_integer(receipt.block_number)
      assert receipt.block_number > 0
      assert is_binary(receipt.from)
      assert String.starts_with?(receipt.from, "0x")
      # `to` can be nil for contract creation txs
      assert is_nil(receipt.to) or String.starts_with?(receipt.to, "0x")
      assert is_integer(receipt.cumulative_gas_used)
      assert receipt.cumulative_gas_used > 0
      assert is_integer(receipt.gas_used)
      assert receipt.gas_used > 0
      assert is_integer(receipt.effective_gas_price)
      assert receipt.effective_gas_price > 0
      # status: 1 = success, 0 = revert
      assert receipt.status in [0, 1]
      # contract_address is nil for non-creation txs
      assert is_nil(receipt.contract_address) or String.starts_with?(receipt.contract_address, "0x")
      assert is_list(receipt.logs)
      assert is_integer(receipt.type)
    end

    test "receipt logs match eth_get_logs structure" do
      {:ok, block} = RPC.get_block_by_number(@test_block, rpc_opts())
      tx_hash = hd(block.transactions)
      {:ok, receipt} = RPC.get_transaction_receipt(tx_hash, rpc_opts())

      # If there are logs, verify they have the same structure as eth_get_logs
      for log <- receipt.logs do
        assert is_binary(log.address)
        assert String.starts_with?(log.address, "0x")
        assert is_list(log.topics)
        assert is_binary(log.data)
        assert is_integer(log.block_number)
        assert is_binary(log.transaction_hash)
        assert is_integer(log.log_index)
        assert is_integer(log.transaction_index)
        assert is_boolean(log.removed)
      end
    end

    test "returns nil for non-existent transaction hash" do
      fake_hash = "0x" <> String.duplicate("00", 32)
      assert {:ok, nil} = RPC.get_transaction_receipt(fake_hash, rpc_opts())
    end
  end

  describe "get_transaction_receipt!/2" do
    test "returns receipt directly" do
      {:ok, block} = RPC.get_block_by_number(@test_block, rpc_opts())
      tx_hash = hd(block.transactions)

      receipt = RPC.get_transaction_receipt!(tx_hash, rpc_opts())
      assert is_map(receipt)
      assert is_integer(receipt.block_number)
    end

    test "returns nil for non-existent hash without raising" do
      fake_hash = "0x" <> String.duplicate("00", 32)
      assert nil == RPC.get_transaction_receipt!(fake_hash, rpc_opts())
    end
  end
end
