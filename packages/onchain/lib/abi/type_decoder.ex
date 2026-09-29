defmodule ABI.TypeDecoder do
  @moduledoc """
  `ABI.TypeDecoder` is responsible for decoding types to the format
  expected by Solidity. We generally take a function selector and binary
  data and decode that into the original arguments according to the
  specification.
  """

  use Descripex, namespace: "/codec"

  alias ABI.FunctionSelector
  alias ABI.Math

  @word_size_bytes 32
  @word_size_bits @word_size_bytes * 8

  defmodule StrictViolation do
    @moduledoc false

    defexception [:detail, :message]

    @impl true
    def exception(detail) do
      %__MODULE__{
        detail: detail,
        message: "strict ABI decode violation: #{inspect(detail)}"
      }
    end
  end

  api(
    :decode,
    "Decode an ABI-encoded payload into a list of values, using a FunctionSelector to drive type interpretation.",
    params: [
      encoded_data: [
        kind: :value,
        description:
          "Raw ABI payload (selector prefix already stripped); pass the binary that follows the 4-byte method id"
      ],
      function_selector: [
        kind: :value,
        description:
          "Pre-parsed FunctionSelector. When :function is non-nil, the payload is interpreted as a single tuple (call-args shape); otherwise types are read sequentially"
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          "Optional keyword list. Supports decode_structs: true to render named tuples as maps with snake_case atom keys"
      ]
    ],
    returns: %{type: :list, description: "List of decoded values in argument order"},
    composes_with: [:decode_raw]
  )

  @doc """
  Decodes the given data based on the function selector.

  Note, we don't currently try to guess the function name?

  ## Examples

      iex> "00000000000000000000000000000000000000000000000000000000000000450000000000000000000000000000000000000000000000000000000000000001"
      ...> |> Base.decode16!(case: :lower)
      ...> |> ABI.TypeDecoder.decode(
      ...>      %ABI.FunctionSelector{
      ...>        function: "baz",
      ...>        types: [
      ...>          %{type: {:uint, 32}},
      ...>          %{type: :bool}
      ...>        ],
      ...>        returns: :bool
      ...>      }
      ...>    )
      [69, true]

      iex> "000000000000000000000000000000000000000000000000000000000000000b68656c6c6f20776f726c64000000000000000000000000000000000000000000"
      ...> |> Base.decode16!(case: :lower)
      ...> |> ABI.TypeDecoder.decode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: :string}
      ...>        ]
      ...>      }
      ...>    )
      ["hello world"]

      iex> "00000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000001"
      ...> |> Base.decode16!(case: :lower)
      ...> |> ABI.TypeDecoder.decode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:tuple, [%{type: {:uint, 32}, name: "a"}, %{type: :bool, name: "b"}]}}
      ...>        ]
      ...>      }
      ...>    )
      [{17, true}]

      iex> "00000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000001"
      ...> |> Base.decode16!(case: :lower)
      ...> |> ABI.TypeDecoder.decode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:tuple, [%{type: {:uint, 32}, name: "a"}, %{type: :bool, name: "b"}]}}
      ...>        ]
      ...>      },
      ...>      decode_structs: true
      ...>    )
      [%{a: 17, b: true}]

      iex> "00000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000001"
      ...> |> Base.decode16!(case: :lower)
      ...> |> ABI.TypeDecoder.decode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:tuple, [%{type: {:uint, 32}}, %{type: :bool}]}}
      ...>        ]
      ...>      }
      ...>    )
      [{17, true}]

      iex> "00000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000001"
      ...> |> Base.decode16!(case: :lower)
      ...> |> ABI.TypeDecoder.decode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:array, {:uint, 32}, 2}}
      ...>        ]
      ...>      }
      ...>    )
      [[17, 1]]

      iex> "000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000001"
      ...> |> Base.decode16!(case: :lower)
      ...> |> ABI.TypeDecoder.decode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:array, {:uint, 32}}}
      ...>        ]
      ...>      }
      ...>    )
      [[17, 1]]

      iex> "0000000000000000000000000000000000000000000000000000000000000011000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000011020000000000000000000000000000000000000000000000000000000000000"
      ...> |> Base.decode16!(case: :lower)
      ...> |> ABI.TypeDecoder.decode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:array, {:uint, 32}, 2}},
      ...>          %{type: :bool},
      ...>          %{type: {:bytes, 2}}
      ...>        ]
      ...>      }
      ...>    )
      [[17, 1], true, <<16, 32>>]

      iex> "000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000007617765736f6d6500000000000000000000000000000000000000000000000000"
      ...> |> Base.decode16!(case: :lower)
      ...> |> ABI.TypeDecoder.decode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:tuple, [%{type: :string}, %{type: :bool}]}}
      ...>        ]
      ...>      }
      ...>    )
      [{"awesome", true}]

      iex> "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000"
      ...> |> Base.decode16!(case: :lower)
      ...> |> ABI.TypeDecoder.decode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:tuple, [%{type: {:array, :address}}]}}
      ...>        ]
      ...>      }
      ...>    )
      [{[]}]

      iex> "00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000c556e617574686f72697a656400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000204a2bf2ff0a4eaf1890c8d8679eaa446fb852c4000000000000000000000000861d9af488d5fa485bb08ab6912fff4f7450849a"
      ...> |> Base.decode16!(case: :lower)
      ...> |> ABI.TypeDecoder.decode(
      ...>      %ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [%{type: {:tuple,[
      ...>          %{type: :string},
      ...>          %{type: {:array, {:uint, 256}}}
      ...>        ]}}]
      ...>      }
      ...>    )
      [{
        "Unauthorized",
        [
          184341788326688649239867304918349890235378717380,
          765664983403968947098136133435535343021479462042,
        ]
      }]

      iex> "000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000034241540000000000000000000000000000000000000000000000000000000000"
      ...> |> Base.decode16!(case: :lower)
      ...> |> ABI.TypeDecoder.decode(
      ...>      %ABI.FunctionSelector{
      ...>        function: "price",
      ...>        types: [
      ...>          %{type: :string}
      ...>        ],
      ...>        returns: {:uint, 256}
      ...>      }
      ...>    )
      ["BAT"]
  """
  @spec decode(binary(), FunctionSelector.t(), keyword()) :: [any()]
  def decode(encoded_data, function_selector, opts \\ []) do
    if is_nil(function_selector.function) do
      decode_raw(encoded_data, function_selector.types, opts)
    else
      [res] = decode_raw(encoded_data, [%{type: {:tuple, function_selector.types}}], opts)

      Tuple.to_list(res)
    end
  end

  api(
    :decode_raw,
    "Decode an ABI-encoded payload directly against an explicit type list, without consulting a FunctionSelector.",
    params: [
      encoded_data: [
        kind: :value,
        description: "Raw ABI payload — for example return values, event log data, or pre-routed calldata"
      ],
      types: [
        kind: :value,
        description:
          "List of FunctionSelector argument-type maps (each %{type: ...} optionally with :name) describing the expected sequence"
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          "Optional keyword list. Supports decode_structs: true to render named tuples as maps with snake_case atom keys"
      ]
    ],
    returns: %{type: :list, description: "List of decoded values in type order"},
    composes_with: [:decode]
  )

  @doc """
  Similar to `ABI.TypeDecoder.decode/2` except accepts a list of types instead
  of a function selector.

  ## Examples

      iex> "000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000007617765736f6d6500000000000000000000000000000000000000000000000000"
      ...> |> Base.decode16!(case: :lower)
      ...> |> ABI.TypeDecoder.decode_raw([%{type: {:tuple, [%{type: :string}, %{type: :bool}]}}])
      [{"awesome", true}]
  """
  @spec decode_raw(binary(), [FunctionSelector.argument_type()], keyword()) ::
          [any()]
  def decode_raw(encoded_data, types, opts \\ []) do
    do_decode(types, encoded_data, [], opts)
  end

  @spec do_decode(
          [FunctionSelector.argument_type()],
          binary(),
          [any()],
          keyword()
        ) :: [any()]
  defp do_decode([], bin, _, opts) when byte_size(bin) > 0 do
    if strict?(opts) do
      strict_violation!({:trailing_bytes, byte_size(bin)})
    else
      raise("Found extra binary data: #{inspect(bin)}")
    end
  end

  defp do_decode([], _, acc, _opts), do: Enum.reverse(acc)

  defp do_decode([type | remaining_types], data, acc, opts) do
    {decoded, remaining_data} = decode_type(type.type, data, opts)

    do_decode(remaining_types, remaining_data, [decoded | acc], opts)
  end

  @spec decode_type(FunctionSelector.type(), binary(), keyword()) ::
          {any(), binary()}
  defp decode_type({:uint, size_in_bits}, data, opts) do
    decode_uint(data, size_in_bits, opts)
  end

  defp decode_type({:int, size_in_bits}, data, opts) do
    decode_int(data, size_in_bits, opts)
  end

  defp decode_type(:address, data, _opts), do: decode_bytes(data, 20, :left)

  defp decode_type(:function, data, _opts), do: decode_bytes(data, 24, :right)

  defp decode_type(:bool, data, opts) do
    {encoded_value, rest} = decode_uint(data, 8, opts)

    value =
      case encoded_value do
        1 -> true
        0 -> false
        other -> decode_invalid_bool!(other, opts)
      end

    {value, rest}
  end

  defp decode_type(:string, data, opts) do
    {string_size_in_bytes, rest} = decode_uint(data, 256, opts)
    validate_dynamic_length!(rest, string_size_in_bytes, :string, opts)
    decode_bytes(rest, string_size_in_bytes, :right)
  end

  defp decode_type(:bytes, data, opts) do
    {byte_size, rest} = decode_uint(data, 256, opts)
    validate_dynamic_length!(rest, byte_size, :bytes, opts)
    decode_bytes(rest, byte_size, :right)
  end

  defp decode_type({:bytes, 0}, data, _opts), do: {<<>>, data}

  defp decode_type({:bytes, size}, data, _opts) when size > 0 and size <= 32 do
    decode_bytes(data, size, :right)
  end

  defp decode_type({:array, type}, data, opts) do
    {element_count, rest} = decode_uint(data, 256, opts)
    decode_type({:array, type, element_count}, rest, opts)
  end

  defp decode_type({:array, _type, 0}, data, _opts), do: {[], data}

  defp decode_type({:array, type, element_count}, data, opts) do
    validate_element_count!(data, type, element_count, opts)

    repeated_type = Enum.map(1..element_count, fn _ -> %{type: type} end)

    {tuple, rest} = decode_type({:tuple, repeated_type}, data, opts)

    {Tuple.to_list(tuple), rest}
  end

  defp decode_type({:tuple, types}, starting_data, opts) do
    decode_structs = Keyword.get(opts, :decode_structs, false)

    # First pass, decode static types. `Enum.map_reduce/3` threads `data`
    # through in order and returns `elements` already in `types` order, so no
    # explicit reverse is needed to undo an accumulator-prepend inversion.
    {elements, rest} =
      Enum.map_reduce(types, starting_data, fn %{type: type}, data ->
        if FunctionSelector.dynamic?(type) do
          {tail_position, rest} = decode_type({:uint, 256}, data, opts)

          {{:dynamic, type, tail_position}, rest}
        else
          decode_type(type, data, opts)
        end
      end)

    # Second pass, decode dynamic types. Same order-preserving property as
    # above, so `elements` is already in `types` order for `tuple_value`.
    {elements, rest} =
      Enum.map_reduce(elements, rest, fn el, data ->
        case el do
          {:dynamic, type, _tail_position} -> decode_type(type, data, opts)
          _ -> {el, data}
        end
      end)

    {tuple_value(types, elements, decode_structs), rest}
  end

  defp decode_type(els, _, _) do
    raise "Unsupported decoding type: #{inspect(els)}"
  end

  api(
    :tuple_value,
    "Combine a list of ABI argument types with decoded element values, returning either a tuple or, when decode_structs is enabled and every type carries a non-empty :name, a map keyed by snake_case atom field names.",
    params: [
      types: [
        kind: :value,
        description: "List of FunctionSelector argument-type maps; each must carry :name for the struct branch to apply"
      ],
      elements: [kind: :value, description: "Decoded values in the same order as types"],
      decode_structs: [
        kind: :value,
        description:
          "Boolean flag. When true and every type has a non-empty :name, returns a map; otherwise returns a tuple"
      ]
    ],
    returns: %{
      type: :union,
      description:
        "Map keyed by atom field names when decode_structs is true and all names are present; otherwise a tuple of the elements in order"
    }
  )

  @doc """
  Combines a list of ABI argument types with a list of decoded element values
  into either a tuple or (when `decode_structs` is true and every type carries
  a non-empty `:name`) a map keyed by the existing snake_case atom for each
  field name.

  Field-name atoms must already exist in the VM atom table — `decode_structs:
  true` calls `String.to_existing_atom/1` on `Macro.underscore(name)` and
  raises `ArgumentError` if the atom has not been interned. This bounds atom
  creation to the set of field names the caller has explicitly referenced in
  their code, closing a DoS surface for consumers that ingest ABIs from
  arbitrary sources.

  Used internally by `decode_type({:tuple, types}, ...)` to render the
  second-pass result; exposed because event-log decoding in `ABI.Event`
  reuses the same shape.
  """
  @spec tuple_value(
          [FunctionSelector.argument_type()],
          [any()],
          boolean()
        ) :: map() | tuple()
  def tuple_value(types, elements, decode_structs) do
    if decode_structs and
         Enum.all?(types, fn type -> type[:name] != nil and type[:name] != <<>> end) do
      types
      |> Enum.zip(elements)
      |> Map.new(fn {type, element} ->
        {atom_key_for!(type[:name]), element}
      end)
    else
      List.to_tuple(elements)
    end
  end

  @spec atom_key_for!(String.t()) :: atom()
  defp atom_key_for!(name) do
    underscored = Macro.underscore(name)

    try do
      String.to_existing_atom(underscored)
    rescue
      ArgumentError ->
        reraise ArgumentError,
                "decode_structs: true requires the snake_case field atom :#{underscored} " <>
                  "(from ABI field \"#{name}\") to already exist in the VM atom table. " <>
                  "Reference the atom in your code (e.g., in a module attribute, a `@type`, " <>
                  "or a compile-time list) before the first decode call. See README " <>
                  "\"Pre-interning atoms for decode_structs: true\" for guidance.",
                __STACKTRACE__
    end
  end

  @spec decode_uint(binary(), integer(), keyword()) :: {integer(), binary()}
  defp decode_uint(data, size_in_bits, opts) do
    validate_uint_padding!(data, size_in_bits, opts)
    total_bit_size = size_in_bits + Math.mod(@word_size_bits - size_in_bits, @word_size_bits)

    <<value::integer-size(^total_bit_size), rest::binary>> = data

    {value, rest}
  end

  @spec decode_int(binary(), integer(), keyword()) :: {integer(), binary()}
  defp decode_int(data, size_in_bits, opts) do
    validate_int_padding!(data, size_in_bits, opts)
    total_bit_size = size_in_bits + Math.mod(@word_size_bits - size_in_bits, @word_size_bits)
    <<value::integer-signed-big-size(^total_bit_size), rest::binary>> = data

    {value, rest}
  end

  # An array of `n` elements needs at least `n * min_element_words(element)`
  # words of payload behind it, so a larger count can never be satisfied.
  # Checked BEFORE the element type list is materialized: the count comes from
  # a chain-supplied length prefix, and building a list that long is an
  # allocation DoS the later decode failure would never get the chance to
  # prevent. Zero-width element types (an empty tuple, a fixed-size array of
  # length zero, or a nest of those) admit no such bound and are left
  # unguarded — Solidity cannot emit them.
  @spec validate_element_count!(binary(), FunctionSelector.type(), non_neg_integer(), keyword()) ::
          :ok
  defp validate_element_count!(data, type, element_count, opts) do
    min_words = min_element_words(type)
    available_words = div(byte_size(data), @word_size_bytes)

    cond do
      min_words == 0 or element_count * min_words <= available_words ->
        :ok

      strict?(opts) ->
        strict_violation!(
          {:length_out_of_bounds,
           %{
             type: {:array, type},
             length: element_count,
             available: byte_size(data)
           }}
        )

      true ->
        raise "Array element count #{element_count} exceeds the #{available_words} remaining 32-byte words"
    end
  end

  # Smallest number of 32-byte words one element of this type can occupy: a
  # single tail-offset word when dynamic, the summed static width otherwise.
  @spec min_element_words(FunctionSelector.type()) :: non_neg_integer()
  defp min_element_words(type) do
    if FunctionSelector.dynamic?(type) do
      1
    else
      static_element_words(type)
    end
  end

  @spec static_element_words(FunctionSelector.type()) :: non_neg_integer()
  defp static_element_words({:tuple, types}) do
    Enum.sum_by(types, fn %{type: member} -> min_element_words(member) end)
  end

  defp static_element_words({:array, inner, count}), do: count * min_element_words(inner)
  defp static_element_words(_type), do: 1

  @spec strict?(keyword()) :: boolean()
  defp strict?(opts), do: Keyword.get(opts, :strict, false)

  @spec strict_violation!(term()) :: no_return()
  defp strict_violation!(detail) do
    raise StrictViolation, detail
  end

  @spec decode_invalid_bool!(integer(), keyword()) :: no_return()
  defp decode_invalid_bool!(value, opts) do
    if strict?(opts) do
      strict_violation!({:invalid_bool, value})
    else
      raise CaseClauseError, term: value
    end
  end

  @spec validate_uint_padding!(binary(), integer(), keyword()) :: :ok
  defp validate_uint_padding!(data, size_in_bits, opts) do
    validate_left_padding!(
      data,
      size_in_bits,
      :zero,
      {:uint, size_in_bits},
      opts
    )
  end

  @spec validate_int_padding!(binary(), integer(), keyword()) :: :ok
  defp validate_int_padding!(data, size_in_bits, opts) do
    validate_left_padding!(
      data,
      size_in_bits,
      :sign,
      {:int, size_in_bits},
      opts
    )
  end

  @spec validate_left_padding!(
          binary(),
          integer(),
          :zero | :sign,
          term(),
          keyword()
        ) :: :ok
  defp validate_left_padding!(_data, @word_size_bits, _mode, _type, _opts), do: :ok

  defp validate_left_padding!(data, size_in_bits, mode, type, opts) do
    if strict?(opts) do
      value_size = div(size_in_bits, 8)
      padding_size = @word_size_bytes - value_size

      {padding, value} = split_left_padded(data, padding_size, value_size)

      expected = expected_left_padding(mode, padding_size, value)

      if padding == expected do
        :ok
      else
        strict_violation!({:non_canonical_padding, %{type: type}})
      end
    else
      :ok
    end
  end

  @spec expected_left_padding(:zero | :sign, non_neg_integer(), binary()) ::
          binary()
  defp expected_left_padding(:zero, padding_size, _value) do
    :binary.copy(<<0>>, padding_size)
  end

  defp expected_left_padding(:sign, padding_size, value) do
    <<sign::1, _::bitstring>> = value
    fill = if sign == 1, do: <<0xFF>>, else: <<0>>
    :binary.copy(fill, padding_size)
  end

  @spec split_left_padded(binary(), non_neg_integer(), non_neg_integer()) ::
          {binary(), binary()}
  defp split_left_padded(data, padding_size, value_size) do
    <<padding::binary-size(^padding_size), after_padding::binary>> = data
    <<value::binary-size(^value_size), _rest::binary>> = after_padding

    {padding, value}
  end

  @spec validate_dynamic_length!(
          binary(),
          non_neg_integer(),
          atom(),
          keyword()
        ) :: :ok
  defp validate_dynamic_length!(data, size_in_bytes, type, opts) do
    if strict?(opts) do
      total_size =
        size_in_bytes +
          Math.mod(
            @word_size_bytes - Math.mod(size_in_bytes, @word_size_bytes),
            @word_size_bytes
          )

      if byte_size(data) >= total_size do
        :ok
      else
        strict_violation!(
          {:length_out_of_bounds,
           %{
             type: type,
             length: size_in_bytes,
             available: byte_size(data)
           }}
        )
      end
    else
      :ok
    end
  end

  api(
    :decode_bytes,
    "Read size_in_bytes of content from a 32-byte-aligned ABI word, skipping padding on the matching side. Used to extract address, uint/int, bytes<M>, and string payloads from their slots.",
    params: [
      data: [kind: :value, description: "Binary containing one padded ABI word followed by remaining bytes"],
      size_in_bytes: [kind: :value, description: "Logical field width to extract from the padded slot"],
      padding_direction: [
        kind: :value,
        description: "Side that was padded — :left for address/uint/int, :right for bytes<M>/string"
      ]
    ],
    returns: %{
      type: :tuple,
      description:
        "Two-tuple {value, rest} where value is the unpadded content and rest is whatever follows the padded word"
    }
  )

  @doc """
  Reads `size_in_bytes` of content out of `data`, skipping the 32-byte-slot
  padding on whichever side matches `padding_direction` (`:left` for
  left-padded types like `address` and `uint`/`int`, `:right` for
  right-padded types like `bytes<M>` and `string`). Returns `{value, rest}`.
  """
  @spec decode_bytes(binary(), integer(), atom()) :: {binary(), binary()}
  def decode_bytes(data, size_in_bytes, padding_direction) do
    Math.unpad(data, size_in_bytes, padding_direction)
  end
end
