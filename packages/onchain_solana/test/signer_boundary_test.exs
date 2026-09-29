defmodule Onchain.Solana.SignerBoundaryTest do
  use ExUnit.Case, async: true

  alias Cartouche.Signer

  describe "algorithm mismatch" do
    @seed Base.decode16!("9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60")

    test "rejects an ed25519 backend under the Eth signer" do
      {:ok, pid} = Signer.start_link(mfa: {Onchain.Solana.Signer.Ed25519, @seed}, name: nil)

      assert {:error, {:algorithm_mismatch, :secp256k1, :ed25519}} = Signer.sign("test", pid)
    end
  end
end
