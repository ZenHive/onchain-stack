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

  @spec assert_one_to_one(module(), {String.t(), String.t()}, tuple(), struct()) :: :ok
  def assert_one_to_one(module, {abi_file, abi_function}, row, struct) do
    fields = for %{field: field} <- List.wrap(module.__info__(:struct)), do: field
    address_fields = abi_address_fields(abi_file, abi_function)

    assert tuple_size(row) == length(fields)

    for {field, index} <- Enum.with_index(fields) do
      raw = elem(row, index)
      actual = Map.fetch!(struct, field)

      # Which fields are checksummed follows the ABI's declared `address`
      # component type, never the byte length of the decoded value: a 20-byte
      # `symbol` is not an address, and lp_sugar.all already carries symbols
      # of exactly 20 bytes.
      if field in address_fields do
        assert actual == Address.checksum!(raw), "#{field}"
      else
        assert actual == raw, "#{field}"
      end
    end

    :ok
  end

  @spec abi_address_fields(String.t(), String.t()) :: [atom()]
  def abi_address_fields(abi_file, abi_function) do
    :onchain_aerodrome
    |> Application.app_dir("priv/abis")
    |> Path.join(abi_file)
    |> File.read!()
    |> Jason.decode!()
    |> Enum.find(&(&1["type"] == "function" and &1["name"] == abi_function))
    |> Map.fetch!("outputs")
    |> hd()
    |> Map.fetch!("components")
    |> Enum.filter(&(&1["type"] == "address"))
    |> Enum.map(&String.to_existing_atom(&1["name"]))
  end

  @spec refute_floats(struct()) :: :ok
  def refute_floats(struct) do
    for {field, value} <- Map.from_struct(struct), is_number(value) do
      assert is_integer(value), "#{field} is #{inspect(value)}"
    end

    :ok
  end
end
