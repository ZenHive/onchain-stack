defmodule Onchain.Aerodrome.TypesCase do
  @moduledoc false

  import ExUnit.Assertions

  alias Onchain.Address
  alias Onchain.Aerodrome.Fixtures

  @spec decode_rows(String.t()) :: [tuple()]
  def decode_rows(id) do
    assert {:ok, [rows]} = Fixtures.decode(Fixtures.load(id))
    rows
  end

  @spec decode_tuple(String.t()) :: tuple()
  def decode_tuple(id) do
    assert {:ok, [row]} = Fixtures.decode(Fixtures.load(id))
    assert is_tuple(row)
    row
  end

  @spec assert_one_to_one(module(), {String.t(), String.t(), [String.t()]}, tuple(), struct()) :: :ok
  @spec assert_one_to_one(module(), {String.t(), String.t(), [String.t()]}, tuple(), struct(), map()) :: :ok
  def assert_one_to_one(module, {abi_file, abi_function, input_types}, row, struct, nested \\ %{})
      when is_list(input_types) do
    components = abi_components(abi_file, abi_function, input_types)
    assert_one_to_one_components(module, components, row, struct, nested)
  end

  @spec abi_components(String.t(), String.t(), [String.t()] | nil) :: [map()]
  def abi_components(abi_file, abi_function, input_types \\ nil) do
    entry = abi_entry(abi_file, abi_function, input_types)

    case entry["outputs"] do
      [%{"components" => components} | _] ->
        components

      outputs ->
        flunk("""
        #{abi_file}: #{signature(abi_function, input_types)} has no tuple output carrying "components"
        outputs: #{inspect(outputs)}\
        """)
    end
  end

  @spec abi_entry(String.t(), String.t(), [String.t()] | nil) :: map()
  def abi_entry(abi_file, abi_function, input_types \\ nil) do
    :onchain_aerodrome
    |> Application.app_dir("priv/abis")
    |> Path.join(abi_file)
    |> File.read!()
    |> Jason.decode!()
    |> resolve_entry(abi_file, abi_function, input_types)
  end

  # The one ABI-entry resolution rule in this package. `input_types` nil means
  # "match on name alone", which is only legal while the name is unique in the
  # file: a capture that grows an overload must fail loudly here rather than
  # silently grade against whichever entry sits first in the JSON array.
  @spec resolve_entry([map()], String.t(), String.t(), [String.t()] | nil) :: map()
  def resolve_entry(entries, source, abi_function, input_types) do
    case Enum.filter(entries, &function_match?(&1, abi_function, input_types)) do
      [entry] ->
        entry

      [] ->
        flunk("""
        #{source}: no ABI function entry matching #{signature(abi_function, input_types)}
        candidates named "#{abi_function}": #{candidate_list(entries, abi_function)}\
        """)

      matches ->
        flunk("""
        #{source}: #{length(matches)} ABI function entries match #{signature(abi_function, input_types)}
        matches: #{Enum.map_join(matches, ", ", &entry_signature/1)}
        pass the overload's input types explicitly\
        """)
    end
  end

  @spec refute_floats(term()) :: :ok
  def refute_floats(struct) when is_struct(struct) do
    for {field, value} <- Map.from_struct(struct) do
      refute_float_value(field, value)
    end

    :ok
  end

  def refute_floats(values) when is_list(values) do
    Enum.each(values, &refute_floats/1)
    :ok
  end

  def refute_floats(_value), do: :ok

  @spec assert_one_to_one_components(module(), [map()], tuple(), struct(), map()) :: :ok
  defp assert_one_to_one_components(module, components, row, struct, nested) do
    fields = for %{field: field} <- List.wrap(module.__info__(:struct)), do: field

    assert tuple_size(row) == length(fields)
    assert length(components) == length(fields)

    fields
    |> Enum.zip(components)
    |> Enum.with_index()
    |> Enum.each(fn {{field, component}, index} ->
      assert_field(field, component, elem(row, index), Map.fetch!(struct, field), nested)
    end)

    :ok
  end

  @spec assert_field(atom(), map(), term(), term(), map()) :: :ok
  defp assert_field(field, %{"type" => "address"}, raw, actual, _nested) do
    # Which fields are checksummed follows the ABI's declared `address`
    # component type, never the byte length of the decoded value: a 20-byte
    # `symbol` is not an address, and lp_sugar.all already carries symbols
    # of exactly 20 bytes.
    assert actual == Address.checksum!(raw), "#{field}"
    :ok
  end

  defp assert_field(field, %{"type" => "address[]"}, raw, actual, _nested) do
    assert actual == Enum.map(raw, &Address.checksum!/1), "#{field}"
    :ok
  end

  defp assert_field(field, %{"type" => "tuple[]", "components" => components}, raw, actual, nested) do
    nested_module = Map.fetch!(nested, field)
    assert is_list(actual), "#{field}"
    assert length(actual) == length(raw), "#{field}"

    for {nested_raw, nested_struct} <- Enum.zip(raw, actual) do
      assert %^nested_module{} = nested_struct, "#{field}"
      assert_one_to_one_components(nested_module, components, nested_raw, nested_struct, %{})
    end

    :ok
  end

  defp assert_field(field, _component, raw, actual, _nested) do
    assert actual == raw, "#{field}"
    :ok
  end

  @spec function_match?(map(), String.t(), [String.t()] | nil) :: boolean()
  defp function_match?(%{"type" => "function", "name" => name}, abi_function, nil) when name == abi_function do
    true
  end

  defp function_match?(%{"type" => "function", "name" => name, "inputs" => inputs}, abi_function, input_types)
       when name == abi_function do
    Enum.map(inputs, & &1["type"]) == input_types
  end

  defp function_match?(_entry, _abi_function, _input_types), do: false

  @spec signature(String.t(), [String.t()] | nil) :: String.t()
  defp signature(abi_function, nil), do: "#{abi_function}(<any inputs>)"
  defp signature(abi_function, input_types), do: "#{abi_function}(#{Enum.join(input_types, ",")})"

  @spec entry_signature(map()) :: String.t()
  defp entry_signature(entry) do
    signature(entry["name"], entry |> Map.get("inputs", []) |> Enum.map(& &1["type"]))
  end

  @spec candidate_list([map()], String.t()) :: String.t()
  defp candidate_list(entries, abi_function) do
    entries
    |> Enum.filter(&(&1["type"] == "function" and &1["name"] == abi_function))
    |> case do
      [] -> "(none)"
      candidates -> Enum.map_join(candidates, ", ", &entry_signature/1)
    end
  end

  @spec refute_float_value(atom(), term()) :: :ok
  defp refute_float_value(field, value) when is_number(value) do
    assert is_integer(value), "#{field} is #{inspect(value)}"
    :ok
  end

  defp refute_float_value(_field, value) when is_struct(value), do: refute_floats(value)

  defp refute_float_value(field, values) when is_list(values) do
    Enum.each(values, &refute_float_value(field, &1))
    :ok
  end

  defp refute_float_value(_field, _value), do: :ok
end
