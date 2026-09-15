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

  # Task-4 goldens captured positions for an account that holds none, so
  # from_raw/1 is exercised against an ABI-shaped tuple. The fixture loop
  # still runs so a recapture that starts returning rows is decoded.
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
    test "maps a positional row one to one" do
      position = Position.from_raw(@raw)

      assert %Position{} = position
      TypesCase.assert_one_to_one(Position, {"lp_sugar.json", "positions"}, @raw, position)
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
