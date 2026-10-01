defmodule Onchain.ABI.HexConvenienceTest do
  use ExUnit.Case, async: true

  alias Onchain.Hex.InvalidHex

  describe "encode_hex_call/2" do
    test "encodes balanceOf(address) with valid 20-byte address" do
      addr = <<1::160>>
      assert {:ok, "0x70a08231" <> _params} = Onchain.ABI.encode_hex_call("balanceOf(address)", [addr])
    end

    test "encodes totalSupply() with empty params (4-byte selector only)" do
      assert {:ok, hex} = Onchain.ABI.encode_hex_call("totalSupply()", [])
      # 4-byte selector = 8 hex chars + "0x" prefix
      assert hex == "0x18160ddd"
    end

    test "encodes function with multiple params baz(uint256,bool)" do
      assert {:ok, "0x" <> hex_body} = Onchain.ABI.encode_hex_call("baz(uint256,bool)", [10, true])
      # 4-byte selector + 2 × 32-byte params = 68 bytes = 136 hex chars
      assert byte_size(hex_body) == 136
    end

    test "returns error for invalid signature" do
      assert {:error, {:encode_error, _reason}} = Onchain.ABI.encode_hex_call("???invalid", [])
    end

    test "returns error for data overflow (uint8 with 9999)" do
      assert {:error, {:encode_error, reason}} = Onchain.ABI.encode_hex_call("foo(uint8)", [9999])
      assert reason =~ "overflow"
    end

    test "returns error for wrong param count" do
      assert {:error, {:encode_error, _reason}} =
               Onchain.ABI.encode_hex_call("balanceOf(address)", [<<1::160>>, <<2::160>>])
    end
  end

  # The rescue clauses in ABI list exception modules explicitly, so an input
  # class raising something outside @abi_errors would escape as a crash instead of an
  # error tuple. One case per exception hieroglyph raises, so adding a class to the
  # upstream surface fails here rather than in a consumer.
  describe "upstream exception coverage" do
    test "every malformed-input class surfaces as an error tuple, never a raise" do
      assert {:error, {:encode_error, _}} = Onchain.ABI.encode_hex_call("???invalid", [])
      assert {:error, {:encode_error, _}} = Onchain.ABI.encode_hex_call("balanceOf(address)", [])
      assert {:error, {:encode_error, _}} = Onchain.ABI.encode_hex_call("f(uint256)", [nil])
      assert {:error, {:encode_error, _}} = Onchain.ABI.encode_hex_call("f(uint257)", [1])
      assert {:error, {:encode_error, _}} = Onchain.ABI.encode_hex_call("f(uint256)", [%{a: 1}])

      assert {:error, {:decode_error, _}} = Onchain.ABI.decode_response("(uint256)", "0x010203")
      assert {:error, {:decode_error, _}} = Onchain.ABI.decode_response("(uint256)", "0x")
      assert {:error, {:decode_error, _}} = Onchain.ABI.decode_response("uint256", Onchain.Hex.encode(<<0::256>>))

      assert {:error, {:decode_error, _}} =
               Onchain.ABI.decode_response("(string)", Onchain.Hex.encode(<<0xFFFFFFFF::256>>))

      assert {:error, {:decode_error, _}} = Onchain.ABI.decode_response("(bool)", Onchain.Hex.encode(<<7::256>>))
    end
  end

  describe "encode_hex_call!/2" do
    test "returns hex string for valid call" do
      assert "0x70a08231" <> _ = Onchain.ABI.encode_hex_call!("balanceOf(address)", [<<1::160>>])
    end

    test "raises on invalid signature" do
      assert_raise MatchError, fn ->
        Onchain.ABI.encode_hex_call!("???invalid", [])
      end
    end
  end

  describe "decode_response/2" do
    test "decodes single uint256" do
      hex = "0x" <> String.duplicate("0", 62) <> "0a"
      assert {:ok, [10]} = Onchain.ABI.decode_response("(uint256)", hex)
    end

    test "decodes multiple return values (uint256,uint256)" do
      hex = "0x" <> String.duplicate("0", 62) <> "0a" <> String.duplicate("0", 62) <> "14"
      assert {:ok, [10, 20]} = Onchain.ABI.decode_response("(uint256,uint256)", hex)
    end

    test "decodes address (returns 20-byte binary)" do
      addr = <<1::160>>
      padded = "0x" <> String.duplicate("0", 24) <> Base.encode16(addr, case: :lower)
      assert {:ok, [^addr]} = Onchain.ABI.decode_response("(address)", padded)
    end

    test "decodes bool" do
      true_hex = "0x" <> String.duplicate("0", 62) <> "01"
      false_hex = "0x" <> String.duplicate("0", 64)
      assert {:ok, [true]} = Onchain.ABI.decode_response("(bool)", true_hex)
      assert {:ok, [false]} = Onchain.ABI.decode_response("(bool)", false_hex)
    end

    test "returns error for invalid hex" do
      assert {:error, {:decode_error, {:invalid_hex, "0xzzzz"}}} =
               Onchain.ABI.decode_response("(uint256)", "0xzzzz")
    end

    test "returns error for truncated data" do
      assert {:error, {:decode_error, _reason}} = Onchain.ABI.decode_response("(uint256)", "0x0102")
    end
  end

  describe "decode_response!/2" do
    test "returns decoded list for valid data" do
      hex = "0x" <> String.duplicate("0", 62) <> "0a"
      assert [10] = Onchain.ABI.decode_response!("(uint256)", hex)
    end

    test "raises on invalid hex" do
      assert_raise InvalidHex, fn ->
        Onchain.ABI.decode_response!("(uint256)", "0xzzzz")
      end
    end

    test "raises on malformed ABI data" do
      assert_raise MatchError, fn ->
        Onchain.ABI.decode_response!("(uint256)", "0x0102")
      end
    end
  end

  describe "roundtrip" do
    test "encode params, strip selector, decode back recovers original values" do
      assert {:ok, calldata} = Onchain.ABI.encode_hex_call("baz(uint256,bool)", [42, true])
      # Strip 4-byte (8 hex char) selector + "0x" prefix, re-add "0x"
      params_hex = "0x" <> String.slice(calldata, 10..-1//1)
      assert {:ok, [42, true]} = Onchain.ABI.decode_response("(uint256,bool)", params_hex)
    end
  end

  describe "decode_types/2 (alias of decode_response/2)" do
    test "matches decode_response/2 on success" do
      hex = "0x" <> String.duplicate("0", 62) <> "0a"
      assert Onchain.ABI.decode_types("(uint256)", hex) == Onchain.ABI.decode_response("(uint256)", hex)
      assert {:ok, [10]} = Onchain.ABI.decode_types("(uint256)", hex)
    end

    test "matches decode_response/2 on multi-value decoding" do
      hex = "0x" <> String.duplicate("0", 62) <> "0a" <> String.duplicate("0", 62) <> "14"
      assert Onchain.ABI.decode_types("(uint256,uint256)", hex) == Onchain.ABI.decode_response("(uint256,uint256)", hex)
      assert {:ok, [10, 20]} = Onchain.ABI.decode_types("(uint256,uint256)", hex)
    end

    test "matches decode_response/2 on invalid hex" do
      assert Onchain.ABI.decode_types("(uint256)", "0xzzzz") == Onchain.ABI.decode_response("(uint256)", "0xzzzz")

      assert {:error, {:decode_error, {:invalid_hex, "0xzzzz"}}} =
               Onchain.ABI.decode_types("(uint256)", "0xzzzz")
    end

    test "matches decode_response/2 on truncated data" do
      assert Onchain.ABI.decode_types("(uint256)", "0x0102") == Onchain.ABI.decode_response("(uint256)", "0x0102")
      assert {:error, {:decode_error, _reason}} = Onchain.ABI.decode_types("(uint256)", "0x0102")
    end
  end

  describe "decode_types!/2 (alias of decode_response!/2)" do
    test "returns decoded list for valid data" do
      hex = "0x" <> String.duplicate("0", 62) <> "0a"
      assert [10] = Onchain.ABI.decode_types!("(uint256)", hex)
      assert Onchain.ABI.decode_types!("(uint256)", hex) == Onchain.ABI.decode_response!("(uint256)", hex)
    end

    test "raises on invalid hex" do
      assert_raise InvalidHex, fn ->
        Onchain.ABI.decode_types!("(uint256)", "0xzzzz")
      end
    end

    test "raises on malformed ABI data" do
      assert_raise MatchError, fn ->
        Onchain.ABI.decode_types!("(uint256)", "0x0102")
      end
    end
  end

  describe "decode_hex_call/3" do
    test "round-trip: encode_call then decode_call recovers args" do
      addr = <<1::160>>
      {:ok, calldata} = Onchain.ABI.encode_hex_call("transfer(address,uint256)", [addr, 1000])
      assert {:ok, [^addr, 1000]} = Onchain.ABI.decode_hex_call("transfer(address,uint256)", calldata)
    end

    test "decodes function with empty args" do
      {:ok, calldata} = Onchain.ABI.encode_hex_call("totalSupply()", [])
      assert {:ok, []} = Onchain.ABI.decode_hex_call("totalSupply()", calldata)
    end

    test "returns :calldata_too_short for data shorter than 4 bytes" do
      assert {:error, {:decode_error, :calldata_too_short}} =
               Onchain.ABI.decode_hex_call("transfer(address,uint256)", "0x010203")
    end

    test "returns :selector_mismatch when first 4 bytes don't match" do
      bogus = "0x" <> String.duplicate("aa", 4) <> String.duplicate("00", 64)

      assert {:error, {:decode_error, :selector_mismatch}} =
               Onchain.ABI.decode_hex_call("transfer(address,uint256)", bogus)
    end

    test "returns {:invalid_hex, _} for non-hex input" do
      assert {:error, {:decode_error, {:invalid_hex, "0xzzzz"}}} =
               Onchain.ABI.decode_hex_call("transfer(address,uint256)", "0xzzzz")
    end

    test "wraps upstream {:error, atom} as {:decode_error, atom} for malformed payload after matching selector" do
      {:ok, full} = Onchain.ABI.encode_hex_call("transfer(address,uint256)", [<<1::160>>, 1000])
      # Keep "0x" + 4-byte selector + a few bytes of malformed args
      truncated = String.slice(full, 0, 14)

      assert {:error, {:decode_error, _reason}} =
               Onchain.ABI.decode_hex_call("transfer(address,uint256)", truncated)
    end
  end

  describe "decode_hex_call!/3" do
    test "returns decoded args directly on success" do
      addr = <<1::160>>
      {:ok, calldata} = Onchain.ABI.encode_hex_call("transfer(address,uint256)", [addr, 1000])
      assert [^addr, 1000] = Onchain.ABI.decode_hex_call!("transfer(address,uint256)", calldata)
    end

    test "raises InvalidHex on bad hex" do
      assert_raise InvalidHex, fn ->
        Onchain.ABI.decode_hex_call!("transfer(address,uint256)", "0xzzzz")
      end
    end

    test "raises MatchError on selector mismatch" do
      bogus = "0x" <> String.duplicate("aa", 4) <> String.duplicate("00", 64)

      assert_raise MatchError, fn ->
        Onchain.ABI.decode_hex_call!("transfer(address,uint256)", bogus)
      end
    end

    test "raises on malformed payload after matching selector" do
      {:ok, full} = Onchain.ABI.encode_hex_call("transfer(address,uint256)", [<<1::160>>, 1000])
      truncated = String.slice(full, 0, 14)

      assert_raise MatchError, fn ->
        Onchain.ABI.decode_hex_call!("transfer(address,uint256)", truncated)
      end
    end
  end

  describe "decode_hex_error/2" do
    test "decodes single-error revert" do
      {:ok, revert_data} = Onchain.ABI.encode_hex_call("MyError(uint256)", [42])

      assert {:ok, %{error: "MyError", args: [42]}} =
               Onchain.ABI.decode_hex_error(revert_data, ["MyError(uint256)"])
    end

    test "matches second definition when first doesn't" do
      addr = <<1::160>>
      {:ok, revert_data} = Onchain.ABI.encode_hex_call("Second(address,uint256)", [addr, 99])

      assert {:ok, %{error: "Second", args: [^addr, 99]}} =
               Onchain.ABI.decode_hex_error(revert_data, ["First()", "Second(address,uint256)"])
    end

    test "returns :calldata_too_short for data shorter than 4 bytes" do
      assert {:error, {:decode_error, :calldata_too_short}} =
               Onchain.ABI.decode_hex_error("0x010203", ["MyError(uint256)"])
    end

    test "returns :no_match when no definition matches" do
      bogus = "0x" <> String.duplicate("aa", 4) <> String.duplicate("00", 64)

      assert {:error, {:decode_error, :no_match}} =
               Onchain.ABI.decode_hex_error(bogus, ["MyError(uint256)"])
    end

    test "returns {:invalid_hex, _} for non-hex input" do
      assert {:error, {:decode_error, {:invalid_hex, "0xzzzz"}}} =
               Onchain.ABI.decode_hex_error("0xzzzz", ["MyError(uint256)"])
    end

    test "wraps upstream {:error, atom} as {:decode_error, atom} for malformed payload after matching selector" do
      {:ok, full} = Onchain.ABI.encode_hex_call("MyError(uint256)", [42])
      # Keep "0x" + 4-byte selector + a few bytes of malformed args
      truncated = String.slice(full, 0, 14)

      assert {:error, {:decode_error, _reason}} =
               Onchain.ABI.decode_hex_error(truncated, ["MyError(uint256)"])
    end
  end

  describe "decode_hex_error!/2" do
    test "returns decoded map directly on success" do
      {:ok, revert_data} = Onchain.ABI.encode_hex_call("MyError(uint256)", [42])

      assert %{error: "MyError", args: [42]} =
               Onchain.ABI.decode_hex_error!(revert_data, ["MyError(uint256)"])
    end

    test "raises InvalidHex on bad hex" do
      assert_raise InvalidHex, fn ->
        Onchain.ABI.decode_hex_error!("0xzzzz", ["MyError(uint256)"])
      end
    end

    test "raises MatchError on no-match" do
      bogus = "0x" <> String.duplicate("aa", 4) <> String.duplicate("00", 64)

      assert_raise MatchError, fn ->
        Onchain.ABI.decode_hex_error!(bogus, ["MyError(uint256)"])
      end
    end
  end

  # Hand-built non-canonical payloads exercising hieroglyph's three documented
  # strict-mode classes. Default (no opts) stays permissive.
  describe "strict decode mode" do
    # Non-zero high padding, last byte = 1. Canonical uint8/int8/bool of 1 is 31
    # zero bytes then 0x01; this puts 0x01 in the high byte as well.
    @dirty_word <<1>> <> :binary.copy(<<0>>, 30) <> <<1>>
    @dirty_hex Onchain.Hex.encode(@dirty_word)
    # Canonical uint256(10) plus an extra 32-byte zero word.
    @trailing_hex Onchain.Hex.encode(<<10::256, 0::256>>)
    # (string)/(bytes) head: offset 0x20, length 0xFFFFFFFF, no payload bytes.
    @overlong_hex Onchain.Hex.encode(<<32::256, 0xFFFFFFFF::256>>)

    defp selector_prefixed(signature, payload_hex) do
      <<"0x", selector::binary-size(8), _::binary>> = Onchain.ABI.encode_hex_call!(signature, [1])
      "0x" <> selector <> String.trim_leading(payload_hex, "0x")
    end

    test "without opts, dirty integer padding still decodes (permissive default)" do
      assert {:ok, [n]} = Onchain.ABI.decode_response("(uint8)", @dirty_hex)
      assert is_integer(n) and n > 1
      assert Onchain.ABI.decode_response("(uint8)", @dirty_hex, []) == Onchain.ABI.decode_response("(uint8)", @dirty_hex)
    end

    test "canonical payload succeeds with strict: true" do
      hex = "0x" <> String.duplicate("0", 62) <> "0a"
      assert {:ok, [10]} = Onchain.ABI.decode_response("(uint256)", hex, strict: true)
      assert [10] = Onchain.ABI.decode_response!("(uint256)", hex, strict: true)
    end

    test "rejects non-zero high padding on bool, uint, and int" do
      padding_uint = {:non_canonical_padding, %{type: {:uint, 8}}}
      padding_int = {:non_canonical_padding, %{type: {:int, 8}}}

      assert {:error, {:decode_error, {:strict_violation, ^padding_uint}}} =
               Onchain.ABI.decode_response("(uint8)", @dirty_hex, strict: true)

      assert {:error, {:decode_error, {:strict_violation, ^padding_uint}}} =
               Onchain.ABI.decode_response("(bool)", @dirty_hex, strict: true)

      assert {:error, {:decode_error, {:strict_violation, ^padding_int}}} =
               Onchain.ABI.decode_response("(int8)", @dirty_hex, strict: true)

      assert Onchain.ABI.decode_types("(uint8)", @dirty_hex, strict: true) ==
               Onchain.ABI.decode_response("(uint8)", @dirty_hex, strict: true)
    end

    test "rejects trailing bytes after the declared payload" do
      assert {:error, {:decode_error, {:strict_violation, {:trailing_bytes, 32}}}} =
               Onchain.ABI.decode_response("(uint256)", @trailing_hex, strict: true)
    end

    test "rejects string/bytes length prefixes that exceed available data" do
      string_detail = {:length_out_of_bounds, %{type: :string, length: 4_294_967_295, available: 0}}
      bytes_detail = {:length_out_of_bounds, %{type: :bytes, length: 4_294_967_295, available: 0}}

      assert {:error, {:decode_error, {:strict_violation, ^string_detail}}} =
               Onchain.ABI.decode_response("(string)", @overlong_hex, strict: true)

      assert {:error, {:decode_error, {:strict_violation, ^bytes_detail}}} =
               Onchain.ABI.decode_response("(bytes)", @overlong_hex, strict: true)
    end

    test "decode_call/3 and decode_error/3 wrap strict_violation in {:decode_error, _}" do
      dirty_call = selector_prefixed("foo(uint8)", @dirty_hex)
      dirty_revert = selector_prefixed("Err(uint8)", @dirty_hex)
      padding = {:non_canonical_padding, %{type: {:uint, 8}}}

      assert {:error, {:decode_error, {:strict_violation, ^padding}}} =
               Onchain.ABI.decode_hex_call("foo(uint8)", dirty_call, strict: true)

      assert {:error, {:decode_error, {:strict_violation, ^padding}}} =
               Onchain.ABI.decode_hex_error(dirty_revert, ["Err(uint8)"], strict: true)
    end

    test "bang variants raise on strict_violation" do
      dirty_call = selector_prefixed("foo(uint8)", @dirty_hex)
      dirty_revert = selector_prefixed("Err(uint8)", @dirty_hex)

      assert_raise RuntimeError, ~r/strict_violation/, fn ->
        Onchain.ABI.decode_response!("(uint8)", @dirty_hex, strict: true)
      end

      assert_raise RuntimeError, ~r/strict_violation/, fn ->
        Onchain.ABI.decode_types!("(uint8)", @dirty_hex, strict: true)
      end

      assert_raise MatchError, fn ->
        Onchain.ABI.decode_hex_call!("foo(uint8)", dirty_call, strict: true)
      end

      assert_raise MatchError, fn ->
        Onchain.ABI.decode_hex_error!(dirty_revert, ["Err(uint8)"], strict: true)
      end
    end
  end
end
