defmodule Onchain.RPC.TransactionIntegrationTest do
  use ExUnit.Case, async: false

  alias Cartouche.RPC
  alias Cartouche.Transaction.Info
  alias Cartouche.Transaction.V2
  alias Onchain.RPC, as: OnchainRPC

  @moduletag :integration

  # Known mainnet block guaranteed to have transactions. Index 0 is the type-2
  # transaction pinned by the portability live test.
  @test_block 20_000_000
  @known_hash "0xbb4b3fc2b746877dce70862850602f1d19bd890ab4db47e6b7ee1da1fe578a0d"

  defp rpc_opts, do: [rpc_url: Onchain.RPCCase.rpc_url!()]

  describe "eth_get_transaction_by_hash/2" do
    test "fetches the first transaction of a known block as an envelope" do
      {:ok, block} = OnchainRPC.get_block_by_number(@test_block, rpc_opts())
      tx_hashes = block.transactions

      assert tx_hashes != [],
             "Expected block #{@test_block} to have transactions"

      assert hd(tx_hashes) == @known_hash
      assert {:ok, %Info{} = info} = RPC.eth_get_transaction_by_hash(@known_hash, rpc_opts())
      assert info.block_number == @test_block
      assert info.transaction_index == 0
      assert info.from == Cartouche.Hex.decode_address!("0xae2fc483527b8ef99eb5d9b44875f005ba1fae13")

      assert %V2{chain_id: 1, nonce: 0x2A109E, max_priority_fee_per_gas: 0} = info.transaction
    end

    test "returns not_found for a hash that does not exist" do
      fake_hash = "0x" <> String.duplicate("00", 32)
      assert {:error, :not_found} = RPC.eth_get_transaction_by_hash(fake_hash, rpc_opts())
    end
  end
end
