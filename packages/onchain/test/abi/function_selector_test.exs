defmodule ABI.FunctionSelectorTest do
  use ExUnit.Case, async: true

  alias ABI.FunctionSelector

  doctest FunctionSelector

  describe "error paths" do
    test "encode/1 raises when the selector has an unrecognized type" do
      selector = %FunctionSelector{function: "foo", types: [%{type: :banana}]}

      assert_raise RuntimeError, ~r/Unsupported type/, fn ->
        FunctionSelector.encode(selector)
      end
    end
  end

  describe "parse-time rejection of unsupported grammar types (upstream #54)" do
    # `fixed` / `ufixed` (bare and explicit-M/N forms) are accepted by the
    # ABI grammar but not implemented by this library — Solidity itself
    # does not fully support fixed-point types (see
    # https://docs.soliditylang.org/en/latest/types.html). Rejecting at
    # parse time surfaces the error on the user's input instead of deep
    # inside the encoder/decoder catch-all.
    #
    # `function` was previously rejected here too; lifted in 1.3.0 — see the
    # "`function` type acceptance" describe block below.

    test "decode_type/1 raises on bare `fixed` (parser expands to fixed128x18)" do
      assert_raise ArgumentError, ~r/fixed/, fn ->
        FunctionSelector.decode_type("fixed")
      end
    end

    test "decode_type/1 raises on bare `ufixed`" do
      assert_raise ArgumentError, ~r/ufixed/, fn ->
        FunctionSelector.decode_type("ufixed")
      end
    end

    test "decode_type/1 raises friendly error on explicit `fixed128x18`" do
      # Pre-fix this raised FunctionClauseError because the lexer
      # tokenized single `x` as `letters` (LETTERS rule shadowed the
      # `x` terminal). Now `fixed`/`ufixed` are dedicated terminals so
      # the parser routes the explicit-M/N form through the same
      # rejection path as the bare form.
      assert_raise ArgumentError, ~r/fixed128x18/, fn ->
        FunctionSelector.decode_type("fixed128x18")
      end
    end

    test "decode_type/1 raises friendly error on explicit `ufixed256x80`" do
      assert_raise ArgumentError, ~r/ufixed256x80/, fn ->
        FunctionSelector.decode_type("ufixed256x80")
      end
    end

    test "decode_type/1 raises on dynamic array of explicit fixed" do
      assert_raise ArgumentError, ~r/fixed128x18/, fn ->
        FunctionSelector.decode_type("fixed128x18[]")
      end
    end

    test "decode_type/1 raises on tuple containing explicit ufixed" do
      assert_raise ArgumentError, ~r/ufixed256x80/, fn ->
        FunctionSelector.decode_type("(uint256,ufixed256x80)")
      end
    end

    test "decode/1 raises on selector argument with explicit fixed" do
      assert_raise ArgumentError, ~r/fixed128x18/, fn ->
        FunctionSelector.decode("foo(fixed128x18)")
      end
    end

    test "decode/1 raises on selector return with explicit ufixed" do
      assert_raise ArgumentError, ~r/ufixed256x80/, fn ->
        FunctionSelector.decode("foo(uint256)->ufixed256x80")
      end
    end

    test "decode_type/1 raises on fixed-size array of rejected type" do
      assert_raise ArgumentError, ~r/fixed/, fn ->
        FunctionSelector.decode_type("fixed[5]")
      end
    end

    test "decode_type/1 still accepts supported types unchanged" do
      assert {:array, {:uint, 256}} = FunctionSelector.decode_type("uint256[]")
      assert {:bytes, 32} = FunctionSelector.decode_type("bytes32")
      assert :address = FunctionSelector.decode_type("address")
    end
  end

  describe "`function` type acceptance (upstream #54 partial — lifted in 1.3.0)" do
    # The `function` ABI type is a 24-byte external function pointer:
    # 20-byte address ++ 4-byte selector, right-padded to 32 bytes on the
    # wire (same layout as `bytes24`). Previously rejected at parse time
    # alongside `fixed`/`ufixed`; lifted in 1.3.0 because — unlike
    # fixed-point types — Solidity itself fully supports `function`.

    test "decode_type/1 accepts bare `function`" do
      assert :function = FunctionSelector.decode_type("function")
    end

    test "decode_type/1 accepts `function[]` (dynamic array)" do
      assert {:array, :function} = FunctionSelector.decode_type("function[]")
    end

    test "decode_type/1 accepts tuple containing `function`" do
      assert {:tuple, [%{type: {:uint, 256}}, %{type: :function}]} =
               FunctionSelector.decode_type("(uint256,function)")
    end

    test "decode/1 accepts selector argument with `function` type" do
      assert %FunctionSelector{
               function: "foo",
               types: [%{type: :function}]
             } = FunctionSelector.decode("foo(function)")
    end

    test "decode/1 accepts selector return with `function` type" do
      assert %FunctionSelector{
               function: "foo",
               types: [%{type: {:uint, 256}}],
               returns: :function
             } = FunctionSelector.decode("foo(uint256)->function")
    end

    test "`function` is static — encoded in place, never head/tail" do
      # `dynamic?/1` is what TypeEncoder/TypeDecoder consult to decide
      # whether a head slot holds the value or a tail offset. The 24-byte
      # external pointer is right-padded into a single word and written in
      # place; classifying it as dynamic would put an offset there instead.
      refute FunctionSelector.dynamic?(:function)

      pointer = <<1::160, 0xA9, 0x05, 0x9C, 0xBB>>
      assert byte_size(pointer) == 24

      assert ABI.encode("foo(function,uint256)", [pointer, 7]) ==
               ABI.method_id("foo(function,uint256)") <>
                 <<1::160, 0xA9, 0x05, 0x9C, 0xBB, 0::64>> <>
                 <<7::256>>
    end
  end

  describe "lexer/parser identifier handling for `x` and fixed/ufixed keywords" do
    # Regression tests for the lexer reorder + dedicated-terminal fix.
    # Pre-fix: single-char `x` lexed as `letters` (LETTERS rule shadowed
    # the `x` terminal). Post-fix: `x` lexes as the `'x'` terminal, and
    # `fixed`/`ufixed` lex as dedicated terminals — the parser must accept
    # all three as identifier_parts so function and argument names still
    # work.

    test "decode/1 parses function named `x`" do
      selector = FunctionSelector.decode("x(uint256)")
      assert selector.function == "x"
      assert selector.types == [%{type: {:uint, 256}}]
    end

    test "decode/1 parses argument named `x`" do
      selector = FunctionSelector.decode("foo(uint256 x)")
      assert selector.function == "foo"
      assert selector.types == [%{type: {:uint, 256}, name: "x"}]
    end

    test "decode/1 parses function named `fixed` (keyword as identifier)" do
      selector = FunctionSelector.decode("fixed(uint256)")
      assert selector.function == "fixed"
      assert selector.types == [%{type: {:uint, 256}}]
    end

    test "decode/1 parses function named `ufixed` (keyword as identifier)" do
      selector = FunctionSelector.decode("ufixed(uint256)")
      assert selector.function == "ufixed"
      assert selector.types == [%{type: {:uint, 256}}]
    end

    test "decode/1 parses function name containing `x` mid-string" do
      selector = FunctionSelector.decode("transfer_x_amount(address,uint256)")
      assert selector.function == "transfer_x_amount"
      assert selector.types == [%{type: :address}, %{type: {:uint, 256}}]
    end
  end

  describe "encode/3 canonical signature rendering" do
    # Pins the `get_type/1` clauses used to build canonical Solidity
    # signature strings (the basis for selector keccak hashing). Each
    # branch maps a parsed type back to its Solidity textual form.

    test "renders {:int, N} as `intN`" do
      selector = %FunctionSelector{
        function: "foo",
        types: [%{type: {:int, 256}}, %{type: {:int, 8}}]
      }

      assert FunctionSelector.encode(selector) == "foo(int256,int8)"
    end

    test "renders {:struct, _, types, _} as a tuple of its types" do
      # `:struct` is an internal shape used when `decode_structs: true` is
      # set on the decoder; documenting the rendering contract here pins
      # behavior for any caller that constructs selectors directly.
      selector = %FunctionSelector{
        function: "foo",
        types: [%{type: {:struct, "Pair", [:address, {:uint, 256}], ["addr", "amount"]}}]
      }

      assert FunctionSelector.encode(selector) == "foo((address,uint256))"
    end

    test "renders `function` type" do
      assert FunctionSelector.encode(%FunctionSelector{
               function: "f",
               types: [%{type: :function}]
             }) == "f(function)"
    end

    test "renders dead-via-parse types when constructed manually" do
      # `{:fixed, _, _}` and `{:ufixed, _, _}` are rejected at parse time
      # per upstream #54, but the `get_type/1` clauses remain for callers
      # that build selectors directly. `nil` is the same shape: defensive
      # against partially-built typeinfo maps.
      assert FunctionSelector.encode(%FunctionSelector{
               function: "f",
               types: [%{type: {:fixed, 128, 18}}]
             }) == "f(fixed128x18)"

      assert FunctionSelector.encode(%FunctionSelector{
               function: "f",
               types: [%{type: {:ufixed, 128, 18}}]
             }) == "f(ufixed128x18)"

      assert FunctionSelector.encode(%FunctionSelector{
               function: "f",
               types: [%{type: nil}]
             }) == "f()"
    end
  end

  describe "parse_specification — indexed event input without a name" do
    test "produces a typeinfo map with :type and :indexed but no :name" do
      # Older Solidity versions and hand-written ABIs may omit `name` on
      # indexed event params. Pins the `parse_specification_type/1` branch
      # that handles `%{"indexed" => _}` without a corresponding `"name"`.
      abi = [
        %{
          "type" => "event",
          "name" => "Transfer",
          "anonymous" => false,
          "inputs" => [
            %{"type" => "address", "indexed" => true},
            %{"type" => "uint256", "indexed" => false}
          ]
        }
      ]

      [%FunctionSelector{types: [first, second]}] = ABI.parse_specification(abi)

      refute Map.has_key?(first, :name)
      assert first.type == :address
      assert first.indexed == true
      assert second.type == {:uint, 256}
    end
  end

  describe "dynamic?/1 zero-length fixed array" do
    # The grammar allows `T[0]` (yrl rule permits N >= 0), so a parseable type
    # `{:array, T, 0}` reaches `dynamic?/1`. Before the fix, no clause matched
    # zero-length arrays — only `len > 0` — and any caller raised
    # FunctionClauseError. A zero-length fixed array has no head/tail layout
    # and no payload, so it's static by any sensible definition.
    test "returns false for zero-length fixed array of value type" do
      refute FunctionSelector.dynamic?({:array, :address, 0})
      refute FunctionSelector.dynamic?({:array, {:uint, 256}, 0})
      refute FunctionSelector.dynamic?({:array, :bool, 0})
    end

    test "returns false for zero-length fixed array of dynamic element type" do
      refute FunctionSelector.dynamic?({:array, :string, 0})
      refute FunctionSelector.dynamic?({:array, :bytes, 0})
    end

    test "non-zero fixed arrays still inherit dynamic? from element type" do
      refute FunctionSelector.dynamic?({:array, :address, 3})
      assert FunctionSelector.dynamic?({:array, :string, 3})
    end

    # A negative fixed length is not a Solidity type and the grammar cannot
    # produce one, but `dynamic?/1` is public and callers can hand-build a
    # type tuple. It must refuse rather than answer: the `len > 0` guard is
    # the only thing standing between `{:array, T, -1}` and a confident
    # `dynamic?/1` verdict on a type that has no layout at all. Drop the
    # guard and the clause silently returns the element type's dynamism.
    test "negative fixed array length has no dynamic? answer" do
      assert_raise FunctionClauseError, fn ->
        FunctionSelector.dynamic?({:array, :bool, -1})
      end

      assert_raise FunctionClauseError, fn ->
        FunctionSelector.dynamic?({:array, :string, -1})
      end
    end
  end

  describe "parse-error position reporting" do
    # `ABI.Parser.parse!/2` prepends a disambiguating start token
    # (`expecting selector` / `expecting type`) so the shared grammar knows
    # which production to enter. That token carries line 1, and on input the
    # lexer reduces to nothing it is the only token the parser sees — so it
    # is also the token yecc reports the syntax error at. Pinning the line
    # keeps the reported position at the start of the user's input.

    test "decode/1 on empty input reports the error at line 1" do
      error = assert_raise MatchError, fn -> FunctionSelector.decode("") end

      assert {:error, {1, :ethereum_abi_parser, _message}} = error.term
    end

    test "decode_type/1 on empty input reports the error at line 1" do
      error =
        assert_raise MatchError, fn -> FunctionSelector.decode_type("") end

      assert {:error, {1, :ethereum_abi_parser, _message}} = error.term
    end
  end
end
