defmodule Cartouche.SignerTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Signer
  alias Cartouche.Signer.Curvy
  alias Cartouche.SignerTest.FixedSignature
  alias Cartouche.SignerTest.HighSBackend

  doctest Signer

  @priv_key ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
  @address ~h[0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7]
  @secp256k1_n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
  @secp256k1_half_n div(@secp256k1_n, 2)

  describe "address/0 and chain_id/0 default name" do
    # The application supervises a signer under the default
    # `Cartouche.Signer.Default` name (config :cartouche, :signer), so the
    # arg-less `address/0` and `chain_id/0` clauses resolve against it.
    test "address/0 returns a 20-byte address using the default name" do
      assert <<_::160>> = Signer.address()
    end

    test "chain_id/0 returns the configured chain id using the default name" do
      # config/test.exs sets :chain_id to :goerli (5).
      assert Signer.chain_id() == 5
    end
  end

  describe "sign_direct/4" do
    test "produces a 65-byte EIP-155 signature recoverable to the address" do
      mfa = {Curvy, :sign, [@priv_key]}

      assert {:ok, <<_r::256, _s::256, _v::binary>> = sig} =
               Signer.sign_direct("test", @address, mfa, 0)

      assert byte_size(sig) == 65
      assert Cartouche.Recover.recover_eth("test", sig) == @address
    end

    test "canonicalizes a high-s MFA signature so the packed s is at most n/2" do
      high_sig = high_s_signature("test")
      assert high_sig.s > @secp256k1_half_n

      mfa = {FixedSignature, :sign, [high_sig]}

      assert {:ok, <<_r::256, s::256, _v::binary>> = packed} =
               Signer.sign_direct("test", @address, mfa, 0)

      assert s <= @secp256k1_half_n
      assert Cartouche.Recover.recover_eth("test", packed) == @address
    end
  end

  describe "{backend, config} carrier (pure-payload path)" do
    setup do
      {:ok, pid} = Signer.start_link(mfa: {Curvy, @priv_key}, name: nil)
      %{signer: pid}
    end

    test "address/1 resolves the address from the backend public key", %{signer: signer} do
      assert Signer.address(signer) == @address
    end

    test "address/1 returns the cached address on a subsequent call", %{signer: signer} do
      assert Signer.address(signer) == @address
      assert Signer.address(signer) == @address
    end

    test "sign/2 produces a signature recoverable to the address", %{signer: signer} do
      assert {:ok, sig} = Signer.sign("test", signer)
      assert byte_size(sig) == 65
      assert Cartouche.Recover.recover_eth("test", sig) == @address
    end

    test "sign/2 uses the cached address on a subsequent call", %{signer: signer} do
      assert {:ok, sig1} = Signer.sign("test", signer)
      assert {:ok, sig2} = Signer.sign("test", signer)
      assert sig1 == sig2
      assert Cartouche.Recover.recover_eth("test", sig2) == @address
    end

    test "canonicalizes a high-s backend signature so the packed s is at most n/2" do
      high_sig = high_s_signature("test")
      assert high_sig.s > @secp256k1_half_n

      {:ok, pid} =
        Signer.start_link(mfa: {HighSBackend, {@priv_key, high_sig}}, name: nil)

      assert {:ok, <<_r::256, s::256, _v::binary>> = packed} = Signer.sign("test", pid)
      assert s <= @secp256k1_half_n
      assert Cartouche.Recover.recover_eth("test", packed) == @address
    end
  end

  describe "legacy MFA carrier" do
    test "start_link/1 still signs through a {module, function, args} triple" do
      {:ok, pid} = Signer.start_link(mfa: {Curvy, :sign, [@priv_key]}, name: nil)

      assert Signer.address(pid) == @address
      assert {:ok, sig} = Signer.sign("test", pid)
      assert Cartouche.Recover.recover_eth("test", sig) == @address
    end

    test "canonicalizes a high-s MFA signature started through start_link/1" do
      high_sig = high_s_signature("test")
      {:ok, pid} = Signer.start_link(mfa: {FixedSignature, :sign, [high_sig]}, name: nil)

      assert {:ok, <<_r::256, s::256, _v::binary>>} = Signer.sign("test", pid)
      assert s <= @secp256k1_half_n
    end
  end

  describe "algorithm mismatch" do
    @seed Base.decode16!("9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60")

    test "rejects an ed25519 backend under the Eth signer" do
      {:ok, pid} = Signer.start_link(mfa: {Cartouche.Solana.Signer.Ed25519, @seed}, name: nil)

      assert {:error, {:algorithm_mismatch, :secp256k1, :ed25519}} = Signer.sign("test", pid)
    end
  end

  @spec high_s_signature(binary()) :: Curvy.Signature.t()
  defp high_s_signature(message) do
    {:ok, sig} = Curvy.sign(message, @priv_key)
    %{sig | s: @secp256k1_n - sig.s, recid: nil}
  end
end
