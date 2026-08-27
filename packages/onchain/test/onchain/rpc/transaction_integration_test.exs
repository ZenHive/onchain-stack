defmodule Onchain.RPC.TransactionIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.RPC

  @moduletag :integration

  # Known mainnet block guaranteed to have transactions
  @test_block 20_000_000

  defp rpc_opts, do: [rpc_url: Onchain.RPCCase.rpc_url!()]

  describe "get_transaction_by_hash/2" do
    test "fetches transaction from a known block's first transaction" do
      {:ok, block} = RPC.get_block_by_number(@test_block, rpc_opts())
      tx_hashes = block.transactions

      assert tx_hashes != [],
             "Expected block #{@test_block} to have transactions"

      tx_hash = hd(tx_hashes)
      assert {:ok, tx} = RPC.get_transaction_by_hash(tx_hash, rpc_opts())
      assert tx

      # Verify parsed fields
      assert is_binary(tx.hash)
      assert String.starts_with?(tx.hash, "0x")
      assert is_integer(tx.nonce)
      assert tx.nonce >= 0
      assert is_binary(tx.block_hash)
      assert String.starts_with?(tx.block_hash, "0x")
      assert is_integer(tx.block_number)
      assert tx.block_number == @test_block
      assert is_integer(tx.transaction_index)
      assert tx.transaction_index >= 0
      assert is_binary(tx.from)
      assert String.starts_with?(tx.from, "0x")
      # `to` can be nil for contract creation txs
      assert is_nil(tx.to) or String.starts_with?(tx.to, "0x")
      assert is_integer(tx.value)
      assert tx.value >= 0
      assert is_integer(tx.gas)
      assert tx.gas > 0
      assert is_binary(tx.input)
      assert String.starts_with?(tx.input, "0x")
      assert is_integer(tx.type)
    end

    test "gas price fields vary by transaction type" do
      {:ok, block} = RPC.get_block_by_number(@test_block, rpc_opts())
      tx_hash = hd(block.transactions)
      {:ok, tx} = RPC.get_transaction_by_hash(tx_hash, rpc_opts())

      # At least one gas price mechanism must be present
      has_legacy = is_integer(tx.gas_price)
      has_eip1559 = is_integer(tx.max_fee_per_gas) and is_integer(tx.max_priority_fee_per_gas)
      assert has_legacy or has_eip1559, "Transaction must have gas_price or EIP-1559 fee fields"
    end

    test "returns nil for non-existent transaction hash" do
      fake_hash = "0x" <> String.duplicate("00", 32)
      assert {:ok, nil} = RPC.get_transaction_by_hash(fake_hash, rpc_opts())
    end
  end

  describe "get_transaction_by_hash!/2" do
    test "returns transaction directly" do
      {:ok, block} = RPC.get_block_by_number(@test_block, rpc_opts())
      tx_hash = hd(block.transactions)

      tx = RPC.get_transaction_by_hash!(tx_hash, rpc_opts())
      assert is_map(tx)
      assert is_integer(tx.block_number)
    end

    test "returns nil for non-existent hash without raising" do
      fake_hash = "0x" <> String.duplicate("00", 32)
      assert nil == RPC.get_transaction_by_hash!(fake_hash, rpc_opts())
    end
  end
end
