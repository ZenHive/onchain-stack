defmodule Onchain.Aerodrome.Types.PositionTest do
  use ExUnit.Case, async: true

  alias Onchain.Address
  alias Onchain.Aerodrome.Types.Position
  alias Onchain.Aerodrome.TypesCase

  @position_fixtures ~w(
    lp_sugar.positions.short
    lp_sugar.positionsByFactory
    lp_sugar.positionsUnstakedConcentrated
  )

  # Keep the synthetic boundary case alongside the live nonempty witness.
  @zero_address_bin <<0::160>>
  @lp <<1::160>>
  @raw {
    42,
    @lp,
    100,
    10,
    7,
    8,
    3,
    4,
    1,
    2,
    9,
    -60,
    60,
    1,
    2,
    @zero_address_bin,
    0,
    @zero_address_bin
  }

  describe "from_raw/1" do
    test "maps every field of a nonempty live position response" do
      rows = TypesCase.decode_rows("nonempty/lp_sugar.positions")
      assert [raw] = rows
      position = Position.from_raw(raw)

      TypesCase.assert_one_to_one(
        Position,
        {"lp_sugar.json", "positions", ["uint256", "uint256", "address"]},
        raw,
        position
      )

      TypesCase.refute_floats(position)
      assert position.lp == "0x723AEf6543aecE026a15662Be4D3fb3424D502A9"
      assert position.liquidity == 35_959_093_315_076
      assert position.amount0 == 130_352_112_252_769_249
      assert position.amount1 == 9_927_634_734
    end

    test "maps a positional row one to one" do
      position = Position.from_raw(@raw)

      assert %Position{} = position

      TypesCase.assert_one_to_one(
        Position,
        {"lp_sugar.json", "positions", ["uint256", "uint256", "address"]},
        @raw,
        position
      )

      TypesCase.refute_floats(position)
    end

    test "decodes every committed positions fixture row" do
      for id <- @position_fixtures, row <- TypesCase.decode_rows(id) do
        position = Position.from_raw(row)
        assert %Position{} = position
        TypesCase.refute_floats(position)
      end
    end

    test "zero locker, unlocks_at and alm stay the contract's zero values" do
      position = Position.from_raw(@raw)
      zero = Address.checksum!(@zero_address_bin)

      assert position.locker == zero
      assert position.unlocks_at == 0
      assert position.alm == zero
    end

    test "raises FunctionClauseError on a tuple of the wrong size" do
      assert_raise FunctionClauseError, fn -> Position.from_raw({}) end
    end
  end
end
