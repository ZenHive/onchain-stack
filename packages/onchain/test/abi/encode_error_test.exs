defmodule ABI.EncodeErrorTest do
  use ExUnit.Case, async: true

  alias ABI.FunctionSelector

  doctest ABI, only: [encode_error: 3]

  describe "encode_error/3" do
    test "accepts a signature string and returns selector-prefixed revert data" do
      revert_data = ABI.encode_error("InsufficientBalance(uint256,uint256)", [10, 100], [])

      assert byte_size(revert_data) == 4 + 64
      assert ABI.method_id("InsufficientBalance(uint256,uint256)") == binary_part(revert_data, 0, 4)
    end

    test "accepts a FunctionSelector struct and returns the same blob as a signature string" do
      selector = %FunctionSelector{
        function: "InsufficientBalance",
        types: [%{type: {:uint, 256}}, %{type: {:uint, 256}}]
      }

      assert ABI.encode_error(selector, [10, 100], []) ==
               ABI.encode_error("InsufficientBalance(uint256,uint256)", [10, 100], [])
    end

    test "raises ArgumentError for FunctionSelector structs without a function name" do
      selector = %FunctionSelector{
        function: nil,
        types: [%{type: {:uint, 256}}]
      }

      message = "encode_error/3 requires a function name; use encode/2 for payload-only data"

      assert_raise ArgumentError, message, fn ->
        ABI.encode_error(selector, [100], [])
      end
    end

    test "api declaration composes with decode_error/2" do
      entry = Enum.find(ABI.__api__(), &(&1.name == :encode_error))

      assert entry.hints.composes_with == [:decode_error]
    end
  end

  describe "encode_error/3 — round-trip with decode_error/2" do
    test "single-error definition" do
      revert_data =
        ABI.encode_error("InsufficientBalance(uint256,uint256)", [10, 100], [])

      assert {:ok, %{error: "InsufficientBalance", args: [10, 100]}} =
               ABI.decode_error(revert_data, ["InsufficientBalance(uint256,uint256)"])
    end

    test "zero-arg error" do
      revert_data = ABI.encode_error("NotFound()", [], [])

      assert {:ok, %{error: "NotFound", args: []}} =
               ABI.decode_error(revert_data, ["NotFound()"])
    end

    test "address arg" do
      revert_data = ABI.encode_error("Unauthorized(address)", [<<1::160>>], [])

      assert {:ok, %{error: "Unauthorized", args: [<<1::160>>]}} =
               ABI.decode_error(revert_data, ["Unauthorized(address)"])
    end

    test "FunctionSelector input round-trips" do
      selector = %FunctionSelector{
        function: "InsufficientBalance",
        types: [%{type: {:uint, 256}}, %{type: {:uint, 256}}]
      }

      revert_data = ABI.encode_error(selector, [10, 100], [])

      assert {:ok, %{error: "InsufficientBalance", args: [10, 100]}} =
               ABI.decode_error(revert_data, [selector])
    end
  end
end
