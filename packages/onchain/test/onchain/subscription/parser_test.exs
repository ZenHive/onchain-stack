defmodule Onchain.Subscription.ParserTest do
  use ExUnit.Case, async: true

  alias Onchain.Subscription.Parser

  describe "parse_event(:new_heads, raw_map)" do
    @raw_head %{
      "number" => "0x12a0b5f",
      "hash" => "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
      "parentHash" => "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
      "timestamp" => "0x6600a1b2",
      "miner" => "0xd8da6bf26964af9d7eed9e03e53415d37aa96045",
      "gasLimit" => "0x1c9c380",
      "gasUsed" => "0xe4e1c0",
      "baseFeePerGas" => "0x3b9aca00",
      "logsBloom" => "0x00000000",
      "transactionsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
      "stateRoot" => "0xd7f8974fb5ac78d9ac099b9ad5018bedc2ce0a72dad1827a1709da30580f0544",
      "receiptsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b422",
      "sha3Uncles" => "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
      "difficulty" => "0x0",
      "extraData" => "0x",
      "mixHash" => "0x0000000000000000000000000000000000000000000000000000000000000000",
      "nonce" => "0x0000000000000000"
    }

    test "converts hex fields to native integers" do
      {:ok, head} = Parser.parse_event(:new_heads, @raw_head)

      assert head.number == 0x12A0B5F
      assert head.timestamp == 0x6600A1B2
      assert head.gas_limit == 0x1C9C380
      assert head.gas_used == 0xE4E1C0
      assert head.base_fee_per_gas == 0x3B9ACA00
    end

    test "checksums the miner address" do
      {:ok, head} = Parser.parse_event(:new_heads, @raw_head)

      assert head.miner == "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
    end

    test "preserves hash fields as hex strings" do
      {:ok, head} = Parser.parse_event(:new_heads, @raw_head)

      assert head.hash == @raw_head["hash"]
      assert head.parent_hash == @raw_head["parentHash"]
      assert head.transactions_root == @raw_head["transactionsRoot"]
      assert head.state_root == @raw_head["stateRoot"]
      assert head.receipts_root == @raw_head["receiptsRoot"]
      assert head.logs_bloom == @raw_head["logsBloom"]
    end

    test "handles nil baseFeePerGas (pre-EIP-1559 blocks)" do
      raw = Map.delete(@raw_head, "baseFeePerGas")
      {:ok, head} = Parser.parse_event(:new_heads, raw)

      assert head.base_fee_per_gas == nil
    end

    test "returns error for non-map input" do
      assert {:error, {:invalid_head, _}} = Parser.parse_event(:new_heads, "not a map")
    end
  end

  describe "parse_event(:pending_transactions, tx_hash)" do
    test "returns valid transaction hash" do
      hash = "0x" <> String.duplicate("ab", 32)
      {:ok, result} = Parser.parse_event(:pending_transactions, hash)

      assert result == hash
    end

    test "returns error for invalid hash (wrong length)" do
      assert {:error, {:invalid_tx_hash, _}} = Parser.parse_event(:pending_transactions, "0xabc")
    end

    test "returns error for non-hex input" do
      assert {:error, {:invalid_tx_hash, _}} = Parser.parse_event(:pending_transactions, "not_hex")
    end
  end

  describe "parse_event(:logs, raw_map)" do
    @raw_log %{
      "address" => "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
      "topics" => [
        "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
        "0x000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045",
        "0x0000000000000000000000001234567890abcdef1234567890abcdef12345678"
      ],
      "data" => "0x00000000000000000000000000000000000000000000000000000000000f4240",
      "blockNumber" => "0x12a0b5f",
      "transactionHash" => "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
      "logIndex" => "0x0",
      "transactionIndex" => "0x5",
      "removed" => false
    }

    test "converts hex fields and checksums address" do
      {:ok, log} = Parser.parse_event(:logs, @raw_log)

      assert log.address == "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
      assert log.block_number == 0x12A0B5F
      assert log.log_index == 0
      assert log.transaction_index == 5
      assert log.removed == false
    end

    test "preserves topics and data as-is" do
      {:ok, log} = Parser.parse_event(:logs, @raw_log)

      assert length(log.topics) == 3
      assert log.data == @raw_log["data"]
      assert log.transaction_hash == @raw_log["transactionHash"]
    end

    test "returns error for non-map input" do
      assert {:error, {:invalid_log, _}} = Parser.parse_event(:logs, "not a map")
    end
  end
end
