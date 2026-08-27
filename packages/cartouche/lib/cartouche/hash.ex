defmodule Cartouche.Hash do
  @moduledoc """
  Keccak-256 helpers for hashing arbitrary binaries.

  Returns either the 32-byte binary digest (`keccak/1`) or its unsigned
  integer interpretation (`keccak_unsigned/1`).
  """

  use Descripex, namespace: "/ethereum/hash"

  api(:keccak, "Hash a binary message with Keccak-256.",
    params: [
      message: [kind: :value, description: "Raw binary message to hash."]
    ],
    returns: %{
      type: :bytes32,
      description: "32-byte Keccak-256 digest of the input message."
    }
  )

  @doc ~S"""
  Returns the keccak of the given binary message.

  ## Examples

    iex> use Cartouche.Hex
    iex> Cartouche.Hash.keccak("test")
    ~h[0x9C22FF5F21F0B81B113E63F7DB6DA94FEDEF11B2119B4088B89664FB9A3CB658]
  """
  @spec keccak(binary()) :: <<_::256>>
  def keccak(message), do: ExSha3.keccak_256(message)

  api(:keccak_unsigned, "Hash a binary message with Keccak-256 and decode the digest as an unsigned integer.",
    params: [
      message: [kind: :value, description: "Raw binary message to hash."]
    ],
    returns: %{
      type: :non_neg_integer,
      description: "Unsigned big-endian integer represented by the 32-byte Keccak-256 digest."
    },
    composes_with: [:keccak]
  )

  @doc ~S"""
  Returns the keccak of the given binary message, as an unsigned.

  ## Examples

    iex> Cartouche.Hash.keccak_unsigned("test")
    70622639689279718371527342103894932928233838121221666359043189029713682937432
  """
  @spec keccak_unsigned(binary()) :: non_neg_integer()
  def keccak_unsigned(message) do
    message
    |> keccak()
    |> :binary.decode_unsigned()
  end
end
