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

  test "decodes indexed memo and returns checksummed addresses" do
    from = <<0xA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48::160>>
    to = <<0xDAC17F958D2EE523A2206206994597C13D831EC7::160>>
    memo = :binary.copy(<<0xAB>>, 32)

    topics = [
      Onchain.ABI.event_signature(Transfer.transfer_with_memo_sig()),
      <<0::96, from::binary>>,
      <<0::96, to::binary>>,
      memo
    ]

    log = %{
      address: "0x20c0000000000000000000000000000000000000",
      topics: Enum.map(topics, &Onchain.Hex.encode/1),
      data: Onchain.Hex.encode(<<42::256>>)
    }

    assert [%{from: decoded_from, to: decoded_to, amount: 42, memo: decoded_memo, token: token}] =
             Transfer.parse_transfer_with_memo_logs([log])

    assert decoded_from == Onchain.Address.checksum!(from)
    assert decoded_to == Onchain.Address.checksum!(to)
    assert decoded_memo == Onchain.Hex.encode(memo)
    assert token == log.address
  end

  test "missing and malformed event data are skipped" do
    topic = Onchain.Hex.encode(Onchain.ABI.event_signature(Transfer.transfer_with_memo_sig()))

    for data <- [nil, "0xzz"] do
      assert [] = Transfer.parse_transfer_with_memo_logs([%{topics: [topic], data: data}])
    end
  end
end
