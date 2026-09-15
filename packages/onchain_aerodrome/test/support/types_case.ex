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

  @spec assert_one_to_one(module(), tuple(), struct()) :: :ok
  def assert_one_to_one(module, row, struct) do
    fields = for %{field: field} <- List.wrap(module.__info__(:struct)), do: field

    assert tuple_size(row) == length(fields)

    for {field, index} <- Enum.with_index(fields) do
      raw = elem(row, index)
      actual = Map.fetch!(struct, field)

      if is_binary(raw) and byte_size(raw) == 20 do
        assert actual == Address.checksum!(raw), "#{field}"
      else
        assert actual == raw, "#{field}"
      end
    end

    :ok
  end

  @spec refute_floats(struct()) :: :ok
  def refute_floats(struct) do
    for {field, value} <- Map.from_struct(struct), is_number(value) do
      assert is_integer(value), "#{field} is #{inspect(value)}"
    end

    :ok
  end
end
