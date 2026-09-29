defmodule Cartouche.HexTest do
  use ExUnit.Case, async: true

  alias Cartouche.Hex.InvalidHex

  doctest Cartouche.Hex

  describe "checksum_address/1" do
    test "handles a 20-byte binary whose first two bytes are ASCII '0x'" do
      # <<0x30, 0x78>> is ASCII "0x". When a raw 20-byte address starts with
      # these bytes, checksum_address/1 must not confuse it with a hex string.
      address = <<0x30, 0x78, 0::144>>
      result = Cartouche.Hex.checksum_address(address)
      assert is_binary(result)
      assert String.starts_with?(result, "0x")
      assert byte_size(result) == 42
    end

    test "checksums a hex string input" do
      assert Cartouche.Hex.checksum_address("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed") ==
               "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
    end
  end

  describe "spec boundaries (Phase 1.4)" do
    # Pins the corrected return shapes for the four functions whose @spec
    # was historically `:error` but actual return is `:invalid_hex`. Doctests
    # cover the documented examples; this block pins the contract per
    # `feedback_doctests_not_substitute_for_tests.md` — doctests read as
    # prose and don't compose for multi-input invariants.

    test "decode_hex/1 returns :invalid_hex on non-hex characters" do
      assert :invalid_hex = Cartouche.Hex.decode_hex("0xZZ")
      assert :invalid_hex = Cartouche.Hex.decode_hex("ZZ")
      assert :invalid_hex = Cartouche.Hex.decode_hex("0xgggg")
    end

    test "decode_hex_number/1 returns :invalid_hex on non-hex characters" do
      assert :invalid_hex = Cartouche.Hex.decode_hex_number("0xZZ")
      assert :invalid_hex = Cartouche.Hex.decode_hex_number("0xgggg")
    end

    test "from_hex/1 inherits :invalid_hex from decode_hex/1" do
      assert :invalid_hex = Cartouche.Hex.from_hex("0xZZ")
      assert Cartouche.Hex.from_hex("0xaabb") == Cartouche.Hex.decode_hex("0xaabb")
    end

    test "from_hex!/1 raises Cartouche.Hex.InvalidHex on bad input" do
      assert_raise InvalidHex, ~s(invalid hex: "0xZZ"), fn ->
        Cartouche.Hex.from_hex!("0xZZ")
      end
    end
  end

  describe "decode_maybe_hex_number!/1" do
    test "returns nil for nil input" do
      assert Cartouche.Hex.decode_maybe_hex_number!(nil) == nil
    end

    test "decodes a hex string to an integer" do
      assert Cartouche.Hex.decode_maybe_hex_number!("0xaabb") == 0xAABB
    end

    test "decodes 0x0 to 0 (boundary: zero is not nil)" do
      assert Cartouche.Hex.decode_maybe_hex_number!("0x0") == 0
    end

    test "raises InvalidHex on non-hex characters" do
      assert_raise InvalidHex, ~s(invalid hex number: "0xgggg"), fn ->
        Cartouche.Hex.decode_maybe_hex_number!("0xgggg")
      end
    end
  end

  describe "deep_encode_binaries/1" do
    test "encodes a binary as 0x-prefixed hex" do
      assert Cartouche.Hex.deep_encode_binaries(<<0xAA, 0xBB>>) == "0xaabb"
    end

    test "recurses into lists" do
      assert Cartouche.Hex.deep_encode_binaries([<<0xAA>>, <<0xBB>>]) == ["0xaa", "0xbb"]
    end

    test "recurses into tuples" do
      assert Cartouche.Hex.deep_encode_binaries({<<0xAA>>, <<0xBB>>}) == {"0xaa", "0xbb"}
    end

    test "passes other terms through unchanged" do
      assert Cartouche.Hex.deep_encode_binaries(42) == 42
      assert Cartouche.Hex.deep_encode_binaries(:atom) == :atom
      assert Cartouche.Hex.deep_encode_binaries(nil) == nil
    end
  end

  describe "encode_quantity/1" do
    test "zero returns \"0x0\"" do
      assert Cartouche.Hex.encode_quantity(0) == "0x0"
    end

    test "small positive integer encodes lowercase, no leading zeros" do
      assert Cartouche.Hex.encode_quantity(55) == "0x37"
    end

    test "single hex digit value encodes without leading zero" do
      assert Cartouche.Hex.encode_quantity(15) == "0xf"
    end

    test "multi-byte block number encodes lowercase" do
      # 24_975_978 = 0x17d1a6a — the live-tunnel-verified value from ROADMAP Task 60
      assert Cartouche.Hex.encode_quantity(24_975_978) == "0x17d1a6a"
    end

    test "all-letter hex digits stay lowercase" do
      # 0xabcdef = 11_259_375
      assert Cartouche.Hex.encode_quantity(11_259_375) == "0xabcdef"
    end

    test "rejects negative integers via guard" do
      assert_raise FunctionClauseError, fn -> Cartouche.Hex.encode_quantity(-1) end
    end
  end
end
