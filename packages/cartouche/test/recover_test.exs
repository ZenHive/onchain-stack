defmodule Cartouche.RecoverTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Recover

  doctest Recover

  # secp256k1 group order.
  @secp256k1_n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

  @priv_key ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
  @address ~h[0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7]

  describe "normalize_low_s/1" do
    test "flips a high-s signature to its low-s counterpart and clears recid" do
      high_s = @secp256k1_n - 1
      sig = %Curvy.Signature{crv: :secp256k1, r: 123, s: high_s, recid: 1}

      normalized = Recover.normalize_low_s(sig)

      assert normalized.s == @secp256k1_n - high_s
      assert normalized.s == 1
      assert normalized.recid == nil
      assert normalized.r == 123
    end

    test "leaves an already-low-s signature unchanged" do
      sig = %Curvy.Signature{crv: :secp256k1, r: 7, s: 9, recid: 0}
      assert Recover.normalize_low_s(sig) == sig
    end

    test "is idempotent" do
      sig = %Curvy.Signature{crv: :secp256k1, r: 7, s: @secp256k1_n - 5, recid: 1}
      once = Recover.normalize_low_s(sig)
      assert Recover.normalize_low_s(once) == once
    end
  end

  describe "digest-native recovery" do
    setup do
      # Sign over a real keccak digest so the digest-native and message-based
      # paths can be cross-checked.
      digest = Cartouche.Hash.keccak("test")
      {:ok, sig} = Cartouche.Signer.Curvy.sign_payload(digest, @priv_key)
      {:ok, recid} = Recover.find_recid_from_digest(digest, sig, @address)
      %{digest: digest, sig: %{sig | recid: recid}, recid: recid}
    end

    test "find_recid_from_digest agrees with the message-based find_recid", %{
      digest: digest,
      sig: sig,
      recid: recid
    } do
      assert {:ok, ^recid} = Recover.find_recid_from_digest(digest, sig, @address)
      assert {:ok, ^recid} = Recover.find_recid("test", sig, @address)
    end

    test "recover_eth_from_digest recovers to the signer address", %{digest: digest, sig: sig} do
      assert Recover.recover_eth_from_digest(digest, sig) == @address
    end

    test "recover_public_key_from_digest matches the message-based recovery", %{
      digest: digest,
      sig: sig
    } do
      assert Recover.recover_public_key_from_digest(digest, sig) ==
               Recover.recover_public_key("test", sig)
    end

    test "find_recid_from_digest reports failure when no recid recovers to the address", %{
      digest: digest,
      sig: sig
    } do
      wrong_address = ~h[0x0000000000000000000000000000000000000001]
      assert {:error, _reason} = Recover.find_recid_from_digest(digest, sig, wrong_address)
    end

    test "works for an arbitrary (non-keccak-of-message) typed-data digest" do
      # Simulates EIP-712 / Hyperliquid: the caller hands a pre-computed digest
      # that is NOT keccak of any plain message, and recovery operates on it
      # directly with no re-hashing.
      typed_digest = :crypto.strong_rand_bytes(32)
      {:ok, sig} = Cartouche.Signer.Curvy.sign_payload(typed_digest, @priv_key)
      {:ok, recid} = Recover.find_recid_from_digest(typed_digest, sig, @address)

      assert Recover.recover_eth_from_digest(typed_digest, %{sig | recid: recid}) == @address
    end
  end

  describe "signature decoding" do
    test "recovers from a 0x-prefixed hex-string signature" do
      {:ok, sig} = Cartouche.Signer.Curvy.sign("test", @priv_key)
      {:ok, recid} = Recover.find_recid("test", sig, @address)

      hex_signature = Hex.encode_hex(<<sig.r::256, sig.s::256, recid>>)

      assert Recover.recover_eth("test", hex_signature) == @address
    end
  end
end

defmodule Cartouche.RecoverHighRecidTest do
  use ExUnit.Case, async: false
  use Cartouche.Hex

  alias Cartouche.Recover

  @priv_key ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
  @address ~h[0x63CC7C25E0CDB121ABB0FE477A6B9901889F99A7]
  @other_priv ~h[0x1111111111111111111111111111111111111111111111111111111111111111]

  # Curvy aliases recid 2/3 onto 0/1, so Enum.find/2 never returns >1 against a
  # real recover. The production clause still has to reject an overflow-only
  # match; stub recover_key so only recid 2/3 land on the expected address.
  test "find_recid_from_digest rejects a match that exists only at recid 2 or 3" do
    digest = <<1::256>>
    signature = %Curvy.Signature{crv: :secp256k1, r: 1, s: 1, recid: nil}

    :meck.new(Curvy, [:passthrough, :unstick, :no_link])

    :meck.expect(Curvy, :recover_key, fn %Curvy.Signature{recid: recid}, _message, _opts ->
      Curvy.Key.from_privkey(if(recid > 1, do: @priv_key, else: @other_priv))
    end)

    try do
      assert {:error, reason} = Recover.find_recid_from_digest(digest, signature, @address)
      assert reason =~ "too high recovery bit"
    after
      :meck.unload(Curvy)
    end
  end
end
