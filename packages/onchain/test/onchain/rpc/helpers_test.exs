defmodule Onchain.RPC.HelpersTest do
  use ExUnit.Case, async: true

  alias Onchain.Hex
  alias Onchain.RPC.Helpers

  describe "normalize_block_number/1" do
    test "accepts non-negative integers and 0x hex" do
      hex_block = Hex.from_integer(19_000_000)
      assert {:ok, ^hex_block} = Helpers.normalize_block_number(19_000_000)
      assert {:ok, ^hex_block} = Helpers.normalize_block_number(hex_block)
    end

    test "rejects block tags" do
      for tag <- Helpers.block_tags() do
        assert {:error, {:invalid_block, ^tag}} = Helpers.normalize_block_number(tag)
      end
    end

    test "rejects invalid quantities" do
      assert {:error, {:invalid_block, -1}} = Helpers.normalize_block_number(-1)
      assert {:error, {:invalid_block, "0xZZ"}} = Helpers.normalize_block_number("0xZZ")
    end
  end

  describe "maybe_put_revert_data_hex/1" do
    test "adds :data as 0x hex when :revert binary present and :data absent" do
      revert = <<8, 195, 121, 160, 0x01>>
      map = %{code: 3, message: "execution reverted", revert: revert}

      assert %{code: 3, message: "execution reverted", revert: ^revert, data: "0x08c379a001"} =
               Helpers.maybe_put_revert_data_hex(map)
    end

    test "does not overwrite existing :data" do
      map = %{code: 3, message: "x", revert: <<1>>, data: "0xabcd"}

      assert %{data: "0xabcd"} = Helpers.maybe_put_revert_data_hex(map)
    end

    test "leaves map unchanged when :revert absent" do
      map = %{code: -32_603, message: "internal error"}

      assert ^map = Helpers.maybe_put_revert_data_hex(map)
    end

    test "empty revert binary encodes to 0x" do
      map = %{code: 3, message: "execution reverted", revert: <<>>}

      assert %{data: "0x"} = Helpers.maybe_put_revert_data_hex(map)
    end
  end

  describe "parse_block_response/1" do
    test "decodes quantities and keeps tx hashes as binaries" do
      raw = %{
        "number" => "0x1312d00",
        "timestamp" => "0x665ba27f",
        "hash" => "0xd24fd97aa00ee83dad68403760f798f91f76f38007ec11516bf38993af9fee45",
        "miner" => "0x95222290dd7278aa3ddd389cc1e1d165cc4bafe5",
        "transactions" => [
          "0xaaa43bbbfc910f02df998749665040163cd840fcfe358bfaa226662e03bf091b",
          "0xbbb43bbbfc910f02df998749665040163cd840fcfe358bfaa226662e03bf091b"
        ],
        "gasLimit" => "0x1c9c380",
        "gasUsed" => "0x123456",
        "baseFeePerGas" => "0x3b9aca00"
      }

      assert {:ok,
              %{
                number: 20_000_000,
                timestamp: 1_717_281_407,
                gas_limit: 30_000_000,
                gas_used: 1_193_046,
                base_fee_per_gas: 1_000_000_000,
                transactions: [_, _],
                miner: miner
              }} = Helpers.parse_block_response(raw)

      assert String.starts_with?(miner, "0x")
      assert byte_size(miner) == 42
    end

    test "decodes full transaction objects when present in transactions list" do
      raw = %{
        "number" => "0x1",
        "timestamp" => "0x2",
        "hash" => "0xcc",
        "transactions" => [
          %{
            "hash" => "0x" <> String.duplicate("ab", 32),
            "nonce" => "0x0",
            "blockHash" => "0xdd",
            "blockNumber" => "0x1",
            "transactionIndex" => "0x0",
            "from" => "0x1111111111111111111111111111111111111111",
            "to" => nil,
            "value" => "0x0",
            "gas" => "0x5208",
            "gasPrice" => "0x3b9aca00",
            "input" => "0x",
            "type" => "0x0",
            "chainId" => "0x1"
          }
        ]
      }

      assert {:ok, %{transactions: [tx]}} = Helpers.parse_block_response(raw)
      assert tx.hash =~ ~r/^0x/
      assert tx.nonce == 0
      assert tx.type == 0
    end

    test "returns error for invalid block number hex instead of masking as pending" do
      raw = %{"number" => "0xZZ", "transactions" => []}

      assert {:error, {:invalid_block_response, :number, "0xZZ"}} =
               Helpers.parse_block_response(raw)
    end

    test "accepts nil number for pending blocks" do
      raw = %{"number" => nil, "transactions" => []}

      assert {:ok, %{number: nil}} = Helpers.parse_block_response(raw)
    end

    test "returns error for non-map/non-binary transaction list member" do
      raw = %{"number" => "0x1", "transactions" => [123]}

      assert {:error, {:invalid_block_response, :transactions, 123}} =
               Helpers.parse_block_response(raw)
    end

    test "returns error for non-map withdrawal list member" do
      raw = %{
        "number" => "0x1",
        "transactions" => [],
        "withdrawals" => ["not-a-map"]
      }

      assert {:error, {:invalid_block_response, :withdrawals, "not-a-map"}} =
               Helpers.parse_block_response(raw)
    end
  end
end
