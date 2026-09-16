defmodule Onchain.Aerodrome.Types.RewardTest do
  use ExUnit.Case, async: true

  alias Onchain.Address
  alias Onchain.Aerodrome.Types.Reward
  alias Onchain.Aerodrome.TypesCase

  @reward_fixtures ~w(rewards_sugar.rewards rewards_sugar.rewardsByAddress)
  @lp <<1::160>>
  @token <<2::160>>
  @fee <<3::160>>
  @bribe <<4::160>>
  @raw {7, @lp, 100, @token, @fee, @bribe}

  describe "from_raw/1" do
    test "maps every field of nonempty live fee rewards" do
      rows = TypesCase.decode_rows("nonempty/rewards_sugar.rewardsByAddress")
      assert [_, _] = rows

      rewards =
        Enum.map(rows, fn raw ->
          reward = Reward.from_raw(raw)

          TypesCase.assert_one_to_one(
            Reward,
            {"rewards_sugar.json", "rewardsByAddress", ["uint256", "address"]},
            raw,
            reward
          )

          TypesCase.refute_floats(reward)
          assert reward.venft_id == 10
          assert reward.lp == "0x42d4a22CaD0F5a49681a5715cE994Af73A43B76b"
          assert reward.amount > 0
          reward
        end)

      assert Enum.map(rewards, & &1.amount) == [783_607_905_508_160_263, 2_231_865]
    end

    test "maps a positional ABI-shaped row one to one" do
      # Keep distinct synthetic addresses alongside the live fee-only rows.
      reward = Reward.from_raw(@raw)

      assert %Reward{} = reward

      TypesCase.assert_one_to_one(
        Reward,
        {"rewards_sugar.json", "rewards", ["uint256", "uint256", "uint256"]},
        @raw,
        reward
      )

      TypesCase.refute_floats(reward)
    end

    test "checksums address fields and keeps amount as an integer" do
      reward = Reward.from_raw(@raw)

      assert reward.venft_id == 7
      assert reward.lp == Address.checksum!(@lp)
      assert reward.amount == 100
      assert reward.token == Address.checksum!(@token)
      assert reward.fee == Address.checksum!(@fee)
      assert reward.bribe == Address.checksum!(@bribe)
      refute is_float(reward.amount)
    end

    test "decodes every committed rewards fixture row" do
      for id <- @reward_fixtures, row <- TypesCase.decode_rows(id) do
        reward = Reward.from_raw(row)
        assert %Reward{} = reward
        TypesCase.refute_floats(reward)
      end
    end

    test "raises FunctionClauseError on a tuple of the wrong size" do
      assert_raise FunctionClauseError, fn -> Reward.from_raw({}) end
    end
  end
end
