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
    test "maps a positional ABI-shaped row one to one" do
      # Task-4 goldens captured rewards for a veNFT that holds none, so
      # from_raw/1 is exercised against an ABI-shaped tuple. The fixture loop
      # still runs so a recapture that starts returning rows is decoded.
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
