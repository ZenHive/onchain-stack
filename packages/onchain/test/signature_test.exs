defmodule Onchain.SignatureTest do
  use ExUnit.Case, async: true

  alias Onchain.Signature
  alias Onchain.Signer.Secp256k1

  test "DER input without recovery parity round-trips through find_recid and recover_eth" do
    key = <<1::256>>
    assert {:ok, sig} = Secp256k1.sign("KMS recovery", key)
    der = :public_key.der_encode(:"ECDSA-Sig-Value", {:"ECDSA-Sig-Value", sig.r, sig.s})
    assert {:ok, parsed} = Signature.from_der(der)
    assert parsed.recid == nil
    assert {:ok, address} = Secp256k1.get_address(key)
    assert {:ok, recid} = Onchain.Recover.find_recid("KMS recovery", parsed, address)
    assert Onchain.Recover.recover_eth("KMS recovery", %{parsed | recid: recid}) == address
  end

  test "malformed or noncanonical DER and out-of-range scalars are rejected" do
    for der <- [
          <<>>,
          <<48, 0>>,
          <<48, 6, 2, 1, 0, 2, 1, 1>>,
          <<48, 6, 2, 1, 128, 2, 1, 1>>,
          <<48, 7, 2, 2, 0, 1, 2, 1, 1>>,
          <<48, 6, 2, 1, 1, 2, 1, 1, 0>>,
          <<48, 4, 2, 0, 2, 0>>
        ] do
      assert Signature.from_der(der) == {:error, :invalid_signature}
    end
  end
end
