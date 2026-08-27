defmodule Onchain.RPC.BlockReadsIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.RPC

  @moduletag :integration

  @known_block 20_000_000
  @known_block_hash "0xd24fd73f794058a3807db926d8898c6481e902b7edb91ce0d479d6760f276183"
  @known_transaction_count 134
  @known_transaction_index 0
  @out_of_range_transaction_index @known_transaction_count
  @known_transaction_hash "0xbb4b3fc2b746877dce70862850602f1d19bd890ab4db47e6b7ee1da1fe578a0d"
  @known_access_list_entries 353
  @known_access_change_address "0x0000000000000068f116a894984e2db1123eb395"

  defp rpc_opts, do: [rpc_url: Onchain.RPCCase.rpc_url!()]

  test "bulk block receipts are byte-identical to the single-receipt result" do
    assert {:ok, receipts} = RPC.get_block_receipts(@known_block, rpc_opts())
    assert length(receipts) == @known_transaction_count

    bulk_receipt = Enum.find(receipts, &(&1.transaction_hash == @known_transaction_hash))
    assert is_map(bulk_receipt)

    assert {:ok, single_receipt} =
             RPC.get_transaction_receipt(@known_transaction_hash, rpc_opts())

    assert bulk_receipt === single_receipt
    assert :erlang.term_to_binary(bulk_receipt) == :erlang.term_to_binary(single_receipt)
  end

  test "block transaction counts match the known mainnet block" do
    assert {:ok, @known_transaction_count} =
             RPC.get_block_transaction_count_by_hash(@known_block_hash, rpc_opts())

    assert {:ok, @known_transaction_count} =
             RPC.get_block_transaction_count_by_number(@known_block, rpc_opts())
  end

  test "by-index reads return the known transaction from both block selectors" do
    assert {:ok, %{hash: @known_transaction_hash, transaction_index: @known_transaction_index}} =
             RPC.get_transaction_by_block_hash_and_index(
               @known_block_hash,
               @known_transaction_index,
               rpc_opts()
             )

    assert {:ok, %{hash: @known_transaction_hash, transaction_index: @known_transaction_index}} =
             RPC.get_transaction_by_block_number_and_index(
               @known_block,
               @known_transaction_index,
               rpc_opts()
             )
  end

  test "an out-of-range transaction index returns nil" do
    assert {:ok, nil} =
             RPC.get_transaction_by_block_number_and_index(
               @known_block,
               @out_of_range_transaction_index,
               rpc_opts()
             )
  end

  test "block access list matches the configured node's observed EIP-7928 shape" do
    # Observed on 2026-08-25 from the configured Reth archive node. Its live
    # camelCase response uses blockAccessIndex/newValue and slot/changes keys.
    case RPC.get_block_access_list(@known_block, rpc_opts()) do
      {:ok, access_list} when is_list(access_list) ->
        assert length(access_list) == @known_access_list_entries

        assert hd(access_list) == %{
                 "address" => "0x0000000000000000000000000000000000000001",
                 "balanceChanges" => [],
                 "codeChanges" => [],
                 "nonceChanges" => [],
                 "storageChanges" => [],
                 "storageReads" => []
               }

        assert Enum.find(access_list, &(&1["address"] == @known_access_change_address)) == %{
                 "address" => @known_access_change_address,
                 "balanceChanges" => [],
                 "codeChanges" => [],
                 "nonceChanges" => [],
                 "storageChanges" => [
                   %{
                     "changes" => [
                       %{
                         "blockAccessIndex" => "0x10",
                         "newValue" => "0x10000000000000000000000000000010001"
                       }
                     ],
                     "slot" => "0x2e966513b1fedabc86e31ff577f5babda0a0a7cfd8791ceb800893391d710012"
                   }
                 ],
                 "storageReads" => [
                   "0x72780b402c8941b9d056bb612ff4bbdab2473fcb7bad41f038ef922a09bbe9f0"
                 ]
               }

      {:ok, result} ->
        flunk("eth_getBlockAccessList returned an unexpected live result: #{inspect(result)}")

      {:error, reason} ->
        flunk("eth_getBlockAccessList failed on the configured live node: #{inspect(reason)}")
    end
  end
end
