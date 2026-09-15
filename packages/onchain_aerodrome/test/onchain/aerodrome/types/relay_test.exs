defmodule Onchain.Aerodrome.Types.RelayTest do
  use ExUnit.Case, async: true

  alias Onchain.Address
  alias Onchain.Aerodrome.Types.Relay
  alias Onchain.Aerodrome.Types.Relay.AccountVeNFT
  alias Onchain.Aerodrome.Types.Vote
  alias Onchain.Aerodrome.TypesCase

  describe "from_raw/1" do
    test "maps a positional all(address) fixture row one to one" do
      row = first_row()
      relay = Relay.from_raw(row)

      assert %Relay{} = relay

      TypesCase.assert_one_to_one(Relay, {"relay_sugar.json", "all"}, row, relay, %{
        votes: Vote,
        account_venfts: AccountVeNFT
      })

      TypesCase.refute_floats(relay)
    end

    test "decodes votes as Types.Vote and checksums managers" do
      row = Enum.find(TypesCase.decode_rows("relay_sugar.all"), &(elem(&1, 6) != []))
      relay = Relay.from_raw(row)

      assert [%Vote{} | _] = relay.votes
      assert hd(relay.votes).lp == Address.checksum!(elem(hd(elem(row, 6)), 0))
      assert hd(relay.votes).weight == elem(hd(elem(row, 6)), 1)
      assert relay.managers == Enum.map(elem(row, 11), &Address.checksum!/1)
      assert is_binary(relay.name)
      assert is_boolean(relay.compounder)
      assert is_integer(relay.amount)
    end

    test "decodes account_venfts as AccountVeNFT from a fixture row that has them" do
      row = Enum.find(TypesCase.decode_rows("relay_sugar.all"), &(elem(&1, 16) != []))
      relay = Relay.from_raw(row)

      assert [%AccountVeNFT{} | _] = relay.account_venfts
      {id, amount, earned} = hd(elem(row, 16))
      assert hd(relay.account_venfts).id == id
      assert hd(relay.account_venfts).amount == amount
      assert hd(relay.account_venfts).earned == earned

      TypesCase.assert_one_to_one(Relay, {"relay_sugar.json", "all"}, row, relay, %{
        votes: Vote,
        account_venfts: AccountVeNFT
      })

      TypesCase.refute_floats(relay)
    end

    test "decodes every committed relay_sugar.all fixture row" do
      for row <- TypesCase.decode_rows("relay_sugar.all") do
        relay = Relay.from_raw(row)
        assert %Relay{} = relay
        TypesCase.refute_floats(relay)
      end
    end

    test "raises FunctionClauseError on a tuple of the wrong size" do
      assert_raise FunctionClauseError, fn -> Relay.from_raw({}) end
      assert_raise FunctionClauseError, fn -> AccountVeNFT.from_raw({}) end
    end
  end

  defp first_row, do: "relay_sugar.all" |> TypesCase.decode_rows() |> hd()
end
