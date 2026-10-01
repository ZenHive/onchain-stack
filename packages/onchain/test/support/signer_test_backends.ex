defmodule Onchain.SignerTest.FixedSignature do
  @moduledoc false

  @doc false
  @spec sign(binary(), Onchain.Signature.t()) :: {:ok, Onchain.Signature.t()}
  def sign(_message, %Onchain.Signature{} = signature), do: {:ok, signature}

  @doc false
  @spec get_address(Onchain.Signature.t()) :: {:ok, binary()}
  def get_address(_signature) do
    {:ok, Base.decode16!("63CC7C25E0CDB121ABB0FE477A6B9901889F99A7", case: :mixed)}
  end
end

defmodule Onchain.SignerTest.HighSBackend do
  @moduledoc false
  @behaviour Onchain.Signer.Backend

  @impl true
  @spec algorithm({binary(), Onchain.Signature.t()}) :: :secp256k1
  def algorithm(_config), do: :secp256k1

  @impl true
  @spec public_key({binary(), Onchain.Signature.t()}) :: {:ok, binary()} | {:error, String.t()}
  def public_key({priv, _signature}), do: Onchain.Signer.Secp256k1.public_key(priv)

  @impl true
  @spec sign_payload(<<_::256>>, {binary(), Onchain.Signature.t()}) :: {:ok, Onchain.Signature.t()}
  def sign_payload(_digest, {_priv, signature}), do: {:ok, signature}
end

defmodule Onchain.Test.HighSSignerBackend do
  @moduledoc false
  @behaviour Onchain.Signer.Backend

  alias Onchain.Signer.Secp256k1

  @secp256k1_n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

  @impl true
  @spec algorithm(binary()) :: :secp256k1
  def algorithm(_private_key), do: :secp256k1

  @impl true
  @spec public_key(binary()) :: {:ok, binary()} | {:error, String.t()}
  def public_key(private_key), do: Secp256k1.public_key(private_key)

  @impl true
  @spec sign_payload(<<_::256>>, binary()) :: {:ok, Onchain.Signature.t()} | {:error, String.t()}
  def sign_payload(digest, private_key) do
    with {:ok, signature} <- Secp256k1.sign_payload(digest, private_key) do
      {:ok, %{signature | s: @secp256k1_n - signature.s, recid: nil}}
    end
  end
end

defmodule Onchain.SignerTest.Ed25519Backend do
  @moduledoc false
  @behaviour Onchain.Signer.Backend

  @impl true
  @spec algorithm(pid()) :: :ed25519
  def algorithm(_owner), do: :ed25519

  @impl true
  @spec public_key(pid()) :: {:ok, binary()}
  def public_key(_owner), do: {:ok, <<0::256>>}

  @impl true
  @spec sign_payload(binary(), pid()) :: {:ok, <<_::512>>}
  def sign_payload(payload, owner) do
    send(owner, {:sign_payload, payload})
    {:ok, <<0::512>>}
  end
end
