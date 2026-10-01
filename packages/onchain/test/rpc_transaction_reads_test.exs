defmodule Onchain.RPCTransactionReadsTest do
  use ExUnit.Case, async: true

  alias Onchain.Hex
  alias Onchain.Receipt
  alias Onchain.RPC
  alias Onchain.Transaction.Info
  alias Onchain.Transaction.V1

  @block_number 16
  @block_hash "0x" <> String.duplicate("cd", 32)
  @transaction_hash "0x" <> String.duplicate("ab", 32)
  @from "0x" <> String.duplicate("11", 20)
  @to "0x" <> String.duplicate("22", 20)
  @transaction_index 2

  test "eth_get_transaction_by_hash/2 validates the hash, decodes the envelope, and reports null as not found" do
    assert {:error, {:invalid_tx_hash, "abcd1234"}} = RPC.eth_get_transaction_by_hash("abcd1234")
    assert {:error, {:invalid_tx_hash, "0xZZZZ"}} = RPC.eth_get_transaction_by_hash("0xZZZZ")
    assert {:error, {:invalid_tx_hash, 12_345}} = RPC.eth_get_transaction_by_hash(12_345)
    short_hash = "0x1234"
    assert {:error, {:invalid_tx_hash, ^short_hash}} = RPC.eth_get_transaction_by_hash(short_hash)
    long_hash = "0x" <> String.duplicate("ab", 33)
    assert {:error, {:invalid_tx_hash, ^long_hash}} = RPC.eth_get_transaction_by_hash(long_hash)

    assert {:ok, %Info{} = info} = RPC.eth_get_transaction_by_hash(@transaction_hash, rpc_opts(raw_transaction()))
    assert_request("eth_getTransactionByHash", [@transaction_hash])
    assert info.hash == Hex.decode_word!(@transaction_hash)
    assert info.from == Hex.decode_address!(@from)
    assert info.block_number == @block_number
    assert info.transaction_index == @transaction_index
    assert %V1{nonce: 3, gas_limit: 21_000, v: 0x1C} = info.transaction

    assert {:error, :not_found} = RPC.eth_get_transaction_by_hash(@transaction_hash, rpc_opts(nil))
  end

  test "by-index reads normalize the position and share the envelope decoder" do
    assert {:ok, by_hash} =
             RPC.eth_get_transaction_by_block_hash_and_index(
               @block_hash,
               @transaction_index,
               rpc_opts(raw_transaction())
             )

    assert_request("eth_getTransactionByBlockHashAndIndex", [@block_hash, "0x2"])

    assert {:ok, by_number} =
             RPC.eth_get_transaction_by_block_number_and_index(
               @block_number,
               "0x2",
               rpc_opts(raw_transaction())
             )

    assert_request("eth_getTransactionByBlockNumberAndIndex", ["0x10", "0x2"])
    assert by_number == by_hash

    assert {:ok, _} =
             RPC.eth_get_transaction_by_block_number_and_index(0, 0, rpc_opts(raw_transaction()))

    assert_request("eth_getTransactionByBlockNumberAndIndex", ["0x0", "0x0"])

    assert {:error, :not_found} =
             RPC.eth_get_transaction_by_block_number_and_index(
               @block_number,
               @transaction_index,
               rpc_opts(nil)
             )
  end

  test "by-index reads reject a malformed block hash or index before calling the node" do
    assert {:error, {:invalid_block_hash, "0x1234"}} =
             RPC.eth_get_transaction_by_block_hash_and_index("0x1234", 0)

    assert {:error, {:invalid_transaction_index, -1}} =
             RPC.eth_get_transaction_by_block_hash_and_index(@block_hash, -1)

    assert {:error, {:invalid_transaction_index, "0xZZ"}} =
             RPC.eth_get_transaction_by_block_number_and_index(@block_number, "0xZZ")

    assert {:error, {:invalid_block, -1}} = RPC.eth_get_block_receipts(-1)
  end

  test "a malformed transaction object returns an error and does not raise" do
    broken = Map.delete(raw_transaction(), "nonce")

    assert {:error, {:missing_field, "nonce"}} =
             RPC.eth_get_transaction_by_hash(@transaction_hash, rpc_opts(broken))

    assert {:error, {:unexpected_transaction, []}} =
             RPC.eth_get_transaction_by_block_number_and_index(@block_number, 0, rpc_opts([]))
  end

  test "eth_get_block_receipts/2 reuses receipt decoding" do
    assert {:ok, [receipt]} = RPC.eth_get_block_receipts(@block_number, rpc_opts([raw_receipt()]))
    assert_request("eth_getBlockReceipts", ["0x10"])
    assert %Receipt{} = receipt
    assert receipt == Receipt.deserialize(raw_receipt())
    assert receipt.transaction_hash == Hex.decode_word!(@transaction_hash)
    assert receipt.transaction_index == @transaction_index
    assert receipt.block_number == @block_number
    assert receipt.gas_used == 21_000

    assert {:ok, nil} = RPC.eth_get_block_receipts(@block_hash, rpc_opts(nil))
    assert_request("eth_getBlockReceipts", [@block_hash])

    assert {:error, message} = RPC.eth_get_block_receipts(@block_number, rpc_opts("not-a-list"))
    assert message =~ "failed to decode `eth_getBlockReceipts` response"
  end

  defp raw_transaction do
    %{
      "hash" => @transaction_hash,
      "nonce" => "0x3",
      "blockHash" => @block_hash,
      "blockNumber" => "0x10",
      "blockTimestamp" => "0x20",
      "transactionIndex" => "0x2",
      "from" => @from,
      "to" => @to,
      "value" => "0x4",
      "gas" => "0x5208",
      "gasPrice" => "0x3b9aca00",
      "input" => "0x",
      "type" => "0x0",
      "v" => "0x1c",
      "r" => "0x1",
      "s" => "0x2"
    }
  end

  defp raw_receipt do
    %{
      "transactionHash" => @transaction_hash,
      "transactionIndex" => "0x2",
      "blockHash" => @block_hash,
      "blockNumber" => "0x10",
      "from" => @from,
      "to" => nil,
      "cumulativeGasUsed" => "0x5208",
      "gasUsed" => "0x5208",
      "effectiveGasPrice" => "0x3b9aca00",
      "status" => "0x1",
      "contractAddress" => nil,
      "logs" => [],
      "logsBloom" => "0x" <> String.duplicate("00", 256),
      "type" => "0x2"
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
