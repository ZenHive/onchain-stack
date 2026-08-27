defmodule Onchain.Tempo.TransferTest do
  use ExUnit.Case, async: true

  alias Onchain.Tempo.Transfer

  describe "transfer_with_memo_sig/0" do
    test "returns the event signature string" do
      sig = Transfer.transfer_with_memo_sig()
      assert is_binary(sig)
      assert sig =~ "TransferWithMemo"
      assert sig =~ "bytes32 indexed memo"
    end
  end

  describe "parse_transfer_with_memo_logs/1" do
    test "returns empty list for empty logs" do
      assert Transfer.parse_transfer_with_memo_logs([]) == []
    end

    test "skips logs that don't match the TransferWithMemo signature" do
      # A log with a random topic that won't match
      log = %{
        address: "0x20c0000000000000000000000000000000000000",
        topics: ["0xdeadbeef"],
        data: "0x",
        block_number: 1,
        transaction_hash: "0xabc",
        log_index: 0
      }

      assert Transfer.parse_transfer_with_memo_logs([log]) == []
    end
  end
end
