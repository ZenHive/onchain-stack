defmodule ABITest do
  use ExUnit.Case, async: true
  use ABI.Hex

  alias ABI.FunctionSelector

  doctest ABI

  describe "empty argument list" do
    # `weth.deposit()`, `rocket_pool.deposit()`, and similar `f()` calls produce
    # calldata that's literally just the 4-byte selector — zero ABI-encoded
    # args. The roundtrip property suite never generates an empty arg list, so
    # this path was untested.

    test "encode/2 with `f()` signature produces only the 4-byte selector" do
      encoded = ABI.encode("deposit()", [])
      # keccak("deposit()")[0..3] — the selector used by WETH9 deposit and
      # Rocket Pool deposit.
      assert encoded == <<0xD0, 0xE3, 0x0D, 0xB0>>
      assert byte_size(encoded) == 4
    end

    test "encode/2 with FunctionSelector struct produces only the selector" do
      selector = %FunctionSelector{function: "deposit", types: []}
      encoded = ABI.encode(selector, [])
      assert encoded == <<0xD0, 0xE3, 0x0D, 0xB0>>
      assert byte_size(encoded) == 4
    end

    test "encode/2 with nil-function selector and empty types produces empty bytes" do
      selector = %FunctionSelector{function: nil, types: []}
      assert ABI.encode(selector, []) == <<>>
    end

    test "decode/3 of empty payload against `f()` returns []" do
      assert ABI.decode("deposit()", <<>>) == []
    end

    test "decode/3 of empty payload against FunctionSelector with no types returns []" do
      assert ABI.decode(%FunctionSelector{types: []}, <<>>) == []
    end
  end

  describe "method_id/1" do
    test "produces the canonical 4-byte selector for known mainnet signatures" do
      assert ABI.method_id("transfer(address,uint256)") == <<0xA9, 0x05, 0x9C, 0xBB>>

      assert ABI.method_id("transferFrom(address,address,uint256)") ==
               <<0x23, 0xB8, 0x72, 0xDD>>

      assert ABI.method_id("deposit()") == <<0xD0, 0xE3, 0x0D, 0xB0>>
      assert ABI.method_id("withdraw(uint256)") == <<0x2E, 0x1A, 0x7D, 0x4D>>
    end

    test "accepts a FunctionSelector struct and a signature string equivalently" do
      [selector] =
        ABI.parse_specification([%{"type" => "function", "name" => "deposit", "inputs" => []}])

      assert ABI.method_id(selector) == ABI.method_id("deposit()")
    end

    test "returns empty binary for selectors with function: nil" do
      selector = %FunctionSelector{
        function: nil,
        types: [%{type: :address}]
      }

      assert ABI.method_id(selector) == <<>>
    end
  end

  describe "encode_call/3" do
    test "accepts a signature string and returns selector-prefixed calldata" do
      expected =
        ~h[0xa9059cbb00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000064]

      assert ABI.encode_call("transfer(address,uint256)", [<<1::160>>, 100], []) == expected
    end

    test "accepts a FunctionSelector struct and returns the same blob as a signature string" do
      selector = %FunctionSelector{
        function: "transfer",
        types: [%{type: :address}, %{type: {:uint, 256}}]
      }

      assert ABI.encode_call(selector, [<<1::160>>, 100], []) ==
               ABI.encode_call("transfer(address,uint256)", [<<1::160>>, 100], [])
    end

    test "raises ArgumentError for FunctionSelector structs without a function name" do
      selector = %FunctionSelector{
        function: nil,
        types: [%{type: {:uint, 256}}]
      }

      message = "encode_call/3 requires a function name; use encode/2 for payload-only data"

      assert_raise ArgumentError, message, fn ->
        ABI.encode_call(selector, [100], [])
      end
    end

    test "api declaration composes with decode_call/3" do
      entry = Enum.find(ABI.__api__(), &(&1.name == :encode_call))

      assert entry.hints.composes_with == [:decode_call]
    end
  end

  describe "encode_constructor/2" do
    test "returns selector-less ABI-encoded args for a constructor selector" do
      [selector] =
        ABI.parse_specification([
          %{
            "type" => "constructor",
            "stateMutability" => "nonpayable",
            "inputs" => [%{"name" => "supply", "type" => "uint256"}]
          }
        ])

      encoded = ABI.encode_constructor(selector, [1000])

      assert encoded == <<1000::256>>
      assert byte_size(encoded) == 32
    end

    test "round-trips through decode/3 against the constructor's parsed types" do
      [selector] =
        ABI.parse_specification([
          %{
            "type" => "constructor",
            "stateMutability" => "nonpayable",
            "inputs" => [
              %{"name" => "owner", "type" => "address"},
              %{"name" => "supply", "type" => "uint256"},
              %{"name" => "symbol", "type" => "string"}
            ]
          }
        ])

      args = [<<1::160>>, 1_000_000, "ABI"]

      assert ABI.decode(selector, ABI.encode_constructor(selector, args)) == args
    end

    test "empty-args constructor returns the empty binary" do
      selector = %FunctionSelector{function_type: :constructor, types: []}

      assert ABI.encode_constructor(selector, []) == <<>>
    end

    test "accepts a constructor selector even when a stray function name is present" do
      selector = %FunctionSelector{
        function: "ignored",
        function_type: :constructor,
        types: [%{type: {:uint, 256}}]
      }

      assert ABI.encode_constructor(selector, [7]) == <<7::256>>
    end

    test "raises ArgumentError for a non-constructor selector" do
      selector = %FunctionSelector{
        function: "transfer",
        function_type: :function,
        types: []
      }

      message =
        "encode_constructor/2 requires a constructor selector (function_type: :constructor)"

      assert_raise ArgumentError, message, fn ->
        ABI.encode_constructor(selector, [])
      end
    end

    test "api declaration is present" do
      entry = Enum.find(ABI.__api__(), &(&1.name == :encode_constructor))

      assert entry
      assert entry.hints.composes_with == [:decode, :parse_specification]
    end
  end

  describe "decode_call/3" do
    test "round-trips through encode/2 for mixed static+dynamic args" do
      sig = "swap(address,uint256,bytes)"
      args = [<<1::160>>, 999, "payload"]
      calldata = ABI.encode(sig, args)

      assert {:ok, ^args} = ABI.decode_call(sig, calldata)
    end

    test "round-trips for empty-args calls" do
      calldata = ABI.encode("deposit()", [])
      assert {:ok, []} = ABI.decode_call("deposit()", calldata)
    end

    test "accepts a FunctionSelector struct" do
      [selector] =
        ABI.parse_specification([
          %{
            "type" => "function",
            "name" => "transfer",
            "inputs" => [
              %{"type" => "address", "name" => "to"},
              %{"type" => "uint256", "name" => "amount"}
            ]
          }
        ])

      calldata = ABI.encode(selector, [<<1::160>>, 100])
      assert {:ok, [<<1::160>>, 100]} = ABI.decode_call(selector, calldata)
    end

    test "returns :selector_mismatch when prefix doesn't match the signature" do
      # `transfer` calldata decoded against `withdraw(uint256)`.
      calldata = ABI.encode("transfer(address,uint256)", [<<1::160>>, 100])

      assert {:error, :selector_mismatch} =
               ABI.decode_call("withdraw(uint256)", calldata)
    end

    test "returns :calldata_too_short for fewer than 4 bytes" do
      sig = "deposit()"
      three_bytes = <<0xD0, 0xE3, 0x0D>>
      assert {:error, :calldata_too_short} = ABI.decode_call(sig, <<>>)
      assert {:error, :calldata_too_short} = ABI.decode_call(sig, <<0xD0>>)
      assert {:error, :calldata_too_short} = ABI.decode_call(sig, three_bytes)
    end

    test "returns :no_function_name when the selector has no function name" do
      selector = %FunctionSelector{
        function: nil,
        types: [%{type: {:uint, 256}}]
      }

      # Anything ≥ 4 bytes; precedence is checked before length.
      assert {:error, :no_function_name} =
               ABI.decode_call(selector, <<0::8*32>>)
    end

    test "passes opts through to decode/3 (decode_structs: true)" do
      [selector] =
        ABI.parse_specification([
          %{
            "type" => "function",
            "name" => "set",
            "inputs" => [
              %{"type" => "uint256", "name" => "first_field"},
              %{"type" => "bool", "name" => "second_field"}
            ]
          }
        ])

      calldata = ABI.encode(selector, [42, true])

      assert {:ok, %{first_field: 42, second_field: true}} =
               ABI.decode_call(selector, calldata, decode_structs: true)
    end
  end

  describe "get_abi_item/3" do
    test "returns {:ok, selector} for a unique name match" do
      abi =
        ABI.parse_specification([
          %{
            "type" => "function",
            "name" => "transfer",
            "inputs" => [
              %{"type" => "address", "name" => "to"},
              %{"type" => "uint256", "name" => "amount"}
            ]
          }
        ])

      assert {:ok, %FunctionSelector{function: "transfer"}} =
               ABI.get_abi_item(abi, "transfer", nil)
    end

    test "returns {:error, :not_found} when no fragment matches the name" do
      abi =
        ABI.parse_specification([
          %{"type" => "function", "name" => "only", "inputs" => []}
        ])

      assert {:error, :not_found} = ABI.get_abi_item(abi, "missing", nil)
    end

    test "returns {:error, {:ambiguous, _}} for overloads without arg_types" do
      abi =
        ABI.parse_specification([
          %{"type" => "function", "name" => "pick", "inputs" => [%{"type" => "uint256"}]},
          %{
            "type" => "function",
            "name" => "pick",
            "inputs" => [
              %{"type" => "uint256"},
              %{"type" => "address"}
            ]
          }
        ])

      assert {:error, {:ambiguous, matches}} = ABI.get_abi_item(abi, "pick", nil)
      assert length(matches) == 2
      assert Enum.all?(matches, &match?(%FunctionSelector{function: "pick"}, &1))
    end

    test "arg_types disambiguates overloads to the matching arity and types" do
      abi =
        ABI.parse_specification([
          %{"type" => "function", "name" => "pick", "inputs" => [%{"type" => "uint256"}]},
          %{
            "type" => "function",
            "name" => "pick",
            "inputs" => [
              %{"type" => "uint256"},
              %{"type" => "address"}
            ]
          }
        ])

      assert {:ok, %FunctionSelector{types: [%{type: {:uint, 256}}]}} =
               ABI.get_abi_item(abi, "pick", [{:uint, 256}])

      assert {:ok,
              %FunctionSelector{
                types: [%{type: {:uint, 256}}, %{type: :address}]
              }} =
               ABI.get_abi_item(abi, "pick", [{:uint, 256}, :address])
    end

    test "returns {:error, :not_found} when arg_types match no overload" do
      abi =
        ABI.parse_specification([
          %{"type" => "function", "name" => "pick", "inputs" => [%{"type" => "uint256"}]},
          %{
            "type" => "function",
            "name" => "pick",
            "inputs" => [
              %{"type" => "uint256"},
              %{"type" => "address"}
            ]
          }
        ])

      assert {:error, :not_found} = ABI.get_abi_item(abi, "pick", [:address])
    end

    test "returns {:error, :not_found} when arg_types miss a unique name match" do
      abi =
        ABI.parse_specification([
          %{"type" => "function", "name" => "pick", "inputs" => [%{"type" => "uint256"}]}
        ])

      assert {:error, :not_found} = ABI.get_abi_item(abi, "pick", [:address])
    end

    test "disambiguates tuple and array input types" do
      abi =
        ABI.parse_specification([
          %{
            "type" => "function",
            "name" => "go",
            "inputs" => [%{"type" => "address[]"}]
          },
          %{
            "type" => "function",
            "name" => "go",
            "inputs" => [
              %{
                "type" => "tuple",
                "components" => [
                  %{"type" => "uint256"},
                  %{"type" => "bytes"}
                ]
              }
            ]
          }
        ])

      assert {:ok, %FunctionSelector{types: [%{type: {:array, :address}}]}} =
               ABI.get_abi_item(abi, "go", [{:array, :address}])

      assert {:ok,
              %FunctionSelector{
                types: [
                  %{
                    type: {:tuple, [%{type: {:uint, 256}}, %{type: :bytes}]}
                  }
                ]
              }} =
               ABI.get_abi_item(abi, "go", [
                 {:tuple, [%{type: {:uint, 256}}, %{type: :bytes}]}
               ])
    end
  end

  describe "format_abi_item/1" do
    test "formats a plain function selector to its canonical signature" do
      [selector] =
        ABI.parse_specification([
          %{
            "type" => "function",
            "name" => "transfer",
            "inputs" => [
              %{"type" => "address", "name" => "to"},
              %{"type" => "uint256", "name" => "amount"}
            ]
          }
        ])

      assert ABI.format_abi_item(selector) == "transfer(address,uint256)"
    end

    test "expands tuples and renders dynamic/fixed arrays" do
      selector = %FunctionSelector{
        function: "swap",
        types: [
          %{type: {:tuple, [%{type: :address}, %{type: {:uint, 256}}]}},
          %{type: {:array, {:uint, 256}}},
          %{type: {:array, :address, 3}}
        ]
      }

      assert ABI.format_abi_item(selector) == "swap((address,uint256),uint256[],address[3])"
    end

    test "formats anonymous (constructor) fragments without a leading name" do
      [selector] =
        ABI.parse_specification([
          %{
            "type" => "constructor",
            "inputs" => [%{"type" => "uint8", "name" => "_numProposals"}]
          }
        ])

      assert selector.function == nil
      assert ABI.format_abi_item(selector) == "(uint8)"
    end

    test "produces the exact string method_id/1 and event_signature/1 hash" do
      sig = "Transfer(address,address,uint256)"
      selector = FunctionSelector.decode(sig)

      # Same canonical builder feeds the hashers, so the formatted string,
      # re-hashed, reproduces the published selector / topic.
      formatted = ABI.format_abi_item(selector)
      assert formatted == sig
      assert ABI.method_id(formatted) == ABI.method_id(sig)
      assert ABI.event_signature(formatted) == ABI.event_signature(sig)
    end

    test "round-trips: parse_specification |> format_abi_item |> decode preserves types" do
      [selector] =
        ABI.parse_specification([
          %{
            "type" => "function",
            "name" => "go",
            "inputs" => [
              %{"name" => "xs", "type" => "address[]"},
              %{"name" => "n", "type" => "uint256"},
              %{
                "name" => "s",
                "type" => "tuple",
                "components" => [
                  %{"name" => "a", "type" => "uint256"},
                  %{"name" => "b", "type" => "bytes"}
                ]
              },
              %{"name" => "fixed", "type" => "bytes32[2]"}
            ]
          }
        ])

      formatted = ABI.format_abi_item(selector)
      reparsed = FunctionSelector.decode(formatted)

      # The canonical string is name-free, so re-parsing yields the same type
      # tree; formatting is idempotent (the round-trip fixed point).
      assert reparsed.function == selector.function
      assert ABI.format_abi_item(reparsed) == formatted
    end
  end

  describe "strict decode mode" do
    test "decode/3 rejects non-zero uint high padding when strict" do
      bad_uint8 = <<1::248, 5>>

      assert {:error, {:strict_violation, _detail}} =
               ABI.decode("(uint8)", bad_uint8, strict: true)
    end

    test "decode/3 rejects invalid int sign extension when strict" do
      bad_int8 = <<0::248, 0xFF>>

      assert {:error, {:strict_violation, _detail}} =
               ABI.decode("(int8)", bad_int8, strict: true)
    end

    test "decode/3 rejects non-zero bool high padding when strict" do
      bad_bool = <<1::248, 1>>

      assert {:error, {:strict_violation, _detail}} =
               ABI.decode("(bool)", bad_bool, strict: true)
    end

    test "decode/3 rejects trailing bytes when strict" do
      payload = ABI.encode("(uint256)", [{1}]) <> <<0>>

      assert {:error, {:strict_violation, _detail}} =
               ABI.decode("(uint256)", payload, strict: true)
    end

    test "decode/3 rejects string length prefixes beyond available data when strict" do
      payload = <<32::256, 5::256, "abc">>

      assert {:error, {:strict_violation, _detail}} =
               ABI.decode("(string)", payload, strict: true)
    end

    test "decode/3 rejects bytes length prefixes beyond available data when strict" do
      payload = <<32::256, 5::256, 1, 2, 3>>

      assert {:error, {:strict_violation, _detail}} =
               ABI.decode("(bytes)", payload, strict: true)
    end

    test "decode/3 keeps permissive default behavior" do
      bad_uint8 = <<1::248, 5>>

      assert [decoded] = ABI.decode("(uint8)", bad_uint8)
      assert decoded == :binary.decode_unsigned(bad_uint8)
    end

    test "decode_call/3 returns strict violations as tagged errors" do
      payload = <<1::248, 5>>
      calldata = ABI.method_id("set(uint8)") <> payload

      assert {:error, {:strict_violation, _detail}} =
               ABI.decode_call("set(uint8)", calldata, strict: true)
    end
  end
end
