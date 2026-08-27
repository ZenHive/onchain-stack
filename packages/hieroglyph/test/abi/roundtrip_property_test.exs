defmodule ABI.RoundtripPropertyTest do
  @moduledoc """
  Property-based `decode(encode(x)) == x` coverage for every type in
  `ABI.FunctionSelector.@type type/0`.

  Structure: per-type properties localize failures to a single clause; the
  recursive `composite` property exercises nested `{:tuple, [{:array, ...}]}`
  shapes where head/tail offsets matter.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ABI.FunctionSelector
  alias ABI.TypeDecoder
  alias ABI.TypeEncoder

  @uint_sizes Enum.map(1..32, &(&1 * 8))
  @int_sizes @uint_sizes
  @bytes_n_sizes 1..32

  # ── Per-type value generators ───────────────────────────────────────────

  @spec uint_value(pos_integer()) :: StreamData.t()
  defp uint_value(size) do
    StreamData.integer(0..(Bitwise.bsl(1, size) - 1))
  end

  @spec int_value(pos_integer()) :: StreamData.t()
  defp int_value(size) do
    StreamData.integer(-Bitwise.bsl(1, size - 1)..(Bitwise.bsl(1, size - 1) - 1))
  end

  @spec address_value() :: StreamData.t()
  defp address_value, do: StreamData.binary(length: 20)
  @spec bool_value() :: StreamData.t()
  defp bool_value, do: StreamData.boolean()
  @spec bytes_n_value(pos_integer()) :: StreamData.t()
  defp bytes_n_value(n), do: StreamData.binary(length: n)
  @spec bytes_value() :: StreamData.t()
  defp bytes_value, do: StreamData.binary(max_length: 64)
  @spec string_value() :: StreamData.t()
  defp string_value, do: StreamData.string(:utf8, max_length: 64)
  @spec function_value() :: StreamData.t()
  defp function_value, do: StreamData.binary(length: 24)

  # ── Dispatcher: return a generator for any valid type ───────────────────

  @spec value_for(FunctionSelector.type()) :: StreamData.t()
  defp value_for({:uint, size}), do: uint_value(size)
  defp value_for({:int, size}), do: int_value(size)
  defp value_for(:address), do: address_value()
  defp value_for(:bool), do: bool_value()
  defp value_for({:bytes, n}), do: bytes_n_value(n)
  defp value_for(:bytes), do: bytes_value()
  defp value_for(:string), do: string_value()
  defp value_for(:function), do: function_value()

  defp value_for({:array, inner, count}) do
    StreamData.list_of(value_for(inner), length: count)
  end

  defp value_for({:array, inner}) do
    StreamData.list_of(value_for(inner), max_length: 4)
  end

  defp value_for({:tuple, arg_types}) do
    arg_types
    |> Enum.map(fn %{type: t} -> value_for(t) end)
    |> StreamData.fixed_list()
    |> StreamData.map(&List.to_tuple/1)
  end

  # ── Recursive type generator ────────────────────────────────────────────
  #
  # Fixed-array count domain is 0..3. `{:array, T, 0}` is now handled
  # statically by `FunctionSelector.dynamic?/1`; if a downstream encoder or
  # decoder path crashes on an empty fixed array, that's a real bug — surface
  # it here, don't suppress it.

  @leaf_types [
    :bool,
    :address,
    :function,
    :string,
    :bytes,
    {:uint, 8},
    {:uint, 256},
    {:int, 8},
    {:int, 256},
    {:bytes, 1},
    {:bytes, 32}
  ]

  @spec leaf_type() :: StreamData.t()
  defp leaf_type, do: StreamData.member_of(@leaf_types)

  @spec type_gen(non_neg_integer()) :: StreamData.t()
  defp type_gen(0), do: leaf_type()

  defp type_gen(depth) do
    StreamData.frequency([
      {4, leaf_type()},
      {1, StreamData.map(type_gen(depth - 1), &{:array, &1})},
      {1,
       StreamData.bind(type_gen(depth - 1), fn inner ->
         StreamData.map(StreamData.integer(0..3), &{:array, inner, &1})
       end)},
      {1,
       (depth - 1)
       |> type_gen()
       |> StreamData.list_of(min_length: 1, max_length: 3)
       |> StreamData.map(fn inners ->
         {:tuple, Enum.map(inners, &%{type: &1})}
       end)}
    ])
  end

  @spec type_and_value_gen(non_neg_integer()) :: StreamData.t()
  defp type_and_value_gen(depth) do
    StreamData.bind(type_gen(depth), fn t ->
      StreamData.map(value_for(t), &{t, &1})
    end)
  end

  # ── Round-trip helpers ──────────────────────────────────────────────────

  @spec roundtrip(FunctionSelector.type(), any()) :: any()
  defp roundtrip(type, value) do
    args = [%{type: type}]
    encoded = TypeEncoder.encode_raw([value], args)
    [decoded] = TypeDecoder.decode_raw(encoded, args)
    decoded
  end

  @spec roundtrip_args([FunctionSelector.type()], [any()]) :: [any()]
  defp roundtrip_args(types, values) do
    args = Enum.map(types, &%{type: &1})
    encoded = TypeEncoder.encode_raw(values, args)
    TypeDecoder.decode_raw(encoded, args)
  end

  # ── Static value types ──────────────────────────────────────────────────

  describe "static value types" do
    property "uint round-trips across all valid sizes" do
      check all(
              size <- StreamData.member_of(@uint_sizes),
              value <- uint_value(size)
            ) do
        assert roundtrip({:uint, size}, value) == value
      end
    end

    property "int round-trips across all valid sizes" do
      check all(
              size <- StreamData.member_of(@int_sizes),
              value <- int_value(size)
            ) do
        assert roundtrip({:int, size}, value) == value
      end
    end

    property "bool round-trips" do
      check all(value <- bool_value()) do
        assert roundtrip(:bool, value) == value
      end
    end

    property "address round-trips (20-byte binary)" do
      check all(value <- address_value()) do
        assert roundtrip(:address, value) == value
      end
    end

    property "function round-trips (24-byte binary: 20-byte address ++ 4-byte selector)" do
      check all(value <- function_value()) do
        assert roundtrip(:function, value) == value
      end
    end

    property "bytesN round-trips across all valid sizes" do
      check all(
              size <- StreamData.member_of(Enum.to_list(@bytes_n_sizes)),
              value <- bytes_n_value(size)
            ) do
        assert roundtrip({:bytes, size}, value) == value
      end
    end
  end

  # ── Dynamic value types ─────────────────────────────────────────────────

  describe "dynamic value types" do
    property "bytes (dynamic) round-trips" do
      check all(value <- bytes_value()) do
        assert roundtrip(:bytes, value) == value
      end
    end

    property "string round-trips" do
      check all(value <- string_value()) do
        assert roundtrip(:string, value) == value
      end
    end

    # Regression: pre-existing exthereum/abi `nul_terminate_string/1` split
    # decoded strings at the first NUL byte, treating Solidity strings as
    # C strings. Solidity strings are length-prefixed UTF-8 — NUL bytes are
    # legal codepoints. Random `StreamData.string(:utf8, ...)` rarely starts
    # with NUL, so the property above missed it for years.

    test "string with leading NUL byte round-trips" do
      assert roundtrip(:string, <<0, 1, 2, 3, "rest">>) == <<0, 1, 2, 3, "rest">>
    end

    test "string with embedded NUL byte round-trips" do
      assert roundtrip(:string, <<"pre", 0, "post">>) == <<"pre", 0, "post">>
    end

    test "string consisting entirely of NUL bytes round-trips" do
      assert roundtrip(:string, <<0, 0, 0, 0>>) == <<0, 0, 0, 0>>
    end
  end

  # ── Arrays ──────────────────────────────────────────────────────────────

  describe "arrays" do
    property "fixed-size uint arrays round-trip (count 1..4)" do
      check all(
              size <- StreamData.integer(1..4),
              value <- StreamData.list_of(uint_value(256), length: size)
            ) do
        assert roundtrip({:array, {:uint, 256}, size}, value) == value
      end
    end

    property "dynamic uint arrays round-trip" do
      check all(value <- StreamData.list_of(uint_value(256), max_length: 4)) do
        assert roundtrip({:array, {:uint, 256}}, value) == value
      end
    end

    property "dynamic address arrays round-trip" do
      check all(value <- StreamData.list_of(address_value(), max_length: 4)) do
        assert roundtrip({:array, :address}, value) == value
      end
    end

    property "dynamic string arrays round-trip" do
      check all(value <- StreamData.list_of(string_value(), max_length: 4)) do
        assert roundtrip({:array, :string}, value) == value
      end
    end

    property "dynamic bytes arrays round-trip" do
      check all(value <- StreamData.list_of(bytes_value(), max_length: 4)) do
        assert roundtrip({:array, :bytes}, value) == value
      end
    end
  end

  # ── Tuples ──────────────────────────────────────────────────────────────

  describe "tuples" do
    property "mixed static+dynamic tuple round-trips" do
      check all(
              u <- uint_value(256),
              s <- string_value(),
              b <- bool_value(),
              bs <- bytes_value()
            ) do
        type =
          {:tuple,
           [
             %{type: {:uint, 256}},
             %{type: :string},
             %{type: :bool},
             %{type: :bytes}
           ]}

        assert roundtrip(type, {u, s, b, bs}) == {u, s, b, bs}
      end
    end

    property "tuple of (uint, dynamic uint[]) round-trips" do
      check all(
              u <- uint_value(256),
              xs <- StreamData.list_of(uint_value(256), max_length: 4)
            ) do
        type =
          {:tuple, [%{type: {:uint, 256}}, %{type: {:array, {:uint, 256}}}]}

        assert roundtrip(type, {u, xs}) == {u, xs}
      end
    end
  end

  # ── tuple[] (dynamic array of tuples) ───────────────────────────────────
  #
  # The defi-skills mining (2026-04-30) surfaced this shape via EigenLayer
  # `queueWithdrawals((address[],uint256[],address)[])` — a dynamic array
  # whose elements are tuples that themselves contain dynamic fields.
  # Production support exists in `TypeEncoder` and `TypeDecoder` via the
  # `{:array, T}` → `{:tuple, [T, T, ...]}` delegation; explicit coverage
  # here pins the layout so a regression can't land silently.

  describe "tuple[] (dynamic array of tuples)" do
    property "tuple[] of static-only elements round-trips" do
      element_type = {:tuple, [%{type: :address}, %{type: {:uint, 256}}]}

      check all(
              elements <-
                StreamData.list_of(
                  StreamData.tuple({address_value(), uint_value(256)}),
                  max_length: 4
                )
            ) do
        assert roundtrip({:array, element_type}, elements) == elements
      end
    end

    property "tuple[] of mixed static+dynamic elements round-trips" do
      element_type =
        {:tuple,
         [
           %{type: :address},
           %{type: :string},
           %{type: {:array, {:uint, 256}}}
         ]}

      element_gen =
        StreamData.tuple({
          address_value(),
          string_value(),
          StreamData.list_of(uint_value(256), max_length: 3)
        })

      check all(elements <- StreamData.list_of(element_gen, max_length: 3)) do
        assert roundtrip({:array, element_type}, elements) == elements
      end
    end

    test "empty tuple[] round-trips" do
      element_type = {:tuple, [%{type: :address}, %{type: {:uint, 256}}]}
      assert roundtrip({:array, element_type}, []) == []
    end
  end

  # ── Empty dynamic fields inside structs ─────────────────────────────────
  #
  # Pinned edge cases — Balancer V2 `singleSwap.userData = "0x"`,
  # EigenLayer `approverSignatureAndExpiry.signature = "0x"`, and Pendle
  # `limit.normalFills = []` all pass empty dynamic fields adjacent to
  # other dynamic fields. Head/tail offset arithmetic must stay exact.

  describe "empty dynamic fields inside structs" do
    test "two adjacent dynamic fields, one empty bytes" do
      type = {:tuple, [%{type: :bytes}, %{type: :string}]}
      value = {<<>>, "non-empty"}
      assert roundtrip(type, value) == value
    end

    test "(bytes, bytes) both empty" do
      type = {:tuple, [%{type: :bytes}, %{type: :bytes}]}
      value = {<<>>, <<>>}
      assert roundtrip(type, value) == value
    end

    test "empty tuple[] as the only dynamic field in a struct" do
      element_type = {:tuple, [%{type: :address}]}

      type =
        {:tuple, [%{type: :address}, %{type: {:array, element_type}}]}

      value = {<<0::160>>, []}
      assert roundtrip(type, value) == value
    end

    test "empty tuple[] followed by non-empty bytes" do
      element_type = {:tuple, [%{type: {:uint, 256}}]}

      type =
        {:tuple, [%{type: {:array, element_type}}, %{type: :bytes}]}

      value = {[], <<1, 2, 3>>}
      assert roundtrip(type, value) == value
    end
  end

  # ── Multiple top-level struct args ──────────────────────────────────────
  #
  # Mirrors the Balancer V2 `swap(SingleSwap, FundManagement, uint256, uint256)`
  # shape — two sibling structs of differing dynamic-rate plus two scalar
  # args. Catches sibling-tuple offset arithmetic when adjacent top-level
  # tuples are dynamic at different rates.

  describe "multiple top-level struct args" do
    property "two sibling structs + two scalars round-trip" do
      # First struct is mixed static+dynamic (dynamic rate: 1 string field).
      # Second struct is static-only (static rate). Scalars pad both ends.
      type_a =
        {:tuple,
         [
           %{type: :address},
           %{type: :string},
           %{type: {:uint, 256}}
         ]}

      type_b =
        {:tuple,
         [
           %{type: :bool},
           %{type: :address},
           %{type: {:uint, 128}}
         ]}

      check all(
              addr_a <- address_value(),
              str_a <- string_value(),
              uint_a <- uint_value(256),
              bool_b <- bool_value(),
              addr_b <- address_value(),
              uint_b <- uint_value(128),
              scalar_pre <- uint_value(256),
              scalar_post <- uint_value(64)
            ) do
        types = [{:uint, 256}, type_a, type_b, {:uint, 64}]

        values = [
          scalar_pre,
          {addr_a, str_a, uint_a},
          {bool_b, addr_b, uint_b},
          scalar_post
        ]

        assert roundtrip_args(types, values) == values
      end
    end
  end

  # ── Composite (recursive) ───────────────────────────────────────────────

  describe "composite" do
    @tag timeout: 300_000
    property "arbitrary valid types and values round-trip (depth ≤ 5)" do
      check all({type, value} <- type_and_value_gen(5), max_runs: 50) do
        assert roundtrip(type, value) == value
      end
    end
  end

  # ── decode_structs: true map round-trip ─────────────────────────────────
  #
  # The decoder applies `Macro.underscore/1` to field names when
  # `decode_structs: true`, so only already-snake_case names round-trip
  # losslessly.

  describe "decode_structs: true round-trip" do
    property "atom-keyed map with snake_case field names round-trips" do
      check all(
              a <- uint_value(256),
              b <- bool_value()
            ) do
        type =
          {:tuple,
           [
             %{type: {:uint, 256}, name: "first_field"},
             %{type: :bool, name: "second_field"}
           ]}

        args = [%{type: type}]
        input = %{first_field: a, second_field: b}

        encoded = TypeEncoder.encode_raw([input], args)
        [decoded] = TypeDecoder.decode_raw(encoded, args, decode_structs: true)

        assert decoded == %{first_field: a, second_field: b}
      end
    end
  end
end
