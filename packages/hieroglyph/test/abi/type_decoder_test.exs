defmodule ABI.TypeDecoderTest do
  use ExUnit.Case, async: true

  alias ABI.TypeDecoder
  alias ABI.TypeEncoder

  doctest TypeDecoder

  # A 32-byte word whose most significant byte is set. Read as a full uint256
  # it is a (nonsensically large) length prefix; read as anything narrower its
  # high byte lands in the padding window instead.
  @high_byte_word <<0xFF, 0::248>>
  @high_byte_value :binary.decode_unsigned(@high_byte_word)

  describe "error paths" do
    test "raises when encoded data has bytes left over after consuming all types" do
      one_uint256_worth = 32
      trailing = 32
      padded = :binary.copy(<<0>>, one_uint256_worth + trailing)

      assert_raise RuntimeError, ~r/Found extra binary data/, fn ->
        TypeDecoder.decode_raw(padded, [%{type: {:uint, 256}}])
      end
    end

    test "raises when asked to decode an unrecognized type atom" do
      assert_raise RuntimeError, "Unsupported decoding type: :banana", fn ->
        TypeDecoder.decode_raw(<<0::256>>, [%{type: :banana}])
      end
    end

    test "raises when an array length prefix exceeds the remaining payload" do
      # A count claiming 2^32-1 elements with no element words behind it. The
      # bound has to fire before the element type list is materialized —
      # otherwise this allocates 4 billion maps first.
      data = <<0xFFFFFFFF::256>>

      assert_raise RuntimeError, ~r/exceeds the 0 remaining 32-byte words/, fn ->
        TypeDecoder.decode_raw(data, [%{type: {:array, {:uint, 256}}}])
      end
    end

    test "reports the oversized array length as a strict violation in strict mode" do
      data = <<0xFFFFFFFF::256>>
      types = [%{type: {:array, {:uint, 256}}}]

      assert_raise TypeDecoder.StrictViolation, ~r/length_out_of_bounds/, fn ->
        TypeDecoder.decode_raw(data, types, strict: true)
      end
    end

    test "arrays of zero-width elements are exempt from the element-count bound" do
      # `bool[0][]` — each element occupies no payload at all, so element count
      # admits no data-length bound. Must still round-trip rather than trip the
      # guard (surfaced by the depth-5 composite property).
      types = [%{type: {:array, {:array, :bool, 0}}}]
      encoded = TypeEncoder.encode_raw([[[]]], types)

      assert [[[]]] = TypeDecoder.decode_raw(encoded, types)
    end
  end

  describe "function type decoding" do
    # `function` is the 24-byte external function pointer (20-byte address
    # ++ 4-byte selector). On the wire it occupies a 32-byte slot with the
    # 24 payload bytes left-aligned and the trailing 8 bytes zero (right-pad).

    @addr :binary.copy(<<0xAB>>, 20)
    @sel <<0xCA, 0xFE, 0xBA, 0xBE>>
    @ptr @addr <> @sel

    test "decode_raw returns the 24-byte payload, dropping the right-padding" do
      slot = @ptr <> <<0::8*8>>
      assert [@ptr] = TypeDecoder.decode_raw(slot, [%{type: :function}])
    end

    test "round-trips inside (uint256, function, bool)" do
      types = [%{type: {:uint, 256}}, %{type: :function}, %{type: :bool}]
      values = [42, @ptr, true]
      encoded = TypeEncoder.encode_raw(values, types)
      assert TypeDecoder.decode_raw(encoded, types) == values
    end

    test "round-trips inside function[3] fixed-size array" do
      ptrs = [@ptr, :binary.copy(<<0x11>>, 24), :binary.copy(<<0xFF>>, 24)]
      types = [%{type: {:array, :function, 3}}]
      encoded = TypeEncoder.encode_raw([ptrs], types)
      assert [^ptrs] = TypeDecoder.decode_raw(encoded, types)
    end

    test "round-trips inside function[] dynamic array" do
      ptrs = [@ptr, :binary.copy(<<0x22>>, 24)]
      types = [%{type: {:array, :function}}]
      encoded = TypeEncoder.encode_raw([ptrs], types)
      assert [^ptrs] = TypeDecoder.decode_raw(encoded, types)
    end
  end

  describe "decode_structs: true atom safety" do
    # The decoder only materializes atoms that already exist in the VM atom
    # table. Tests in this block use field-name strings whose snake_case form
    # is intentionally non-existent ("neverInterned…") or referenced as a
    # literal atom in the assertion ("preInterned…"); literal atoms are
    # interned at module-load time regardless of source line order.

    test "raises ArgumentError naming both the atom and the ABI field" do
      types = [%{type: {:uint, 256}, name: "neverInternedFieldXyzZ47Q"}]
      tuple_type = [%{type: {:tuple, types}}]
      encoded = TypeEncoder.encode_raw([{42}], tuple_type)

      err =
        assert_raise ArgumentError, fn ->
          TypeDecoder.decode_raw(encoded, tuple_type, decode_structs: true)
        end

      assert err.message ==
               "decode_structs: true requires the snake_case field atom " <>
                 ":never_interned_field_xyz_z47_q (from ABI field " <>
                 "\"neverInternedFieldXyzZ47Q\") to already exist in the VM atom table. " <>
                 "Reference the atom in your code (e.g., in a module attribute, a `@type`, " <>
                 "or a compile-time list) before the first decode call. See README " <>
                 "\"Pre-interning atoms for decode_structs: true\" for guidance."
    end

    test "decodes successfully when the snake_case field atom has been interned" do
      types = [
        %{type: {:uint, 256}, name: "preInternedFieldA"},
        %{type: :bool, name: "preInternedFieldB"}
      ]

      tuple_type = [%{type: {:tuple, types}}]
      encoded = TypeEncoder.encode_raw([{42, true}], tuple_type)
      opts = [decode_structs: true]

      [decoded] = TypeDecoder.decode_raw(encoded, tuple_type, opts)

      # The literal atoms `:pre_interned_field_a` / `:pre_interned_field_b`
      # in this assertion intern them at compile time, satisfying the
      # decoder's `String.to_existing_atom/1` lookup.
      assert decoded == %{pre_interned_field_a: 42, pre_interned_field_b: true}
    end

    test "falls through to a tuple when decode_structs is false (no atom lookup)" do
      types = [
        %{type: {:uint, 256}, name: "yetAnotherNeverInternedFieldZ47Q"},
        %{type: :bool, name: "stillNeverInternedFieldZ47Q"}
      ]

      tuple_type = [%{type: {:tuple, types}}]
      encoded = TypeEncoder.encode_raw([{42, true}], tuple_type)

      # Default behavior: returns a tuple, never touches the atom table.
      assert [{42, true}] = TypeDecoder.decode_raw(encoded, tuple_type)
    end

    test "falls through to a tuple when any field name is empty (no atom lookup)" do
      types = [
        %{type: {:uint, 256}, name: "namedFieldXyzZ47Q"},
        # Empty :name forces the tuple fallback even with decode_structs: true.
        %{type: :bool, name: ""}
      ]

      tuple_type = [%{type: {:tuple, types}}]
      encoded = TypeEncoder.encode_raw([{42, true}], tuple_type)
      opts = [decode_structs: true]

      assert [{42, true}] = TypeDecoder.decode_raw(encoded, tuple_type, opts)
    end
  end

  describe "StrictViolation exception" do
    test "carries the raised detail term and renders it into the message" do
      err =
        assert_raise TypeDecoder.StrictViolation, fn ->
          TypeDecoder.decode_raw(<<0::248, 2>>, [%{type: :bool}], strict: true)
        end

      assert err.detail == {:invalid_bool, 2}
      assert err.message == "strict ABI decode violation: {:invalid_bool, 2}"
    end
  end

  describe "strict mode accepts canonical payloads" do
    test "zero-padded uint8 and uint16 slots" do
      assert strict_decode(<<0::248, 7>>, [%{type: {:uint, 8}}]) == [7]
      assert strict_decode(<<0::240, 5::16>>, [%{type: {:uint, 16}}]) == [5]
    end

    test "a positive int8 padded with zero fill" do
      assert strict_decode(<<0::248, 5>>, [%{type: {:int, 8}}]) == [5]
    end

    test "a negative value padded with 0xFF sign fill" do
      # -5 sign-extended to a full word. The 0xFF fill is what makes the slot
      # canonical, and the byte pattern is the same at both widths.
      data = :binary.copy(<<0xFF>>, 31) <> <<0xFB>>

      assert strict_decode(data, [%{type: {:int, 8}}]) == [-5]
      assert strict_decode(data, [%{type: {:int, 64}}]) == [-5]
    end

    test "a bool whose value byte is the only non-zero byte in the slot" do
      assert strict_decode(<<0::248, 1>>, [%{type: :bool}]) == [true]
      assert strict_decode(<<0::256>>, [%{type: :bool}]) == [false]
    end

    test "a string whose content is padded up to the next word boundary" do
      data = <<5::256>> <> "abcde" <> <<0::27*8>>

      assert strict_decode(data, [%{type: :string}]) == ["abcde"]
    end

    test "a string whose length is an exact multiple of the 32-byte word" do
      # 32 needs no alignment padding at all: the bound is exactly the
      # content length, and the payload sits right on the >= boundary.
      content = :binary.copy("a", 32)
      data = <<32::256>> <> content

      assert strict_decode(data, [%{type: :string}]) == [content]
    end
  end

  describe "strict mode rejects non-canonical left padding" do
    test "a uint8 slot with a non-zero byte above the value" do
      detail = strict_detail(<<1::248, 5>>, [%{type: {:uint, 8}}])

      assert detail == {:non_canonical_padding, %{type: {:uint, 8}}}
    end

    test "a uint64 slot with a byte set just above the value window" do
      # Byte 23 is the last padding byte for a 64-bit value; a value width
      # computed as anything wider would read straight past it.
      data = <<0::23*8, 0xFF, 0::64>>
      detail = strict_detail(data, [%{type: {:uint, 64}}])

      assert detail == {:non_canonical_padding, %{type: {:uint, 64}}}
    end

    test "an int8 whose sign bit is set but whose fill is zero" do
      detail = strict_detail(<<0::248, 0xFF>>, [%{type: {:int, 8}}])

      assert detail == {:non_canonical_padding, %{type: {:int, 8}}}
    end
  end

  describe "strict mode dynamic length bound" do
    test "rejects a string whose content is not padded out to a full word" do
      detail = strict_detail(<<5::256>> <> "abcde", [%{type: :string}])
      expected = %{type: :string, length: 5, available: 5}

      assert detail == {:length_out_of_bounds, expected}
    end

    test "rejects a string with only a partial trailing word behind it" do
      data = <<5::256>> <> "abcde" <> <<0::11*8>>
      detail = strict_detail(data, [%{type: :string}])
      expected = %{type: :string, length: 5, available: 16}

      assert detail == {:length_out_of_bounds, expected}
    end

    test "rejects a string length prefix whose high byte is set" do
      detail = strict_detail(@high_byte_word, [%{type: :string}])
      expected = %{type: :string, length: @high_byte_value, available: 0}

      assert detail == {:length_out_of_bounds, expected}
    end

    test "rejects a bytes length prefix whose high byte is set" do
      detail = strict_detail(@high_byte_word, [%{type: :bytes}])
      expected = %{type: :bytes, length: @high_byte_value, available: 0}

      assert detail == {:length_out_of_bounds, expected}
    end

    test "the bound is not applied outside strict mode" do
      err =
        assert_raise MatchError, fn ->
          TypeDecoder.decode_raw(<<5::256>> <> "abcde", [%{type: :string}])
        end

      assert err.term == ""
    end
  end

  describe "strict mode trailing bytes" do
    test "reports how many bytes were left over" do
      detail = strict_detail(<<0::256, 0, 0, 0>>, [%{type: {:uint, 256}}])

      assert detail == {:trailing_bytes, 3}
    end
  end

  describe "bool decoding" do
    test "raises CaseClauseError naming the offending word when permissive" do
      err =
        assert_raise CaseClauseError, fn ->
          TypeDecoder.decode_raw(<<0::248, 2>>, [%{type: :bool}])
        end

      assert err.term == 2
    end
  end

  describe "array element-count bound" do
    @two_word_tuple {:tuple, [%{type: {:uint, 256}}, %{type: {:uint, 256}}]}
    @dynamic_tuple {:tuple, [%{type: :string}, %{type: {:uint, 256}}]}
    @uint256_array [%{type: {:array, {:uint, 256}}}]

    test "a static tuple element is counted at its full word width" do
      # 3 elements x 2 static words = 6, against the 4 words behind the count.
      data = <<3::256, 0::256, 0::256, 0::256, 0::256>>
      types = [%{type: {:array, @two_word_tuple}}]
      message = "Array element count 3 exceeds the 4 remaining 32-byte words"

      assert_raise RuntimeError, message, fn ->
        TypeDecoder.decode_raw(data, types)
      end
    end

    test "a dynamic element is counted as exactly one tail-offset word" do
      # 2 elements x 1 word fits the 2 words behind the count, so the bound
      # does not fire; the decode then runs out of data on the first tail.
      data = <<2::256, 0::256, 0::256>>

      for type <- [:string, @dynamic_tuple] do
        err =
          assert_raise MatchError, fn ->
            TypeDecoder.decode_raw(data, [%{type: {:array, type}}])
          end

        assert err.term == ""
      end
    end

    test "a dynamic element still needs one word per element" do
      data = <<5::256, 0::256>>
      types = [%{type: {:array, :string}}]
      message = "Array element count 5 exceeds the 1 remaining 32-byte words"

      assert_raise RuntimeError, message, fn ->
        TypeDecoder.decode_raw(data, types)
      end
    end

    test "reports the count, array type and available bytes when strict" do
      detail = strict_detail(<<5::256, 0::256>>, @uint256_array)
      expected = %{type: {:array, {:uint, 256}}, length: 5, available: 32}

      assert detail == {:length_out_of_bounds, expected}
    end

    test "rejects an element count whose high byte is set" do
      count = @high_byte_value
      detail = strict_detail(@high_byte_word, @uint256_array)
      expected = %{type: {:array, {:uint, 256}}, length: count, available: 0}

      assert detail == {:length_out_of_bounds, expected}
    end
  end

  describe "fixed-size bytes" do
    test "bytes0 yields an empty binary and consumes no payload" do
      types = [%{type: {:bytes, 0}}, %{type: {:uint, 256}}]

      assert TypeDecoder.decode_raw(<<7::256>>, types) == [<<>>, 7]
    end

    test "rejects a fixed-size bytes wider than one word" do
      assert_raise RuntimeError, "Unsupported decoding type: {:bytes, 33}", fn ->
        TypeDecoder.decode_raw(<<0::256>>, [%{type: {:bytes, 33}}])
      end
    end
  end

  describe "tuple head/tail offsets" do
    test "strict mode reads the tail-offset word as a full uint256 slot" do
      # The two-pass decode returns elements in `types` order, so the
      # tail-offset word is read but never dereferenced: all 32 bytes of it
      # are uint256 content and carry no narrower padding constraint.
      data = @high_byte_word <> <<3::256>> <> "abc" <> <<0::29*8>>
      types = [%{type: {:tuple, [%{type: :string}]}}]

      assert strict_decode(data, types) == [{"abc"}]
    end
  end

  @spec strict_decode(binary(), [map()]) :: [term()]
  defp strict_decode(data, types) do
    TypeDecoder.decode_raw(data, types, strict: true)
  end

  # Asserts that a strict decode raises, and hands back the violation's
  # detail term so each caller pins the exact payload rather than the shape.
  @spec strict_detail(binary(), [map()]) :: term()
  defp strict_detail(data, types) do
    err =
      assert_raise TypeDecoder.StrictViolation, fn ->
        TypeDecoder.decode_raw(data, types, strict: true)
      end

    err.detail
  end
end
