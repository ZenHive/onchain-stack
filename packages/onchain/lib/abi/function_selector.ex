defmodule ABI.FunctionSelector do
  @moduledoc """
  Module to help parse the ABI function signatures, e.g.
  `my_function(uint64, string[])`.
  """

  use Descripex, namespace: "/selector"

  alias ABI.Parser

  @typedoc """
  A Solidity ABI type.

  Note that `address payable` is **not** a distinct variant. Solidity ABI
  JSON only emits `"address"` for both `address` and `address payable`,
  and the on-the-wire encoding is identical (20-byte left-padded). Payability
  is a property of function state mutability (`:payable` in
  `t:state_mutability/0`), not the address type itself, so both forms
  collapse to `:address` here.
  """
  @type type ::
          {:uint, integer()}
          | :bool
          | :bytes
          | {:bytes, pos_integer()}
          | :string
          | :address
          | :function
          | {:int, integer()}
          | {:array, type}
          | {:array, type, non_neg_integer}
          | {:tuple, [argument_type]}

  @type argument_type ::
          %{
            :type => type,
            optional(:name) => String.t(),
            optional(:indexed) => boolean()
          }

  @type function_type ::
          :function | :constructor | :fallback | :receive | :error | :event

  @type state_mutability :: :nonpayable | :pure | :view | :payable

  @type t :: %__MODULE__{
          function: String.t() | nil,
          function_type: function_type() | nil,
          state_mutability: state_mutability() | nil,
          types: [argument_type()],
          returns: type() | [argument_type()] | :anonymous | nil
        }

  # An ABI JSON parameter object: a string-keyed map (`"name"`, `"type"`,
  # `"indexed"`, `"components"`) as produced by decoding ABI JSON.
  @typep spec_param :: %{optional(String.t()) => term()}

  defstruct [:function, :function_type, :state_mutability, :types, :returns]

  api(
    :decode,
    "Parse a Solidity function or event signature string into a FunctionSelector struct exposing function name, parameter types, and (when present) named parameters.",
    params: [
      signature: [
        kind: :value,
        description:
          "Signature string such as transfer(address,uint256), or a parenthesized type list such as (uint256,bool); supports nested tuples and arrays, optional parameter names, and the indexed keyword for event parameters"
      ]
    ],
    returns: %{
      type: :struct,
      description:
        "ABI.FunctionSelector struct with :function, :types, optional :function_type/:state_mutability/:returns/:indexed metadata"
    },
    composes_with: [:encode]
  )

  @doc """
  Decodes a function selector to a struct.

  ## Examples

      iex> ABI.FunctionSelector.decode("bark(uint256,bool)")
      %ABI.FunctionSelector{
        function: "bark",
        types: [
          %{type: {:uint, 256}},
          %{type: :bool}
        ]
      }

      iex> ABI.FunctionSelector.decode("bark(uint256 name, bool loud)")
      %ABI.FunctionSelector{
        function: "bark",
        types: [
          %{type: {:uint, 256}, name: "name"},
          %{type: :bool, name: "loud"}
        ]
      }

      iex> ABI.FunctionSelector.decode("bark(uint256 name,bool indexed loud)")
      %ABI.FunctionSelector{
        function: "bark",
        types: [
          %{type: {:uint, 256}, name: "name"},
          %{type: :bool, name: "loud", indexed: true}
        ]
      }

      iex> ABI.FunctionSelector.decode("(uint256,bool)")
      %ABI.FunctionSelector{
        function: nil,
        types: [
          %{type: {:uint, 256}},
          %{type: :bool}
        ]
      }

      iex> ABI.FunctionSelector.decode("growl(uint,address,string[])")
      %ABI.FunctionSelector{
        function: "growl",
        types: [
          %{type: {:uint, 256}},
          %{type: :address},
          %{type: {:array, :string}}
        ]
      }

      iex> ABI.FunctionSelector.decode("rollover()")
      %ABI.FunctionSelector{
        function: "rollover",
        types: []
      }

      iex> ABI.FunctionSelector.decode("do_playDead3()")
      %ABI.FunctionSelector{
        function: "do_playDead3",
        types: []
      }

      iex> ABI.FunctionSelector.decode("pet(address[])")
      %ABI.FunctionSelector{
        function: "pet",
        types: [
          %{type: {:array, :address}}
        ]
      }

      iex> ABI.FunctionSelector.decode("paw(string[2])")
      %ABI.FunctionSelector{
        function: "paw",
        types: [
          %{type: {:array, :string, 2}}
        ]
      }

      iex> ABI.FunctionSelector.decode("scram(uint256[])")
      %ABI.FunctionSelector{
        function: "scram",
        types: [
          %{type: {:array, {:uint, 256}}}
        ]
      }

      iex> ABI.FunctionSelector.decode("shake((string))")
      %ABI.FunctionSelector{
        function: "shake",
        types: [
          %{type: {:tuple, [%{type: :string}]}}
        ]
      }
  """
  @spec decode(String.t()) :: t()
  def decode(signature) do
    Parser.parse!(signature, as: :selector)
  end

  api(
    :decode_raw,
    "Parse a comma-separated list of Solidity type names into a list of internal type representations, without function-name framing.",
    params: [
      type_string: [
        kind: :value,
        description:
          "Comma-separated type names such as string,uint256 (no surrounding parens, no function name); empty string returns []"
      ]
    ],
    returns: %{type: :list, description: "Ordered list of internal type tuples like [:string, {:uint, 256}]"}
  )

  @doc """
  Decodes the given type-string as a simple array of types.

  ## Examples

      iex> ABI.FunctionSelector.decode_raw("string,uint256")
      [:string, {:uint, 256}]

      iex> ABI.FunctionSelector.decode_raw("")
      []
  """
  @spec decode_raw(String.t()) :: [type()]
  def decode_raw(type_string) do
    {:tuple, types} = decode_type("(#{type_string})")
    Enum.map(types, fn argument_type -> argument_type.type end)
  end

  api(
    :parse_specification_item,
    "Parse a single ABI specification item (function, event, fallback, receive, error) from a decoded JSON ABI map into a FunctionSelector struct.",
    params: [
      item: [
        kind: :value,
        description:
          "Map decoded from a contract ABI JSON entry, with string keys: type (function/event/error/...), name, inputs, outputs, stateMutability, components for tuples"
      ]
    ],
    returns: %{
      type: :struct,
      description:
        "ABI.FunctionSelector populated with :function, :function_type, :state_mutability, :types, and :returns from the JSON entry"
    }
  )

  @doc """
  Parse a function selector, e.g. from an abi.json file.

  ## Examples

      iex> ABI.FunctionSelector.parse_specification_item(%{"type" => "function", "name" => "fun", "inputs" => [%{"name" => "a", "type" => "uint96", "internalType" => "uint96"}]})
      %ABI.FunctionSelector{
        function: "fun",
        function_type: :function,
        types: [%{type: {:uint, 96}, name: "a"}],
        returns: nil
      }

      iex> ABI.FunctionSelector.parse_specification_item(%{"type" => "function", "name" => "fun", "inputs" => [%{"name" => "s", "type" => "tuple", "internalType" => "tuple", "components" => [%{"name" => "a", "type" => "uint256", "internalType" => "uint256"},%{"name" => "b", "type" => "address", "internalType" => "address"},%{"name" => "c", "type" => "bytes", "internalType" => "bytes"}]},%{"name" => "d", "type" => "uint256", "internalType" => "uint256"}],"outputs" => [%{"name" => "", "type" => "bytes", "internalType" => "bytes"}],"stateMutability" => "view"})
      %ABI.FunctionSelector{
        function: "fun",
        function_type: :function,
        state_mutability: :view,
        types: [
          %{
            type:
              {:tuple, [
                %{type: {:uint, 256}, name: "a"},
                %{type: :address, name: "b"},
                %{type: :bytes, name: "c"}
              ]},
              name: "s"
          }, %{
            type: {:uint, 256},
            name: "d"
          }
        ],
        returns: [%{name: "", type: :bytes}],
      }

      iex> ABI.FunctionSelector.parse_specification_item(%{"type" => "function", "name" => "fun", "inputs" => [%{"name" => "s", "type" => "tuple", "internalType" => "struct Contract.Struct", "components" => [%{"name" => "a", "type" => "uint256", "internalType" => "uint256"},%{"name" => "b", "type" => "address", "internalType" => "address"},%{"name" => "c", "type" => "bytes", "internalType" => "bytes"}]},%{"name" => "d", "type" => "uint256", "internalType" => "uint256"}],"outputs" => [%{"name" => "", "type" => "bytes", "internalType" => "bytes"}],"stateMutability" => "pure"})
      %ABI.FunctionSelector{
        function: "fun",
        function_type: :function,
        state_mutability: :pure,
        types: [
          %{
            type:
              {:tuple, [
                %{type: {:uint, 256}, name: "a"},
                %{type: :address, name: "b"},
                %{type: :bytes, name: "c"}
              ]},
              name: "s"
          }, %{
            type: {:uint, 256},
            name: "d"
          }
        ],
        returns: [%{name: "", type: :bytes}],
      }

      iex> ABI.FunctionSelector.parse_specification_item(%{"type" => "function", "name" => "fun", "inputs" => [%{"name" => "s", "type" => "tuple", "internalType" => "struct Contract.Struct", "components" => [%{"name" => "a", "type" => "uint256", "internalType" => "uint256"},%{"type" => "address", "internalType" => "address"},%{"name" => "c", "type" => "bytes", "internalType" => "bytes"}]},%{"name" => "d", "type" => "uint256", "internalType" => "uint256"}],"outputs" => [%{"name" => "", "type" => "bytes", "internalType" => "bytes"}],"stateMutability" => "payable"})
      %ABI.FunctionSelector{
        function: "fun",
        function_type: :function,
        state_mutability: :payable,
        types: [
          %{
            type:
              {:tuple, [
                %{type: {:uint, 256}, name: "a"},
                %{type: :address},
                %{type: :bytes, name: "c"}
              ]},
              name: "s"
          }, %{
            type: {:uint, 256},
            name: "d"
          }
        ],
        returns: [%{name: "", type: :bytes}],
      }

      iex> ABI.FunctionSelector.parse_specification_item(%{"type" => "fallback"})
      %ABI.FunctionSelector{
        function: nil,
        function_type: :fallback,
        types: [],
        returns: nil
      }

      iex> ABI.FunctionSelector.parse_specification_item(%{"type" => "receive"})
      %ABI.FunctionSelector{
        function: nil,
        function_type: :receive,
        types: [],
        returns: nil
      }

      iex> ABI.FunctionSelector.parse_specification_item(%{"inputs" => [%{"internalType" => "address[]", "name" => "xs", "type" => "address[]"}, %{"internalType" => "bytes[]", "name" => "ys", "type" => "bytes[]"}, %{"components" => [%{"internalType" => "enum Z", "name" => "za", "type" => "uint8"}, %{"internalType" => "enum Z", "name" => "zb", "type" => "uint8"}], "internalType" => "struct Z.Z[]", "name" => "zs", "type" => "tuple[]"}, %{"internalType" => "bytes[]", "name" => "zz", "type" => "bytes[]"}], "name" => "go", "outputs" => [%{"internalType" => "bytes[]", "name" => "", "type" => "bytes[]"}], "stateMutability" => "nonpayable", "type" => "function"})
      %ABI.FunctionSelector{
        function: "go",
        function_type: :function,
        state_mutability: :nonpayable,
        types: [
          %{name: "xs", type: {:array, :address}},
          %{name: "ys", type: {:array, :bytes}},
          %{
            name: "zs",
            type:
              {:array,
               {:tuple,
                [%{name: "za", type: {:uint, 8}}, %{name: "zb", type: {:uint, 8}}]}}
          },
          %{name: "zz", type: {:array, :bytes}}
        ],
        returns: [%{name: "", type: {:array, :bytes}}]
      }

      iex> ABI.FunctionSelector.parse_specification_item(%{"anonymous" => false, "inputs" => [%{"indexed" => true, "internalType" => "address", "name" => "z0", "type" => "address"}, %{"indexed" => true, "internalType" => "address", "name" => "z1", "type" => "address"}, %{"indexed" => false, "internalType" => "address", "name" => "z2", "type" => "address"}, %{"indexed" => false, "internalType" => "bytes32", "name" => "z3", "type" => "bytes32"}], "name" => "z4", "type" => "event"})
      %ABI.FunctionSelector{
        function: "z4",
        function_type: :event,
        state_mutability: nil,
        types: [
          %{name: "z0", type: :address, indexed: true},
          %{name: "z1", type: :address, indexed: true},
          %{name: "z2", type: :address, indexed: false},
          %{name: "z3", type: {:bytes, 32}, indexed: false}
        ],
        returns: nil
      }

      iex> ABI.FunctionSelector.parse_specification_item(%{"inputs" => [], "name" => "Abc", "type" => "error"})
      %ABI.FunctionSelector{function: "Abc", function_type: :error, state_mutability: nil, types: [], returns: nil}
  """
  @spec parse_specification_item(map()) :: t()
  def parse_specification_item(%{"type" => function_type} = item) do
    input_types = Enum.map(Map.get(item, "inputs", []), &parse_specification_type/1)

    output_types =
      cond do
        Map.get(item, "anonymous") == true -> :anonymous
        Map.has_key?(item, "outputs") -> Enum.map(item["outputs"], &parse_specification_type/1)
        true -> nil
      end

    state_mutability =
      if Map.has_key?(item, "stateMutability"),
        do: get_state_mutability(item["stateMutability"])

    %ABI.FunctionSelector{
      function: Map.get(item, "name"),
      function_type: get_function_type(function_type),
      state_mutability: state_mutability,
      types: input_types,
      returns: output_types
    }
  end

  @spec parse_specification_type(spec_param()) :: argument_type()
  defp parse_specification_type(%{"name" => name, "indexed" => indexed} = record) do
    %{name: name, type: parse_specification_type_type(record), indexed: indexed}
  end

  defp parse_specification_type(%{"indexed" => indexed} = record) do
    %{type: parse_specification_type_type(record), indexed: indexed}
  end

  defp parse_specification_type(%{"name" => name} = record) do
    %{name: name, type: parse_specification_type_type(record)}
  end

  defp parse_specification_type(record) do
    %{type: parse_specification_type_type(record)}
  end

  @spec parse_specification_type_type(spec_param()) :: type()
  defp parse_specification_type_type(%{"type" => "tuple[]", "components" => components}) do
    {:array, {:tuple, Enum.map(components, &parse_specification_type/1)}}
  end

  defp parse_specification_type_type(%{"type" => "tuple", "components" => components}) do
    {:tuple, Enum.map(components, &parse_specification_type/1)}
  end

  defp parse_specification_type_type(%{"type" => type}) do
    decode_type(type)
  end

  api(
    :decode_type,
    "Parse a single Solidity type expression into the internal type representation. Useful for one-off type parsing without function-name framing.",
    params: [
      single_type: [
        kind: :value,
        description:
          "Single Solidity type such as uint256, (bool,address), or address[][3]; supports nested tuples and arrays"
      ]
    ],
    returns: %{
      type: :tuple,
      description: "Internal type representation such as {:uint, 256}, {:tuple, [...]}, or {:array, type, count}"
    }
  )

  @doc """
  Decodes the given type-string as a single type.

  ## Examples

      iex> ABI.FunctionSelector.decode_type("uint256")
      {:uint, 256}

      iex> ABI.FunctionSelector.decode_type("(bool,address)")
      {:tuple, [%{type: :bool}, %{type: :address}]}

      iex> ABI.FunctionSelector.decode_type("address[][3]")
      {:array, {:array, :address}, 3}
  """
  @spec decode_type(String.t()) :: type()
  def decode_type(single_type) do
    Parser.parse!(single_type, as: :type)
  end

  api(
    :encode,
    "Render a FunctionSelector struct as its canonical Solidity signature string, optionally annotating indexed event params and parameter names.",
    params: [
      function_selector: [kind: :value, description: "FunctionSelector with :function and :types"],
      indexed: [
        kind: :value,
        default: false,
        description:
          "When true, append the indexed keyword after parameter types whose argument map carries indexed: true (event signatures)"
      ],
      names: [
        kind: :value,
        default: false,
        description:
          "When true, append parameter names after each type (uses :name from the argument map, or var0/var1/... when missing)"
      ]
    ],
    returns: %{
      type: :string,
      description:
        "Canonical signature string such as transfer(address,uint256), or with indexed/names annotations applied"
    },
    composes_with: [:decode]
  )

  @doc """
  Encodes a function call signature. If `indexed=true`, returns
  the `"indexed"` keyword after indexed parameters.

  ## Example

      iex> ABI.FunctionSelector.encode(%ABI.FunctionSelector{
      ...>   function: "bark",
      ...>   types: [
      ...>     %{type: {:uint, 256}},
      ...>     %{type: :bool, indexed: true},
      ...>     %{type: {:array, :string}},
      ...>     %{type: {:array, :string, 3}},
      ...>     %{type: {:tuple, [%{type: {:uint, 256}}, %{type: :bool}]}}
      ...>   ]
      ...> })
      "bark(uint256,bool,string[],string[3],(uint256,bool))"

      iex> ABI.FunctionSelector.encode(%ABI.FunctionSelector{
      ...>   function: "bark",
      ...>   types: [
      ...>     %{type: {:uint, 256}},
      ...>     %{type: :bool, indexed: true},
      ...>     %{type: {:array, :string}},
      ...>     %{type: {:array, :string, 3}},
      ...>     %{type: {:tuple, [%{type: {:uint, 256}}, %{type: :bool}]}}
      ...>   ]
      ...> }, true)
      "bark(uint256,bool indexed,string[],string[3],(uint256,bool))"

      iex> ABI.FunctionSelector.encode(%ABI.FunctionSelector{
      ...>   function: "bark",
      ...>   types: [
      ...>     %{type: {:uint, 256}},
      ...>     %{type: :bool, indexed: true},
      ...>     %{type: {:array, :string}},
      ...>     %{type: {:array, :string, 3}},
      ...>     %{type: {:tuple, [%{type: {:uint, 256}}, %{type: :bool}]}}
      ...>   ]
      ...> }, true, true)
      "bark(uint256 var0,bool indexed var1,string[] var2,string[3] var3,(uint256,bool) var4)"

      iex> ABI.FunctionSelector.encode(%ABI.FunctionSelector{
      ...>   function: "bark",
      ...>   types: [
      ...>     %{type: {:uint, 256}},
      ...>     %{type: :bool, indexed: true},
      ...>     %{type: {:array, :string}},
      ...>     %{type: {:array, :string, 3}},
      ...>     %{type: {:tuple, [%{type: {:uint, 256}}, %{type: :bool}]}}
      ...>   ]
      ...> }, false, true)
      "bark(uint256 var0,bool var1,string[] var2,string[3] var3,(uint256,bool) var4)"

      iex> ABI.FunctionSelector.encode(%ABI.FunctionSelector{
      ...>   function: "bark",
      ...>   types: [
      ...>     %{type: {:uint, 256}, name: "a"},
      ...>     %{type: :bool, indexed: true, name: "b"},
      ...>     %{type: {:array, :string}, name: "c"},
      ...>     %{type: {:array, :string, 3}, name: "d"},
      ...>     %{type: {:tuple, [%{type: {:uint, 256}}, %{type: :bool}]}, name: "e"}
      ...>   ]
      ...> }, false, true)
      "bark(uint256 a,bool b,string[] c,string[3] d,(uint256,bool) e)"
  """
  @spec encode(t(), boolean(), boolean()) :: String.t()
  def encode(function_selector, indexed \\ false, names \\ false) do
    types = function_selector |> get_types(indexed, names) |> Enum.join(",")

    "#{function_selector.function}(#{types})"
  end

  @spec get_types(t(), boolean(), boolean()) :: [String.t()]
  defp get_types(function_selector, indexed, names) do
    for {%{type: type} = t, i} <- Enum.with_index(function_selector.types) do
      indexed_postfix = if indexed and Map.get(t, :indexed, false), do: " indexed", else: ""
      name_postfix = if names, do: " #{Map.get(t, :name, "var#{i}")}", else: ""
      "#{get_type(type)}#{indexed_postfix}#{name_postfix}"
    end
  end

  @spec get_type(
          type()
          | nil
          | {:fixed, non_neg_integer(), non_neg_integer()}
          | {:ufixed, non_neg_integer(), non_neg_integer()}
          | {:struct, String.t(), [type()], [String.t()]}
        ) :: String.t() | nil
  defp get_type(nil), do: nil
  defp get_type({:int, size}), do: "int#{size}"
  defp get_type({:uint, size}), do: "uint#{size}"
  defp get_type(:address), do: "address"
  defp get_type(:bool), do: "bool"
  defp get_type({:fixed, element_count, precision}), do: "fixed#{element_count}x#{precision}"
  defp get_type({:ufixed, element_count, precision}), do: "ufixed#{element_count}x#{precision}"
  defp get_type({:bytes, size}), do: "bytes#{size}"
  defp get_type(:function), do: "function"

  defp get_type({:array, type, element_count}), do: "#{get_type(type)}[#{element_count}]"

  defp get_type(:bytes), do: "bytes"
  defp get_type(:string), do: "string"
  defp get_type({:array, type}), do: "#{get_type(type)}[]"

  defp get_type({:tuple, types}) do
    encoded_types = Enum.map(types, fn argument_type -> get_type(argument_type.type) end)
    "(#{Enum.join(encoded_types, ",")})"
  end

  defp get_type({:struct, _name, types, _names}) do
    encoded_types = Enum.map(types, &get_type/1)
    "(#{Enum.join(encoded_types, ",")})"
  end

  defp get_type(els), do: raise("Unsupported type: #{inspect(els)}")

  @doc false
  @spec dynamic?(ABI.FunctionSelector.type()) :: boolean
  def dynamic?(:bytes), do: true
  def dynamic?(:string), do: true
  def dynamic?({:array, _type}), do: true
  def dynamic?({:array, _type, 0}), do: false
  def dynamic?({:array, type, len}) when len > 0, do: dynamic?(type)

  def dynamic?({:tuple, types}), do: Enum.any?(types, fn arg_type -> dynamic?(arg_type.type) end)

  def dynamic?({:bytes, _}), do: false
  def dynamic?({:int, _}), do: false
  def dynamic?({:uint, _}), do: false
  def dynamic?(:bool), do: false
  def dynamic?(:address), do: false
  def dynamic?(:function), do: false

  @doc false
  @spec get_function_type(String.t()) :: function_type()
  def get_function_type("function"), do: :function
  def get_function_type("constructor"), do: :constructor
  def get_function_type("receive"), do: :receive
  def get_function_type("fallback"), do: :fallback
  def get_function_type("error"), do: :error
  def get_function_type("event"), do: :event

  @doc false
  @spec get_state_mutability(String.t()) :: state_mutability()
  def get_state_mutability("nonpayable"), do: :nonpayable
  def get_state_mutability("pure"), do: :pure
  def get_state_mutability("view"), do: :view
  def get_state_mutability("payable"), do: :payable
end
