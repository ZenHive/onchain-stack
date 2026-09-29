defmodule Cartouche.ReceiptTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Receipt
  alias Cartouche.Receipt.Log

  doctest Receipt
  doctest Log

  @base_receipt %{
    "blockHash" => "0xa957d47df264a31badc3ae823e10ac1d444b098d9b73d204c40426e57f47e8c3",
    "blockNumber" => "0xeff35f",
    "contractAddress" => nil,
    "cumulativeGasUsed" => "0xa12515",
    "effectiveGasPrice" => "0x5a9c688d4",
    "from" => "0x6221a9c005f6e47eb398fd867784cacfdcfff4e7",
    "gasUsed" => "0xb4c8",
    "logs" => [],
    "logsBloom" => "0x" <> String.duplicate("00", 256),
    "status" => "0x1",
    "to" => "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
    "transactionHash" => "0x85d995eba9763907fdf35cd2034144dd9d53ce32cbec21349d4b12823c6860c5",
    "transactionIndex" => "0x66",
    "type" => "0x2"
  }

  describe "Receipt.deserialize/1" do
    test "contract creation: to is nil, contractAddress populated" do
      params = %{
        @base_receipt
        | "to" => nil,
          "contractAddress" => "0x16c5785ac562ff41e2dcfdf829c5a142f1fccd7d"
      }

      receipt = Receipt.deserialize(params)

      assert receipt.to == nil
      assert receipt.contract_address == ~h[0x16c5785ac562ff41e2dcfdf829c5a142f1fccd7d]
    end

    test "non-creation receipt: contract_address is nil" do
      receipt = Receipt.deserialize(@base_receipt)

      assert receipt.contract_address == nil
      assert receipt.to == ~h[0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2]
    end
  end

  describe "deserialize/1 — EIP-4844 blob fields (Task 67)" do
    test "populates blob fields on a type-3 receipt" do
      receipt =
        @base_receipt
        |> Map.merge(%{
          "blobGasUsed" => "0x20000",
          "blobGasPrice" => "0x1",
          "type" => "0x3"
        })
        |> Receipt.deserialize()

      assert receipt.blob_gas_used == 0x20000
      assert receipt.blob_gas_price == 0x1
    end

    test "keeps blob fields nil when JSON keys are absent" do
      receipt = Receipt.deserialize(@base_receipt)

      assert receipt.blob_gas_used == nil
      assert receipt.blob_gas_price == nil
    end

    test "decodes zero blob gas used as 0, not nil" do
      receipt =
        @base_receipt
        |> Map.merge(%{
          "blobGasUsed" => "0x0",
          "blobGasPrice" => "0x1",
          "type" => "0x3"
        })
        |> Receipt.deserialize()

      assert receipt.blob_gas_used == 0
      assert receipt.blob_gas_price == 1
    end
  end

  describe "Log.deserialize/1" do
    @log_skeleton %{
      "logIndex" => "0x0",
      "blockNumber" => "0x1",
      "blockHash" => "0xa957d47df264a31badc3ae823e10ac1d444b098d9b73d204c40426e57f47e8c3",
      "transactionHash" => "0xaadf829c5a142f1fccd7d8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcf",
      "transactionIndex" => "0x0",
      "address" => "0x16c5785ac562ff41e2dcfdf829c5a142f1fccd7d",
      "data" => "0x",
      "topics" => []
    }

    test "log with empty data and no topics" do
      log = Log.deserialize(@log_skeleton)

      assert log.data == <<>>
      assert log.topics == []
    end

    test "log with 4 topics (max indexed args)" do
      topics = [
        "0x3ffe5de331422c5ec98e2d9ced07156f640bb51e235ef956e50263d4b28d3ae4",
        "0x0000000000000000000000002326aba712500ae3114b664aeb51dba2c2fb416d",
        "0x0000000000000000000000002326aba712500ae3114b664aeb51dba2c2fb416d",
        "0x0000000000000000000000000000000000000000000000000000000000000055"
      ]

      log = Log.deserialize(%{@log_skeleton | "topics" => topics})

      assert [_, _, _, _] = log.topics
      assert Enum.all?(log.topics, &(byte_size(&1) == 32))
    end

    test "log with 2 topics" do
      topics = [
        "0x3ffe5de331422c5ec98e2d9ced07156f640bb51e235ef956e50263d4b28d3ae4",
        "0x0000000000000000000000002326aba712500ae3114b664aeb51dba2c2fb416d"
      ]

      log = Log.deserialize(%{@log_skeleton | "topics" => topics})

      assert [_, _] = log.topics
    end
  end
end
