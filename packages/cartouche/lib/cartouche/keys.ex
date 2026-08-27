defmodule Cartouche.Keys do
  @moduledoc """
  Cartouche library to generate Ethereum key pairs.
  """

  use Descripex, namespace: "/ethereum/keys"

  api(:generate_keypair, "Generate a fresh Ethereum keypair.",
    returns: %{
      type: :ethereum_keypair,
      description: "`{address, private_key}` where address is a 20-byte Ethereum address and private_key is 32 bytes."
    }
  )

  @doc """
  Generates a new keypair as an `{eth_address, private_key}`.

  ## Examples

      iex> {address, priv_key} = Cartouche.Keys.generate_keypair()
      iex> {byte_size(address), byte_size(priv_key)}
      {20, 32}
  """
  @spec generate_keypair() :: {<<_::160>>, <<_::256>>}
  def generate_keypair do
    {<<4, pub_key::binary-size(64)>>, <<priv_key::binary-size(32)>>} =
      :crypto.generate_key(:ecdh, :secp256k1)

    <<_::96, address::binary-size(20)>> = Cartouche.Hash.keccak(pub_key)

    {address, priv_key}
  end
end
