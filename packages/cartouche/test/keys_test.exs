defmodule Cartouche.KeysTest do
  use ExUnit.Case, async: true

  doctest Cartouche.Keys

  test "generate keypair" do
    {address, priv_key} = Cartouche.Keys.generate_keypair()
    {:ok, sig} = Cartouche.Signer.Curvy.sign("test", priv_key)
    {:ok, recid} = Cartouche.Recover.find_recid("test", sig, address)
    assert Cartouche.Recover.recover_eth("test", %{sig | recid: recid}) == address
  end
end
