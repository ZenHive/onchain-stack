defmodule Onchain.Signer.Secp256k1 do
  @moduledoc """
  Signer backend that signs with a local secp256k1 private key.

  Implements `Onchain.Signer.Backend` — its `config` is the raw private-key
  binary. The behaviour's `c:Onchain.Signer.Backend.sign_payload/2` signs the
  32-byte digest it is handed directly; `sign/2` is a convenience wrapper that
  keccaks a raw message first.

  Uses the precompiled RustCrypto k256 backend. Private keys remain in BEAM memory;
  use `Onchain.Signer.CloudKMS` when keys must stay in an HSM.
  """
  @behaviour Onchain.Signer.Backend

  import Onchain.Hash, only: [keccak: 1]

  @impl true
  @spec algorithm(binary()) :: :secp256k1
  def algorithm(_private_key), do: :secp256k1

  @doc ~S"""
  Get the uncompressed secp256k1 public key for the given private key.

  ## Examples

      iex> priv_key = "800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf" |> Base.decode16!(case: :mixed)
      iex> {:ok, pub} = Onchain.Signer.Secp256k1.public_key(priv_key)
      iex> Onchain.Hex.to_address(Onchain.Address.from_public_key(pub))
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  @impl true
  @spec public_key(binary()) :: {:ok, binary()} | {:error, atom()}
  def public_key(private_key) do
    # ExSecp256k1 0.8 returns {:error, atom} at runtime but specs a bare atom;
    # accept both so callers and Dialyzer see the tagged contract.
    case ExSecp256k1.create_public_key(private_key) do
      {:ok, public_key} -> {:ok, public_key}
      {:error, reason} -> {:error, reason}
      reason when is_atom(reason) -> {:error, reason}
    end
  end

  @doc ~S"""
  Get the Ethereum address associated with the given private key.

  ## Examples

      iex> priv_key = "800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf" |> Base.decode16!(case: :mixed)
      iex> {:ok, address} = Onchain.Signer.Secp256k1.get_address(priv_key)
      iex> Onchain.Hex.to_address(address)
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  @spec get_address(binary()) :: {:ok, binary()} | {:error, atom()}
  def get_address(private_key) do
    with {:ok, pub} <- public_key(private_key) do
      {:ok, Onchain.Address.from_public_key(pub)}
    end
  end

  @doc ~S"""
  Signs the 32-byte digest it is handed directly — the pure-payload contract.

  This performs no hashing: the caller (`Onchain.Signer`) owns digest
  computation, so the same backend serves plain Eth tx, EIP-712, and Hyperliquid.

  ## Examples

      iex> use Onchain.Hex
      iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
      iex> message_hash = ~h[0x9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658]
      iex> {:ok, sig} = Onchain.Signer.Secp256k1.sign_payload(message_hash, priv_key)
      iex> {:ok, recid} = Onchain.Recover.find_recid("test", sig, ~h[0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7])
      iex> Onchain.Recover.recover_eth("test", %{sig|recid: recid}) |> Onchain.Hex.to_address()
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  @impl true
  @spec sign_payload(<<_::256>>, binary()) :: {:ok, Onchain.Signature.t()} | {:error, atom()}
  def sign_payload(<<digest::binary-size(32)>>, private_key) do
    with {:ok, {r, s, recid}} <- ExSecp256k1.sign(digest, private_key) do
      {:ok, %Onchain.Signature{r: :binary.decode_unsigned(r), s: :binary.decode_unsigned(s), recid: recid}}
    end
  end

  @doc ~S"""
  Signs a raw message, keccak-digesting it first.

  Back-compat convenience over `sign_payload/2` for EIP-191-style raw-message
  signing; for typed data (EIP-712, Hyperliquid) the caller should compute the
  digest and call `sign_payload/2` directly.

  ## Examples

      iex> use Onchain.Hex
      iex> priv_key = ~h[0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf]
      iex> {:ok, sig} = Onchain.Signer.Secp256k1.sign("test", priv_key)
      iex> {:ok, recid} = Onchain.Recover.find_recid("test", sig, ~h[0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7])
      iex> Onchain.Recover.recover_eth("test", %{sig|recid: recid}) |> Onchain.Hex.to_address()
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  @spec sign(String.t(), binary()) :: {:ok, Onchain.Signature.t()} | {:error, atom()}
  def sign(message, private_key) when is_binary(message) do
    sign_payload(keccak(message), private_key)
  end

  @doc ~S"""
  Deprecated alias for `sign_payload/2`; signs an already-digested message.
  """
  @spec sign_digest(String.t(), binary()) :: {:ok, Onchain.Signature.t()} | {:error, atom()}
  def sign_digest(message_hash, private_key) when is_binary(message_hash) do
    sign_payload(message_hash, private_key)
  end
end
