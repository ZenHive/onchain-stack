defmodule Onchain.ABI.TypeEncoder do
  @moduledoc """
  `Onchain.ABI.TypeEncoder` is responsible for encoding types to the format
  expected by Solidity. We generally take a function selector and an
  array of data and encode that array according to the specification.
  """

  use Descripex, namespace: "/codec"

  alias Onchain.ABI.Alloy
  alias Onchain.ABI.FunctionSelector

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
      ...> |> Onchain.ABI.TypeEncoder.encode(
      ...>      %Onchain.ABI.FunctionSelector{
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
      ...> |> Onchain.ABI.TypeEncoder.encode(
      ...>      %Onchain.ABI.FunctionSelector{
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
      ...> |> Onchain.ABI.TypeEncoder.encode(
      ...>      %Onchain.ABI.FunctionSelector{
      ...>        function: "price",
      ...>        types: [
      ...>          %{type: :address}
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "aea91078000000000000000000000000ffffffffffffffffffffffffffffffffffffffff"

      iex> [1]
      ...> |> Onchain.ABI.TypeEncoder.encode(
      ...>      %Onchain.ABI.FunctionSelector{
      ...>        function: "price",
      ...>        types: [
      ...>          %{type: :address}
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "aea910780000000000000000000000000000000000000000000000000000000000000001"

      iex> ["hello world"]
      ...> |> Onchain.ABI.TypeEncoder.encode(
      ...>      %Onchain.ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: :string},
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000000b68656c6c6f20776f726c64000000000000000000000000000000000000000000"

      iex> [{{0x11, 0x22}, "hello world"}]
      ...> |> Onchain.ABI.TypeEncoder.encode(
      ...>      %Onchain.ABI.FunctionSelector{
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
      ...> |> Onchain.ABI.TypeEncoder.encode(
      ...>      %Onchain.ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:tuple, [%{type: :string}, %{type: :bool}]}}
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000007617765736f6d6500000000000000000000000000000000000000000000000000"

      iex> [{17, true, <<32, 64>>}]
      ...> |> Onchain.ABI.TypeEncoder.encode(
      ...>      %Onchain.ABI.FunctionSelector{
      ...>        function: nil,
      ...>        types: [
      ...>          %{type: {:tuple, [%{type: {:uint, 32}}, %{type: :bool}, %{type: {:bytes, 2}}]}}
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000001100000000000000000000000000000000000000000000000000000000000000012040000000000000000000000000000000000000000000000000000000000000"

      iex> [[17, 1]]
      ...> |> Onchain.ABI.TypeEncoder.encode(
      ...>      %Onchain.ABI.FunctionSelector{
      ...>        function: "baz",
      ...>        types: [
      ...>          %{type: {:array, {:uint, 32}, 2}}
      ...>        ]
      ...>      }
      ...>    )
      ...> |> Base.encode16(case: :lower)
      "3d0ec53300000000000000000000000000000000000000000000000000000000000000110000000000000000000000000000000000000000000000000000000000000001"

      iex> [[17, 1], true]
      ...> |> Onchain.ABI.TypeEncoder.encode(
      ...>      %Onchain.ABI.FunctionSelector{
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
      ...> |> Onchain.ABI.TypeEncoder.encode(
      ...>      %Onchain.ABI.FunctionSelector{
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
      ...> |> Onchain.ABI.TypeEncoder.encode(
      ...>   %Onchain.ABI.FunctionSelector{
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
      ...> |> Onchain.ABI.TypeEncoder.encode(
      ...>      %Onchain.ABI.FunctionSelector{
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
      ...> |> Onchain.ABI.TypeEncoder.encode(%Onchain.ABI.FunctionSelector{function: nil, types: [%{type: {:int, 16}}]})
      ...> |> Base.encode16(case: :lower)
      "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff01"
  """
  @spec encode([any()], FunctionSelector.t()) :: binary()
  def encode(data, function_selector) do
    Onchain.ABI.method_id(function_selector) <>
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
  Simiar to `Onchain.ABI.TypeEncoder.encode/2` except we accept
  an array of types instead of a function selector. We also
  do not pre-pend the method id.

  ## Examples

      iex> [{"awesome", true}]
      ...> |> Onchain.ABI.TypeEncoder.encode_raw([%{type: {:tuple, [%{type: :string}, %{type: :bool}]}}])
      ...> |> Base.encode16(case: :lower)
      "000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000007617765736f6d6500000000000000000000000000000000000000000000000000"
  """
  @spec encode_raw([any()], [FunctionSelector.argument_type()]) :: binary()
  def encode_raw(data, types) do
    Alloy.encode_raw(data, types)
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

      iex> Onchain.ABI.TypeEncoder.encode_packed(
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

    Alloy.encode_packed(data, types)
  end
end
