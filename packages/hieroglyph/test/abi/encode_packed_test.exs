defmodule ABI.EncodePackedTest do
  use ExUnit.Case, async: true

  alias ABI.FunctionSelector
  alias ABI.Math
  alias ABI.TypeEncoder

  doctest ABI, only: [encode_packed: 2]
  doctest TypeEncoder, only: [encode_packed: 2]

  describe "encode_packed/2 — golden vectors from Solidity spec" do
    test "canonical spec example for int16, bytes1, uint16, string" do
      # Per Solidity ABI spec § Non-standard Packed Mode:
      #   int16(-1), bytes1(0x42), uint16(0x03), string("Hello, world!")
      # encodes to 0xffff42000348656c6c6f2c20776f726c6421.
      assert ABI.encode_packed(
               "spec(int16,bytes1,uint16,string)",
               [-1, <<0x42>>, 3, "Hello, world!"]
             ) ==
               <<0xFF, 0xFF, 0x42, 0x00, 0x03>> <> "Hello, world!"
    end

    test "string with no padding at the end (top-level)" do
      assert ABI.encode_packed("foo(string)", ["hello"]) == "hello"
    end

    test "bytes with no padding at the end (top-level)" do
      assert ABI.encode_packed("foo(bytes)", [<<0xDE, 0xAD, 0xBE, 0xEF>>]) ==
               <<0xDE, 0xAD, 0xBE, 0xEF>>
    end
  end

  describe "encode_packed/2 — scalar types (top-level)" do
    test "uint8: 1 byte, no padding" do
      assert ABI.encode_packed("foo(uint8)", [255]) == <<0xFF>>
      assert ABI.encode_packed("foo(uint8)", [0]) == <<0x00>>
    end

    test "uint16: 2 bytes, no padding" do
      assert ABI.encode_packed("foo(uint16)", [0x1234]) == <<0x12, 0x34>>
    end

    test "uint256: 32 bytes" do
      assert ABI.encode_packed("foo(uint256)", [1]) == <<0::248, 1>>
    end

    test "int8: 1 byte, two's complement" do
      assert ABI.encode_packed("foo(int8)", [-1]) == <<0xFF>>
      assert ABI.encode_packed("foo(int8)", [-128]) == <<0x80>>
      assert ABI.encode_packed("foo(int8)", [0]) == <<0x00>>
      assert ABI.encode_packed("foo(int8)", [127]) == <<0x7F>>
    end

    test "int16: 2 bytes, two's complement" do
      assert ABI.encode_packed("foo(int16)", [-1]) == <<0xFF, 0xFF>>
      assert ABI.encode_packed("foo(int16)", [-256]) == <<0xFF, 0x00>>
    end

    test "int overflow rejected" do
      assert_raise ArgumentError, ~r/int8/, fn ->
        ABI.encode_packed("foo(int8)", [128])
      end

      assert_raise ArgumentError, ~r/int8/, fn ->
        ABI.encode_packed("foo(int8)", [-129])
      end
    end

    test "uint overflow rejected" do
      assert_raise ArgumentError, ~r/uint8/, fn ->
        ABI.encode_packed("foo(uint8)", [256])
      end

      assert_raise ArgumentError, ~r/uint8/, fn ->
        ABI.encode_packed("foo(uint8)", [-1])
      end
    end

    test "address: 20 bytes (binary form)" do
      assert ABI.encode_packed("foo(address)", [<<1::160>>]) == <<1::160>>
    end

    test "address: 20 bytes (integer form)" do
      assert ABI.encode_packed("foo(address)", [1]) == <<0::152, 1>>
    end

    test "function: 24 bytes tight (20-byte address ++ 4-byte selector, no padding)" do
      addr = :binary.copy(<<0xAB>>, 20)
      sel = <<0xCA, 0xFE, 0xBA, 0xBE>>
      ptr = addr <> sel
      assert ABI.encode_packed("foo(function)", [ptr]) == ptr
      assert byte_size(ABI.encode_packed("foo(function)", [ptr])) == 24
    end

    test "function size mismatch raises" do
      assert_raise ArgumentError, ~r/function/, fn ->
        ABI.encode_packed("foo(function)", [<<0::8*23>>])
      end
    end

    test "function: non-binary value raises with type-specific error" do
      assert_raise ArgumentError, ~r/expected 24-byte binary/, fn ->
        ABI.encode_packed("foo(function)", [42])
      end
    end

    test "bool: 1 byte" do
      assert ABI.encode_packed("foo(bool)", [true]) == <<1>>
      assert ABI.encode_packed("foo(bool)", [false]) == <<0>>
    end

    test "bool with invalid value raises" do
      assert_raise ArgumentError, ~r/bool/, fn ->
        ABI.encode_packed("foo(bool)", [:nope])
      end
    end

    test "bytes1: exactly 1 byte" do
      assert ABI.encode_packed("foo(bytes1)", [<<0x42>>]) == <<0x42>>
    end

    test "bytes32: exactly 32 bytes" do
      thirty_two = :binary.copy(<<0xAA>>, 32)
      assert ABI.encode_packed("foo(bytes32)", [thirty_two]) == thirty_two
    end

    test "bytesN size mismatch raises" do
      assert_raise ArgumentError, ~r/bytes4/, fn ->
        ABI.encode_packed("foo(bytes4)", [<<0x42>>])
      end
    end
  end

  describe "encode_packed/2 — Merkle leaf golden vector" do
    test "address + uint256 produces 52 bytes (canonical airdrop leaf)" do
      # leaf = keccak256(abi.encodePacked(account, amount))
      # 20-byte account + 32-byte amount = 52 bytes pre-hash.
      account = <<0xB2B7C1795F19FBC28FDA77A95E59EDBB8B3709C8::160>>
      amount = 100

      packed = ABI.encode_packed("leaf(address,uint256)", [account, amount])

      assert byte_size(packed) == 52

      assert <<^account::binary-size(20), encoded::binary-size(32)>> =
               packed

      assert encoded == <<0::248, 100>>
    end
  end

  describe "encode_packed/2 — arrays (elements padded to 32 bytes)" do
    test "uint8[]: each element padded to 32 bytes" do
      result = ABI.encode_packed("foo(uint8[])", [[1, 2, 3]])

      # 3 elements × 32 bytes = 96 bytes, no length prefix
      assert byte_size(result) == 96
      assert <<0::248, 1, 0::248, 2, 0::248, 3>> == result
    end

    test "uint256[]: each element 32 bytes" do
      result = ABI.encode_packed("foo(uint256[])", [[1, 2]])
      assert byte_size(result) == 64
      assert <<0::248, 1, 0::248, 2>> == result
    end

    test "fixed-size array uint256[3]: 96 bytes total" do
      result = ABI.encode_packed("foo(uint256[3])", [[10, 20, 30]])
      assert byte_size(result) == 96
      assert <<0::248, 10, 0::248, 20, 0::248, 30>> == result
    end

    test "fixed-size array size mismatch raises" do
      assert_raise ArgumentError, ~r/size mismatch/, fn ->
        ABI.encode_packed("foo(uint256[3])", [[1, 2]])
      end
    end

    test "address[]: each element 32 bytes (left-padded uint160)" do
      result = ABI.encode_packed("foo(address[])", [[<<1::160>>, <<2::160>>]])
      assert byte_size(result) == 64
      # Inside an array, addresses are left-padded to 32 bytes per the spec.
      assert <<0::96, 1::160, 0::96, 2::160>> == result
    end

    test "string[]: each element padded to a 32-byte multiple (right-zero-pad)" do
      # "abc" → 3 bytes → padded to 32 bytes
      # "hello" → 5 bytes → padded to 32 bytes
      result = ABI.encode_packed("foo(string[])", [["abc", "hello"]])
      assert byte_size(result) == 64
      <<first::binary-size(32), second::binary-size(32)>> = result
      assert <<"abc", 0::29*8>> == first
      assert <<"hello", 0::27*8>> == second
    end

    test "bytes[]: each element padded to a 32-byte multiple (right-zero-pad)" do
      result =
        ABI.encode_packed("foo(bytes[])", [[<<0xDE, 0xAD>>, <<0xBE, 0xEF, 0x01>>]])

      assert byte_size(result) == 64
      <<first::binary-size(32), second::binary-size(32)>> = result
      assert <<0xDE, 0xAD, 0::30*8>> == first
      assert <<0xBE, 0xEF, 0x01, 0::29*8>> == second
    end

    test "string[]: element exceeding 32 bytes pads to 64-byte multiple" do
      thirty_three = String.duplicate("x", 33)
      result = ABI.encode_packed("foo(string[])", [[thirty_three]])
      assert byte_size(result) == 64
      assert binary_part(result, 0, 33) == thirty_three
      assert binary_part(result, 33, 31) == :binary.copy(<<0>>, 31)
    end
  end

  describe "encode_packed/2 — unsupported types raise" do
    test "tuple/struct as one of multiple top-level args raises" do
      sel = %FunctionSelector{
        function: "foo",
        types: [
          %{type: {:uint, 256}},
          %{type: {:tuple, [%{type: {:uint, 256}}, %{type: :address}]}}
        ]
      }

      assert_raise ArgumentError, ~r/tuple|struct/, fn ->
        ABI.encode_packed(sel, [42, {1, <<1::160>>}])
      end
    end

    test "paren-only signature parses as struct arg and raises" do
      # The parser treats "(uint8,bool)" as a single tuple parameter, not a
      # comma-separated arg list — pass one tuple value to align arity.
      assert_raise ArgumentError, ~r/tuple|struct/, fn ->
        ABI.encode_packed("(uint8,bool)", [{42, true}])
      end
    end

    test "nested array (uint256[][]) raises" do
      assert_raise ArgumentError, ~r/nested arrays/, fn ->
        ABI.encode_packed("foo(uint256[][])", [[[1, 2], [3, 4]]])
      end
    end

    test "nested array (uint256[2][]) raises" do
      assert_raise ArgumentError, ~r/nested arrays/, fn ->
        ABI.encode_packed("foo(uint256[2][])", [[[1, 2], [3, 4]]])
      end
    end

    test "tuple inside array raises" do
      sel = %FunctionSelector{
        function: "foo",
        types: [%{type: {:array, {:tuple, [%{type: {:uint, 256}}]}}}]
      }

      assert_raise ArgumentError, ~r/tuple|struct/, fn ->
        ABI.encode_packed(sel, [[{1}]])
      end
    end
  end

  describe "encode_packed/2 — input shape variants" do
    test "accepts pre-parsed FunctionSelector struct" do
      sel = %FunctionSelector{
        function: nil,
        types: [%{type: {:uint, 8}}, %{type: :bool}]
      }

      assert ABI.encode_packed(sel, [42, true]) == <<42, 1>>
    end

    test "arity mismatch raises" do
      assert_raise ArgumentError, ~r/arity mismatch/, fn ->
        ABI.encode_packed("foo(uint8,bool)", [42])
      end
    end

    test "uintN accepts a binary value (left-padded to N/8 bytes)" do
      assert ABI.encode_packed("foo(uint16)", [<<0x42>>]) == <<0x00, 0x42>>
      assert ABI.encode_packed("foo(uint16)", [<<0x12, 0x34>>]) == <<0x12, 0x34>>
    end

    test "uintN binary value too long raises" do
      assert_raise ArgumentError, ~r/uint8.*too long/, fn ->
        ABI.encode_packed("foo(uint8)", [<<0x12, 0x34>>])
      end
    end

    test "unrecognized type tag raises (fallback)" do
      sel = %FunctionSelector{function: "foo", types: [%{type: {:weird, 8}}]}

      assert_raise ArgumentError, ~r/unsupported type/, fn ->
        ABI.encode_packed(sel, [42])
      end
    end
  end

  describe "encode_packed/2 — keccak256 cross-impl spot check" do
    test "keccak256 of the spec example matches a fresh hash of the spec bytes" do
      # The byte-exact encoding is what `cast keccak --packed ...` would feed
      # into keccak256. We assert the encoding is byte-exact here; downstream
      # consumers can pass it to ABI.Math.kec/1 for the hash.
      packed =
        ABI.encode_packed(
          "spec(int16,bytes1,uint16,string)",
          [-1, <<0x42>>, 3, "Hello, world!"]
        )

      hash = Math.kec(packed)
      assert byte_size(hash) == 32

      # Spot-check: the encoding alone matches the spec — we don't depend on a
      # specific keccak vector here because the spec doesn't publish one for
      # this input. The byte-exact match against the spec's encoding example
      # is the verification.
      assert packed == <<0xFF, 0xFF, 0x42, 0x00, 0x03>> <> "Hello, world!"
    end
  end

  describe "encode_packed/2 — error contract (exact messages)" do
    # Each assertion pins the caller-facing message byte-for-byte: these are
    # the strings downstream consumers match on, so a one-character edit is a
    # contract break, not a cosmetic change.

    test "arity mismatch names both counts" do
      assert_raise ArgumentError,
                   "encode_packed arity mismatch: got 1 values for 2 types",
                   fn -> ABI.encode_packed("foo(uint8,bool)", [42]) end
    end

    test "function with a wrong-sized binary names the byte count" do
      assert_raise ArgumentError,
                   "encode_packed function: size mismatch (expected 24 bytes, got 23)",
                   fn -> ABI.encode_packed("foo(function)", [<<0::8*23>>]) end
    end

    test "function with a non-binary value inspects the value" do
      assert_raise ArgumentError,
                   "encode_packed function: expected 24-byte binary, got 42",
                   fn -> ABI.encode_packed("foo(function)", [42]) end
    end

    test "bool with a non-boolean value inspects the value" do
      assert_raise ArgumentError,
                   "encode_packed bool: invalid value :nope",
                   fn -> ABI.encode_packed("foo(bool)", [:nope]) end
    end

    test "bytesN size mismatch names the size and the actual byte count" do
      assert_raise ArgumentError,
                   "encode_packed bytes4: size mismatch (expected 4 bytes, got 1)",
                   fn -> ABI.encode_packed("foo(bytes4)", [<<0x42>>]) end
    end

    test "fixed-size array size mismatch names both lengths" do
      assert_raise ArgumentError,
                   "encode_packed array: size mismatch (expected 3, got 2)",
                   fn -> ABI.encode_packed("foo(uint256[3])", [[1, 2]]) end
    end

    test "top-level tuple/struct cites the Solidity spec section" do
      assert_raise ArgumentError,
                   "encode_packed: tuple/struct types are not supported by Solidity's packed mode (see https://docs.soliditylang.org/en/stable/abi-spec.html#non-standard-packed-mode)",
                   fn -> ABI.encode_packed("(uint8,bool)", [{42, true}]) end
    end

    test "unrecognized type tag inspects the type" do
      sel = %FunctionSelector{function: "foo", types: [%{type: {:weird, 8}}]}

      assert_raise ArgumentError,
                   "encode_packed: unsupported type {:weird, 8}",
                   fn -> ABI.encode_packed(sel, [42]) end
    end

    test "fixed-size array nested in a dynamic array is rejected" do
      assert_raise ArgumentError,
                   "encode_packed: nested arrays are not supported by Solidity's packed mode",
                   fn -> ABI.encode_packed("foo(uint256[2][])", [[[1, 2], [3, 4]]]) end
    end

    test "dynamic array nested in a dynamic array is rejected" do
      assert_raise ArgumentError,
                   "encode_packed: nested arrays are not supported by Solidity's packed mode",
                   fn -> ABI.encode_packed("foo(uint256[][])", [[[1, 2], [3, 4]]]) end
    end

    test "tuple inside an array is rejected without the spec link" do
      sel = %FunctionSelector{
        function: "foo",
        types: [%{type: {:array, {:tuple, [%{type: {:uint, 256}}]}}}]
      }

      assert_raise ArgumentError,
                   "encode_packed: tuple/struct types are not supported by Solidity's packed mode",
                   fn -> ABI.encode_packed(sel, [[{1}]]) end
    end
  end

  describe "encode/2 — error contract (exact messages)" do
    # The standard (non-packed) encoder shares ABI.TypeEncoder with
    # encode_packed/2; its raise sites carry a distinct, unprefixed vocabulary
    # that callers distinguish on, so they are pinned the same way.

    test "function with a wrong-sized binary spells out the 24-byte layout" do
      assert_raise ArgumentError,
                   "function: size mismatch (expected 24 bytes — 20-byte address ++ 4-byte selector — got 23)",
                   fn -> ABI.encode("foo(function)", [<<0::8*23>>]) end
    end

    test "function with a non-binary value inspects the value" do
      assert_raise ArgumentError,
                   "function: expected 24-byte binary, got 42",
                   fn -> ABI.encode("foo(function)", [42]) end
    end

    test "bool with a non-boolean value interpolates the value" do
      assert_raise RuntimeError, "Invalid data for bool: yes", fn ->
        ABI.encode("foo(bool)", ["yes"])
      end
    end

    test "bytesN longer than the declared size inspects the value" do
      assert_raise RuntimeError, "size mismatch for bytes4: <<1, 2, 3, 4, 5>>", fn ->
        ABI.encode("foo(bytes4)", [<<1, 2, 3, 4, 5>>])
      end
    end

    test "bytesN with a non-binary value inspects the value" do
      assert_raise RuntimeError, "wrong datatype for bytes4: 42", fn ->
        ABI.encode("foo(bytes4)", [42])
      end
    end

    test "unrecognized type tag inspects the type" do
      sel = %FunctionSelector{function: nil, types: [%{type: {:weird, 8}}]}

      assert_raise RuntimeError, "Unsupported encoding type: {:weird, 8}", fn ->
        TypeEncoder.encode([42], sel)
      end
    end

    test "struct encoded from a map with an unnamed field reports type and data" do
      sel = %FunctionSelector{
        function: nil,
        types: [%{type: {:tuple, [%{type: {:uint, 256}}]}}]
      }

      assert_raise RuntimeError,
                   "Cannot decode struct with map when no name given in type `%{type: {:uint, 256}}`\n\n\tfor data:\n\n\t%{\"bar\" => 1}",
                   fn -> TypeEncoder.encode([%{"bar" => 1}], sel) end
    end

    test "struct encoded from a map missing the field names both key forms" do
      sel = %FunctionSelector{
        function: nil,
        types: [%{type: {:tuple, [%{type: {:uint, 256}, name: "Foo"}]}}]
      }

      assert_raise RuntimeError,
                   ~s(Cannot find key `:foo` or `"Foo"` for type `%{name: "Foo", type: {:uint, 256}}`\n\n\tin data:\n\n\t%{"bar" => 1}),
                   fn -> TypeEncoder.encode([%{"bar" => 1}], sel) end
    end
  end
end
