defmodule Cartouche.Typed do
  @moduledoc """
  Module to build EIP-712 typed data, which can then be signed or recovered from.
  """
  use Cartouche.Hex

  defstruct [:domain, :types, :value]

  @type value_map() :: %{String.t() => term()}
  @type type_map() :: %{String.t() => __MODULE__.Type.t()}
  @type t() :: %__MODULE__{
          domain: __MODULE__.Domain.t(),
          types: type_map(),
          value: value_map()
        }

  defmodule Type do
    @moduledoc """
    EIP-712 type definition — an ordered list of `{name, field_type}` field
    entries. Field types are either primitives (`:address`, `{:uint, 256}`,
    `:bool`, …) or string references to other named types.
    """
    defstruct [:fields]

    @type primitive() ::
            :address
            | {:uint, number()}
            | {:int, pos_integer()}
            | {:bytes, number()}
            | :string
            | :bytes
            | {:array, field_type()}
            | :bool
    @type field_type() :: primitive() | String.t()
    @type type_list() :: [{String.t(), field_type()}]
    @type t() :: %__MODULE__{fields: type_list()}

    @doc ~S"""
    Deserializes a Type from JSON or a map into a struct.

    ## Examples

        iex> [%{
        ...>   "name" => "from",
        ...>   "type" => "Person",
        ...> }, %{
        ...>   "name" => "to",
        ...>   "type" => "Person",
        ...> }, %{
        ...>   "name" => "contents",
        ...>   "type" => "string",
        ...> }]
        ...> |> Cartouche.Typed.Type.deserialize()
        %Cartouche.Typed.Type{fields: [{"from", "Person"}, {"to", "Person"}, {"contents", :string}]}
    """
    @spec deserialize([%{name: String.t(), type: String.t()}]) :: t()
    def deserialize(types) do
      fields =
        for %{"name" => name, "type" => type} <- types do
          {name, deserialize_type(type)}
        end

      %__MODULE__{
        fields: fields
      }
    end

    @doc ~S"""
    Serializes a Type, such that it can be used with JSON or JavaScript.

    ## Examples

        iex> %Cartouche.Typed.Type{fields: [{"from", "Person"}, {"to", "Person"}, {"contents", :string}]}
        ...> |> Cartouche.Typed.Type.serialize()
        [%{
          "name" => "from",
          "type" => "Person",
        }, %{
          "name" => "to",
          "type" => "Person",
        }, %{
          "name" => "contents",
          "type" => "string",
        }]

    """
    @spec serialize(t()) :: [%{name: String.t(), type: String.t()}]
    def serialize(%__MODULE__{fields: fields}) do
      for {name, type} <- fields do
        %{
          "name" => name,
          "type" => serialize_type(type)
        }
      end
    end

    @doc ~S"""
    Serializes a primitive or custom type.

    ## Examples

        iex> Cartouche.Typed.Type.serialize_type(:address)
        "address"

        iex> Cartouche.Typed.Type.serialize_type({:uint, 256})
        "uint256"

        iex> Cartouche.Typed.Type.serialize_type({:bytes, 32})
        "bytes32"

        iex> Cartouche.Typed.Type.serialize_type(:bytes)
        "bytes"

        iex> Cartouche.Typed.Type.serialize_type(:bool)
        "bool"

        iex> Cartouche.Typed.Type.serialize_type({:array, :bytes})
        "bytes[]"

        iex> Cartouche.Typed.Type.serialize_type("Person")
        "Person"
    """
    @spec serialize_type(field_type()) :: String.t()
    def serialize_type(:address), do: "address"
    def serialize_type({:int, sz}), do: "int#{sz}"
    def serialize_type({:uint, sz}), do: "uint#{sz}"
    def serialize_type({:bytes, sz}), do: "bytes#{sz}"
    def serialize_type(:string), do: "string"
    def serialize_type(:bytes), do: "bytes"
    def serialize_type(:bool), do: "bool"
    def serialize_type({:array, ty}), do: "#{serialize_type(ty)}[]"
    def serialize_type(custom_type) when is_binary(custom_type), do: custom_type

    @doc ~S"""
    Deserializes a primitive or custom type. We differentiate
    custom types by not being a primitive type.

    ## Examples

        iex> Cartouche.Typed.Type.deserialize_type("address")
        :address

        iex> Cartouche.Typed.Type.deserialize_type("bytes")
        :bytes

        iex> Cartouche.Typed.Type.deserialize_type("uint256")
        {:uint, 256}

        iex> Cartouche.Typed.Type.deserialize_type("bytes32")
        {:bytes, 32}

        iex> Cartouche.Typed.Type.deserialize_type("bool")
        :bool

        iex> Cartouche.Typed.Type.deserialize_type("bytes32[]")
        {:array, {:bytes, 32}}

        iex> Cartouche.Typed.Type.deserialize_type("Person")
        "Person"

        iex> Cartouche.Typed.Type.deserialize_type("bag")
        ** (RuntimeError) unknown type: bag
    """
    @spec deserialize_type(String.t()) :: field_type()
    def deserialize_type("address"), do: :address
    def deserialize_type("string"), do: :string
    def deserialize_type("bool"), do: :bool
    def deserialize_type("bytes"), do: :bytes

    for width <- 8..256//8 do
      def deserialize_type(unquote("int#{width}")), do: {:int, unquote(width)}
      def deserialize_type(unquote("uint#{width}")), do: {:uint, unquote(width)}
    end

    for size <- 1..32 do
      def deserialize_type(unquote("bytes#{size}")), do: {:bytes, unquote(size)}
    end

    def deserialize_type(ty) when is_binary(ty) do
      cond do
        String.ends_with?(ty, "[]") ->
          {:array, deserialize_type(String.slice(ty, 0, String.length(ty) - 2))}

        String.length(ty) > 0 and String.slice(ty, 0, 1) == String.upcase(String.slice(ty, 0, 1)) ->
          ty

        true ->
          raise "unknown type: #{ty}"
      end
    end

    @doc ~S"""
    Deserializes a value of a given type for being stored in this struct.

    ## Examples

        iex> Cartouche.Typed.Type.deserialize_value!("0x0000000000000000000000000000000000000001", :address)
        <<1::160>>

        iex> Cartouche.Typed.Type.deserialize_value!(55, {:uint, 256})
        55

        iex> Cartouche.Typed.Type.deserialize_value!(true, :bool)
        true

        iex> Cartouche.Typed.Type.deserialize_value!("0x00000000000000000000000000000000000000000000000000000000000000CC", {:bytes, 32})
        <<0xCC::256>>

        iex> Cartouche.Typed.Type.deserialize_value!("0xCC", {:bytes, 32})
        <<0xCC, 0::248>>

        iex> Cartouche.Typed.Type.deserialize_value!("Cow", :string)
        "Cow"

        iex> Cartouche.Typed.Type.deserialize_value!("0xCCDD", :bytes)
        <<0xCC, 0xDD>>

        iex> Cartouche.Typed.Type.deserialize_value!(["0xCCDD", "0xEE"], {:array, :bytes})
        [<<0xCC, 0xDD>>, <<0xEE>>]
    """
    @spec deserialize_value!(term(), primitive()) :: term()
    def deserialize_value!(value, :address), do: from_hex!(value)
    def deserialize_value!(value, :string), do: value
    def deserialize_value!(value, :bytes), do: from_hex!(value)
    def deserialize_value!(value, {:uint, _}), do: value
    def deserialize_value!(value, {:int, _}), do: value
    def deserialize_value!(value, :bool), do: value

    def deserialize_value!(value, {:bytes, sz}), do: Cartouche.Hex.pad_right(from_hex!(value), sz)

    def deserialize_value!(value, {:array, ty}) when is_list(value), do: Enum.map(value, &deserialize_value!(&1, ty))

    @doc ~S"""
    Serializes a value of a given type to pass to JSON or JavaScript.

    ## Examples

        iex> Cartouche.Typed.Type.serialize_value(<<1::160>>, :address)
        "0x0000000000000000000000000000000000000001"

        iex> Cartouche.Typed.Type.serialize_value(55, {:uint, 256})
        55

        iex> Cartouche.Typed.Type.serialize_value(true, :bool)
        true

        iex> Cartouche.Typed.Type.serialize_value(<<0xCC::256>>, {:bytes, 32})
        "0x00000000000000000000000000000000000000000000000000000000000000cc"

        iex> Cartouche.Typed.Type.serialize_value(<<0xCC>>, {:bytes, 32})
        "0xcc00000000000000000000000000000000000000000000000000000000000000"

        iex> Cartouche.Typed.Type.serialize_value("Cow", :string)
        "Cow"

        iex> Cartouche.Typed.Type.serialize_value(<<0xCC, 0xDD>>, :bytes)
        "0xccdd"

        iex> Cartouche.Typed.Type.serialize_value([<<0xCC, 0xDD>>, <<0xEE>>], {:array, :bytes})
        ["0xccdd", "0xee"]
    """
    @spec serialize_value(term(), primitive()) :: term()
    def serialize_value(value, :address), do: value |> Cartouche.Hex.pad(20) |> to_hex()
    def serialize_value(value, :string), do: value
    def serialize_value(value, :bytes), do: to_hex(value)
    def serialize_value(value, :bool), do: value
    def serialize_value(value, {:uint, _}), do: value
    def serialize_value(value, {:int, _}), do: value

    def serialize_value(value, {:bytes, sz}) do
      value
      |> Cartouche.Hex.pad_right(sz)
      |> to_hex()
    end

    def serialize_value(value, {:array, ty}) when is_list(value), do: Enum.map(value, &serialize_value(&1, ty))

    @doc ~S"""
    Encodes a value for `encodeData`, as per the EIP-712 spec. Specifically, raw values are
    expanded to 32-bytes, and dynamic types are hashed. Pass the type map as the
    third argument when encoding structs or arrays containing structs.

    ## Examples

        iex> Cartouche.Typed.Type.encode_data_value(<<1::160>>, :address)
        <<1::256>>

        iex> Cartouche.Typed.Type.encode_data_value(55, {:uint, 256})
        <<0::248, 55>>

        iex> Cartouche.Typed.Type.encode_data_value(<<0xCC>>, {:bytes, 32})
        <<0xCC, 0::248>>

        iex> Cartouche.Typed.Type.encode_data_value(<<0xCC, 0xDD>>, :bytes)
        ~h[9014B850703629D30F5C8C6C86A6AD981AB9319997490629D7DA37E8CAE985A1]

        iex> Cartouche.Typed.Type.encode_data_value("Cow", :string)
        ~h[8C1D2BD5348394761719DA11EC67EEDAE9502D137E8940FEE8ECD6F641EE1648]

        iex> Cartouche.Typed.Type.encode_data_value([<<0xCC, 0xDD>>, <<0xEE>>], {:array, :bytes})
        ~h[134619415A3C9FE841D99F7CFD5C0BCCFC7CF0DAE90743A3D717C748A3961CF5]
    """
    @spec encode_data_value(term(), field_type(), Cartouche.Typed.type_map()) :: binary()
    def encode_data_value(value, type, types \\ %{})

    def encode_data_value(value, :address, _types), do: Cartouche.Hex.pad(value, 32)
    def encode_data_value(value, {:uint, _}, _types), do: Cartouche.Hex.encode_bytes(value, 32)
    def encode_data_value(value, :string, _types), do: Cartouche.Hash.keccak(value)
    def encode_data_value(value, :bytes, _types), do: Cartouche.Hash.keccak(value)
    def encode_data_value(value, {:bytes, _}, _types), do: Cartouche.Hex.pad_right(value, 32)

    def encode_data_value(value, {:int, width}, _types)
        when is_integer(width) and width in 8..256 and rem(width, 8) == 0 and is_integer(value) do
      limit = Integer.pow(2, width - 1)

      if value < -limit or value >= limit do
        raise ArgumentError, "value out of range for int#{width}"
      end

      <<value::signed-big-256>>
    end

    def encode_data_value(value, :bool, types), do: encode_data_value(if(value, do: 1, else: 0), {:uint, 256}, types)

    def encode_data_value(value, {:array, ty}, types) do
      value
      |> Enum.map_join(&encode_data_value(&1, ty, types))
      |> Cartouche.Hash.keccak()
    end

    def encode_data_value(value, type, types) when is_binary(type), do: Cartouche.Typed.hash_struct(type, value, types)
  end

  defmodule Domain do
    @moduledoc """
    EIP-712 domain separator — the standard `EIP712Domain` struct
    (`name`, `version`, `chainId`, `verifyingContract`, `salt`). Each field is
    optional; only the populated fields contribute to the encoded domain type.
    """
    defstruct [:name, :version, :chain_id, :verifying_contract, :salt]

    @type t() :: %__MODULE__{
            name: nil | String.t(),
            version: nil | String.t(),
            chain_id: nil | number(),
            verifying_contract: nil | <<_::160>>,
            salt: nil | <<_::256>>
          }

    @domain_key_keyword [
      name: {"name", :string},
      version: {"version", :string},
      chain_id: {"chainId", {:uint, 256}},
      verifying_contract: {"verifyingContract", :address},
      salt: {"salt", {:bytes, 32}}
    ]

    @inverted_key_map for {k, {v, _type}} <- @domain_key_keyword, into: %{}, do: {v, k}

    @doc ~S"""
    Builds the EIP-712 domain type based on a given domain.

    ## Examples

        iex> %Cartouche.Typed.Domain{
        ...>   name: "Ether Mail",
        ...>   version: "1",
        ...>   chain_id: 1,
        ...>   verifying_contract: ~h[CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC]
        ...> }
        ...> |> Cartouche.Typed.Domain.domain_type()
        %{"EIP712Domain" => %Cartouche.Typed.Type{fields: [{"name", :string}, {"version", :string}, {"chainId", {:uint, 256}}, {"verifyingContract", :address}]}}

        iex> %Cartouche.Typed.Domain{
        ...>   name: "Ether Mail",
        ...>   version: "1",
        ...> }
        ...> |> Cartouche.Typed.Domain.domain_type()
        %{"EIP712Domain" => %Cartouche.Typed.Type{fields: [{"name", :string}, {"version", :string}]}}
    """
    @spec domain_type(t()) :: %{String.t() => Type.t()}
    def domain_type(domain),
      do: %{
        "EIP712Domain" => %Type{
          fields:
            @domain_key_keyword
            |> Enum.filter(fn {key, _} -> not is_nil(Map.get(domain, key)) end)
            |> Enum.map(fn {_, v} -> v end)
        }
      }

    @doc ~S"""
    Deserializes a domain from JSON or JavaScript encoding to a struct.

    ## Examples

        iex> %{
        ...>   "name" => "Ether Mail",
        ...>   "version" => "1",
        ...>   "chainId" => 1,
        ...>   "verifyingContract" => "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC",
        ...> }
        ...> |> Cartouche.Typed.Domain.deserialize()
        %Cartouche.Typed.Domain{
          name: "Ether Mail",
          version: "1",
          chain_id: 1,
          verifying_contract: ~h[CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC]
        }

        iex> %{
        ...>   "name" => "Ether Mail",
        ...>   "version" => "1"
        ...> }
        ...> |> Cartouche.Typed.Domain.deserialize()
        %Cartouche.Typed.Domain{
          name: "Ether Mail",
          version: "1"
        }
    """
    @spec deserialize(map()) :: t()
    def deserialize(params) do
      mod_params =
        for {key, value} <- params, into: %{} do
          atom_key =
            cond do
              is_atom(key) ->
                key

              is_binary(key) ->
                Map.fetch!(@inverted_key_map, key)
            end

          deserialized_value =
            case atom_key do
              :verifying_contract ->
                Type.deserialize_value!(value, :address)

              :salt ->
                Type.deserialize_value!(value, {:bytes, 32})

              _ ->
                value
            end

          {atom_key, deserialized_value}
        end

      struct(%__MODULE__{}, mod_params)
    end

    @doc ~S"""
    Serializes a domain, such that it can be JSON-encoded or passed to JavaScript.

    ## Examples

        iex> %Cartouche.Typed.Domain{
        ...>   name: "Ether Mail",
        ...>   version: "1",
        ...>   chain_id: 1,
        ...>   verifying_contract: ~h[CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC]
        ...> }
        ...> |> Cartouche.Typed.Domain.serialize()
        %{
          "name" => "Ether Mail",
          "version" => "1",
          "chainId" => 1,
          "verifyingContract" => "0xcccccccccccccccccccccccccccccccccccccccc",
        }

        iex> %Cartouche.Typed.Domain{
        ...>   name: "Ether Mail",
        ...>   version: "1"
        ...> }
        ...> |> Cartouche.Typed.Domain.serialize()
        %{
          "name" => "Ether Mail",
          "version" => "1"
        }
    """
    @spec serialize(t()) :: %{String.t() => term()}
    def serialize(%__MODULE__{
          name: name,
          version: version,
          chain_id: chain_id,
          verifying_contract: verifying_contract,
          salt: salt
        }) do
      values = %{
        "name" => name,
        "version" => version,
        "chainId" => chain_id,
        "verifyingContract" =>
          if(is_nil(verifying_contract),
            do: nil,
            else: Type.serialize_value(verifying_contract, :address)
          ),
        "salt" => if(is_nil(salt), do: nil, else: Type.serialize_value(salt, {:bytes, 32}))
      }

      filter_nils(values)
    end

    @doc ~S"""
    Serializes a domain's keys to be JSON-compatible. This is so that it can be used
    as a value for `hashStruct`, per the EIP-712 spec to build a domain specifier.

    ## Examples

        iex> use Cartouche.Hex
        iex> %Cartouche.Typed.Domain{
        ...>   name: "Ether Mail",
        ...>   version: "1",
        ...>   chain_id: 1,
        ...>   verifying_contract: ~h[CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC]
        ...> }
        ...> |> Cartouche.Typed.Domain.serialize_keys()
        %{
          "name" => "Ether Mail",
          "version" => "1",
          "chainId" => 1,
          "verifyingContract" => ~h[CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC]
        }

        iex> use Cartouche.Hex
        iex> %Cartouche.Typed.Domain{
        ...>   name: "Ether Mail",
        ...>   version: "1",
        ...> }
        ...> |> Cartouche.Typed.Domain.serialize_keys()
        %{
          "name" => "Ether Mail",
          "version" => "1"
        }
    """
    @spec serialize_keys(t()) :: %{String.t() => term()}
    def serialize_keys(%__MODULE__{
          name: name,
          version: version,
          chain_id: chain_id,
          verifying_contract: verifying_contract,
          salt: salt
        }) do
      values = %{
        "name" => name,
        "version" => version,
        "chainId" => chain_id,
        "verifyingContract" => verifying_contract,
        "salt" => salt
      }

      filter_nils(values)
    end

    @spec filter_nils(map()) :: map()
    defp filter_nils(map) do
      map
      |> Map.to_list()
      |> Enum.filter(fn {_, v} -> not is_nil(v) end)
      |> Map.new()
    end
  end

  # Gets a value from a map, first converting all key values to strings
  # Note: we could simplify this, but it's a deep-nested struct that
  #       sometimes has atoms as keys, so it's just easier to do it this
  #       way for now.
  @spec fetch_value(map() | Enumerable.t(), String.t()) :: term()
  defp fetch_value(value, field) do
    string_keyed_value =
      for {k, v} <- value, into: %{} do
        {to_string(k), v}
      end

    Map.fetch!(string_keyed_value, field)
  end

  @spec transform_value(term(), Type.field_type(), type_map(), (term(), Type.primitive() -> term())) :: term()
  defp transform_value(value, {:array, type}, types, transform) do
    Enum.map(value, &transform_value(&1, type, types, transform))
  end

  defp transform_value(value, type, types, transform) when is_binary(type) do
    transform_value_map(value, Map.fetch!(types, type).fields, types, transform)
  end

  defp transform_value(value, type, _types, transform), do: transform.(value, type)

  @spec transform_value_map(value_map(), Type.type_list(), type_map(), (term(), Type.primitive() -> term())) ::
          value_map()
  defp transform_value_map(value, fields, types, transform) do
    for {field, type} <- fields, into: %{} do
      {field, transform_value(fetch_value(value, field), type, types, transform)}
    end
  end

  @spec encode_value_map(value_map(), Type.type_list(), type_map()) :: binary()
  defp encode_value_map(value, fields, types) do
    for {field, type} <- fields, into: <<>> do
      Type.encode_data_value(fetch_value(value, field), type, types)
    end
  end

  # Tries to match a type based on its parameters, which looks to be how EIP-712 libraries work.
  @spec find_type([String.t()], type_map()) :: {String.t(), Type.t()}
  defp find_type(field_names, types) do
    sorted_field_names =
      field_names
      |> Enum.sort()
      |> Enum.map(&to_string/1)

    case Enum.filter(types, &type_fields_match?(&1, sorted_field_names)) do
      [] ->
        raise "Failed to find matching type for field names #{inspect(field_names)}"

      [{k, v}] ->
        {k, v}

      els ->
        raise "Found multiple types #{inspect(els)}"
    end
  end

  @spec type_fields_match?({String.t(), Type.t()}, [String.t()]) :: boolean()
  defp type_fields_match?({_name, type}, sorted_field_names) do
    type.fields |> Enum.map(fn {k, _v} -> k end) |> Enum.sort() == sorted_field_names
  end

  @doc ~S"""
  Deserializes a Typed value from JSON or a map into a struct.

  ## Examples
      iex> %{
      ...>   "domain" => %{
      ...>     "name" => "Ether Mail",
      ...>     "version" => "1",
      ...>     "chainId" => 1,
      ...>     "verifyingContract" => "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"
      ...>   },
      ...>   "types" => %{
      ...>     "Person" => [
      ...>       %{
      ...>         "name" => "name",
      ...>         "type" => "string"
      ...>       },
      ...>       %{
      ...>         "name" => "wallet",
      ...>         "type" => "address"
      ...>       },
      ...>     ],
      ...>     "Mail" => [
      ...>       %{
      ...>         "name" => "from",
      ...>         "type" => "Person"
      ...>       },
      ...>       %{
      ...>         "name" => "to",
      ...>         "type" => "Person"
      ...>       },
      ...>       %{
      ...>         "name" => "contents",
      ...>         "type" => "string"
      ...>       },
      ...>     ]
      ...>   },
      ...>   "value" => %{
      ...>     "from" => %{ "name" => "Cow", "wallet" => "0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826" },
      ...>     "to" => %{ "name" => "Bob", "wallet" => "0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB" },
      ...>     "contents" => "Hello, Bob!"
      ...>   }
      ...> }
      ...> |> Cartouche.Typed.deserialize()
      %Cartouche.Typed{
        domain: %Cartouche.Typed.Domain{
          chain_id: 1,
          name: "Ether Mail",
          verifying_contract: ~h[CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC],
          version: "1"
        },
        types: %{
          "Mail" => %Cartouche.Typed.Type{fields: [{"from", "Person"}, {"to", "Person"}, {"contents", :string}]},
          "Person" => %Cartouche.Typed.Type{fields: [{"name", :string}, {"wallet", :address}]}
        },
        value: %{
          "contents" => "Hello, Bob!",
          "from" => %{
            "name" => "Cow",
            "wallet" => ~h[CD2A3D9F938E13CD947EC05ABC7FE734DF8DD826]
          },
          "to" => %{
            "name" => "Bob",
            "wallet" => ~h[BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB]
          }
        }
      }
  """
  @spec deserialize(%{}) :: t()
  def deserialize(%{domain: domain, types: types_map, value: value}),
    do: deserialize(%{"domain" => domain, "types" => types_map, "value" => value})

  def deserialize(%{"domain" => domain, "types" => types_map, "value" => value}) do
    types =
      for {k, fields} <- types_map, into: %{} do
        {k, Type.deserialize(fields)}
      end

    {_, type} = find_type(Map.keys(value), types)

    %__MODULE__{
      domain: Domain.deserialize(domain),
      types: types,
      value: transform_value_map(value, type.fields, types, &Type.deserialize_value!/2)
    }
  end

  @doc ~S"""
  Serializes a Typed value, such that it can be passed to JSON or JavaScript.

  ## Examples
      iex> %Cartouche.Typed{
      ...>   domain: %Cartouche.Typed.Domain{
      ...>     chain_id: 1,
      ...>     name: "Ether Mail",
      ...>     verifying_contract: ~h[CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC],
      ...>     version: "1"
      ...>   },
      ...>   types: %{
      ...>     "Mail" => %Cartouche.Typed.Type{fields: [{"from", "Person"}, {"to", "Person"}, {"contents", :string}]},
      ...>     "Person" => %Cartouche.Typed.Type{fields: [{"name", :string}, {"wallet", :address}]}
      ...>   },
      ...>   value: %{
      ...>     "contents" => "Hello, Bob!",
      ...>     "from" => %{
      ...>       "name" => "Cow",
      ...>       "wallet" => ~h[CD2A3D9F938E13CD947EC05ABC7FE734DF8DD826]
      ...>     },
      ...>     "to" => %{
      ...>       "name" => "Bob",
      ...>       "wallet" => ~h[BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB]
      ...>     }
      ...>   }
      ...> }
      ...> |> Cartouche.Typed.serialize()
      %{
        "domain" => %{
          "name" => "Ether Mail",
          "version" => "1",
          "chainId" => 1,
          "verifyingContract" => "0xcccccccccccccccccccccccccccccccccccccccc"
        },
        "types" => %{
          "Person" => [
            %{
              "name" => "name",
              "type" => "string"
            },
            %{
              "name" => "wallet",
              "type" => "address"
            },
          ],
          "Mail" => [
            %{
              "name" => "from",
              "type" => "Person"
            },
            %{
              "name" => "to",
              "type" => "Person"
            },
            %{
              "name" => "contents",
              "type" => "string"
            },
          ]
        },
        "value" => %{
          "from" => %{ "name" => "Cow", "wallet" => "0xcd2a3d9f938e13cd947ec05abc7fe734df8dd826" },
          "to" => %{ "name" => "Bob", "wallet" => "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" },
          "contents" => "Hello, Bob!"
        }
      }
  """
  @spec serialize(t()) :: %{}
  def serialize(%__MODULE__{domain: domain, types: types, value: value}) do
    types_map =
      for {k, type} <- types, into: %{} do
        {k, Type.serialize(type)}
      end

    {_, type} = find_type(Map.keys(value), types)

    %{
      "domain" => Domain.serialize(domain),
      "types" => types_map,
      "value" => transform_value_map(value, type.fields, types, &Type.serialize_value/2)
    }
  end

  @doc ~S"""
  Encodes the struct type per EIP-712. For this, we basically build an ABI-style value
  like `Mail(Person from,Person to,string contents)`, but then to that we need to append
  any other types we've seen, like:

  `Mail(Person from,Person to,string contents)Person(string name,address wallet)`.

  This is a tail-call optimized implementation to build the types then track and append types that need to be added.

  ## Examples

      iex> Cartouche.Typed.encode_type("Mail", %{
      ...>   "Mail" => %Cartouche.Typed.Type{fields: [{"from", "Person"}, {"to", "Person"}, {"contents", :string}]},
      ...>   "Person" => %Cartouche.Typed.Type{fields: [{"name", :string}, {"wallet", :address}]}
      ...> })
      "Mail(Person from,Person to,string contents)Person(string name,address wallet)"
  """
  @spec encode_type(String.t(), type_map()) :: String.t()
  def encode_type(name, types) do
    dependencies = types |> collect_types([name], %{}) |> Map.delete(name) |> Map.keys() |> Enum.sort()

    Enum.map_join([name | dependencies], fn type_name ->
      fields = Map.fetch!(types, type_name).fields
      inner = Enum.map_join(fields, ",", fn {field, type} -> "#{Type.serialize_type(type)} #{field}" end)
      "#{type_name}(#{inner})"
    end)
  end

  @spec collect_types(type_map(), [String.t()], %{String.t() => true}) :: %{String.t() => true}
  defp collect_types(_types, [], seen), do: seen

  defp collect_types(types, [name | rest], seen) do
    if Map.has_key?(seen, name) do
      collect_types(types, rest, seen)
    else
      references = Enum.flat_map(Map.fetch!(types, name).fields, fn {_, type} -> referenced_types(type) end)
      collect_types(types, references ++ rest, Map.put(seen, name, true))
    end
  end

  @spec referenced_types(Type.field_type()) :: [String.t()]
  defp referenced_types({:array, type}), do: referenced_types(type)
  defp referenced_types(type) when is_binary(type), do: [type]
  defp referenced_types(_type), do: []

  @doc """
  Hashes a struct value, per the EIP-712 spec.

  ## Examples

      iex> types = %{
      ...>   "Mail" => %Cartouche.Typed.Type{fields: [{"from", "Person"}, {"to", "Person"}, {"contents", :string}]},
      ...>   "Person" => %Cartouche.Typed.Type{fields: [{"name", :string}, {"wallet", :address}]}
      ...> }
      ...> value = %{
      ...>   "contents" => "Hello, Bob!",
      ...>   "from" => %{
      ...>     "name" => "Cow",
      ...>     "wallet" => ~h[0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826]
      ...>   },
      ...>   "to" => %{
      ...>     "name" => "Bob",
      ...>     "wallet" => ~h[0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB]
      ...>   }
      ...> }
      iex> to_hex(Cartouche.Typed.hash_struct("Mail", value, types))
      "0xc52c0ee5d84264471806290a3f2c4cecfc5490626bf912d01f240d7a274b371e"
  """
  @spec hash_struct(String.t(), value_map(), type_map()) :: binary()
  def hash_struct(name, value, types) do
    type = Map.fetch!(types, name)
    encoded_type = encode_type(name, types)
    type_hash = Cartouche.Hash.keccak(encoded_type)
    encode_data = encode_value_map(value, type.fields, types)

    Cartouche.Hash.keccak(type_hash <> encode_data)
  end

  @doc """
  Builds a domain struct for a given type, per the EIP-712 spec.

  ## Examples

      iex> %Cartouche.Typed{
      ...>   domain: %Cartouche.Typed.Domain{
      ...>     chain_id: 1,
      ...>     name: "Ether Mail",
      ...>     verifying_contract: ~h[0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC],
      ...>     version: "1"
      ...>   },
      ...>   types: %{
      ...>     "Mail" => %Cartouche.Typed.Type{fields: [{"from", "Person"}, {"to", "Person"}, {"contents", :string}]},
      ...>     "Person" => %Cartouche.Typed.Type{fields: [{"name", :string}, {"wallet", :address}]}
      ...>   },
      ...>   value: %{
      ...>     "contents" => "Hello, Bob!",
      ...>     "from" => %{
      ...>       "name" => "Cow",
      ...>       "wallet" => ~h[0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826]
      ...>     },
      ...>     "to" => %{
      ...>       "name" => "Bob",
      ...>       "wallet" => ~h[0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB]
      ...>     }
      ...>   }
      ...> }
      ...> |> Cartouche.Typed.domain_seperator()
      ...> |> to_hex()
      "0xf2cee375fa42b42143804025fc449deafd50cc031ca257e0b194a650a912090f"
  """
  @spec domain_seperator(t()) :: binary()
  def domain_seperator(%__MODULE__{domain: domain}) do
    hash_struct("EIP712Domain", Domain.serialize_keys(domain), Domain.domain_type(domain))
  end

  @doc """
  Encodes a given typed value such that it can be signed or recovered.

  ## Examples

      iex> %Cartouche.Typed{
      ...>   domain: %Cartouche.Typed.Domain{
      ...>     chain_id: 1,
      ...>     name: "Ether Mail",
      ...>     verifying_contract: ~h[0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC],
      ...>     version: "1"
      ...>   },
      ...>   types: %{
      ...>     "Mail" => %Cartouche.Typed.Type{fields: [{"from", "Person"}, {"to", "Person"}, {"contents", :string}]},
      ...>     "Person" => %Cartouche.Typed.Type{fields: [{"name", :string}, {"wallet", :address}]}
      ...>   },
      ...>   value: %{
      ...>     "contents" => "Hello, Bob!",
      ...>     "from" => %{
      ...>       "name" => "Cow",
      ...>       "wallet" => ~h[0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826]
      ...>     },
      ...>     "to" => %{
      ...>       "name" => "Bob",
      ...>       "wallet" => ~h[0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB]
      ...>     }
      ...>   }
      ...> }
      ...> |> Cartouche.Typed.encode()
      ...> |> to_hex()
      "0x1901f2cee375fa42b42143804025fc449deafd50cc031ca257e0b194a650a912090fc52c0ee5d84264471806290a3f2c4cecfc5490626bf912d01f240d7a274b371e"

      iex> %Cartouche.Typed{
      ...>   domain: %Cartouche.Typed.Domain{
      ...>     chain_id: 1,
      ...>     name: "Complex Array",
      ...>     verifying_contract: ~h[0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC],
      ...>     version: "1"
      ...>   },
      ...>   types: %{
      ...>     "Array" => %Cartouche.Typed.Type{fields: [{"a", {:uint, 256}}, {"b", {:uint, 256}}, {"c", :string}, {"d", {:array, :bytes}}]}
      ...>   },
      ...>   value: %{
      ...>     "a" => 55,
      ...>     "b" => 66,
      ...>     "c" => "Hello",
      ...>     "d" => [<<0x11, 0x22>>, <<0x33, 0x44>>]
      ...>   }
      ...> }
      ...> |> Cartouche.Typed.encode()
      ...> |> to_hex()
      "0x190103bd1627b4c5f7540c63d7ee347524dcef247eed29c833dd3b1455b8dec4009fcc95538bfc3f979ca59d9ef7de5ed402a4e403857b3de87d1fc8ed4a2a7cddd9"

      iex> %Cartouche.Typed{
      ...>   domain: %Cartouche.Typed.Domain{
      ...>     name: "Complex Array",
      ...>     version: "1"
      ...>   },
      ...>   types: %{
      ...>     "Array" => %Cartouche.Typed.Type{fields: [{"a", {:uint, 256}}, {"b", {:uint, 256}}, {"c", :string}, {"d", {:array, :bytes}}]}
      ...>   },
      ...>   value: %{
      ...>     "a" => 55,
      ...>     "b" => 66,
      ...>     "c" => "Hello",
      ...>     "d" => [<<0x11, 0x22>>, <<0x33, 0x44>>]
      ...>   }
      ...> }
      ...> |> Cartouche.Typed.encode()
      ...> |> to_hex()
      "0x1901f4806c1a9dae718712eca4906bfca239a3a4a6dea2e9b9a1284fee5ff4df4b1ccc95538bfc3f979ca59d9ef7de5ed402a4e403857b3de87d1fc8ed4a2a7cddd9"

      iex> %Cartouche.Typed{
      ...>   domain: %Cartouche.Typed.Domain{
      ...>     name: "Complex Array",
      ...>     version: "1"
      ...>   },
      ...>   types: %{
      ...>     "Array" => %Cartouche.Typed.Type{fields: [{"a", {:uint, 256}}, {"b", {:uint, 256}}, {"c", :string}, {"d", :bool}]}
      ...>   },
      ...>   value: %{
      ...>     "a" => 55,
      ...>     "b" => 66,
      ...>     "c" => "Hello",
      ...>     "d" => true
      ...>   }
      ...> }
      ...> |> Cartouche.Typed.encode()
      ...> |> to_hex()
      "0x1901f4806c1a9dae718712eca4906bfca239a3a4a6dea2e9b9a1284fee5ff4df4b1c8c56315a01fe3937526fe8c2b472b7e9e1c21728f6c14d5ffb0e0c156f74aca0"
  """
  @spec encode(t()) :: binary()
  def encode(%__MODULE__{types: types, value: value} = typed) do
    {name, _type} = find_type(Map.keys(value), types)
    domain_separator = domain_seperator(typed)
    hash_struct_message = hash_struct(name, value, types)

    <<0x19, 0x01, domain_separator::binary, hash_struct_message::binary>>
  end
end
