defmodule Cartouche.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Cartouche.Signer.Backend

  @doc false
  @spec chain_id() :: integer()
  def chain_id, do: Cartouche.Chain.parse_id(Application.get_env(:cartouche, :chain_id, 1))

  @doc false
  @spec ethereum_node() :: String.t()
  def ethereum_node, do: Application.get_env(:cartouche, :ethereum_node, "https://mainnet.infura.io")

  @impl true
  def start(_type, _args) do
    eth_signers = Application.get_env(:cartouche, :signer, [])

    # No HTTP pool child: Req manages its own Finch pool (`Req.Finch`). Consumers
    # who need a tuned pool pass `req_options: [finch: MyFinch]` and supervise it
    # themselves.
    children = Enum.map(eth_signers, &get_signer_spec/1)

    opts = [strategy: :one_for_one, name: Cartouche.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # --- Ethereum signers ---

  @doc false
  @spec get_signer_spec({atom(), tuple()}) :: Supervisor.child_spec()
  def get_signer_spec({name, signer_type}) do
    name =
      case name do
        :default -> Cartouche.Signer.Default
        els -> els
      end

    Supervisor.child_spec(
      {Cartouche.Signer, mfa: signer_mfa(signer_type), name: name},
      id: name
    )
  end

  # Translate a `:signer` config entry into a `{backend_module, config}` carrier.
  #
  # The `:priv_key` / `:cloud_kms` shorthands are kept (they translate into the
  # backend contract); an explicit `{BackendModule, config}` form is also
  # accepted for backends not covered by a shorthand.
  @spec signer_mfa(tuple()) :: Backend.t()
  defp signer_mfa({:priv_key, priv_key}) do
    {Cartouche.Signer.Secp256k1, Cartouche.Hex.decode_hex_input!(priv_key)}
  end

  defp signer_mfa({:cloud_kms, kms_credentials, key_path, version}) do
    {project, location, key_ring, key_id} = parse_kms_key_path(key_path)
    {Cartouche.Signer.CloudKMS, {kms_credentials, project, location, key_ring, key_id, version}}
  end

  defp signer_mfa({backend, config}) when is_atom(backend) do
    {backend, config}
  end

  # E.g. "projects/*/locations/*/keyRings/*/cryptoKeys/*"
  @spec parse_kms_key_path(String.t()) :: {String.t(), String.t(), String.t(), String.t()}
  defp parse_kms_key_path(key_path) do
    ["projects", project, "locations", location, "keyRings", key_ring, "cryptoKeys", key_id] =
      String.split(key_path, "/")

    {project, location, key_ring, key_id}
  end
end
