defmodule Onchain.Aerodrome.Types.VoteTest do
  use ExUnit.Case, async: true

  alias Onchain.Address
  alias Onchain.Aerodrome.Types.Vote
  alias Onchain.Aerodrome.TypesCase

  @lp <<153, 207, 62, 139, 251, 2, 195, 0, 49, 44, 83, 170, 197, 208, 176, 130, 227, 213, 151, 92>>
  @raw {@lp, 11_404_430_561_017_237_824_090_617}

  describe "from_raw/1" do
    test "checksums lp and keeps weight as an integer" do
      vote = Vote.from_raw(@raw)

      assert %Vote{} = vote
      assert vote.lp == Address.checksum!(@lp)
      assert vote.weight == 11_404_430_561_017_237_824_090_617
      TypesCase.refute_floats(vote)
    end

    test "raises FunctionClauseError on a tuple of the wrong size" do
      assert_raise FunctionClauseError, fn -> Vote.from_raw({}) end
    end
  end
end
