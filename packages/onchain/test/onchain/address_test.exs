defmodule Onchain.AddressTest do
  use ExUnit.Case, async: true

  import Onchain.TypeEvasion, only: [untyped: 1]

  alias Cartouche.Hex.InvalidHex
  alias Onchain.Address

  # EIP-55 test vectors from the spec
  @checksummed_vectors [
    "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed",
    "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359",
    "0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB",
    "0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb"
  ]

  @zero_hex "0x0000000000000000000000000000000000000000"
  @zero_binary <<0::160>>

  # A known address as 20-byte binary
  @sample_binary Cartouche.Hex.decode_address!("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")

  describe "validate/1" do
    test "validates lowercase hex" do
      assert {:ok, @sample_binary} = Address.validate("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed")
    end

    test "validates uppercase hex" do
      assert {:ok, @sample_binary} = Address.validate("0x5AAEB6053F3E94C9B9A09F33669435E7EF1BEAED")
    end

    test "validates mixed case (checksummed) hex" do
      assert {:ok, @sample_binary} = Address.validate("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
    end

    test "validates bare hex without 0x prefix" do
      assert {:ok, @sample_binary} = Address.validate("5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
    end

    test "validates 20-byte binary" do
      assert {:ok, @sample_binary} = Address.validate(@sample_binary)
    end

    test "validates zero address" do
      assert {:ok, @zero_binary} = Address.validate(@zero_hex)
    end

    test "returns error for wrong-size hex (too short)" do
      assert {:error, {:invalid_address, "0xaabb"}} = Address.validate("0xaabb")
    end

    test "returns error for wrong-size hex (too long)" do
      long = "0x" <> String.duplicate("aa", 21)
      assert {:error, {:invalid_address, ^long}} = Address.validate(long)
    end

    test "returns error for wrong-size binary" do
      assert {:error, {:invalid_address, <<1, 2, 3>>}} = Address.validate(<<1, 2, 3>>)
    end

    test "returns error for invalid hex characters" do
      assert {:error, {:invalid_address, "0xgggggggggggggggggggggggggggggggggggggggg"}} =
               Address.validate("0xgggggggggggggggggggggggggggggggggggggggg")
    end

    test "returns error for nil" do
      assert {:error, {:invalid_address, nil}} = Address.validate(nil)
    end

    test "returns error for integer" do
      assert {:error, {:invalid_address, 42}} = Address.validate(42)
    end

    test "returns error for empty string" do
      assert {:error, {:invalid_address, ""}} = Address.validate("")
    end
  end

  describe "valid?/1" do
    test "returns true for valid hex address" do
      assert Address.valid?("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
    end

    test "returns true for 20-byte binary" do
      assert Address.valid?(@sample_binary)
    end

    test "returns false for wrong-size hex" do
      refute Address.valid?("0xaabb")
    end

    test "returns false for nil" do
      refute Address.valid?(nil)
    end

    test "returns false for integer" do
      refute Address.valid?(42)
    end

    test "returns false for empty string" do
      refute Address.valid?("")
    end
  end

  describe "checksum/1" do
    test "produces correct EIP-55 checksums from lowercase input" do
      for expected <- @checksummed_vectors do
        lower = String.downcase(expected)
        assert {:ok, ^expected} = Address.checksum(lower)
      end
    end

    test "produces correct EIP-55 checksums from binary input" do
      for expected <- @checksummed_vectors do
        binary = Cartouche.Hex.decode_address!(expected)
        assert {:ok, ^expected} = Address.checksum(binary)
      end
    end

    test "produces correct checksum for zero address" do
      assert {:ok, @zero_hex} = Address.checksum(@zero_binary)
    end

    test "idempotent — checksumming a checksummed address returns the same" do
      for expected <- @checksummed_vectors do
        assert {:ok, ^expected} = Address.checksum(expected)
      end
    end

    test "returns error for invalid input" do
      assert {:error, {:invalid_address, "not_an_address"}} = Address.checksum("not_an_address")
    end

    test "returns error for wrong-size binary" do
      assert {:error, {:invalid_address, <<1, 2, 3>>}} = Address.checksum(<<1, 2, 3>>)
    end
  end

  describe "checksum!/1" do
    test "returns checksummed string for valid address" do
      assert "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" =
               Address.checksum!("0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed")
    end

    test "works with binary input" do
      assert "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed" = Address.checksum!(@sample_binary)
    end

    test "raises on invalid input" do
      assert_raise InvalidHex, fn ->
        Address.checksum!("0xaabb")
      end
    end

    test "raises on nil" do
      assert_raise InvalidHex, fn ->
        Address.checksum!(untyped(nil))
      end
    end
  end

  describe "normalize/1" do
    test "returns lowercase 0x-prefixed hex" do
      assert {:ok, "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"} =
               Address.normalize("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
    end

    test "normalizes from binary input" do
      assert {:ok, "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"} =
               Address.normalize(@sample_binary)
    end

    test "normalizes zero address" do
      assert {:ok, "0x" <> hex} = Address.normalize(@zero_binary)
      assert String.length(hex) == 40
      assert hex == String.duplicate("0", 40)
    end

    test "returns error for invalid input" do
      assert {:error, {:invalid_address, "bad"}} = Address.normalize("bad")
    end
  end

  describe "equal?/2" do
    test "same address, different cases" do
      lower = "0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed"
      upper = "0x5AAEB6053F3E94C9B9A09F33669435E7EF1BEAED"
      assert Address.equal?(lower, upper)
    end

    test "hex vs binary" do
      hex = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
      assert Address.equal?(hex, @sample_binary)
    end

    test "binary vs binary" do
      assert Address.equal?(@sample_binary, @sample_binary)
    end

    test "different addresses" do
      a = "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed"
      b = "0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359"
      refute Address.equal?(a, b)
    end

    test "returns false when either input is invalid" do
      refute Address.equal?("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed", "not_valid")
      refute Address.equal?("not_valid", "0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
      refute Address.equal?(nil, nil)
    end
  end

  describe "zero?/1" do
    test "returns true for zero address hex" do
      assert Address.zero?(@zero_hex)
    end

    test "returns true for zero address binary" do
      assert Address.zero?(@zero_binary)
    end

    test "returns false for non-zero address" do
      refute Address.zero?("0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed")
    end

    test "returns false for non-zero binary" do
      refute Address.zero?(@sample_binary)
    end

    test "returns false for invalid input" do
      refute Address.zero?("bad")
      refute Address.zero?(nil)
    end
  end
end
