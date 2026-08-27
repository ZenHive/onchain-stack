defmodule Cartouche.CloudKMS do
  @moduledoc """
  Shared helpers for the Google Cloud KMS signer backends
  (`Cartouche.Signer.CloudKMS` and `Cartouche.Solana.Signer.CloudKMS`).

  The HTTP transport (`get_public_key/3`, `asymmetric_sign/4`) is identical for
  both the secp256k1 (Ethereum) and Ed25519 (Solana) signers — only the request
  body and the public-key parsing differ, and those stay in the signer modules.
  Goth credential resolution stays in the signers too, since `Goth` is an
  optional dependency and this module is always loaded.

  `config_key` is the signer module (passed as `__MODULE__`); it selects that
  signer's `Application.get_env(:cartouche, config_key)` block, so per-signer
  `:req_options` continue to resolve under their existing keys.
  """

  @kms_base_url "https://cloudkms.googleapis.com/v1"

  @doc """
  Builds the fully-qualified Cloud KMS crypto-key-version resource name from its
  component parts, e.g.
  `projects/p/locations/l/keyRings/kc/cryptoKeys/k/cryptoKeyVersions/v`.
  """
  @spec key_version_name(String.t(), String.t(), String.t(), String.t(), String.t() | non_neg_integer()) ::
          String.t()
  def key_version_name(project, location, keychain, key, version) do
    "projects/#{project}/locations/#{location}/keyRings/#{keychain}" <>
      "/cryptoKeys/#{key}/cryptoKeyVersions/#{version}"
  end

  @doc """
  Fetches the PEM-encoded public key for a KMS key version. Returns the raw KMS
  JSON map (`%{"algorithm" => _, "pem" => _}`); the caller parses the PEM for its
  curve.
  """
  @spec get_public_key(String.t(), String.t(), module()) :: {:ok, map()} | {:error, term()}
  def get_public_key(token, name, config_key), do: request(token, :get, config_key, "#{name}/publicKey")

  @doc """
  Calls `asymmetricSign` on a KMS key version. `body` is the signer-specific
  request payload (`%{digest: ...}` for secp256k1, `%{data: ...}` for Ed25519).
  """
  @spec asymmetric_sign(String.t(), String.t(), map(), module()) :: {:ok, map()} | {:error, term()}
  def asymmetric_sign(token, name, body, config_key),
    do: request(token, :post, config_key, "#{name}:asymmetricSign", json: body)

  @spec request(String.t(), atom(), module(), String.t(), Keyword.t()) :: {:ok, map()} | {:error, term()}
  defp request(token, method, config_key, path, options \\ []) do
    [
      method: method,
      url: "#{@kms_base_url}/#{path}",
      auth: {:bearer, token},
      retry: false
    ]
    |> Keyword.merge(req_options(config_key))
    |> Req.request(options)
    |> normalize_response()
  end

  @spec normalize_response({:ok, Req.Response.t()} | {:error, Exception.t()}) :: {:ok, map()} | {:error, term()}
  defp normalize_response({:ok, %Req.Response{status: status, body: body}}) when status >= 200 and status < 300 do
    {:ok, body}
  end

  defp normalize_response({:ok, %Req.Response{} = response}), do: {:error, response}
  defp normalize_response({:error, exception}), do: {:error, Exception.message(exception)}

  @spec req_options(module()) :: Keyword.t()
  defp req_options(config_key), do: :cartouche |> Application.get_env(config_key, []) |> Keyword.get(:req_options, [])
end
