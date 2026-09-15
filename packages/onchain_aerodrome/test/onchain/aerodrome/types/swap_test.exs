defmodule Onchain.Aerodrome.Types.SwapTest do
  use ExUnit.Case, async: true

  alias Onchain.Aerodrome.Types.Swap
  alias Onchain.Aerodrome.TypesCase

  describe "from_raw/1" do
    test "maps a positional fixture row one to one" do
      row = first_row()
      swap = Swap.from_raw(row)

      assert %Swap{} = swap
      TypesCase.assert_one_to_one(Swap, row, swap)
      TypesCase.refute_floats(swap)
      assert is_integer(swap.pool_fee)
    end

    test "decodes every committed forSwaps fixture row" do
      for row <- TypesCase.decode_rows("lp_sugar.forSwaps") do
        swap = Swap.from_raw(row)
        assert %Swap{} = swap
        TypesCase.refute_floats(swap)
      end
    end

    test "raises FunctionClauseError on a tuple of the wrong size" do
      assert_raise FunctionClauseError, fn -> Swap.from_raw({}) end
    end
  end

  defp first_row, do: "lp_sugar.forSwaps" |> TypesCase.decode_rows() |> hd()
end
