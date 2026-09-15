defmodule Onchain.Aerodrome.Integration.VoterCalldataTest do
  use ExUnit.Case, async: false

  alias Onchain.ABI
  alias Onchain.Aerodrome.Bindings.Abi
  alias Onchain.Aerodrome.CalldataFixture
  alias Onchain.Aerodrome.Contracts
  alias Onchain.Aerodrome.RPCCase
  alias Onchain.Hex

  @moduletag :integration
  @moduletag timeout: 180_000

  # Existing Sugar fixture block, outside Voter's epoch distribution window.
  @block "0x" <> Integer.to_string(51_348_944, 16)

  test "cast-exact reset of unowned id 2 reverts NotApprovedOrOwner on both endpoints" do
    assert {:ok, signature} = Abi.signature("voter.json", "reset")
    assert {:ok, return_type} = Abi.return_type("voter.json", "reset")
    assert {:ok, calldata} = ABI.encode_call(signature, [2])
    assert CalldataFixture.assert_calldata(calldata, signature, ["2"])
    expected_revert = CalldataFixture.reference!("NotApprovedOrOwner()", [])

    {primary, secondary} =
      RPCCase.run_on_both_endpoints(fn ->
        # Discover id 1's owner, then id 2's actual owner: changing only the
        # sender must turn the ownership revert into a simulated void return.
        assert {:error, {:rpc_error, %{data: revert}}} =
                 CalldataFixture.eth_call_as_sugar_owner(Contracts.address!(:voter), calldata, 1,
                   block: @block,
                   timeout: 30_000
                 )

        assert Hex.decode!(revert) == Hex.decode!(expected_revert)

        assert {:ok, "0x" = response} =
                 CalldataFixture.eth_call_as_sugar_owner(Contracts.address!(:voter), calldata, 2,
                   block: @block,
                   timeout: 30_000
                 )

        assert {:ok, []} = ABI.decode_response(return_type, response)
        revert
      end)

    assert primary == secondary
  end
end
