defmodule Onchain.KeysTest do
  use ExUnit.Case, async: true

  doctest Onchain.Keys

  test "generate keypair" do
    {address, priv_key} = Onchain.Keys.generate_keypair()
    {:ok, sig} = Onchain.Signer.Secp256k1.sign("test", priv_key)
    {:ok, recid} = Onchain.Recover.find_recid("test", sig, address)
    assert Onchain.Recover.recover_eth("test", %{sig | recid: recid}) == address
  end
end
