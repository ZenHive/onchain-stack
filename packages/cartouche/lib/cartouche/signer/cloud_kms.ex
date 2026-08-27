if Code.ensure_loaded?(Goth) do
  defmodule Cartouche.Signer.CloudKMS do
    @moduledoc """
    Signer backend that signs with a Google Cloud KMS secp256k1 key.

    Implements `Cartouche.Signer.Backend` — its `config` is the
    `{credentials, project, location, keychain, key, version}` key-coordinate
    tuple. `c:Cartouche.Signer.Backend.sign_payload/2` sends the 32-byte digest
    to KMS directly (no internal keccak) and returns the DER-parsed signature
    as KMS produced it. `sign/7` is a back-compat MFA wrapper: it keccaks a
    raw message first and canonicalizes low-s before returning, so plugging
    it into `Cartouche.Signer.sign_direct/4` cannot emit a high-s signature.
    """
    @behaviour Cartouche.Signer.Backend

    import Cartouche.Hash, only: [keccak: 1]

    alias Cartouche.CloudKMS

    @typedoc "Cloud KMS key coordinates: `{credentials, project, location, keychain, key, version}`."
    @type config :: {term(), String.t(), String.t(), String.t(), String.t(), String.t()}

    @impl true
    @spec algorithm(config()) :: :secp256k1
    def algorithm(_config), do: :secp256k1

    @doc """
    Get the uncompressed secp256k1 public key for the given KMS key version.
    """
    @impl true
    @spec public_key(config()) :: {:ok, binary()} | {:error, term()}
    def public_key({cred, project, location, keychain, key, version}) do
      name = CloudKMS.key_version_name(project, location, keychain, key, version)

      with {:ok, %{"algorithm" => algorithm, "pem" => pem}} <-
             CloudKMS.get_public_key(credential_token(cred), name, __MODULE__) do
        case algorithm do
          "EC_SIGN_SECP256K1_SHA256" ->
            [certs] = :public_key.pem_decode(pem)
            {{:ECPoint, public_key}, _} = :public_key.pem_entry_decode(certs)
            {:ok, public_key}

          _ ->
            {:error, "Invalid algorithm: #{algorithm}"}
        end
      end
    end

    @doc ~S"""
    Get the Ethereum address associated with the given KMS key version.

    ## Examples

        iex> {:ok, address} = Cartouche.Signer.CloudKMS.get_address("token", "project", "location", "keychain", "key", "version")
        iex> Cartouche.Hex.to_hex(address)
        "0xdda641b2a76a4a7c3617815bb13281dd207b74d5"
    """
    @spec get_address(term(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
            {:ok, binary()} | {:error, term()}
    def get_address(cred, project, location, keychain, key, version) do
      with {:ok, pub} <- public_key({cred, project, location, keychain, key, version}) do
        {:ok, Cartouche.Address.from_public_key(pub)}
      end
    end

    @doc """
    Signs the 32-byte digest it is handed directly via KMS — the pure-payload
    contract. Performs no hashing; the caller owns digest computation.
    """
    @impl true
    @spec sign_payload(<<_::256>>, config()) :: {:ok, Curvy.Signature.t()} | {:error, term()}
    def sign_payload(<<digest::binary-size(32)>>, {cred, project, location, keychain, key, version}) do
      name = CloudKMS.key_version_name(project, location, keychain, key, version)

      with {:ok, %{"signature" => signature}} <-
             CloudKMS.asymmetric_sign(
               credential_token(cred),
               name,
               %{digest: %{sha256: Base.encode64(digest)}},
               __MODULE__
             ),
           {:ok, decoded_sig} <- Base.decode64(signature) do
        parse_kms_signature(decoded_sig)
      end
    end

    @doc ~S"""
    Signs a raw message via KMS, keccak-digesting it first.

    Back-compat convenience over `sign_payload/2`. Canonicalizes the
    returned signature to low-s (EIP-2) so this MFA-shaped wrapper is not
    an unnormalized signing entry point; `sign_payload/2` stays raw per
    the backend contract.

    ## Examples

        iex> use Cartouche.Hex
        iex> {:ok, sig} = Cartouche.Signer.CloudKMS.sign("test", "token", "project", "location", "keychain", "key", "version")
        iex> {:ok, recid} = Cartouche.Recover.find_recid("test", sig, ~h[0xDDA641B2A76A4A7C3617815BB13281DD207B74D5])
        iex> Cartouche.Recover.recover_eth("test", %{sig|recid: recid}) |> Hex.to_address()
        "0xDDa641B2A76a4A7c3617815bb13281DD207b74d5"
    """
    @spec sign(String.t(), term(), String.t(), String.t(), String.t(), String.t(), String.t()) ::
            {:ok, Curvy.Signature.t()} | {:error, term()}
    def sign(message, cred, project, location, keychain, key, version) when is_binary(message) do
      with {:ok, signature} <-
             sign_payload(keccak(message), {cred, project, location, keychain, key, version}) do
        {:ok, Cartouche.Recover.normalize_low_s(signature)}
      end
    end

    @spec parse_kms_signature(binary()) :: {:ok, Curvy.Signature.t()} | {:error, :invalid_signature}
    defp parse_kms_signature(decoded_sig) do
      case Curvy.Signature.parse(decoded_sig) do
        %Curvy.Signature{} = parsed -> {:ok, parsed}
        _ -> {:error, :invalid_signature}
      end
    end

    @spec credential_token(term()) :: String.t()
    defp credential_token(token) when is_binary(token), do: token

    defp credential_token(cred) do
      %{token: token, type: "Bearer"} = Goth.fetch!(cred)
      token
    end
  end
end
