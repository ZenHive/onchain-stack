defmodule Cartouche.Address do
  @moduledoc """
  Helpers for Ethereum addresses.
  """

  use Descripex, namespace: "/ethereum/address"

  api(:from_public_key, "Derive an Ethereum address from an uncompressed secp256k1 public key in SEC1 form.",
    params: [
      public_key: [
        kind: :value,
        description: "Uncompressed secp256k1 public key bytes in SEC1 form, beginning with the `0x04` prefix byte."
      ]
    ],
    returns: %{
      type: :ethereum_address_binary,
      description: "20-byte Ethereum address derived from the Keccak-256 hash of the raw public key coordinates."
    }
  )

  @doc ~S"""
  Returns an Ethereum address from a given uncompressed secp256k1 public key in SEC1 form (`0x04 || X || Y`).

  ## Examples

      iex> use Cartouche.Hex
      iex> public_key = ~h[0x0422]
      iex> Cartouche.Address.from_public_key(public_key)
      ...> |> Cartouche.Hex.encode_hex()
      "0x759f1afdc24aba433a3e18b683f8c04a6eaa69f0"
  """
  @spec from_public_key(binary()) :: <<_::160>>
  def from_public_key(public_key) do
    <<4, public_key_raw::binary>> = public_key
    <<_::bitstring-size(96), address::bitstring-size(160)>> = Cartouche.Hash.keccak(public_key_raw)

    address
  end
end
