defmodule Onchain.RPC.BlockReadsTest do
  use ExUnit.Case, async: true

  alias Onchain.RPC

  @block_number 16
  @block_hash "0x" <> String.duplicate("cd", 32)
  @transaction_hash "0x" <> String.duplicate("ab", 32)
  @transaction_index 2

  test "get_block_receipts/2 normalizes the block and reuses receipt parsing" do
    assert {:ok, [receipt]} = RPC.get_block_receipts(@block_number, rpc_opts([raw_receipt()]))
    assert_request("eth_getBlockReceipts", ["0x10"])
    assert receipt.transaction_hash == @transaction_hash
    assert receipt.transaction_index == @transaction_index
    assert receipt.block_number == @block_number
    assert receipt.gas_used == 21_000

    assert {:ok, nil} = RPC.get_block_receipts(@block_hash, rpc_opts(nil))
    assert_request("eth_getBlockReceipts", [@block_hash])
  end

  test "block transaction count wrappers normalize inputs and nullable quantities" do
    assert {:ok, @transaction_index} =
             RPC.get_block_transaction_count_by_hash(@block_hash, rpc_opts("0x2"))

    assert_request("eth_getBlockTransactionCountByHash", [@block_hash])

    assert {:ok, @transaction_index} =
             RPC.get_block_transaction_count_by_number(@block_number, rpc_opts("0x2"))

    assert_request("eth_getBlockTransactionCountByNumber", ["0x10"])

    assert {:ok, nil} =
             RPC.get_block_transaction_count_by_number("latest", rpc_opts(nil))

    assert_request("eth_getBlockTransactionCountByNumber", ["latest"])
  end

  test "by-index wrappers normalize positions and reuse transaction parsing" do
    assert {:ok, transaction_by_hash} =
             RPC.get_transaction_by_block_hash_and_index(
               @block_hash,
               @transaction_index,
               rpc_opts(raw_transaction())
             )

    assert_request("eth_getTransactionByBlockHashAndIndex", [@block_hash, "0x2"])
    assert transaction_by_hash.hash == @transaction_hash
    assert transaction_by_hash.transaction_index == @transaction_index

    assert {:ok, transaction_by_number} =
             RPC.get_transaction_by_block_number_and_index(
               @block_number,
               "0x2",
               rpc_opts(raw_transaction())
             )

    assert_request("eth_getTransactionByBlockNumberAndIndex", ["0x10", "0x2"])
    assert transaction_by_number == transaction_by_hash

    assert {:ok, nil} =
             RPC.get_transaction_by_block_number_and_index(
               @block_number,
               @transaction_index,
               rpc_opts(nil)
             )
  end

  test "get_block_access_list/2 preserves the node's raw camelCase shape" do
    access_list = [
      %{
        "address" => "0x" <> String.duplicate("00", 19) <> "01",
        "balanceChanges" => [],
        "codeChanges" => [],
        "nonceChanges" => [],
        "storageChanges" => [],
        "storageReads" => []
      }
    ]

    assert {:ok, ^access_list} = RPC.get_block_access_list(@block_hash, rpc_opts(access_list))
    assert_request("eth_getBlockAccessList", [@block_hash])

    assert {:ok, nil} = RPC.get_block_access_list(@block_number, rpc_opts(nil))
    assert_request("eth_getBlockAccessList", ["0x10"])
  end

  test "block read validation rejects malformed block hashes and indexes" do
    assert {:error, {:invalid_block, -1}} = RPC.get_block_receipts(-1)

    assert {:error, {:invalid_block_hash, "0xshort"}} =
             RPC.get_block_transaction_count_by_hash("0xshort")

    assert {:error, {:invalid_block, :unknown}} =
             RPC.get_block_transaction_count_by_number(:unknown)

    assert {:error, {:invalid_transaction_index, -1}} =
             RPC.get_transaction_by_block_hash_and_index(@block_hash, -1)

    assert {:error, {:invalid_transaction_index, "0xZZ"}} =
             RPC.get_transaction_by_block_number_and_index(@block_number, "0xZZ")

    assert {:error, {:invalid_block, :unknown}} = RPC.get_block_access_list(:unknown)
  end

  test "typed block reads reject malformed successful RPC payloads" do
    assert {:error, {:rpc_error, %{message: count_message}}} =
             RPC.get_block_transaction_count_by_number(@block_number, rpc_opts("not-a-quantity"))

    assert count_message =~ "unexpected block transaction count response"

    assert {:error, {:rpc_error, %{message: receipts_message}}} =
             RPC.get_block_receipts(@block_number, rpc_opts([nil]))

    assert receipts_message =~ "unexpected block receipts response"

    assert {:error, {:rpc_error, %{message: transaction_message}}} =
             RPC.get_transaction_by_block_number_and_index(
               @block_number,
               @transaction_index,
               rpc_opts([])
             )

    assert transaction_message =~ "unexpected block transaction response"

    assert {:error, {:rpc_error, %{message: access_list_message}}} =
             RPC.get_block_access_list(@block_number, rpc_opts("not-a-list"))

    assert access_list_message =~ "unexpected block access list response"

    assert {:error, {:rpc_error, %{message: access_list_entry_message}}} =
             RPC.get_block_access_list(@block_number, rpc_opts([nil]))

    assert access_list_entry_message =~ "unexpected block access list response"
  end

  test "bang variants unwrap successful block reads" do
    assert [receipt] = RPC.get_block_receipts!(@block_number, rpc_opts([raw_receipt()]))
    assert receipt.transaction_hash == @transaction_hash

    assert @transaction_index ==
             RPC.get_block_transaction_count_by_hash!(@block_hash, rpc_opts("0x2"))

    assert @transaction_index ==
             RPC.get_block_transaction_count_by_number!(@block_number, rpc_opts("0x2"))

    assert %{hash: @transaction_hash} =
             RPC.get_transaction_by_block_hash_and_index!(
               @block_hash,
               @transaction_index,
               rpc_opts(raw_transaction())
             )

    assert %{hash: @transaction_hash} =
             RPC.get_transaction_by_block_number_and_index!(
               @block_number,
               @transaction_index,
               rpc_opts(raw_transaction())
             )

    assert [] == RPC.get_block_access_list!(@block_number, rpc_opts([]))
  end

  defp raw_receipt do
    %{
      "transactionHash" => @transaction_hash,
      "transactionIndex" => "0x2",
      "blockHash" => @block_hash,
      "blockNumber" => "0x10",
      "from" => "0x" <> String.duplicate("11", 20),
      "to" => nil,
      "cumulativeGasUsed" => "0x5208",
      "gasUsed" => "0x5208",
      "effectiveGasPrice" => "0x3b9aca00",
      "status" => "0x1",
      "contractAddress" => nil,
      "logs" => [],
      "type" => "0x2"
    }
  end

  defp raw_transaction do
    %{
      "hash" => @transaction_hash,
      "nonce" => "0x3",
      "blockHash" => @block_hash,
      "blockNumber" => "0x10",
      "transactionIndex" => "0x2",
      "from" => "0x" <> String.duplicate("11", 20),
      "to" => "0x" <> String.duplicate("22", 20),
      "value" => "0x4",
      "gas" => "0x5208",
      "gasPrice" => "0x3b9aca00",
      "input" => "0x",
      "type" => "0x0",
      "chainId" => "0x1"
    }
  end

  defp rpc_opts(result) do
    test_pid = self()

    plug = fn conn ->
      request = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
      send(test_pid, {:rpc_request, request})
      Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => request["id"], "result" => result})
    end

    [rpc_url: "http://stub.invalid", req_options: [plug: plug]]
  end

  defp assert_request(method, params) do
    assert_receive {:rpc_request, %{"method" => ^method, "params" => ^params}}
  end
end
