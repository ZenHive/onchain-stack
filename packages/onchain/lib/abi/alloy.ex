defmodule ABI.Alloy do
  @moduledoc false
  alias ABI.FunctionSelector
  alias ABI.Native

  @typep arg_type :: FunctionSelector.argument_type()

  @doc false
  @spec signature(FunctionSelector.t(), :function | :event) :: binary()
  def signature(selector, kind) do
    cached(:signature, {kind, selector}, fn ->
      unwrap(Native.abi(:signature, FunctionSelector.encode(selector), kind))
    end)
  end

  @doc false
  @spec schema([arg_type()], binary()) :: reference()
  def schema(types, topic0 \\ <<>>) do
    cached(:schema, {types, topic0}, fn ->
      text = FunctionSelector.encode(%FunctionSelector{types: wire_types(types)})
      unwrap(Native.compile(text, topic0))
    end)
  end

  # One persistent_term per cache, so a miss in one never rewrites the other.
  # Inserts merge on retry when a concurrent miss publishes a stale map snapshot,
  # so entries are not dropped. The cap bounds retained NIF resources for applications
  # accepting arbitrary schemas.
  defp cached(name, key, compute) do
    term_key = {__MODULE__, name}

    case cache_fetch(term_key, key) do
      {:ok, value} ->
        value

      :error ->
        value = compute.()
        cache_ensure(term_key, key, value)
        value
    end
  end

  defp cache_fetch(term_key, key) do
    term_key |> :persistent_term.get(%{}) |> Map.fetch(key)
  end

  defp cache_ensure(term_key, key, value, attempts \\ 0)

  defp cache_ensure(_term_key, _key, _value, attempts) when attempts >= 32, do: :ok

  defp cache_ensure(term_key, key, value, attempts) do
    cache = :persistent_term.get(term_key, %{})

    cond do
      Map.has_key?(cache, key) ->
        :ok

      map_size(cache) >= 1024 ->
        :ok

      true ->
        :persistent_term.put(term_key, Map.put(cache, key, value))

        case cache_fetch(term_key, key) do
          {:ok, _} -> :ok
          :error -> cache_ensure(term_key, key, value, attempts + 1)
        end
    end
  end

  @doc false
  @spec encode_raw([term()], [arg_type()]) :: binary()
  def encode_raw(values, types) do
    normalized = normalize(types, values)
    unwrap(Native.abi(:raw_encode, schema(types), List.to_tuple(normalized)))
  end

  @doc false
  @spec encode_packed([term()], [arg_type()]) :: binary()
  def encode_packed(values, types) do
    Enum.zip_with(types, values, fn %{type: type}, value -> validate_packed(type, value) end)
    normalized = normalize(types, values)
    unwrap(Native.abi(:packed, schema(types), List.to_tuple(normalized)))
  end

  @doc false
  @spec decode_raw(binary(), [arg_type()], keyword()) :: [term()]
  def decode_raw(data, types, opts) do
    chunks = ABI.Validation.chunks(data, types, opts)
    values = unwrap(Native.abi(:raw_decode, schema(types), chunks))
    Enum.zip_with(types, values, fn %{type: type}, value -> render(type, value, opts) end)
  end

  @doc false
  @spec render(FunctionSelector.type(), term(), keyword()) :: term()
  def render({:tuple, types}, values, opts) do
    rendered = Enum.zip_with(types, Tuple.to_list(values), fn %{type: t}, v -> render(t, v, opts) end)
    ABI.TypeDecoder.tuple_value(types, rendered, Keyword.get(opts, :decode_structs, false))
  end

  def render({:array, type}, values, opts), do: Enum.map(values, &render(type, &1, opts))
  def render({:array, _, 0}, {}, _), do: []
  def render({:array, type, _}, values, opts), do: Enum.map(values, &render(type, &1, opts))
  def render({:bytes, 0}, {}, _), do: <<>>
  def render(_, value, _), do: value

  defp wire_types(types), do: Enum.map(types, fn %{type: t} = p -> %{p | type: wire_type(t)} end)
  defp wire_type(:string), do: :bytes
  defp wire_type({:bytes, 0}), do: {:tuple, []}
  defp wire_type({:tuple, types}), do: {:tuple, wire_types(types)}
  defp wire_type({:array, type}), do: {:array, wire_type(type)}
  defp wire_type({:array, _, 0}), do: {:tuple, []}
  defp wire_type({:array, type, n}), do: {:array, wire_type(type), n}
  defp wire_type(t), do: t

  defp normalize([], _values), do: []
  defp normalize([%{type: type} | rest], [value | values]), do: [normalize_value(type, value) | normalize(rest, values)]
  defp normalize([%{type: type} | _], []), do: raise("Unsupported encoding type: #{inspect(type)}")

  defp normalize_value({:tuple, types}, value) do
    values = data_to_list(types, value)
    normalized = normalize(types, values)

    case Enum.drop(values, length(types)) do
      [] ->
        List.to_tuple(normalized)

      extra ->
        encoded = unwrap(Native.abi(:encode, schema(types), List.to_tuple(normalized)))
        size = Enum.sum_by(types, &head_size(&1.type))
        <<head::binary-size(^size), tail::binary>> = encoded
        :erlang.error({:badmatch, {head, tail, extra, byte_size(encoded)}})
    end
  end

  defp normalize_value({:array, type}, values), do: Enum.map(values, &normalize_value(type, &1))
  defp normalize_value({:array, _, 0}, []), do: {}

  defp normalize_value({:array, type, n}, values) when n <= 100_000 do
    types = List.duplicate(%{type: type}, n)
    {:tuple, types} |> normalize_value(List.to_tuple(values)) |> Tuple.to_list()
  end

  defp normalize_value({:bytes, 0}, <<>>), do: {}

  defp normalize_value({:uint, bits}, value) do
    bin = if is_binary(value), do: value, else: :binary.encode_unsigned(value)
    if byte_size(bin) > div(bits, 8), do: raise("Data overflow encoding uint, data `#{value}` cannot fit in #{bits} bits")
    :binary.decode_unsigned(bin)
  end

  defp normalize_value({:int, bits}, value) when is_integer(value) do
    max = Bitwise.bsl(1, bits - 1)

    if value >= max or value < -max do
      raise "Data overflow encoding int, data `#{value}` cannot fit in #{bits}-bit signed range (-#{max}..#{max - 1})"
    end

    value
  end

  defp normalize_value({:int, _}, _), do: :erlang.error(:function_clause)

  defp normalize_value(:address, value) do
    n = normalize_value({:uint, 160}, value)
    <<n::160>>
  end

  defp normalize_value(:bool, value) when is_boolean(value), do: value
  defp normalize_value(:bool, value), do: raise("Invalid data for bool: #{value}")
  defp normalize_value(:function, value) when is_binary(value) and byte_size(value) == 24, do: value

  defp normalize_value(:function, value) when is_binary(value),
    do:
      raise(
        ArgumentError,
        "function: size mismatch (expected 24 bytes — 20-byte address ++ 4-byte selector — got #{byte_size(value)})"
      )

  defp normalize_value(:function, value),
    do: raise(ArgumentError, "function: expected 24-byte binary, got #{inspect(value)}")

  defp normalize_value({:bytes, n}, value) when is_binary(value) and byte_size(value) <= n, do: value

  defp normalize_value({:bytes, n}, value) when is_binary(value),
    do: raise("size mismatch for bytes#{n}: #{inspect(value)}")

  defp normalize_value({:bytes, n}, value), do: raise("wrong datatype for bytes#{n}: #{inspect(value)}")
  defp normalize_value(type, value) when type in [:string, :bytes], do: value
  defp normalize_value(type, _), do: raise("Unsupported encoding type: #{inspect(type)}")

  defp head_size(type) do
    if FunctionSelector.dynamic?(type), do: 32, else: static_size(type)
  end

  defp static_size({:tuple, types}), do: Enum.sum_by(types, &head_size(&1.type))
  defp static_size({:array, type, n}), do: n * head_size(type)
  defp static_size({:bytes, 0}), do: 0
  defp static_size(_), do: 32

  defp validate_packed({:tuple, _}, _),
    do:
      raise(
        ArgumentError,
        "encode_packed: tuple/struct types are not supported by Solidity's packed mode (see https://docs.soliditylang.org/en/stable/abi-spec.html#non-standard-packed-mode)"
      )

  defp validate_packed({:array, inner, n}, values) do
    if length(values) != n,
      do: raise(ArgumentError, "encode_packed array: size mismatch (expected #{n}, got #{length(values)})")

    validate_packed({:array, inner}, values)
  end

  defp validate_packed({:array, inner}, values) do
    case inner do
      {:array, _} -> raise ArgumentError, "encode_packed: nested arrays are not supported by Solidity's packed mode"
      {:array, _, _} -> raise ArgumentError, "encode_packed: nested arrays are not supported by Solidity's packed mode"
      {:tuple, _} -> raise ArgumentError, "encode_packed: tuple/struct types are not supported by Solidity's packed mode"
      _ -> Enum.each(values, &normalize_value(inner, &1))
    end
  end

  defp validate_packed({:uint, bits}, value) when is_integer(value) do
    cond do
      value < 0 ->
        raise ArgumentError, "encode_packed uint#{bits}: negative value #{value}"

      value >= Bitwise.bsl(1, bits) ->
        raise ArgumentError, "encode_packed uint#{bits}: #{value} doesn't fit in uint#{bits}"

      true ->
        :ok
    end
  end

  defp validate_packed({:uint, bits}, value) when is_binary(value) do
    if byte_size(value) > div(bits, 8),
      do: raise(ArgumentError, "encode_packed uint#{bits}: binary too long (#{byte_size(value)} bytes for uint#{bits})")
  end

  defp validate_packed({:int, bits}, value) do
    max = Bitwise.bsl(1, bits - 1)

    if value >= max or value < -max,
      do: raise(ArgumentError, "encode_packed int#{bits}: #{value} doesn't fit in signed range (-#{max}..#{max - 1})")
  end

  defp validate_packed(:address, value) when is_binary(value) and byte_size(value) != 20,
    do: raise(ArgumentError, "encode_packed address: expected 20 bytes, got #{byte_size(value)}")

  defp validate_packed(:address, value), do: validate_packed({:uint, 160}, value)
  defp validate_packed(:bool, value) when is_boolean(value), do: :ok
  defp validate_packed(:bool, value), do: raise(ArgumentError, "encode_packed bool: invalid value #{inspect(value)}")
  defp validate_packed(:function, value) when is_binary(value) and byte_size(value) == 24, do: :ok

  defp validate_packed(:function, value) when is_binary(value),
    do: raise(ArgumentError, "encode_packed function: size mismatch (expected 24 bytes, got #{byte_size(value)})")

  defp validate_packed(:function, value),
    do: raise(ArgumentError, "encode_packed function: expected 24-byte binary, got #{inspect(value)}")

  defp validate_packed({:bytes, n}, value) when is_binary(value) do
    if byte_size(value) != n,
      do: raise(ArgumentError, "encode_packed bytes#{n}: size mismatch (expected #{n} bytes, got #{byte_size(value)})")
  end

  defp validate_packed(type, value) when type in [:string, :bytes] and is_binary(value), do: :ok
  defp validate_packed(type, _), do: raise(ArgumentError, "encode_packed: unsupported type #{inspect(type)}")

  defp unwrap({:ok, value}), do: value
  defp unwrap({:error, reason}), do: raise(ArgumentError, "ABI: #{inspect(reason)}")
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
end
