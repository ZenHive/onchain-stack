defmodule Cartouche.SignerTest.FixedSignature do
  @moduledoc false

  @doc false
  @spec sign(binary(), Cartouche.Signature.t()) :: {:ok, Cartouche.Signature.t()}
  def sign(_message, %Cartouche.Signature{} = signature), do: {:ok, signature}

  @doc false
  @spec get_address(Cartouche.Signature.t()) :: {:ok, binary()}
  def get_address(_signature) do
    {:ok, Base.decode16!("63CC7C25E0CDB121ABB0FE477A6B9901889F99A7", case: :mixed)}
  end
end

defmodule Cartouche.SignerTest.HighSBackend do
  @moduledoc false
  @behaviour Cartouche.Signer.Backend

  @impl true
  @spec algorithm({binary(), Cartouche.Signature.t()}) :: :secp256k1
  def algorithm(_config), do: :secp256k1

  @impl true
  @spec public_key({binary(), Cartouche.Signature.t()}) :: {:ok, binary()} | {:error, String.t()}
  def public_key({priv, _signature}), do: Cartouche.Signer.Secp256k1.public_key(priv)

  @impl true
  @spec sign_payload(<<_::256>>, {binary(), Cartouche.Signature.t()}) :: {:ok, Cartouche.Signature.t()}
  def sign_payload(_digest, {_priv, signature}), do: {:ok, signature}
end

defmodule Cartouche.Test.HighSSignerBackend do
  @moduledoc false
  @behaviour Cartouche.Signer.Backend

  alias Cartouche.Signer.Secp256k1

  @secp256k1_n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

  @impl true
  @spec algorithm(binary()) :: :secp256k1
  def algorithm(_private_key), do: :secp256k1

  @impl true
  @spec public_key(binary()) :: {:ok, binary()} | {:error, String.t()}
  def public_key(private_key), do: Secp256k1.public_key(private_key)

  @impl true
  @spec sign_payload(<<_::256>>, binary()) :: {:ok, Cartouche.Signature.t()} | {:error, String.t()}
  def sign_payload(digest, private_key) do
    with {:ok, signature} <- Secp256k1.sign_payload(digest, private_key) do
      {:ok, %{signature | s: @secp256k1_n - signature.s, recid: nil}}
    end
  end
end
