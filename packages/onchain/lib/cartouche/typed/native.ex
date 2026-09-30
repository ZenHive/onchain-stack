defmodule Cartouche.Typed.Native do
  @moduledoc false
  alias Cartouche.Typed
  alias Cartouche.Typed.Domain
  alias Cartouche.Typed.Type

  @doc false
  @spec signing_hash(Typed.t()) :: binary()
  def signing_hash(typed), do: run!("hash", document(typed))

  @doc false
  @spec encode(Typed.t()) :: binary()
  def encode(typed), do: run!("encode", document(typed))

  @doc false
  @spec hash_struct(String.t(), map(), Typed.type_map()) :: binary()
  def hash_struct(name, value, types), do: run!("hash_struct", document(name, value, types))

  @doc false
  @spec encode_value(term(), Type.field_type(), Typed.type_map()) :: binary()
  def encode_value(value, type, types) do
    # A single field's encodeData is exactly its EIP-712 data word.
    name = fresh_name(types, "CartoucheValue")
    types = Map.put(types, name, %Type{fields: [{"value", type}]})
    run!("encode_data", document(name, %{"value" => value}, types))
  end

  @spec fresh_name(map(), String.t()) :: String.t()
  defp fresh_name(types, name) do
    if Map.has_key?(types, name), do: fresh_name(types, name <> "_"), else: name
  end

  @spec document(Typed.t()) :: map()
  defp document(%Typed{domain: domain, types: types, value: value} = typed) do
    # Preserve Cartouche's existing root-type selection and ambiguity errors.
    serialized = Typed.serialize(typed)
    fields = value |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
    {name, _} = Enum.find(types, fn {_, type} -> Enum.sort(Enum.map(type.fields, &elem(&1, 0))) == fields end)

    name
    |> document(value, types)
    |> Map.put("domain", domain_json(serialized["domain"]))
    |> update_in(["types"], &Map.merge(&1, serialize_types(Domain.domain_type(domain))))
  end

  @spec domain_json(map()) :: map()
  defp domain_json(domain) do
    case domain do
      %{"chainId" => value} when is_integer(value) ->
        Map.put(domain, "chainId", serialize_value(value, {:uint, 256}, %{}))

      _ ->
        domain
    end
  end

  @spec document(String.t(), map(), Typed.type_map()) :: map()
  defp document(name, value, types) do
    %{
      "domain" => %{},
      "types" => serialize_types(types),
      "primaryType" => name,
      "message" => if(value == %{}, do: %{}, else: serialize_value(value, name, types))
    }
  end

  @spec serialize_types(Typed.type_map()) :: map()
  defp serialize_types(types), do: Map.new(types, fn {name, type} -> {name, Type.serialize(type)} end)

  @spec serialize_value(term(), Type.field_type(), Typed.type_map()) :: term()
  defp serialize_value(value, type, types) when is_binary(type) do
    value = Map.new(value, fn {key, item} -> {to_string(key), item} end)

    Map.new(Map.fetch!(types, type).fields, fn {field, field_type} ->
      {field, serialize_value(Map.fetch!(value, field), field_type, types)}
    end)
  end

  defp serialize_value(values, {:array, type}, types), do: Enum.map(values, &serialize_value(&1, type, types))

  defp serialize_value(value, {kind, width}, _) when kind in [:int, :uint] do
    min = if kind == :int, do: -Integer.pow(2, width - 1), else: 0
    max = if kind == :int, do: Integer.pow(2, width - 1), else: Integer.pow(2, width)
    if value < min or value >= max, do: raise(ArgumentError, "value out of range for #{kind}#{width}")
    Integer.to_string(value)
  end

  defp serialize_value(value, :bool, _), do: !!value
  defp serialize_value(value, type, _), do: Type.serialize_value(value, type)

  @spec run!(String.t(), map()) :: binary()
  defp run!(operation, document) do
    case ABI.Native.consensus("typed", operation, document) do
      {:ok, value} -> value
      {:error, reason} -> raise ArgumentError, reason
    end
  end
end
