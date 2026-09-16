defmodule Onchain.Aerodrome.Types.VeNFTTest do
  use ExUnit.Case, async: true

  alias Onchain.Address
  alias Onchain.Aerodrome.Types.VeNFT
  alias Onchain.Aerodrome.Types.Vote
  alias Onchain.Aerodrome.TypesCase

  @ve_fixtures ~w(ve_sugar.all ve_sugar.byAccount)

  describe "from_raw/1" do
    test "maps a positional byId fixture row one to one" do
      row = TypesCase.decode_tuple("ve_sugar.byId")
      venft = VeNFT.from_raw(row)

      assert %VeNFT{} = venft
      TypesCase.assert_one_to_one(VeNFT, {"ve_sugar.json", "byId", ["uint256"]}, row, venft, %{votes: Vote})
      TypesCase.refute_floats(venft)
    end

    test "checksums address fields and keeps amount fields as integers" do
      row = TypesCase.decode_tuple("ve_sugar.byId")
      venft = VeNFT.from_raw(row)

      assert venft.account == Address.checksum!(elem(row, 1))
      assert venft.token == Address.checksum!(elem(row, 10))
      assert is_integer(venft.amount)
      assert is_integer(venft.voting_amount)
      assert is_boolean(venft.permanent)
      refute is_float(venft.amount)
    end

    test "decodes nested votes as Types.Vote from the all fixture" do
      row = Enum.find(TypesCase.decode_rows("ve_sugar.all"), &(elem(&1, 9) != []))
      venft = VeNFT.from_raw(row)

      TypesCase.assert_one_to_one(VeNFT, {"ve_sugar.json", "byId", ["uint256"]}, row, venft, %{votes: Vote})
      assert [%Vote{} | _] = venft.votes
      assert hd(venft.votes).lp == Address.checksum!(elem(hd(elem(row, 9)), 0))
      assert hd(venft.votes).weight == elem(hd(elem(row, 9)), 1)
      TypesCase.refute_floats(venft)
    end

    test "decodes every committed VeSugar fixture row" do
      by_id = VeNFT.from_raw(TypesCase.decode_tuple("ve_sugar.byId"))
      assert %VeNFT{} = by_id
      TypesCase.refute_floats(by_id)

      for id <- @ve_fixtures, row <- TypesCase.decode_rows(id) do
        venft = VeNFT.from_raw(row)
        assert %VeNFT{} = venft
        TypesCase.refute_floats(venft)
      end
    end

    test "raises FunctionClauseError on a tuple of the wrong size" do
      assert_raise FunctionClauseError, fn -> VeNFT.from_raw({}) end
    end
  end
end
