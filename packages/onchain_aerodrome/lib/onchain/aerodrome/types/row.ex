defmodule Onchain.Aerodrome.Types.Row do
  @moduledoc """
  Shared positional constructor for Sugar structs.

  `from_raw/4` zips an ABI tuple onto a struct's field list in source order.
  Address fields are EIP-55 checksummed; every other value is stored verbatim.
  Money stays integer — there is no float conversion here.
  """

  alias Onchain.Address

  @doc """
  Build `module`'s struct from a positional decode tuple.

  `fields` is the ABI component order. `address_fields` is the subset to
  checksum. Raises `FunctionClauseError` when the tuple length does not
  match `fields`.
  """
  @spec from_raw(module(), [atom()], [atom()], tuple()) :: struct()
  def from_raw(module, fields, address_fields, raw)
      when is_atom(module) and is_list(fields) and is_list(address_fields) and is_tuple(raw) and
             tuple_size(raw) == length(fields) do
    addresses = MapSet.new(address_fields)

    values =
      fields
      |> Enum.with_index()
      |> Enum.map(fn {field, index} ->
        {field, cast(MapSet.member?(addresses, field), elem(raw, index))}
      end)

    struct!(module, values)
  end

  @spec cast(boolean(), term()) :: term()
  defp cast(true, value), do: Address.checksum!(value)
  defp cast(false, value), do: value
end
