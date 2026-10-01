defmodule Onchain.Tempo.Codec do
  @moduledoc false

  alias Onchain.Signer.Secp256k1
  alias Onchain.Tempo.Native

  @doc false
  @spec run(String.t(), map()) :: {:ok, term()} | {:error, String.t()}
  def run(operation, request) do
    with {:ok, json} <- Jason.encode(Map.put(request, "operation", operation)),
         {:ok, result} <- Native.transaction_json(json) do
      Jason.decode(result)
    end
  end

  @doc false
  @spec hex(binary()) :: String.t()
  def hex(bytes), do: "0x" <> Base.encode16(bytes, case: :lower)

  @doc false
  @spec bytes(String.t()) :: binary()
  def bytes("0x" <> hex), do: Base.decode16!(hex, case: :mixed)

  @doc false
  @spec quantity(non_neg_integer()) :: String.t()
  def quantity(n), do: "0x" <> Integer.to_string(n, 16)

  @doc false
  @spec integer(String.t()) :: non_neg_integer()
  def integer("0x" <> hex), do: String.to_integer(hex, 16)

  @doc false
  @spec signature(Onchain.Signature.t()) :: String.t()
  def signature(sig), do: hex(<<sig.r::256, sig.s::256, sig.recid + 27>>)

  @doc false
  @spec sign(map(), binary(), boolean()) :: {:ok, String.t()} | {:error, term()}
  def sign(transaction, private_key, placeholder) do
    with {:ok, %{"hash" => hash}} <- run("prepare", %{"transaction" => transaction}),
         {:ok, sig} <- Secp256k1.sign_payload(bytes(hash), private_key) do
      run("serialize", %{"transaction" => transaction, "signature" => signature(sig), "placeholder" => placeholder})
    end
  end
end
