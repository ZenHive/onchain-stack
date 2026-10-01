defmodule Onchain.MEVTest do
  use ExUnit.Case, async: true

  alias Onchain.Hex
  alias Onchain.MEV

  @raw_tx "0x" <> String.duplicate("ab", 50)
  @raw_tx2 "0x" <> String.duplicate("cd", 50)
  # Loopback port 1 refuses connections — deterministic transport failure.
  @unavailable_endpoint "http://127.0.0.1:1"
  @short_timeout_ms 50

  describe "build_private_transaction_params/2" do
    test "wraps the signed tx in a single param map" do
      assert {:ok, [%{"tx" => @raw_tx} = param]} = MEV.build_private_transaction_params(@raw_tx, [])
      refute Map.has_key?(param, "maxBlockNumber")
      refute Map.has_key?(param, "preferences")
    end

    test "encodes :max_block_number to hex" do
      assert {:ok, [param]} = MEV.build_private_transaction_params(@raw_tx, max_block_number: 19_000_000)
      assert param["maxBlockNumber"] == Hex.from_integer(19_000_000)
    end

    test "accepts a 0x hex :max_block_number verbatim" do
      assert {:ok, [param]} = MEV.build_private_transaction_params(@raw_tx, max_block_number: "0x1221860")
      assert param["maxBlockNumber"] == "0x1221860"
    end

    test "passes :preferences through verbatim" do
      prefs = %{"fast" => true, "privacy" => %{"hints" => ["calldata"]}}
      assert {:ok, [param]} = MEV.build_private_transaction_params(@raw_tx, preferences: prefs)
      assert param["preferences"] == prefs
    end

    test "rejects a signed tx that is not 0x hex" do
      assert {:error, {:invalid_data, "abc"}} = MEV.build_private_transaction_params("abc", [])
    end

    test "rejects an invalid :max_block_number" do
      assert {:error, {:invalid_block, -1}} = MEV.build_private_transaction_params(@raw_tx, max_block_number: -1)
    end

    test "rejects block tags for :max_block_number" do
      for tag <- ~w(latest pending finalized earliest safe) do
        assert {:error, {:invalid_block, ^tag}} =
                 MEV.build_private_transaction_params(@raw_tx, max_block_number: tag)
      end
    end
  end

  describe "build_bundle_params/2" do
    test "shapes txs + target block into a single param map" do
      assert {:ok, [param]} = MEV.build_bundle_params([@raw_tx, @raw_tx2], block_number: 19_000_000)
      assert param["txs"] == [@raw_tx, @raw_tx2]
      assert param["blockNumber"] == Hex.from_integer(19_000_000)
      refute Map.has_key?(param, "minTimestamp")
    end

    test "preserves tx order" do
      assert {:ok, [param]} = MEV.build_bundle_params([@raw_tx2, @raw_tx], block_number: 1)
      assert param["txs"] == [@raw_tx2, @raw_tx]
    end

    test "includes optional validity-window and reverting fields" do
      assert {:ok, [param]} =
               MEV.build_bundle_params([@raw_tx],
                 block_number: 1,
                 min_timestamp: 0,
                 max_timestamp: 1_615_920_932,
                 reverting_tx_hashes: ["0xdeadbeef"]
               )

      assert param["minTimestamp"] == 0
      assert param["maxTimestamp"] == 1_615_920_932
      assert param["revertingTxHashes"] == ["0xdeadbeef"]
    end

    test "rejects an empty bundle" do
      assert {:error, :empty_bundle} = MEV.build_bundle_params([], block_number: 1)
    end

    test "rejects a bundle missing the target block" do
      assert {:error, :missing_block_number} = MEV.build_bundle_params([@raw_tx], [])
    end

    test "rejects an invalid target block" do
      assert {:error, {:invalid_block, :soon}} = MEV.build_bundle_params([@raw_tx], block_number: :soon)
    end

    test "rejects block tags for :block_number" do
      for tag <- ~w(latest pending finalized earliest safe) do
        assert {:error, {:invalid_block, ^tag}} = MEV.build_bundle_params([@raw_tx], block_number: tag)
      end
    end

    test "rejects a bundle containing a non-hex tx" do
      assert {:error, {:invalid_data, "nope"}} = MEV.build_bundle_params([@raw_tx, "nope"], block_number: 1)
    end

    test "rejects a non-list bundle" do
      assert {:error, {:invalid_bundle, "0xabc"}} = MEV.build_bundle_params("0xabc", block_number: 1)
    end
  end

  describe "send_private_transaction/2 error envelopes" do
    test "requires an :endpoint (never falls back to the public node)" do
      assert {:error, :missing_endpoint} = MEV.send_private_transaction(@raw_tx, [])
    end

    test "rejects a non-binary :endpoint" do
      assert {:error, {:invalid_endpoint, :relay}} =
               MEV.send_private_transaction(@raw_tx, endpoint: :relay)
    end

    test "validates the signed tx before requiring an endpoint" do
      assert {:error, {:invalid_data, "abc"}} = MEV.send_private_transaction("abc", [])
    end

    test "wraps transport failures as {:rpc_error, map}" do
      assert {:error, {:rpc_error, %{message: message}}} =
               MEV.send_private_transaction(@raw_tx,
                 endpoint: @unavailable_endpoint,
                 timeout: @short_timeout_ms
               )

      assert is_binary(message)
    end
  end

  describe "send_bundle/2 error envelopes" do
    test "requires an :endpoint" do
      assert {:error, :missing_endpoint} = MEV.send_bundle([@raw_tx], block_number: 1)
    end

    test "validates the bundle before requiring an endpoint" do
      assert {:error, :empty_bundle} = MEV.send_bundle([], block_number: 1)
    end

    test "wraps transport failures as {:rpc_error, map}" do
      assert {:error, {:rpc_error, %{message: message}}} =
               MEV.send_bundle([@raw_tx],
                 block_number: 1,
                 endpoint: @unavailable_endpoint,
                 timeout: @short_timeout_ms
               )

      assert is_binary(message)
    end
  end
end
