defmodule Onchain.RPC.ReceiptIntegrationTest do
  use ExUnit.Case, async: false

  alias Cartouche.RPC

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
      assert byte_size(receipt.transaction_hash) == 32
      assert is_integer(receipt.transaction_index)
      assert is_binary(receipt.block_hash)
      assert byte_size(receipt.block_hash) == 32
      assert is_integer(receipt.block_number)
      assert receipt.block_number > 0
      assert is_binary(receipt.from)
      assert byte_size(receipt.from) == 20
      # `to` can be nil for contract creation txs
      assert is_nil(receipt.to) or byte_size(receipt.to) == 20
      assert is_integer(receipt.cumulative_gas_used)
      assert receipt.cumulative_gas_used > 0
      assert is_integer(receipt.gas_used)
      assert receipt.gas_used > 0
      assert is_integer(receipt.effective_gas_price)
      assert receipt.effective_gas_price > 0
      # status: 1 = success, 0 = revert
      assert receipt.status in [0, 1]
      # contract_address is nil for non-creation txs
      assert is_nil(receipt.contract_address) or byte_size(receipt.contract_address) == 20
      assert is_list(receipt.logs)
      assert is_integer(receipt.type)
    end

    test "decodes receipt logs as shared structs" do
      {:ok, block} = RPC.get_block_by_number(@test_block, rpc_opts())
      tx_hash = hd(block.transactions)
      {:ok, receipt} = RPC.get_transaction_receipt(tx_hash, rpc_opts())

      for log <- receipt.logs do
        assert %Cartouche.Filter.Log{} = log
        assert is_binary(log.address)
        assert byte_size(log.address) == 20
        assert is_list(log.topics)
        assert is_binary(log.data)
        assert is_integer(log.block_number)
        assert is_binary(log.transaction_hash)
        assert is_integer(log.log_index)
        assert is_integer(log.transaction_index)
        assert is_boolean(log.removed)
      end
    end

    test "pins the decoded logs of a known USDC transfer receipt" do
      tx_hash = "0x6742cd57e6aefce4b96887bb3090371ac49414c6b45a21e43d9e41e0ea9ed5ab"
      assert {:ok, receipt} = RPC.get_transaction_receipt(tx_hash, rpc_opts())

      log = Enum.find(receipt.logs, &(&1.log_index == 8))

      assert log.address == Cartouche.Hex.from_hex!("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")

      assert hd(log.topics) ==
               Cartouche.Hex.from_hex!("0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef")

      assert log.block_number == 18_000_000
      assert log.transaction_hash == Cartouche.Hex.from_hex!(tx_hash)
      assert log.removed == false
      assert is_binary(log.data)
      assert is_integer(log.transaction_index)
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
