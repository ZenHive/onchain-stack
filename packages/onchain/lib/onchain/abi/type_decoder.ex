defmodule Onchain.ABI.TypeDecoder do
  @moduledoc """
  `Onchain.ABI.TypeDecoder` is responsible for decoding types to the format
  expected by Solidity. We generally take a function selector and binary
  data and decode that into the original arguments according to the
  specification.
  """

  use Descripex, namespace: "/codec"

  alias Onchain.ABI.FunctionSelector
  alias Onchain.ABI.Math

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
      ...> |> Onchain.ABI.TypeDecoder.decode(
      ...>      %Onchain.ABI.FunctionSelector{
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
      ...> |> Onchain.ABI.TypeDecoder.decode(
      ...>      %Onchain.ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: :string}
      ...>        ]
      ...>      }
      ...>    )
      ["hello world"]

      iex> "00000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000001"
      ...> |> Base.decode16!(case: :lower)
      ...> |> Onchain.ABI.TypeDecoder.decode(
      ...>      %Onchain.ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:tuple, [%{type: {:uint, 32}, name: "a"}, %{type: :bool, name: "b"}]}}
      ...>        ]
      ...>      }
      ...>    )
      [{17, true}]

      iex> "00000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000001"
      ...> |> Base.decode16!(case: :lower)
      ...> |> Onchain.ABI.TypeDecoder.decode(
      ...>      %Onchain.ABI.FunctionSelector{
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
      ...> |> Onchain.ABI.TypeDecoder.decode(
      ...>      %Onchain.ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:tuple, [%{type: {:uint, 32}}, %{type: :bool}]}}
      ...>        ]
      ...>      }
      ...>    )
      [{17, true}]

      iex> "00000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000001"
      ...> |> Base.decode16!(case: :lower)
      ...> |> Onchain.ABI.TypeDecoder.decode(
      ...>      %Onchain.ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:array, {:uint, 32}, 2}}
      ...>        ]
      ...>      }
      ...>    )
      [[17, 1]]

      iex> "000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000001"
      ...> |> Base.decode16!(case: :lower)
      ...> |> Onchain.ABI.TypeDecoder.decode(
      ...>      %Onchain.ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:array, {:uint, 32}}}
      ...>        ]
      ...>      }
      ...>    )
      [[17, 1]]

      iex> "0000000000000000000000000000000000000000000000000000000000000011000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000011020000000000000000000000000000000000000000000000000000000000000"
      ...> |> Base.decode16!(case: :lower)
      ...> |> Onchain.ABI.TypeDecoder.decode(
      ...>      %Onchain.ABI.FunctionSelector{
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
      ...> |> Onchain.ABI.TypeDecoder.decode(
      ...>      %Onchain.ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:tuple, [%{type: :string}, %{type: :bool}]}}
      ...>        ]
      ...>      }
      ...>    )
      [{"awesome", true}]

      iex> "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000"
      ...> |> Base.decode16!(case: :lower)
      ...> |> Onchain.ABI.TypeDecoder.decode(
      ...>      %Onchain.ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:tuple, [%{type: {:array, :address}}]}}
      ...>        ]
      ...>      }
      ...>    )
      [{[]}]

      iex> "00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000c556e617574686f72697a656400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000000000000000000000204a2bf2ff0a4eaf1890c8d8679eaa446fb852c4000000000000000000000000861d9af488d5fa485bb08ab6912fff4f7450849a"
      ...> |> Base.decode16!(case: :lower)
      ...> |> Onchain.ABI.TypeDecoder.decode(
      ...>      %Onchain.ABI.FunctionSelector{
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
      ...> |> Onchain.ABI.TypeDecoder.decode(
      ...>      %Onchain.ABI.FunctionSelector{
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
  Similar to `Onchain.ABI.TypeDecoder.decode/2` except accepts a list of types instead
  of a function selector.

  ## Examples

      iex> "000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000007617765736f6d6500000000000000000000000000000000000000000000000000"
      ...> |> Base.decode16!(case: :lower)
      ...> |> Onchain.ABI.TypeDecoder.decode_raw([%{type: {:tuple, [%{type: :string}, %{type: :bool}]}}])
      [{"awesome", true}]
  """
  @spec decode_raw(binary(), [FunctionSelector.argument_type()], keyword()) ::
          [any()]
  def decode_raw(encoded_data, types, opts \\ []) do
    Onchain.ABI.Alloy.decode_raw(encoded_data, types, opts)
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
  second-pass result; exposed because event-log decoding in `Onchain.ABI.Event`
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
