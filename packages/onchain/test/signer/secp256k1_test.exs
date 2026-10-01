defmodule Onchain.Signer.Secp256k1Test do
  use ExUnit.Case, async: true
  use Onchain.Hex

  alias Onchain.Signer.Secp256k1

  doctest Secp256k1

  @priv_key ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
  @address ~h[0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7]

  test "algorithm/1 reports secp256k1" do
    assert Secp256k1.algorithm(@priv_key) == :secp256k1
  end

  test "sign_digest/2 is a back-compat alias for sign_payload/2" do
    digest = Onchain.Hash.keccak("test")
    assert Secp256k1.sign_digest(digest, @priv_key) == Secp256k1.sign_payload(digest, @priv_key)
  end

  test "get_address/1 derives the Ethereum address from the public key" do
    assert {:ok, @address} = Secp256k1.get_address(@priv_key)
  end

  test "sign_payload/2 rejects a short and an over-long payload" do
    assert_raise FunctionClauseError, fn -> Secp256k1.sign_payload(<<0::248>>, @priv_key) end
    assert_raise FunctionClauseError, fn -> Secp256k1.sign_payload(<<0::264>>, @priv_key) end
  end
end

defmodule Onchain.Signer.Secp256k1VectorsTest do
  use ExUnit.Case, async: true

  alias Onchain.Signer.Secp256k1

  @order 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
  # Captured from unmodified Curvy 0.3.1 before removing the dependency:
  # Curvy.sign(digest, key, hash: :keccak, recovery: true); raw_s uses normalize: false.
  # Includes the doctest key and pinned ethers 6.17.0 transaction/EIP-712 vectors.
  @vectors "../fixtures/curvy-0.3.1.json" |> Path.expand(__DIR__) |> File.read!() |> Jason.decode!()

  test "RFC 6979 signatures match Curvy byte for byte, including recovery parity" do
    for vector <- @vectors do
      key = Base.decode16!(vector["private_key"], case: :lower)
      digest = Base.decode16!(vector["digest"], case: :lower)
      expected = Base.decode16!(vector["signature"], case: :lower)
      assert {:ok, sig} = Secp256k1.sign_payload(digest, key)
      assert <<sig.r::256, sig.s::256, sig.recid>> == expected
      assert Secp256k1.sign_payload(digest, key) == {:ok, sig}
      assert {:ok, address} = Secp256k1.get_address(key)
      assert Onchain.Recover.recover_eth_from_digest(digest, sig) == address
      assert Onchain.Recover.find_recid_from_digest(digest, sig, address) == {:ok, sig.recid}
    end
  end

  test "a deterministic nonce producing high s before canonicalization emits low s" do
    # k256's signing API already normalizes internally; its raw API never emits high s.
    vector = Enum.find(@vectors, &(String.to_integer(&1["raw_s"], 16) > div(@order, 2)))
    assert vector
    key = Base.decode16!(vector["private_key"], case: :lower)
    digest = Base.decode16!(vector["digest"], case: :lower)
    assert {:ok, signature} = Secp256k1.sign_payload(digest, key)
    assert signature.s == @order - String.to_integer(vector["raw_s"], 16)
    assert signature.s <= div(@order, 2)
  end

  test "invalid private scalars return errors through signing and key derivation" do
    for key <- [<<0::256>>, <<@order::256>>, <<1::248>>, <<1::264>>] do
      assert {:error, _} = Secp256k1.sign_payload(<<1::256>>, key)
      assert {:error, _} = Secp256k1.public_key(key)
      assert {:error, _} = Secp256k1.get_address(key)
    end
  end
end
