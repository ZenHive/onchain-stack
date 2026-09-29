defmodule Cartouche.Transaction.MutationGapTest do
  @moduledoc false
  # Paths the ROADMAP task 114 mutation campaign reported as never executed by any
  # test — mutants there were not "surviving", they were never attempted, which is
  # the weaker of the two positions. Each test below makes one such site reachable
  # and asserts the behaviour that a mutation of it would break.

  use ExUnit.Case, async: false

  alias Cartouche.Signer
  alias Cartouche.Transaction.V3
  alias Cartouche.Transaction.V4

  @blob_versioned_hash <<0x01>> <> :binary.copy(<<0xFF>>, 31)
  @authorization {1, <<2::160>>, 7, false, <<1::256>>, <<2::256>>}

  describe "V3.sign/1 default signer" do
    test "signs through the default signer process and recovers its address" do
      transaction = v3_transaction()
      default_address = Signer.address(Signer.Default)

      assert {:ok, signed} = V3.sign(transaction)
      assert {:ok, ^default_address} = V3.recover_signer(signed)
    end

    test "the default-signer route agrees with the explicit-signer route" do
      transaction = v3_transaction()

      assert {:ok, implicit} = V3.sign(transaction)
      assert {:ok, explicit} = V3.sign(transaction, Signer.Default)

      assert V3.encode(implicit) == V3.encode(explicit)
    end
  end

  describe "V4 encoding with a nil access list" do
    test "a nil access list encodes as the empty list" do
      transaction = v4_transaction()

      assert V4.encode(%{transaction | access_list: nil}) ==
               V4.encode(%{transaction | access_list: []})
    end

    test "the nil access list survives a round trip as an empty list" do
      transaction = v4_transaction()

      assert {:ok, decoded} = V4.decode(V4.encode(%{transaction | access_list: nil}))
      assert decoded.access_list == []
    end
  end

  describe "V4 decoding of malformed scalar fields" do
    test "rejects a y-parity field wider than one byte" do
      assert {:error, "invalid v4 transaction"} =
               V4.decode(signed_v4_wire(<<0, 1>>, <<1::256>>, <<2::256>>))
    end

    test "accepts the same envelope with a one-byte y parity" do
      assert {:ok, decoded} = V4.decode(signed_v4_wire(<<1>>, <<1::256>>, <<2::256>>))
      assert decoded.signature_y_parity == true
    end

    # RLP encodes scalars minimally, so a signature word arrives shorter than 32
    # bytes whenever it has leading zeros. `decode_word/1` left-pads those back to
    # a full word and only rejects one that is genuinely oversized.
    test "left-pads a signature word that RLP shortened" do
      assert {:ok, decoded} = V4.decode(signed_v4_wire(<<1>>, <<1::248>>, <<2::256>>))
      assert decoded.signature_r == <<1::256>>
      assert byte_size(decoded.signature_r) == 32
    end

    test "rejects a signature word wider than 32 bytes" do
      assert {:error, "invalid v4 transaction"} =
               V4.decode(signed_v4_wire(<<1>>, <<1::264>>, <<2::256>>))
    end
  end

  defp v3_transaction do
    V3.new(
      1,
      {1, :gwei},
      {100, :gwei},
      100_000,
      <<1::160>>,
      {2, :wei},
      <<1, 2, 3>>,
      [],
      {1, :gwei},
      [@blob_versioned_hash],
      5
    )
  end

  defp v4_transaction do
    V4.new(
      1,
      {1, :gwei},
      {100, :gwei},
      100_000,
      <<1::160>>,
      {2, :wei},
      <<1, 2, 3>>,
      [],
      [@authorization],
      5
    )
  end

  # A 13-field (signed) EIP-7702 envelope built at the wire level, so the
  # signature fields can carry widths the struct API would never produce.
  defp signed_v4_wire(y_parity, r, s) do
    fields = [
      <<5>>,
      <<1>>,
      <<0x3B, 0x9A, 0xCA, 0x00>>,
      <<0x17, 0x48, 0x76, 0xE8, 0x00>>,
      <<0x01, 0x86, 0xA0>>,
      <<1::160>>,
      <<2>>,
      <<1, 2, 3>>,
      [],
      [[<<1>>, <<2::160>>, <<7>>, <<>>, <<1::256>>, <<2::256>>]],
      y_parity,
      r,
      s
    ]

    <<0x04>> <> ExRLP.encode(fields)
  end
end
