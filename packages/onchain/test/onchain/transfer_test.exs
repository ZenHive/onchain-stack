defmodule Onchain.TransferTest do
  use ExUnit.Case, async: true

  alias Onchain.Transfer

  # --- Fixture helpers ---

  # Precomputed topic hashes (matching the module's compile-time constants)
  @transfer_topic Onchain.Hex.encode(Cartouche.Hash.keccak("Transfer(address,address,uint256)"))
  @transfer_single_topic Onchain.Hex.encode(
                           Cartouche.Hash.keccak("TransferSingle(address,address,address,uint256,uint256)")
                         )
  @transfer_batch_topic Onchain.Hex.encode(
                          Cartouche.Hash.keccak("TransferBatch(address,address,address,uint256[],uint256[])")
                        )

  # Test addresses (padded to 32 bytes for topics)
  @usdc_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @from_addr_padded "0x000000000000000000000000dAC17F958D2ee523a2206206994597C13D831ec7"
  @to_addr_padded "0x000000000000000000000000A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @operator_padded "0x0000000000000000000000001111111111111111111111111111111111111111"

  @doc false
  # Builds a raw log map matching what RPC.eth_get_logs returns (atom-keyed).
  defp build_log(opts) do
    %{
      address: Keyword.get(opts, :address, @usdc_address),
      topics: Keyword.fetch!(opts, :topics),
      data: Keyword.get(opts, :data, "0x"),
      block_number: Keyword.get(opts, :block_number, 18_000_000),
      transaction_hash:
        Keyword.get(
          opts,
          :transaction_hash,
          "0xabc123def456abc123def456abc123def456abc123def456abc123def456abc1"
        ),
      log_index: Keyword.get(opts, :log_index, 42)
    }
  end

  @doc false
  # Encodes a uint256 value as 32-byte ABI-encoded hex data.
  defp encode_uint256(value) do
    "0x" <> (value |> :binary.encode_unsigned() |> pad_left(32) |> Base.encode16(case: :lower))
  end

  @doc false
  # Encodes two uint256 values as ABI-encoded data (id, value for ERC-1155 TransferSingle).
  defp encode_uint256_pair(id, value) do
    id_bin = id |> :binary.encode_unsigned() |> pad_left(32)
    value_bin = value |> :binary.encode_unsigned() |> pad_left(32)
    "0x" <> Base.encode16(id_bin <> value_bin, case: :lower)
  end

  @doc false
  # Encodes two uint256[] arrays as ABI-encoded data for ERC-1155 TransferBatch.
  # Uses standard ABI encoding: offset(ids), offset(values), len(ids), ids..., len(values), values...
  defp encode_uint256_arrays(ids, values) do
    encoded = ABI.encode("(uint256[],uint256[])", [{ids, values}])
    "0x" <> Base.encode16(encoded, case: :lower)
  end

  @doc false
  # Encodes a tokenId as a 32-byte padded topic hex string.
  defp encode_topic_uint256(value) do
    "0x" <> (value |> :binary.encode_unsigned() |> pad_left(32) |> Base.encode16(case: :lower))
  end

  defp pad_left(bin, size) when byte_size(bin) >= size, do: bin
  defp pad_left(bin, size), do: :binary.copy(<<0>>, size - byte_size(bin)) <> bin

  # --- Tests ---

  describe "transfer_topics/0" do
    test "returns 3 valid hex topic hashes" do
      topics = Transfer.transfer_topics()
      assert length(topics) == 3
      assert Enum.all?(topics, &String.starts_with?(&1, "0x"))
      assert Enum.all?(topics, &(String.length(&1) == 66))
    end

    test "contains the known Transfer topic hash" do
      [transfer | _] = Transfer.transfer_topics()
      # Well-known ERC-20 Transfer topic
      assert transfer == "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
    end
  end

  describe "parse_log/1 — ERC-20" do
    test "parses 3-topic Transfer log into ERC-20 struct" do
      log =
        build_log(
          topics: [@transfer_topic, @from_addr_padded, @to_addr_padded],
          data: encode_uint256(1_000_000)
        )

      assert {:ok, %Transfer{} = transfer} = Transfer.parse_log(log)
      assert transfer.token_standard == :erc20
      assert transfer.amount == 1_000_000
      assert transfer.token_id == nil
      assert transfer.operator == nil
      assert transfer.block_number == 18_000_000
      assert transfer.log_index == 42
    end

    test "checksums from/to/token addresses" do
      log =
        build_log(
          topics: [@transfer_topic, @from_addr_padded, @to_addr_padded],
          data: encode_uint256(100)
        )

      assert {:ok, transfer} = Transfer.parse_log(log)
      # Addresses should be EIP-55 checksummed
      assert transfer.from == Onchain.Address.checksum!("0xdAC17F958D2ee523a2206206994597C13D831ec7")
      assert transfer.to == Onchain.Address.checksum!("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")
      assert transfer.token == Onchain.Address.checksum!(@usdc_address)
    end

    test "handles zero-value transfer" do
      log =
        build_log(
          topics: [@transfer_topic, @from_addr_padded, @to_addr_padded],
          data: encode_uint256(0)
        )

      assert {:ok, transfer} = Transfer.parse_log(log)
      assert transfer.amount == 0
    end
  end

  describe "parse_log/1 — ERC-721" do
    test "parses 4-topic Transfer log into ERC-721 struct" do
      token_id = 12_345

      log =
        build_log(
          topics: [@transfer_topic, @from_addr_padded, @to_addr_padded, encode_topic_uint256(token_id)],
          data: "0x"
        )

      assert {:ok, %Transfer{} = transfer} = Transfer.parse_log(log)
      assert transfer.token_standard == :erc721
      assert transfer.token_id == token_id
      assert transfer.amount == nil
      assert transfer.operator == nil
    end
  end

  describe "parse_log/1 — ERC-1155 TransferSingle" do
    test "parses TransferSingle log with operator, id, and value" do
      log =
        build_log(
          topics: [@transfer_single_topic, @operator_padded, @from_addr_padded, @to_addr_padded],
          data: encode_uint256_pair(42, 100)
        )

      assert {:ok, %Transfer{} = transfer} = Transfer.parse_log(log)
      assert transfer.token_standard == :erc1155
      assert transfer.token_id == 42
      assert transfer.amount == 100
      assert transfer.operator == Onchain.Address.checksum!("0x1111111111111111111111111111111111111111")
    end
  end

  describe "parse_log/1 — ERC-1155 TransferBatch" do
    test "expands batch into list of structs" do
      ids = [1, 2, 3]
      values = [100, 200, 300]

      log =
        build_log(
          topics: [@transfer_batch_topic, @operator_padded, @from_addr_padded, @to_addr_padded],
          data: encode_uint256_arrays(ids, values)
        )

      assert {:ok, transfers} = Transfer.parse_log(log)
      assert is_list(transfers)
      assert length(transfers) == 3

      assert Enum.map(transfers, & &1.token_id) == [1, 2, 3]
      assert Enum.map(transfers, & &1.amount) == [100, 200, 300]
      assert Enum.all?(transfers, &(&1.token_standard == :erc1155))
      assert Enum.all?(transfers, &(&1.log_index == 42))

      # All share the same operator
      operator = Onchain.Address.checksum!("0x1111111111111111111111111111111111111111")
      assert Enum.all?(transfers, &(&1.operator == operator))
    end
  end

  describe "parse_log/1 — errors" do
    test "returns error for unknown event topic" do
      unknown_topic = "0x0000000000000000000000000000000000000000000000000000000000000001"

      log = build_log(topics: [unknown_topic, @from_addr_padded, @to_addr_padded], data: "0x")

      assert {:error, {:unknown_event, :not_a_transfer}} = Transfer.parse_log(log)
    end

    test "returns error for non-map input" do
      assert {:error, {:unknown_event, :not_a_transfer}} = Transfer.parse_log("not a log")
    end

    test "returns error for log with no topics" do
      log = build_log(topics: [])
      assert {:error, {:unknown_event, :not_a_transfer}} = Transfer.parse_log(log)
    end
  end

  describe "parse_log!/1" do
    test "returns struct directly on success" do
      log =
        build_log(
          topics: [@transfer_topic, @from_addr_padded, @to_addr_padded],
          data: encode_uint256(500)
        )

      assert %Transfer{amount: 500} = Transfer.parse_log!(log)
    end

    test "raises on unknown event" do
      log = build_log(topics: ["0x0000000000000000000000000000000000000000000000000000000000000001"])

      assert_raise RuntimeError, ~r/parse_log failed/, fn ->
        Transfer.parse_log!(log)
      end
    end
  end

  describe "parse_logs/1" do
    test "parses mixed Transfer and non-Transfer logs" do
      erc20_log =
        build_log(
          topics: [@transfer_topic, @from_addr_padded, @to_addr_padded],
          data: encode_uint256(1000)
        )

      # Approval event — should be skipped
      approval_topic = Onchain.Hex.encode(Cartouche.Hash.keccak("Approval(address,address,uint256)"))

      non_transfer_log =
        build_log(
          topics: [approval_topic, @from_addr_padded, @to_addr_padded],
          data: encode_uint256(999)
        )

      assert {:ok, transfers} = Transfer.parse_logs([erc20_log, non_transfer_log])
      assert length(transfers) == 1
      assert hd(transfers).amount == 1000
    end

    test "returns empty list for empty input" do
      assert {:ok, []} = Transfer.parse_logs([])
    end

    test "flattens batch expansion into list" do
      erc20_log =
        build_log(
          topics: [@transfer_topic, @from_addr_padded, @to_addr_padded],
          data: encode_uint256(100)
        )

      batch_log =
        build_log(
          topics: [@transfer_batch_topic, @operator_padded, @from_addr_padded, @to_addr_padded],
          data: encode_uint256_arrays([1, 2], [10, 20])
        )

      assert {:ok, transfers} = Transfer.parse_logs([erc20_log, batch_log])
      # 1 ERC-20 + 2 from batch = 3 total
      assert length(transfers) == 3
    end
  end

  describe "parse_logs!/1" do
    test "returns list directly" do
      log =
        build_log(
          topics: [@transfer_topic, @from_addr_padded, @to_addr_padded],
          data: encode_uint256(100)
        )

      assert [%Transfer{}] = Transfer.parse_logs!([log])
    end
  end

  describe "parse_logs/1 — decode error path" do
    test "skips logs that fail to decode with warning" do
      # Log with correct Transfer topic but truncated data (can't decode as uint256)
      bad_log =
        build_log(
          topics: [@transfer_topic, @from_addr_padded, @to_addr_padded],
          data: "0xdead"
        )

      good_log =
        build_log(
          topics: [@transfer_topic, @from_addr_padded, @to_addr_padded],
          data: encode_uint256(500)
        )

      assert {:ok, transfers} = Transfer.parse_logs([bad_log, good_log])
      # Bad log skipped, good log parsed
      assert length(transfers) == 1
      assert hd(transfers).amount == 500
    end
  end

  describe "fetch!/2" do
    test "raises on invalid filter" do
      assert_raise RuntimeError, ~r/fetch failed/, fn ->
        Transfer.fetch!(%{from_block: "bogus"})
      end
    end
  end
end
