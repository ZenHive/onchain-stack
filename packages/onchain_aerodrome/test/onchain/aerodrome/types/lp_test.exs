defmodule Onchain.Aerodrome.Types.LpTest do
  use ExUnit.Case, async: true

  alias Onchain.Address
  alias Onchain.Aerodrome.Types.Lp
  alias Onchain.Aerodrome.TypesCase

  @all_fixtures ~w(lp_sugar.all.page0 lp_sugar.all.page1 lp_sugar.all.tail lp_sugar.all.filtered_short)

  describe "from_raw/1" do
    test "maps a positional fixture row one to one" do
      row = first_row("lp_sugar.all.page0")
      lp = Lp.from_raw(row)

      assert %Lp{} = lp
      TypesCase.assert_one_to_one(Lp, {"lp_sugar.json", "all"}, row, lp)
      TypesCase.refute_floats(lp)
    end

    test "checksums address fields and leaves money as integers" do
      row = first_row("lp_sugar.all.page0")
      lp = Lp.from_raw(row)

      assert lp.lp == Address.checksum!(elem(row, 0))
      assert is_binary(lp.symbol)
      assert is_integer(lp.liquidity)
      assert is_integer(lp.emissions)
      assert is_integer(lp.reserve0)
      assert is_integer(lp.emissions_cap)
      refute is_float(lp.liquidity)
    end

    test "carries the type discriminator values from the all fixtures" do
      types =
        for id <- @all_fixtures,
            row <- TypesCase.decode_rows(id),
            lp = Lp.from_raw(row) do
          lp.type
        end

      assert -1 in types
      assert 0 in types
      assert Enum.any?(types, &(&1 > 0))
    end

    test "decodes every committed all fixture row" do
      for id <- @all_fixtures, row <- TypesCase.decode_rows(id) do
        lp = Lp.from_raw(row)
        assert %Lp{} = lp
        TypesCase.refute_floats(lp)
      end
    end

    test "raises FunctionClauseError on a tuple of the wrong size" do
      assert_raise FunctionClauseError, fn -> Lp.from_raw({}) end
    end
  end

  defp first_row(id), do: id |> TypesCase.decode_rows() |> hd()
end
