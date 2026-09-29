defmodule Onchain.Solana.Application do
  @moduledoc false
  use Application

  alias Cartouche.Signer.Backend

  @impl true
  @spec start(Application.start_type(), term()) :: Supervisor.on_start()
  def start(_type, _args) do
    children =
      :cartouche
      |> Application.get_env(:solana_signer, [])
      |> Enum.map(&get_solana_signer_spec/1)

    Supervisor.start_link(children, strategy: :one_for_one, name: Onchain.Solana.Supervisor)
  end

  # --- Solana signers ---

  @spec get_solana_signer_spec({atom(), tuple()}) :: Supervisor.child_spec()
  defp get_solana_signer_spec({name, signer_type}) do
    name =
      case name do
        :default -> Onchain.Solana.Signer.Default
        els -> els
      end

    Supervisor.child_spec(
      {Onchain.Solana.Signer, mfa: solana_signer_mfa(signer_type), name: name},
      id: name
    )
  end

  @spec solana_signer_mfa(tuple()) :: Backend.t()
  defp solana_signer_mfa({:ed25519, seed}) do
    {Onchain.Solana.Signer.Ed25519, decode_solana_key!(seed)}
  end

  defp solana_signer_mfa({:cloud_kms, kms_credentials, key_path, version}) do
    {project, location, key_ring, key_id} = parse_kms_key_path(key_path)
    {Onchain.Solana.Signer.CloudKMS, {kms_credentials, project, location, key_ring, key_id, version}}
  end

  defp solana_signer_mfa({backend, config}) when is_atom(backend) do
    {backend, config}
  end

  # E.g. "projects/*/locations/*/keyRings/*/cryptoKeys/*"
  @spec parse_kms_key_path(String.t()) :: {String.t(), String.t(), String.t(), String.t()}
  defp parse_kms_key_path(key_path) do
    ["projects", project, "locations", location, "keyRings", key_ring, "cryptoKeys", key_id] =
      String.split(key_path, "/")

    {project, location, key_ring, key_id}
  end

  # Solana keys can be raw 32-byte binaries, hex-encoded, or Base58-encoded
  @spec decode_solana_key!(binary()) :: <<_::256>>
  defp decode_solana_key!(key) when byte_size(key) == 32, do: key

  defp decode_solana_key!(key) when is_binary(key) do
    case Base.decode16(key, case: :mixed) do
      {:ok, <<decoded::binary-32>>} ->
        decoded

      _ ->
        case Onchain.Solana.Base58.decode(key) do
          {:ok, <<decoded::binary-32>>} -> decoded
          _ -> Cartouche.Hex.decode_hex_input!(key)
        end
    end
  end
end
