defmodule ABI.TypeEncoder do
  @moduledoc """
  `ABI.TypeEncoder` is responsible for encoding types to the format
  expected by Solidity. We generally take a function selector and an
  array of data and encode that array according to the specification.
  """

  use Descripex, namespace: "/codec"

  alias ABI.FunctionSelector
  alias ABI.Math

  # A single ABI argument descriptor (`%{type: ..., optional :name}`).
  @typep arg_type :: FunctionSelector.argument_type()
  # head/tail reducer accumulator: `{head, tail, remaining_data, tail_offset}`.
  @typep tuple_acc :: {binary(), binary(), [any()], non_neg_integer()}

  api(
    :encode,
    "Encode a list of values into ABI calldata using the given FunctionSelector, prefixing the 4-byte selector when the function name is set.",
    params: [
      data: [
        kind: :value,
        description:
          "List of values in argument order; tuples may be passed as Elixir tuples, lists for arrays, and named maps for tuple/struct types whose argument metadata carries :name"
      ],
      function_selector: [
        kind: :value,
        description:
          "Pre-parsed FunctionSelector. When :function is non-nil, the 4-byte method id is prepended; when nil, the head/tail body is emitted without prefix"
      ]
    ],
    returns: %{
      type: :binary,
      description: "ABI-encoded calldata (selector-prefixed when the function name is set, raw payload otherwise)"
    },
    composes_with: [:encode_raw]
  )

  @doc """
  Encodes the given data based on the function selector.

  ## Examples

      iex> [69, true]
      ...> |> ABI.TypeEncoder.encode(
      ...>      %ABI.FunctionSelector{
      ...>        function: "baz",
      ...>        types: [
      ...>          %{type: {:uint, 32}},
      ...>          %{type: :bool}
      ...>        ],
      ...>        returns: :bool
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "cdcd77c000000000000000000000000000000000000000000000000000000000000000450000000000000000000000000000000000000000000000000000000000000001"

      iex> ["BAT"]
      ...> |> ABI.TypeEncoder.encode(
      ...>      %ABI.FunctionSelector{
      ...>        function: "price",
      ...>        types: [
      ...>          %{type: :string}
      ...>        ],
      ...>        returns: {:uint, 256}
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "fe2c6198000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000034241540000000000000000000000000000000000000000000000000000000000"


      iex> [Base.decode16!("ffffffffffffffffffffffffffffffffffffffff", case: :lower)]
      ...> |> ABI.TypeEncoder.encode(
      ...>      %ABI.FunctionSelector{
      ...>        function: "price",
      ...>        types: [
      ...>          %{type: :address}
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "aea91078000000000000000000000000ffffffffffffffffffffffffffffffffffffffff"

      iex> [1]
      ...> |> ABI.TypeEncoder.encode(
      ...>      %ABI.FunctionSelector{
      ...>        function: "price",
      ...>        types: [
      ...>          %{type: :address}
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "aea910780000000000000000000000000000000000000000000000000000000000000001"

      iex> ["hello world"]
      ...> |> ABI.TypeEncoder.encode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: :string},
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000000b68656c6c6f20776f726c64000000000000000000000000000000000000000000"

      iex> [{{0x11, 0x22}, "hello world"}]
      ...> |> ABI.TypeEncoder.encode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:tuple, [
      ...>            %{type: {:tuple, [%{type: {:uint, 256}},%{type: {:uint, 256}}]}},
      ...>            %{type: :string},
      ...>          ]}}
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000001100000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000b68656c6c6f20776f726c64000000000000000000000000000000000000000000"

      iex> [{"awesome", true}]
      ...> |> ABI.TypeEncoder.encode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:tuple, [%{type: :string}, %{type: :bool}]}}
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000007617765736f6d6500000000000000000000000000000000000000000000000000"

      iex> [{17, true, <<32, 64>>}]
      ...> |> ABI.TypeEncoder.encode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:tuple, [%{type: {:uint, 32}}, %{type: :bool}, %{type: {:bytes, 2}}]}}
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000001100000000000000000000000000000000000000000000000000000000000000012040000000000000000000000000000000000000000000000000000000000000"

      iex> [[17, 1]]
      ...> |> ABI.TypeEncoder.encode(
      ...>      %ABI.FunctionSelector{
      ...>        function: "baz",
      ...>        types: [
      ...>          %{type: {:array, {:uint, 32}, 2}}
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "3d0ec53300000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000001"

      iex> [[17, 1], true]
      ...> |> ABI.TypeEncoder.encode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:array, {:uint, 32}, 2}},
      ...>          %{type: :bool}
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000001100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001"

      iex> [[17, 1]]
      ...> |> ABI.TypeEncoder.encode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:array, {:uint, 32}}}
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000001"

      iex> [
      ...>   <<1::160>>,
      ...>   <<2::160>>,
      ...>   <<3::256>>,
      ...>   {
      ...>     4,
      ...>     <<5::160>>,
      ...>     <<6>>,
      ...>     <<7::512>>,
      ...>     8
      ...>   },
      ...>   9,
      ...>   <<0xa::256>>,
      ...>   <<0xb::256>>
      ...> ]
      ...> |> ABI.TypeEncoder.encode(
      ...>   %ABI.FunctionSelector{
      ...>     function: "test",
      ...>     function_type: :function,
      ...>     state_mutability: :nonpayable,
      ...>     types: [
      ...>       %{name: "a", type: :address},
      ...>       %{name: "b", type: :address},
      ...>       %{name: "c", type: {:bytes, 32}},
      ...>       %{
      ...>         name: "d",
      ...>         type:
      ...>           {:tuple,
      ...>            [
      ...>              %{name: "e", type: {:uint, 96}},
      ...>              %{name: "f", type: :address},
      ...>              %{name: "g", type: :bytes},
      ...>              %{name: "h", type: :bytes},
      ...>              %{name: "i", type: {:uint, 256}}
      ...>            ]}
      ...>       },
      ...>       %{name: "j", type: {:uint, 8}},
      ...>       %{name: "k", type: {:bytes, 32}},
      ...>       %{name: "l", type: {:bytes, 32}}
      ...>     ],
      ...>     returns: [%{name: "", type: :bytes}]
      ...>   }
      ...> )
      ...> |> Base.encode16(case: :lower)
      "19c9d90a00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000300000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000b0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000500000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000010600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007"

      iex> [%{x: 42, flag: true}]
      ...> |> ABI.TypeEncoder.encode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:tuple, [
      ...>            %{name: "x", type: {:uint, 32}},
      ...>            %{name: "flag", type: :bool}
      ...>          ]}}
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000002a0000000000000000000000000000000000000000000000000000000000000001"

      iex> [-255]
      ...> |> ABI.TypeEncoder.encode(%ABI.FunctionSelector{function: nil, types: [%{type: {:int, 16}}]})
      ...> |> Base.encode16(case: :lower)
      "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff01"
  """
  @spec encode([any()], FunctionSelector.t()) :: binary()
  def encode(data, function_selector) do
    ABI.method_id(function_selector) <>
      do_encode_data(data, function_selector)
  end

  @spec do_encode_data([any()], FunctionSelector.t()) :: binary()
  defp do_encode_data(data, %FunctionSelector{function: nil} = function_selector) do
    encode_raw(data, function_selector.types)
  end

  defp do_encode_data(data, %FunctionSelector{} = function_selector) do
    encode_raw([List.to_tuple(data)], [%{type: {:tuple, function_selector.types}}])
  end

  api(
    :encode_raw,
    "Encode a list of values directly against an explicit type list, without prepending a method-id selector. Used for return values, event data, or pre-routed calldata payloads.",
    params: [
      data: [
        kind: :value,
        description: "List of values in type order; same shapes accepted as encode/2 (tuples, lists, named maps)"
      ],
      types: [
        kind: :value,
        description:
          "List of FunctionSelector argument-type maps (each %{type: ...} optionally with :name) describing the parameter sequence"
      ]
    ],
    returns: %{type: :binary, description: "ABI-encoded payload with no selector prefix"},
    composes_with: [:encode]
  )

  @doc """
  Simiar to `ABI.TypeEncoder.encode/2` except we accept
  an array of types instead of a function selector. We also
  do not pre-pend the method id.

  ## Examples

      iex> [{"awesome", true}]
      ...> |> ABI.TypeEncoder.encode_raw([%{type: {:tuple, [%{type: :string}, %{type: :bool}]}}])
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000007617765736f6d6500000000000000000000000000000000000000000000000000"
  """
  @spec encode_raw([any()], [FunctionSelector.argument_type()]) :: binary()
  def encode_raw(data, types) do
    do_encode(types, data, [])
  end

  api(
    :encode_packed,
    "Encodes values using Solidity's non-standard packed mode (abi.encodePacked) — types <32 bytes concatenated tight, dynamic types in-place without length prefix, array elements padded to 32 bytes.",
    params: [
      data: [
        kind: :value,
        description:
          "List of values in argument order; same value shapes accepted as encode_raw/2 (numbers, binaries, lists for arrays)"
      ],
      types: [
        kind: :value,
        description:
          "List of FunctionSelector argument-type maps (each %{type: ...}) describing the parameter sequence. Tuple/struct types and nested arrays raise — the spec does not define their packed encoding."
      ]
    ],
    returns: %{
      type: :binary,
      description:
        "Tightly-packed bytes per the Solidity spec — never selector-prefixed and not decodable (the spec is ambiguous in the presence of multiple dynamic args)."
    },
    composes_with: [:encode_raw]
  )

  @doc """
  Encodes a list of values using Solidity's
  [non-standard packed mode](https://docs.soliditylang.org/en/stable/abi-spec.html#non-standard-packed-mode).

  Used primarily for `keccak256(abi.encodePacked(...))` Merkle leaves and
  signature schemes; never used for actual function calls (the spec defines
  no decoding function — encoding is ambiguous with multiple dynamic args).

  Tuple/struct values and nested arrays raise `ArgumentError` — Solidity's
  spec does not define their packed encoding.

  ## Examples

      iex> ABI.TypeEncoder.encode_packed(
      ...>   [-1, <<0x42>>, 3, "Hello, world!"],
      ...>   [
      ...>     %{type: {:int, 16}},
      ...>     %{type: {:bytes, 1}},
      ...>     %{type: {:uint, 16}},
      ...>     %{type: :string}
      ...>   ]
      ...> ) |> Base.encode16(case: :lower)
      "ffff42000348656c6c6f2c20776f726c6421"
  """
  @spec encode_packed([any()], [FunctionSelector.argument_type()]) :: binary()
  def encode_packed(data, types) when is_list(data) and is_list(types) do
    if length(data) != length(types) do
      raise ArgumentError,
            "encode_packed arity mismatch: got #{length(data)} values for #{length(types)} types"
    end

    types
    |> Enum.zip(data)
    |> Enum.map_join(<<>>, fn {%{type: t}, v} -> packed_top(t, v) end)
  end

  @spec do_encode([FunctionSelector.argument_type()], [any()], [binary()]) ::
          binary()
  defp do_encode([], _, acc), do: :erlang.iolist_to_binary(Enum.reverse(acc))

  defp do_encode([type | remaining_types], data, acc) do
    {encoded, remaining_data} = encode_type(type.type, data)

    do_encode(remaining_types, remaining_data, [encoded | acc])
  end

  @spec encode_type(FunctionSelector.type(), [any()]) :: {binary(), [any()]}
  defp encode_type({:uint, size}, [data | rest]) do
    {encode_uint(data, size), rest}
  end

  defp encode_type({:int, size}, [data | rest]) do
    {encode_int(data, size), rest}
  end

  defp encode_type(:address, data), do: encode_type({:uint, 160}, data)

  defp encode_type(:function, [data | rest]) when is_binary(data) and byte_size(data) == 24 do
    {encode_bytes(data), rest}
  end

  defp encode_type(:function, [data | _]) when is_binary(data) do
    raise ArgumentError,
          "function: size mismatch (expected 24 bytes — 20-byte address ++ 4-byte selector — got #{byte_size(data)})"
  end

  defp encode_type(:function, [data | _]) do
    raise ArgumentError, "function: expected 24-byte binary, got #{inspect(data)}"
  end

  defp encode_type(:bool, [data | rest]) do
    value =
      case data do
        true -> encode_uint(1, 8)
        false -> encode_uint(0, 8)
        _ -> raise "Invalid data for bool: #{data}"
      end

    {value, rest}
  end

  defp encode_type(:string, [data | rest]) do
    {encode_uint(byte_size(data), 256) <> encode_bytes(data), rest}
  end

  defp encode_type(:bytes, [data | rest]) do
    {encode_uint(byte_size(data), 256) <> encode_bytes(data), rest}
  end

  defp encode_type({:bytes, size}, [data | rest]) when is_binary(data) and byte_size(data) <= size do
    {encode_bytes(data), rest}
  end

  defp encode_type({:bytes, size}, [data | _]) when is_binary(data) do
    raise "size mismatch for bytes#{size}: #{inspect(data)}"
  end

  defp encode_type({:bytes, size}, [data | _]) do
    raise "wrong datatype for bytes#{size}: #{inspect(data)}"
  end

  defp encode_type({:tuple, types}, [data | rest]) do
    # all head items are 32 bytes in length and there will be exactly
    # `count(types)` of them, so the tail starts at `32 * count(types)`.
    # Note: `count(types)` accounts for inlined tuples.
    tail_start = count(types) * 32
    initial_acc = {<<>>, <<>>, data_to_list(types, data), tail_start}

    {head, tail, [], _} = Enum.reduce(types, initial_acc, &encode_tuple_element/2)

    {head <> tail, rest}
  end

  defp encode_type({:array, type, element_count}, [data | rest]) do
    repeated_type =
      if element_count == 0 do
        []
      else
        Enum.map(1..element_count, fn _ -> %{type: type} end)
      end

    encode_type({:tuple, repeated_type}, [List.to_tuple(data) | rest])
  end

  defp encode_type({:array, type}, [data | _rest] = all_data) do
    element_count = Enum.count(data)

    encoded_uint = encode_uint(element_count, 256)
    {encoded_array, rest} = encode_type({:array, type, element_count}, all_data)

    {encoded_uint <> encoded_array, rest}
  end

  defp encode_type(els, _) do
    raise "Unsupported encoding type: #{inspect(els)}"
  end

  @spec encode_tuple_element(arg_type(), tuple_acc()) :: tuple_acc()
  defp encode_tuple_element(argument_type, {head, tail, data, tail_position}) do
    type = argument_type.type
    {el, rest} = encode_type(type, data)

    if FunctionSelector.dynamic?(type) do
      # Dynamic type: write offset into head, element bytes into tail.
      {
        head <> encode_uint(tail_position, 256),
        tail <> el,
        rest,
        tail_position + byte_size(el)
      }
    else
      # Static type: element goes directly into head.
      {head <> el, tail, rest, tail_position}
    end
  end

  @spec encode_bytes(binary()) :: binary()
  defp encode_bytes(bytes) do
    Math.pad(bytes, byte_size(bytes), :right)
  end

  # Top-level packed encoding: scalars are NOT padded, dynamic types are
  # encoded in-place without a length prefix, arrays delegate to packed_array
  # (which DOES pad each element to 32 bytes per the spec).

  @spec packed_top(FunctionSelector.type(), any()) :: binary()
  defp packed_top({:uint, size}, value), do: pack_uint(value, size)

  defp packed_top({:int, size}, value), do: pack_int(value, size)

  defp packed_top(:address, value) when is_binary(value) and byte_size(value) == 20, do: value
  defp packed_top(:address, value) when is_integer(value), do: pack_uint(value, 160)

  defp packed_top(:function, value) when is_binary(value) and byte_size(value) == 24, do: value

  defp packed_top(:function, value) when is_binary(value) do
    raise ArgumentError,
          "encode_packed function: size mismatch (expected 24 bytes, got #{byte_size(value)})"
  end

  defp packed_top(:function, value) do
    raise ArgumentError, "encode_packed function: expected 24-byte binary, got #{inspect(value)}"
  end

  defp packed_top(:bool, true), do: <<1>>
  defp packed_top(:bool, false), do: <<0>>
  defp packed_top(:bool, v), do: raise(ArgumentError, "encode_packed bool: invalid value #{inspect(v)}")

  defp packed_top({:bytes, size}, value) when is_binary(value) and byte_size(value) == size, do: value

  defp packed_top({:bytes, size}, value) when is_binary(value) do
    raise ArgumentError,
          "encode_packed bytes#{size}: size mismatch (expected #{size} bytes, got #{byte_size(value)})"
  end

  defp packed_top(:bytes, value) when is_binary(value), do: value
  defp packed_top(:string, value) when is_binary(value), do: value

  defp packed_top({:array, inner, n}, list) when is_list(list) and length(list) == n do
    packed_array(inner, list)
  end

  defp packed_top({:array, _, n}, list) when is_list(list) do
    raise ArgumentError,
          "encode_packed array: size mismatch (expected #{n}, got #{length(list)})"
  end

  defp packed_top({:array, inner}, list) when is_list(list), do: packed_array(inner, list)

  defp packed_top({:tuple, _}, _) do
    raise ArgumentError,
          "encode_packed: tuple/struct types are not supported by Solidity's packed mode (see https://docs.soliditylang.org/en/stable/abi-spec.html#non-standard-packed-mode)"
  end

  defp packed_top(other, _) do
    raise ArgumentError, "encode_packed: unsupported type #{inspect(other)}"
  end

  # Inside-array packed encoding: each element padded to 32 bytes (per spec).
  # Nested arrays and tuples raise — neither is supported.

  @spec packed_array(FunctionSelector.type(), [any()]) :: binary()
  defp packed_array({:array, _, _}, _) do
    raise ArgumentError, "encode_packed: nested arrays are not supported by Solidity's packed mode"
  end

  defp packed_array({:array, _}, _) do
    raise ArgumentError, "encode_packed: nested arrays are not supported by Solidity's packed mode"
  end

  defp packed_array({:tuple, _}, _) do
    raise ArgumentError,
          "encode_packed: tuple/struct types are not supported by Solidity's packed mode"
  end

  defp packed_array(:string, list) do
    Enum.map_join(list, <<>>, &pad_right_to_32_multiple/1)
  end

  defp packed_array(:bytes, list) do
    Enum.map_join(list, <<>>, &pad_right_to_32_multiple/1)
  end

  defp packed_array(inner, list) do
    # uint/int/bool/address/bytes<N>: encode_type already pads to 32 bytes
    # via Math.pad's 32-byte rounding rule, so we reuse it directly.
    Enum.map_join(list, <<>>, fn value ->
      {encoded, []} = encode_type(inner, [value])
      encoded
    end)
  end

  @spec pad_right_to_32_multiple(binary()) :: binary()
  defp pad_right_to_32_multiple(bin) when is_binary(bin) do
    size = byte_size(bin)
    pad = Math.mod(32 - Math.mod(size, 32), 32)
    bin <> :binary.copy(<<0>>, pad)
  end

  @spec pack_uint(integer() | binary(), pos_integer()) :: binary()
  defp pack_uint(int, bits) when is_integer(int) and rem(bits, 8) == 0 and bits > 0 and bits <= 256 do
    if int < 0 do
      raise ArgumentError, "encode_packed uint#{bits}: negative value #{int}"
    end

    max = Bitwise.bsl(1, bits)

    if int >= max do
      raise ArgumentError, "encode_packed uint#{bits}: #{int} doesn't fit in uint#{bits}"
    end

    bytes = div(bits, 8)
    bin = :binary.encode_unsigned(int)
    pad_size = bytes - byte_size(bin)
    :binary.copy(<<0>>, pad_size) <> bin
  end

  defp pack_uint(bin, bits) when is_binary(bin) and rem(bits, 8) == 0 do
    bytes = div(bits, 8)

    if byte_size(bin) > bytes do
      raise ArgumentError,
            "encode_packed uint#{bits}: binary too long (#{byte_size(bin)} bytes for uint#{bits})"
    end

    pad_size = bytes - byte_size(bin)
    :binary.copy(<<0>>, pad_size) <> bin
  end

  @spec pack_int(integer(), pos_integer()) :: binary()
  defp pack_int(int, bits) when is_integer(int) and rem(bits, 8) == 0 and bits > 0 and bits <= 256 do
    max = Bitwise.bsl(1, bits - 1)

    if int >= max or int < -max do
      raise ArgumentError,
            "encode_packed int#{bits}: #{int} doesn't fit in signed range (-#{max}..#{max - 1})"
    end

    if int >= 0 do
      pack_uint(int, bits)
    else
      pack_uint(Bitwise.bsl(1, bits) + int, bits)
    end
  end

  @spec encode_int(integer(), pos_integer()) :: binary()
  defp encode_int(int, desired_size_bits) when rem(desired_size_bits, 8) == 0 and is_integer(int) do
    desired_size_bytes = ceil(desired_size_bits / 8)
    max = Bitwise.bsl(1, desired_size_bits - 1)

    if int >= max or int < -max do
      raise(
        "Data overflow encoding int, data `#{int}` cannot fit in #{desired_size_bits}-bit signed range (-#{max}..#{max - 1})"
      )
    end

    sign_byte = if(int < 0, do: <<0xFF>>, else: <<0x00>>)

    significant_bytes =
      if int >= 0 do
        maybe_encode_unsigned(abs(int))
      else
        # two's complement encoding: 2**(integer_bit_size) - abs(integer)
        actual_bit_size = (-1 * int) |> :binary.encode_unsigned() |> bit_size()
        maybe_encode_unsigned(Bitwise.bsl(1, actual_bit_size) + int)
      end

    Math.pad(significant_bytes, desired_size_bytes, :left, fill_byte: sign_byte)
  end

  # Note, we'll accept a binary or an integer here, so long as the
  # binary is not longer than our allowed data size
  @spec encode_uint(integer() | binary(), pos_integer()) :: binary()
  defp encode_uint(data, size_in_bits) when rem(size_in_bits, 8) == 0 do
    size_in_bytes = round(size_in_bits / 8)
    bin = maybe_encode_unsigned(data)

    if byte_size(bin) > size_in_bytes,
      do: raise("Data overflow encoding uint, data `#{data}` cannot fit in #{size_in_bytes * 8} bits")

    Math.pad(bin, size_in_bytes, :left)
  end

  # Returns the total number of static types, accounting for inlined tuples
  @spec count([arg_type()]) :: non_neg_integer()
  defp count(sub_types) do
    Enum.sum_by(sub_types, &do_count/1)
  end

  @spec do_count(arg_type()) :: non_neg_integer()
  defp do_count(%{type: {:tuple, sub_types} = t}) do
    if FunctionSelector.dynamic?(t) do
      1
    else
      Enum.sum_by(sub_types, &do_count/1)
    end
  end

  # A static `T[k]` is inlined into the head as `enc(X[0]) ... enc(X[k-1])`
  # (abi-spec.html#formal-specification-of-the-encoding), so it occupies
  # `k` times the head size of its element type -- not one word. Counting it
  # as one word understates `tail_start` for every dynamic sibling.
  defp do_count(%{type: {:array, sub_type, element_count} = t}) do
    if FunctionSelector.dynamic?(t) do
      1
    else
      element_count * do_count(%{type: sub_type})
    end
  end

  defp do_count(_), do: 1

  @spec data_to_list([arg_type()], [any()] | tuple() | map()) :: [any()]
  defp data_to_list(_types, data) when is_list(data), do: data
  defp data_to_list(_types, data) when is_tuple(data), do: Tuple.to_list(data)

  defp data_to_list(types, data) when is_map(data) do
    Enum.map(types, &fetch_named_field(&1, data))
  end

  @spec fetch_named_field(arg_type(), map()) :: any()
  defp fetch_named_field(type, data) do
    if type[:name] do
      fetch_by_name(type, data)
    else
      raise "Cannot decode struct with map when no name given in type `#{inspect(type)}`\n\n\tfor data:\n\n\t#{inspect(data)}"
    end
  end

  @spec fetch_by_name(arg_type(), map()) :: any()
  defp fetch_by_name(type, data) do
    name = type[:name]
    underscored = Macro.underscore(name)
    atom_lookup = existing_atom(underscored)

    cond do
      Map.has_key?(data, name) ->
        Map.fetch!(data, name)

      atom_in_map?(atom_lookup, data) ->
        {:ok, atom_name} = atom_lookup
        Map.fetch!(data, atom_name)

      true ->
        raise "Cannot find key `:#{underscored}` or `\"#{name}\"` for type `#{inspect(type)}`\n\n\tin data:\n\n\t#{inspect(data)}"
    end
  end

  @spec atom_in_map?({:ok, atom()} | :error, map()) :: boolean()
  defp atom_in_map?({:ok, atom}, data), do: Map.has_key?(data, atom)
  defp atom_in_map?(:error, _data), do: false

  # Returns `{:ok, atom}` when the snake_case atom for `string` already
  # exists in the VM atom table, or `:error` otherwise. We never *create*
  # atoms here — `fetch_by_name/2` only uses the atom for a map lookup, and
  # a consumer's input map can only contain atom keys that already exist in
  # the VM. The tagged-tuple shape (rather than `atom() | nil`) keeps the
  # "no existing atom" case distinct from a successful lookup that happens
  # to return `nil` — `Macro.underscore("Nil") == "nil"` and
  # `String.to_existing_atom("nil") == nil`, so a field whose snake_case
  # form is `"nil"` would otherwise be indistinguishable from the
  # not-interned case.
  @spec existing_atom(String.t()) :: {:ok, atom()} | :error
  defp existing_atom(string) do
    {:ok, String.to_existing_atom(string)}
  rescue
    ArgumentError -> :error
  end

  @spec maybe_encode_unsigned(binary() | integer()) :: binary()
  defp maybe_encode_unsigned(bin) when is_binary(bin), do: bin
  defp maybe_encode_unsigned(int) when is_integer(int), do: :binary.encode_unsigned(int)
end
