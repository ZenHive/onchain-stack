defmodule ABI.TypeEncoderTest do
  use ExUnit.Case, async: true

  alias ABI.FunctionSelector
  alias ABI.TypeEncoder

  doctest TypeEncoder

  describe "map-input encoding (data_to_list/2 map branch)" do
    @named_selector %FunctionSelector{
      function: nil,
      types: [
        %{
          type:
            {:tuple,
             [
               %{name: "x", type: {:uint, 32}},
               %{name: "flag", type: :bool}
             ]}
        }
      ]
    }

    test "atom-keyed map encodes identically to the tuple form" do
      assert TypeEncoder.encode([%{x: 42, flag: true}], @named_selector) ==
               TypeEncoder.encode([{42, true}], @named_selector)
    end

    test "string-keyed map encodes identically to the tuple form" do
      assert TypeEncoder.encode([%{"x" => 42, "flag" => true}], @named_selector) ==
               TypeEncoder.encode([{42, true}], @named_selector)
    end

    test "camelCase name resolves to the snake_case atom key" do
      selector = %FunctionSelector{
        function: nil,
        types: [%{type: {:tuple, [%{name: "myField", type: :string}]}}]
      }

      assert TypeEncoder.encode([%{my_field: "hello"}], selector) ==
               TypeEncoder.encode([{"hello"}], selector)
    end

    test "string key takes priority over atom key when both are present" do
      selector = %FunctionSelector{
        function: nil,
        types: [%{type: {:tuple, [%{name: "x", type: {:uint, 32}}]}}]
      }

      assert TypeEncoder.encode([%{"x" => 1, x: 2}], selector) ==
               TypeEncoder.encode([{1}], selector)
    end

    test "integer values inside a nested named-struct map round-trip through both map branches" do
      selector = %FunctionSelector{
        function: nil,
        types: [
          %{
            type:
              {:tuple,
               [
                 %{name: "amount", type: {:int, 32}},
                 %{
                   name: "inner",
                   type:
                     {:tuple,
                      [
                        %{name: "x", type: {:uint, 8}},
                        %{name: "y", type: {:uint, 8}}
                      ]}
                 }
               ]}
          }
        ]
      }

      map_input = [%{amount: -5, inner: %{x: 1, y: 2}}]
      tuple_input = [{-5, {1, 2}}]

      assert TypeEncoder.encode(map_input, selector) ==
               TypeEncoder.encode(tuple_input, selector)
    end

    test "raises a descriptive error when a required field is missing from the map" do
      selector = %FunctionSelector{
        function: nil,
        types: [%{type: {:tuple, [%{name: "required", type: :bool}]}}]
      }

      assert_raise RuntimeError, ~r/Cannot find key/, fn ->
        TypeEncoder.encode([%{other: true}], selector)
      end
    end

    test "raises when a map value targets types without :name" do
      selector = %FunctionSelector{
        function: nil,
        types: [%{type: {:tuple, [%{type: :bool}]}}]
      }

      assert_raise RuntimeError, ~r/no name given/, fn ->
        TypeEncoder.encode([%{anything: true}], selector)
      end
    end

    # String keys are looked up verbatim (no underscore normalization), so a
    # caller passing the snake_case form of a camelCase ABI name must convert
    # it themselves or switch to an atom key. Documented so the asymmetry with
    # atom-key lookup stays inspectable.
    test "raises when string key is the snake_case form of a camelCase field name" do
      selector = %FunctionSelector{
        function: nil,
        types: [%{type: {:tuple, [%{name: "myField", type: {:uint, 8}}]}}]
      }

      assert_raise RuntimeError, ~r/Cannot find key/, fn ->
        TypeEncoder.encode([%{"my_field" => 9}], selector)
      end
    end

    # The encoder uses `String.to_existing_atom/1` for the atom-key fallback
    # branch — atoms are never created. These two tests exercise both
    # outcomes when the snake_case form of a camelCase ABI name is NOT
    # interned anywhere in the VM atom table.

    test "string-key match succeeds even when the snake_case atom does not exist" do
      selector = %FunctionSelector{
        function: nil,
        types: [%{type: {:tuple, [%{name: "encoderOnlyFieldZ47Q", type: {:uint, 32}}]}}]
      }

      # Verbatim camelCase string key → first cond branch matches; the
      # snake_case atom is never consulted, so its existence is irrelevant.
      assert TypeEncoder.encode([%{"encoderOnlyFieldZ47Q" => 7}], selector) ==
               TypeEncoder.encode([{7}], selector)
    end

    test "missing-key raise reports the snake_case form even when the atom does not exist" do
      selector = %FunctionSelector{
        function: nil,
        types: [
          %{type: {:tuple, [%{name: "anotherEncoderOnlyFieldZ47Q", type: :bool}]}}
        ]
      }

      err =
        assert_raise RuntimeError, fn ->
          TypeEncoder.encode([%{"unrelatedKey" => true}], selector)
        end

      assert err.message =~ ":another_encoder_only_field_z47_q"
      assert err.message =~ "\"anotherEncoderOnlyFieldZ47Q\""
    end
  end

  describe "type-error paths" do
    test "bool with non-boolean value raises" do
      selector = %FunctionSelector{function: nil, types: [%{type: :bool}]}

      assert_raise RuntimeError, ~r/Invalid data for bool/, fn ->
        TypeEncoder.encode([42], selector)
      end
    end

    test "bytes<N> with a binary longer than N raises size mismatch" do
      selector = %FunctionSelector{function: nil, types: [%{type: {:bytes, 4}}]}

      assert_raise RuntimeError, ~r/size mismatch for bytes4/, fn ->
        TypeEncoder.encode([<<1, 2, 3, 4, 5>>], selector)
      end
    end

    test "bytes<N> with a non-binary value raises wrong datatype" do
      selector = %FunctionSelector{function: nil, types: [%{type: {:bytes, 4}}]}

      assert_raise RuntimeError, ~r/wrong datatype for bytes4/, fn ->
        TypeEncoder.encode([42], selector)
      end
    end

    test "unrecognized type atom raises unsupported encoding type" do
      selector = %FunctionSelector{function: nil, types: [%{type: :banana}]}

      assert_raise RuntimeError, ~r/Unsupported encoding type/, fn ->
        TypeEncoder.encode([:anything], selector)
      end
    end

    test "int overflow raises at the signed-range boundary" do
      selector = %FunctionSelector{function: nil, types: [%{type: {:int, 8}}]}

      # int8 range is -128..127; the boundary cases must raise.
      for value <- [128, -129, -200, 1_000] do
        assert_raise RuntimeError, ~r/Data overflow encoding int/, fn ->
          TypeEncoder.encode([value], selector)
        end
      end

      # In-range values must NOT raise (regression guard against the
      # byte-vs-bit overflow check that previously rejected ALL int8 input,
      # including 0).
      for value <- [-128, -1, 0, 1, 127] do
        assert is_binary(TypeEncoder.encode([value], selector))
      end
    end

    test "uint overflow raises data overflow" do
      selector = %FunctionSelector{function: nil, types: [%{type: {:uint, 8}}]}

      assert_raise RuntimeError, ~r/Data overflow encoding uint/, fn ->
        TypeEncoder.encode([256], selector)
      end
    end
  end

  describe "function type encoding" do
    # `function` is a 24-byte external function pointer: 20-byte address ++
    # 4-byte selector. On the wire it's right-padded to 32 bytes (same
    # layout as `bytes24`).

    @addr :binary.copy(<<0xAB>>, 20)
    @sel <<0xCA, 0xFE, 0xBA, 0xBE>>
    @ptr @addr <> @sel

    test "encode/2 produces a 32-byte right-padded slot" do
      selector = %FunctionSelector{function: nil, types: [%{type: :function}]}
      encoded = TypeEncoder.encode([@ptr], selector)

      # 24-byte payload, then 8 zero bytes of right padding.
      assert encoded == @ptr <> <<0::8*8>>
      assert byte_size(encoded) == 32
    end

    test "encode/2 raises ArgumentError on a binary of the wrong size" do
      selector = %FunctionSelector{function: nil, types: [%{type: :function}]}

      assert_raise ArgumentError, ~r/expected 24 bytes/, fn ->
        TypeEncoder.encode([<<0::8*23>>], selector)
      end

      assert_raise ArgumentError, ~r/expected 24 bytes/, fn ->
        TypeEncoder.encode([<<0::8*25>>], selector)
      end
    end

    test "encode/2 raises ArgumentError on a non-binary value" do
      selector = %FunctionSelector{function: nil, types: [%{type: :function}]}

      assert_raise ArgumentError, ~r/expected 24-byte binary/, fn ->
        TypeEncoder.encode([42], selector)
      end
    end
  end

  # The mutants below were flagged by the muex campaign as surviving: every
  # assertion here pins an exact byte string or an exact exception message,
  # because the loose `~r/.../` forms above cannot see a wrong bound, a
  # wrong slot width, or an error that reports the data where it should
  # report the type.

  describe "overflow errors carry exact bounds" do
    test "int overflow message names the exact signed range" do
      selector = %FunctionSelector{function: nil, types: [%{type: {:int, 8}}]}

      assert_raise RuntimeError,
                   "Data overflow encoding int, data `128` cannot fit in " <>
                     "8-bit signed range (-128..127)",
                   fn -> TypeEncoder.encode([128], selector) end

      assert_raise RuntimeError,
                   "Data overflow encoding int, data `-129` cannot fit in " <>
                     "8-bit signed range (-128..127)",
                   fn -> TypeEncoder.encode([-129], selector) end
    end

    test "int256 overflow message names the full 2^255 bound" do
      selector = %FunctionSelector{function: nil, types: [%{type: {:int, 256}}]}
      max = Bitwise.bsl(1, 255)

      message =
        "Data overflow encoding int, data `#{max}` cannot fit in " <>
          "256-bit signed range (-#{max}..#{max - 1})"

      assert_raise RuntimeError, message, fn ->
        TypeEncoder.encode([max], selector)
      end
    end

    test "uint overflow message names the exact bit width" do
      uint8 = %FunctionSelector{function: nil, types: [%{type: {:uint, 8}}]}
      uint16 = %FunctionSelector{function: nil, types: [%{type: {:uint, 16}}]}

      assert_raise RuntimeError,
                   "Data overflow encoding uint, data `256` cannot fit in 8 bits",
                   fn -> TypeEncoder.encode([256], uint8) end

      assert_raise RuntimeError,
                   "Data overflow encoding uint, data `65536` cannot fit in 16 bits",
                   fn -> TypeEncoder.encode([65_536], uint16) end
    end
  end

  describe "error messages name the offending type or value" do
    test "unsupported type error reports the type, not the data list" do
      selector = %FunctionSelector{function: nil, types: [%{type: :banana}]}

      assert_raise RuntimeError, "Unsupported encoding type: :banana", fn ->
        TypeEncoder.encode([:anything], selector)
      end
    end

    test "function errors report the value and the actual byte size" do
      selector = %FunctionSelector{function: nil, types: [%{type: :function}]}

      assert_raise ArgumentError,
                   "function: expected 24-byte binary, got 42",
                   fn -> TypeEncoder.encode([42], selector) end

      assert_raise ArgumentError,
                   "function: size mismatch (expected 24 bytes — 20-byte " <>
                     "address ++ 4-byte selector — got 23)",
                   fn -> TypeEncoder.encode([<<0::8*23>>], selector) end
    end

    test "bytes<N> errors report the offending value" do
      selector = %FunctionSelector{function: nil, types: [%{type: {:bytes, 4}}]}

      assert_raise RuntimeError,
                   "wrong datatype for bytes4: 42",
                   fn -> TypeEncoder.encode([42], selector) end

      assert_raise RuntimeError,
                   "size mismatch for bytes4: <<1, 2, 3, 4, 5>>",
                   fn -> TypeEncoder.encode([<<1, 2, 3, 4, 5>>], selector) end
    end
  end

  describe "signed integer word layout" do
    test "zero encodes to an all-zero word at every width" do
      for bits <- [8, 16, 64, 256] do
        types = [%{type: {:int, bits}}]
        selector = %FunctionSelector{function: nil, types: types}

        assert TypeEncoder.encode([0], selector) == <<0::256>>
      end
    end

    test "wide negative values occupy exactly one 32-byte word" do
      int64 = %FunctionSelector{function: nil, types: [%{type: {:int, 64}}]}

      assert TypeEncoder.encode([-1], int64) == :binary.copy(<<0xFF>>, 32)

      assert TypeEncoder.encode([-2], int64) ==
               :binary.copy(<<0xFF>>, 31) <> <<0xFE>>

      assert byte_size(TypeEncoder.encode([-1], int64)) == 32
    end

    test "int256 encodes both ends of the signed range in one word" do
      int256 = %FunctionSelector{function: nil, types: [%{type: {:int, 256}}]}
      max = Bitwise.bsl(1, 255)

      # -2^255 is the one input whose two's-complement intermediate already
      # fills all 32 bytes, so no sign-extension byte may be prepended.
      assert TypeEncoder.encode([-max], int256) == <<0x80>> <> <<0::248>>

      assert TypeEncoder.encode([max - 1], int256) ==
               <<0x7F>> <> :binary.copy(<<0xFF>>, 31)
    end
  end

  describe "encode_raw/2 data handling" do
    test "a tuple type accepts a plain list value" do
      selector = %FunctionSelector{
        function: nil,
        types: [%{type: {:tuple, [%{type: {:uint, 8}}, %{type: :bool}]}}]
      }

      assert TypeEncoder.encode([[7, true]], selector) ==
               <<0::248, 7>> <> <<0::248, 1>>
    end

    test "types are consumed in order and surplus data values are ignored" do
      assert TypeEncoder.encode_raw([1, 2, 3], [%{type: {:uint, 8}}]) ==
               <<0::248, 1>>
    end
  end

  describe "encode_packed/2 exact bytes and messages" do
    test "int256 packs into exactly 32 bytes" do
      types = [%{type: {:int, 256}}]
      max = Bitwise.bsl(1, 255)

      assert TypeEncoder.encode_packed([1], types) == <<0::248, 1>>
      assert TypeEncoder.encode_packed([-1], types) == :binary.copy(<<0xFF>>, 32)
      assert TypeEncoder.encode_packed([-max], types) == <<0x80>> <> <<0::248>>
    end

    test "uint256 given a binary left-pads to exactly 32 bytes" do
      types = [%{type: {:uint, 256}}]

      assert TypeEncoder.encode_packed([<<0x42>>], types) == <<0::248, 0x42>>
      assert byte_size(TypeEncoder.encode_packed([<<0x42>>], types)) == 32
    end

    test "packed int overflow message names the exact signed range" do
      types = [%{type: {:int, 8}}]

      assert_raise ArgumentError,
                   "encode_packed int8: 128 doesn't fit in signed range " <>
                     "(-128..127)",
                   fn -> TypeEncoder.encode_packed([128], types) end

      assert_raise ArgumentError,
                   "encode_packed int8: -129 doesn't fit in signed range " <>
                     "(-128..127)",
                   fn -> TypeEncoder.encode_packed([-129], types) end
    end

    test "packed uint errors name the width and the offending value" do
      types = [%{type: {:uint, 8}}]

      assert_raise ArgumentError,
                   "encode_packed uint8: 256 doesn't fit in uint8",
                   fn -> TypeEncoder.encode_packed([256], types) end

      assert_raise ArgumentError,
                   "encode_packed uint8: negative value -1",
                   fn -> TypeEncoder.encode_packed([-1], types) end

      assert_raise ArgumentError,
                   "encode_packed uint8: binary too long (2 bytes for uint8)",
                   fn -> TypeEncoder.encode_packed([<<0x12, 0x34>>], types) end
    end

    test "packed function errors distinguish size mismatch from wrong type" do
      types = [%{type: :function}]

      assert_raise ArgumentError,
                   "encode_packed function: size mismatch " <>
                     "(expected 24 bytes, got 23)",
                   fn -> TypeEncoder.encode_packed([<<0::8*23>>], types) end

      assert_raise ArgumentError,
                   "encode_packed function: expected 24-byte binary, got 42",
                   fn -> TypeEncoder.encode_packed([42], types) end
    end

    test "packed tuple raises the packed-mode-specific message" do
      types = [%{type: {:tuple, [%{type: {:uint, 8}}]}}]

      assert_raise ArgumentError,
                   "encode_packed: tuple/struct types are not supported by " <>
                     "Solidity's packed mode (see " <>
                     "https://docs.soliditylang.org/en/stable/abi-spec.html" <>
                     "#non-standard-packed-mode)",
                   fn -> TypeEncoder.encode_packed([{1}], types) end
    end

    test "packed unsupported type message names the type" do
      types = [%{type: {:weird, 8}}]

      assert_raise ArgumentError,
                   "encode_packed: unsupported type {:weird, 8}",
                   fn -> TypeEncoder.encode_packed([42], types) end
    end
  end
end
