defmodule ABI.DecodeErrorTest do
  use ExUnit.Case, async: true

  alias ABI.FunctionSelector

  doctest ABI, only: [decode_error: 3]

  describe "decode_error/2 — selector match" do
    test "single-error definition: matches and decodes args" do
      revert_data = ABI.encode("InsufficientBalance(uint256,uint256)", [10, 100])

      assert {:ok, %{error: "InsufficientBalance", args: [10, 100]}} =
               ABI.decode_error(revert_data, ["InsufficientBalance(uint256,uint256)"])
    end

    test "multi-error list: first matching definition wins" do
      revert_data = ABI.encode("Unauthorized(address)", [<<1::160>>])

      assert {:ok, %{error: "Unauthorized", args: [<<1::160>>]}} =
               ABI.decode_error(revert_data, [
                 "InsufficientBalance(uint256,uint256)",
                 "Unauthorized(address)",
                 "NotFound()"
               ])
    end

    test "zero-arg error: returns empty args list" do
      revert_data = ABI.encode("NotFound()", [])

      assert {:ok, %{error: "NotFound", args: []}} =
               ABI.decode_error(revert_data, ["NotFound()"])
    end

    test "accepts pre-parsed FunctionSelector struct in the list" do
      sel = %FunctionSelector{
        function: "InsufficientBalance",
        types: [%{type: {:uint, 256}}, %{type: {:uint, 256}}]
      }

      revert_data = ABI.encode(sel, [10, 100])

      assert {:ok, %{error: "InsufficientBalance", args: [10, 100]}} =
               ABI.decode_error(revert_data, [sel])
    end

    test "accepts mixed strings and FunctionSelector structs in the list" do
      sel = %FunctionSelector{function: "NotFound", types: []}
      revert_data = ABI.encode("Unauthorized(address)", [<<2::160>>])

      assert {:ok, %{error: "Unauthorized", args: [<<2::160>>]}} =
               ABI.decode_error(revert_data, [sel, "Unauthorized(address)"])
    end
  end

  describe "decode_error/2 — error paths" do
    test "returns :calldata_too_short when fewer than 4 bytes" do
      assert {:error, :calldata_too_short} =
               ABI.decode_error(<<0xA9, 0x05>>, ["NotFound()"])
    end

    test "returns :calldata_too_short when revert_data is empty" do
      assert {:error, :calldata_too_short} =
               ABI.decode_error(<<>>, ["NotFound()"])
    end

    test "returns :calldata_too_short at exactly one byte short" do
      # The guard is `byte_size(revert_data) < 4`, so 3 bytes is the
      # boundary case: one byte fewer than a selector. Anything looser
      # falls through to the `<<actual::binary-size(4), _::binary>>` match
      # and raises MatchError instead of returning the tagged error.
      assert {:error, :calldata_too_short} =
               ABI.decode_error(<<0x08, 0xC3, 0x79>>, ["NotFound()"])

      assert {:error, :calldata_too_short} =
               ABI.decode_error(<<0x08, 0xC3, 0x79>>, [])
    end

    test "returns :no_match when no definition's selector matches" do
      # 4 bytes that won't collide with NotFound() selector.
      bad_revert = <<0xDE, 0xAD, 0xBE, 0xEF>>

      assert {:error, :no_match} =
               ABI.decode_error(bad_revert, ["NotFound()"])
    end

    test "returns :no_match when the definition list is empty" do
      revert_data = ABI.encode("NotFound()", [])

      assert {:error, :no_match} =
               ABI.decode_error(revert_data, [])
    end

    test "raises on malformed payload after selector match (mirrors decode_call/3)" do
      # Compute the correct selector for InsufficientBalance(uint256,uint256),
      # then append a too-short payload (only 32 bytes instead of 64).
      selector = ABI.method_id("InsufficientBalance(uint256,uint256)")
      truncated_payload = <<0::256>>
      revert_data = selector <> truncated_payload

      assert_raise MatchError, fn ->
        ABI.decode_error(revert_data, ["InsufficientBalance(uint256,uint256)"])
      end
    end

    test "returns strict violation for non-canonical payload when strict" do
      selector = ABI.method_id("Bad(uint8)")
      revert_data = selector <> <<1::248, 5>>

      assert {:error, {:strict_violation, _detail}} =
               ABI.decode_error(revert_data, ["Bad(uint8)"], strict: true)
    end
  end

  describe "decode_error/2 — built-in errors" do
    test "Error(string) resolves with empty error_definitions" do
      revert_data = ABI.encode("Error(string)", ["insufficient balance"])

      assert {:ok, %{error: "Error", args: ["insufficient balance"]}} =
               ABI.decode_error(revert_data, [])
    end

    test "Error(string) selector is 0x08c379a0" do
      revert_data = ABI.encode("Error(string)", ["nope"])
      assert <<0x08, 0xC3, 0x79, 0xA0, _payload::binary>> = revert_data
    end

    test "Panic(uint256) resolves the panic code with empty error_definitions" do
      for code <- [0x01, 0x11, 0x12, 0x32] do
        revert_data = ABI.encode("Panic(uint256)", [code])

        assert {:ok, %{error: "Panic", args: [^code]}} =
                 ABI.decode_error(revert_data, [])
      end
    end

    test "Panic(uint256) selector is 0x4e487b71" do
      revert_data = ABI.encode("Panic(uint256)", [0x11])
      assert <<0x4E, 0x48, 0x7B, 0x71, _payload::binary>> = revert_data
    end

    test "built-ins resolve even when a non-colliding user list is supplied" do
      revert_data = ABI.encode("Error(string)", ["reverted"])

      assert {:ok, %{error: "Error", args: ["reverted"]}} =
               ABI.decode_error(revert_data, ["NotFound()", "Unauthorized(address)"])
    end

    test "user definitions are consulted before the built-in fallback" do
      # A non-canonical Error(...) definition proves the user list wins before
      # the built-in fallback when its distinct selector matches. The exact
      # built-in signature is also accepted explicitly below, preserving the
      # pre-existing user-supplied Error(string) path.
      user_error = %FunctionSelector{
        function: "Error",
        types: [%{type: :string}, %{type: :string}]
      }

      revert_data = ABI.encode(user_error, ["a", "b"])

      assert {:ok, %{error: "Error", args: ["a", "b"]}} =
               ABI.decode_error(revert_data, [user_error])

      # And a user definition with the canonical built-in signature still
      # resolves (no back-compat break): supplying "Error(string)" yourself
      # behaves exactly as before built-ins existed.
      canonical = ABI.encode("Error(string)", ["boom"])

      assert {:ok, %{error: "Error", args: ["boom"]}} =
               ABI.decode_error(canonical, ["Error(string)"])
    end
  end

  describe "decode_error/2 — selector independence" do
    test "two errors with different signatures produce different selectors" do
      # Sanity check: we rely on selector uniqueness to disambiguate.
      sel_a = ABI.method_id("InsufficientBalance(uint256,uint256)")
      sel_b = ABI.method_id("Unauthorized(address)")
      sel_c = ABI.method_id("NotFound()")

      assert sel_a != sel_b
      assert sel_b != sel_c
      assert sel_a != sel_c
    end
  end
end
