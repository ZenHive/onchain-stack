defmodule Onchain.Aerodrome.Types.LpEpochTest do
  use ExUnit.Case, async: true

  alias Onchain.Address
  alias Onchain.Aerodrome.Types.LpEpoch
  alias Onchain.Aerodrome.Types.LpEpoch.TokenAmount
  alias Onchain.Aerodrome.TypesCase

  @epoch_fixtures ~w(rewards_sugar.epochsLatest rewards_sugar.epochsByAddress)
  @token <<35, 106, 165, 9, 121, 213, 243, 222, 59, 209, 238, 180, 14, 129, 19, 127, 34, 171, 121, 75>>
  @lp <<1::160>>

  describe "from_raw/1" do
    test "maps a positional epochsLatest fixture row one to one" do
      row = first_row("rewards_sugar.epochsLatest")
      epoch = LpEpoch.from_raw(row)

      assert %LpEpoch{} = epoch

      TypesCase.assert_one_to_one(LpEpoch, {"rewards_sugar.json", "epochsLatest", ["uint256", "uint256"]}, row, epoch, %{
        bribes: TokenAmount,
        fees: TokenAmount
      })

      TypesCase.refute_floats(epoch)
    end

    test "decodes fees as TokenAmount and keeps votes as an integer" do
      row = Enum.find(TypesCase.decode_rows("rewards_sugar.epochsLatest"), &(elem(&1, 5) != []))
      epoch = LpEpoch.from_raw(row)

      assert is_integer(epoch.votes)
      refute is_list(epoch.votes)
      assert [%TokenAmount{} | _] = epoch.fees
      assert hd(epoch.fees).token == Address.checksum!(elem(hd(elem(row, 5)), 0))
      assert hd(epoch.fees).amount == elem(hd(elem(row, 5)), 1)
      assert epoch.bribes == []
    end

    test "decodes a synthetic row with both bribes and fees as TokenAmount, not Reward" do
      bribe = {@token, 100}
      fee = {@token, 50}
      raw = {1_704_326_400, @lp, 10, 20, [bribe], [fee]}
      epoch = LpEpoch.from_raw(raw)

      assert [%TokenAmount{amount: 100}] = epoch.bribes
      assert [%TokenAmount{amount: 50}] = epoch.fees
      assert hd(epoch.bribes).token == Address.checksum!(@token)
      TypesCase.refute_floats(epoch)
    end

    test "decodes every committed epochs fixture row" do
      for id <- @epoch_fixtures, row <- TypesCase.decode_rows(id) do
        epoch = LpEpoch.from_raw(row)
        assert %LpEpoch{} = epoch
        TypesCase.refute_floats(epoch)
      end
    end

    test "raises FunctionClauseError on a tuple of the wrong size" do
      assert_raise FunctionClauseError, fn -> LpEpoch.from_raw({}) end
      assert_raise FunctionClauseError, fn -> TokenAmount.from_raw({}) end
    end
  end

  defp first_row(id), do: id |> TypesCase.decode_rows() |> hd()
end
