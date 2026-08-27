defmodule Onchain.HexTest do
  use ExUnit.Case, async: true

  alias Cartouche.Hex.InvalidHex
  alias Onchain.Hex

  describe "decode/1" do
    test "decodes hex with 0x prefix" do
      assert {:ok, <<170, 187>>} = Hex.decode("0xaabb")
    end

    test "decodes hex without prefix" do
      assert {:ok, <<170, 187>>} = Hex.decode("aabb")
    end

    test "decodes odd-length hex with padding" do
      assert {:ok, <<10, 171>>} = Hex.decode("0xaab")
    end

    test "returns error for invalid characters" do
      assert {:error, {:invalid_hex, "0xgggg"}} = Hex.decode("0xgggg")
    end

    test "decodes bare 0x prefix to empty binary" do
      assert {:ok, <<>>} = Hex.decode("0x")
    end

    test "decodes uppercase hex" do
      assert {:ok, <<170, 187>>} = Hex.decode("0xAABB")
    end

    test "decodes mixed case hex" do
      assert {:ok, <<170, 187>>} = Hex.decode("0xAaBb")
    end
  end

  describe "decode!/1" do
    test "returns binary for valid hex" do
      assert <<170, 187>> = Hex.decode!("0xaabb")
    end

    test "raises on invalid hex" do
      assert_raise InvalidHex, fn ->
        Hex.decode!("0xgggg")
      end
    end
  end

  describe "encode/1" do
    test "encodes binary to 0x-prefixed lowercase hex" do
      assert "0xaabb" = Hex.encode(<<170, 187>>)
    end

    test "encodes empty binary" do
      assert "0x" = Hex.encode(<<>>)
    end

    test "roundtrip: decode!(encode(bin)) == bin" do
      bin = <<1, 2, 3, 255, 0>>
      assert bin == Hex.decode!(Hex.encode(bin))
    end
  end

  describe "to_integer/1" do
    test "decodes 0x0 to 0" do
      assert {:ok, 0} = Hex.to_integer("0x0")
    end

    test "decodes 0xff to 255" do
      assert {:ok, 255} = Hex.to_integer("0xff")
    end

    test "decodes 0xaabb to 43707" do
      assert {:ok, 43_707} = Hex.to_integer("0xaabb")
    end

    test "returns error for invalid hex" do
      assert {:error, {:invalid_hex, "0xzzzz"}} = Hex.to_integer("0xzzzz")
    end

    test "returns error for bare 0x prefix" do
      assert {:error, {:invalid_hex, "0x"}} = Hex.to_integer("0x")
    end

    test "returns error for empty string" do
      assert {:error, {:invalid_hex, ""}} = Hex.to_integer("")
    end
  end

  describe "to_integer!/1" do
    test "returns integer for valid hex" do
      assert 255 = Hex.to_integer!("0xff")
    end

    test "raises on invalid hex" do
      assert_raise InvalidHex, fn ->
        Hex.to_integer!("0xzzzz")
      end
    end
  end

  describe "from_integer/1" do
    test "encodes 0 as 0x0" do
      assert "0x0" = Hex.from_integer(0)
    end

    test "encodes 255 as compact hex" do
      assert "0xff" = Hex.from_integer(255)
    end

    test "encodes large number correctly" do
      assert "0x" <> _ = Hex.from_integer(1_000_000)
    end

    test "raises on negative integer" do
      assert_raise FunctionClauseError, fn ->
        Hex.from_integer(-1)
      end
    end

    test "raises on float input" do
      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(Hex, :from_integer, [1.5])
      end
    end

    test "roundtrip: to_integer!(from_integer(n)) == n" do
      for n <- [0, 1, 255, 65_535, 1_000_000] do
        assert n == Hex.to_integer!(Hex.from_integer(n))
      end
    end
  end

  describe "valid?/1" do
    test "returns true for valid hex with prefix" do
      assert Hex.valid?("0xaabb")
    end

    test "returns true for valid hex without prefix" do
      assert Hex.valid?("aabb")
    end

    test "returns true for uppercase hex" do
      assert Hex.valid?("0xAABB")
    end

    test "returns false for invalid characters" do
      refute Hex.valid?("0xgggg")
    end

    test "returns false for empty string" do
      refute Hex.valid?("")
    end

    test "returns true for bare 0x prefix (empty bytes)" do
      assert Hex.valid?("0x")
    end

    test "returns false for non-binary input" do
      refute Hex.valid?(123)
      refute Hex.valid?(nil)
      refute Hex.valid?(:atom)
    end
  end
end
