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

  @spec assert_one_to_one(module(), {String.t(), String.t()}, tuple(), struct()) :: :ok
  @spec assert_one_to_one(module(), {String.t(), String.t()}, tuple(), struct(), map()) :: :ok
  def assert_one_to_one(module, {abi_file, abi_function}, row, struct, nested \\ %{}) do
    components = abi_components(abi_file, abi_function)
    assert_one_to_one_components(module, components, row, struct, nested)
  end

  @spec abi_address_fields(String.t(), String.t()) :: [atom()]
  def abi_address_fields(abi_file, abi_function) do
    abi_file
    |> abi_components(abi_function)
    |> Enum.filter(&(&1["type"] == "address"))
    |> Enum.map(&String.to_existing_atom(&1["name"]))
  end

  @spec abi_components(String.t(), String.t()) :: [map()]
  def abi_components(abi_file, abi_function) do
    abi_file
    |> abi_entry(abi_function)
    |> Map.fetch!("outputs")
    |> hd()
    |> Map.fetch!("components")
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

    for {field, index} <- Enum.with_index(fields) do
      assert_field(field, Enum.at(components, index), elem(row, index), Map.fetch!(struct, field), nested)
    end

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

  @spec abi_entry(String.t(), String.t()) :: map()
  defp abi_entry(abi_file, abi_function) do
    :onchain_aerodrome
    |> Application.app_dir("priv/abis")
    |> Path.join(abi_file)
    |> File.read!()
    |> Jason.decode!()
    |> Enum.find(&(&1["type"] == "function" and &1["name"] == abi_function))
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
