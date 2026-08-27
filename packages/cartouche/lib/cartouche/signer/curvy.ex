defmodule Cartouche.Signer.Curvy do
  @moduledoc """
  Signer backend that signs with a local secp256k1 private key.

  Implements `Cartouche.Signer.Backend` — its `config` is the raw private-key
  binary. The behaviour's `c:Cartouche.Signer.Backend.sign_payload/2` signs the
  32-byte digest it is handed directly; `sign/2` is a convenience wrapper that
  keccaks a raw message first.

  Note: this should not be used in production systems. Please see `Cartouche.Signer.CloudKMS`.
  """
  @behaviour Cartouche.Signer.Backend

  import Cartouche.Hash, only: [keccak: 1]

  @impl true
  @spec algorithm(binary()) :: :secp256k1
  def algorithm(_private_key), do: :secp256k1

  @doc ~S"""
  Get the uncompressed secp256k1 public key for the given private key.

  ## Examples

      iex> priv_key = "800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf" |> Base.decode16!(case: :mixed)
      iex> {:ok, pub} = Cartouche.Signer.Curvy.public_key(priv_key)
      iex> Cartouche.Hex.to_address(Cartouche.Address.from_public_key(pub))
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  @impl true
  @spec public_key(binary()) :: {:ok, binary()} | {:error, String.t()}
  def public_key(private_key) do
    private_key
    |> Curvy.Key.from_privkey()
    |> Curvy.Key.to_pubkey(compressed: false)
    |> ok!()
  end

  @doc ~S"""
  Get the Ethereum address associated with the given private key.

  ## Examples

      iex> priv_key = "800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf" |> Base.decode16!(case: :mixed)
      iex> {:ok, address} = Cartouche.Signer.Curvy.get_address(priv_key)
      iex> Cartouche.Hex.to_address(address)
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  @spec get_address(binary()) :: {:ok, binary()} | {:error, String.t()}
  def get_address(private_key) do
    with {:ok, pub} <- public_key(private_key) do
      {:ok, Cartouche.Address.from_public_key(pub)}
    end
  end

  @doc ~S"""
  Signs the 32-byte digest it is handed directly — the pure-payload contract.

  This performs no hashing: the caller (`Cartouche.Signer`) owns digest
  computation, so the same backend serves plain Eth tx, EIP-712, and Hyperliquid.

  ## Examples

      iex> use Cartouche.Hex
      iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
      iex> message_hash = ~h[0x9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658]
      iex> {:ok, sig} = Cartouche.Signer.Curvy.sign_payload(message_hash, priv_key)
      iex> {:ok, recid} = Cartouche.Recover.find_recid("test", sig, ~h[0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7])
      iex> Cartouche.Recover.recover_eth("test", %{sig|recid: recid}) |> Cartouche.Hex.to_address()
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  @impl true
  @spec sign_payload(<<_::256>>, binary()) :: {:ok, Curvy.Signature.t()} | {:error, String.t()}
  def sign_payload(<<digest::binary-size(32)>>, private_key) do
    priv_key = Curvy.Key.from_privkey(private_key)

    digest
    |> Curvy.sign(priv_key, hash: :keccak)
    |> Curvy.Signature.parse()
    |> ok!()
  end

  @doc ~S"""
  Signs a raw message, keccak-digesting it first.

  Back-compat convenience over `sign_payload/2` for EIP-191-style raw-message
  signing; for typed data (EIP-712, Hyperliquid) the caller should compute the
  digest and call `sign_payload/2` directly.

  ## Examples

      iex> use Cartouche.Hex
      iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
      iex> {:ok, sig} = Cartouche.Signer.Curvy.sign("test", priv_key)
      iex> {:ok, recid} = Cartouche.Recover.find_recid("test", sig, ~h[0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7])
      iex> Cartouche.Recover.recover_eth("test", %{sig|recid: recid}) |> Cartouche.Hex.to_address()
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  @spec sign(String.t(), binary()) :: {:ok, Curvy.Signature.t()} | {:error, String.t()}
  def sign(message, private_key) when is_binary(message) do
    sign_payload(keccak(message), private_key)
  end

  @doc ~S"""
  Deprecated alias for `sign_payload/2`; signs an already-digested message.
  """
  @spec sign_digest(String.t(), binary()) :: {:ok, Curvy.Signature.t()} | {:error, String.t()}
  def sign_digest(message_hash, private_key) when is_binary(message_hash) do
    sign_payload(message_hash, private_key)
  end

  @spec ok!(term()) :: {:ok, term()}
  defp ok!(v), do: {:ok, v}
end
