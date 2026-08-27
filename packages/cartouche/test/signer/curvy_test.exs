defmodule Cartouche.Signer.CurvyTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Signer.Curvy

  doctest Curvy

  @priv_key ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
  @address ~h[0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7]

  test "algorithm/1 reports secp256k1" do
    assert Curvy.algorithm(@priv_key) == :secp256k1
  end

  test "sign_digest/2 is a back-compat alias for sign_payload/2" do
    digest = Cartouche.Hash.keccak("test")
    assert Curvy.sign_digest(digest, @priv_key) == Curvy.sign_payload(digest, @priv_key)
  end

  test "get_address/1 derives the Ethereum address from the public key" do
    assert {:ok, @address} = Curvy.get_address(@priv_key)
  end

  test "sign_payload/2 rejects a short and an over-long payload" do
    assert_raise FunctionClauseError, fn -> Curvy.sign_payload(<<0::248>>, @priv_key) end
    assert_raise FunctionClauseError, fn -> Curvy.sign_payload(<<0::264>>, @priv_key) end
  end
end
