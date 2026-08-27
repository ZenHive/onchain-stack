defmodule Cartouche.Solana.Signer do
  @moduledoc """
  GenServer that wraps Ed25519 signing backends for Solana.

  Follows the same MFA (module, function, args) backend pattern as the
  Ethereum `Cartouche.Signer`, but much simpler: no recovery bit brute-force,
  no chain ID encoding.

  Delegates to a backend module (e.g., `Cartouche.Solana.Signer.Ed25519` for
  local keys, or `Cartouche.Solana.Signer.CloudKMS` for GCP KMS). Caches
  the public key on first use.

  ## Examples

      # Start via supervisor or manually:
      {:ok, pid} = Cartouche.Solana.Signer.start_link(
        mfa: {Cartouche.Solana.Signer.Ed25519, :sign, [seed]},
        name: MySolSigner
      )

      # Sign a message:
      {:ok, signature} = Cartouche.Solana.Signer.sign(message, MySolSigner)

      # Get the signer's public key:
      pub_key = Cartouche.Solana.Signer.address(MySolSigner)
  """
  use Descripex, namespace: "/solana/signer"
  use GenServer

  alias Cartouche.Signer.Backend
  alias Cartouche.Solana.Signer.Default

  require Logger

  api(:child_spec, "Build the supervisor child specification for a Solana signer process.",
    params: [
      init_arg: [
        kind: :value,
        description: "Initialization argument passed by a supervisor when starting Cartouche.Solana.Signer."
      ]
    ],
    returns: %{
      type: :supervisor_child_spec,
      description: "Supervisor child spec map that starts Cartouche.Solana.Signer."
    }
  )

  api(:start_link, "Start a Solana signer process backed by the provided Ed25519 signer backend carrier.",
    params: [
      opts: [
        kind: :value,
        description:
          "Keyword list containing `:mfa` as a `{backend_module, config}` carrier (or a legacy `{module, function, args}` MFA) and `:name` as the GenServer name."
      ]
    ],
    returns: %{
      type: :genserver_on_start,
      description: "`{:ok, pid}` when the signer starts, or the standard GenServer start error tuple."
    }
  )

  @doc """
  Starts a new Solana signer process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    mfa = Keyword.fetch!(opts, :mfa)
    name = Keyword.fetch!(opts, :name)
    Logger.info("Starting Cartouche.Solana.Signer #{inspect(name)}...")
    GenServer.start_link(__MODULE__, %{mfa: mfa, name: name}, name: name)
  end

  @doc false
  @impl true
  def init(state) do
    {:ok, state}
  end

  api(:sign, "Sign raw Solana message bytes with a running signer process.",
    params: [
      message: [kind: :value, description: "Raw message bytes to sign."],
      name: [kind: :value, default: Default, description: "Signer GenServer name or pid."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description: "`{:ok, signature}` with a 64-byte Ed25519 signature, or `{:error, reason}` from the signing backend."
    }
  )

  @doc """
  Sign raw message bytes. Returns a 64-byte Ed25519 signature.

  ## Examples

      iex> signer = Cartouche.Solana.Test.Signer.start_signer()
      iex> {:ok, sig} = Cartouche.Solana.Signer.sign("test", signer)
      iex> byte_size(sig)
      64
  """
  @spec sign(binary(), GenServer.server()) :: {:ok, <<_::512>>} | {:error, term()}
  def sign(message, name \\ Default) when is_binary(message) do
    GenServer.call(name, {:sign, message})
  end

  api(:address, "Get the Solana public key controlled by a signer process.",
    params: [
      name: [kind: :value, default: Default, description: "Signer GenServer name or pid."]
    ],
    returns: %{
      type: :solana_pubkey,
      description:
        "32-byte Solana public key; encode with `Cartouche.Solana.Keys.to_address/1` for the base58 address string."
    }
  )

  @doc """
  Get the 32-byte public key (Solana address) for this signer.

  ## Examples

      iex> signer = Cartouche.Solana.Test.Signer.start_signer()
      iex> address = Cartouche.Solana.Signer.address(signer)
      iex> byte_size(address)
      32
  """
  @spec address(GenServer.server()) :: <<_::256>>
  def address(name \\ Default) do
    GenServer.call(name, :get_address)
  end

  api(:verify, "Verify an Ed25519 signature against raw Solana message bytes and a public key.",
    params: [
      message: [kind: :value, description: "Raw message bytes that were signed."],
      signature: [kind: :value, description: "64-byte Ed25519 signature."],
      pub_key: [
        kind: :value,
        description: "32-byte Solana public key; base58 address strings should be decoded before calling."
      ]
    ],
    returns: %{
      type: :boolean,
      description: "`true` when the signature verifies for the message and public key; otherwise `false`."
    }
  )

  @doc """
  Verify an Ed25519 signature. Standalone function, no GenServer needed.

  ## Examples

      iex> seed = Base.decode16!("9D61B19DEFFD5A60BA844AF492EC2CC44449C5697B326919703BAC031CAE7F60")
      iex> pub = Base.decode16!("D75A980182B10AB7D54BFED3C964073A0EE172F3DAA62325AF021A68F707511A")
      iex> {:ok, sig} = Cartouche.Solana.Signer.Ed25519.sign("test", seed)
      iex> Cartouche.Solana.Signer.verify("test", sig, pub)
      true
  """
  @spec verify(binary(), <<_::512>>, <<_::256>>) :: boolean()
  def verify(message, <<signature::binary-64>>, <<pub_key::binary-32>>) when is_binary(message) do
    :crypto.verify(:eddsa, :none, message, signature, [pub_key, :ed25519])
  end

  # --- GenServer callbacks ---

  @doc false
  @impl true
  def handle_call({:sign, message}, _from, %{mfa: mfa} = state) do
    {:reply, backend_sign(mfa, message), state}
  end

  def handle_call(:get_address, _from, %{address: address} = state) do
    {:reply, address, state}
  end

  def handle_call(:get_address, _from, %{name: name, mfa: mfa} = state) do
    {:ok, address} = backend_address(mfa)

    Logger.info("Cartouche.Solana.Signer #{inspect(name)} address: #{Cartouche.Solana.Keys.to_address(address)}")

    {:reply, address, Map.put(state, :address, address)}
  end

  # --- Backend dispatch (pure-payload contract) ---
  #
  # The runtime carries a backend as either the new `{backend_module, config}`
  # pair (`Cartouche.Signer.Backend`) or, for back-compat, a legacy
  # `{module, function, args}` MFA. Ed25519 signs raw message bytes, so there is
  # no digest/recid/chain-id step.

  @spec backend_sign(Backend.t() | {module(), atom(), [term()]}, binary()) ::
          {:ok, <<_::512>>} | {:error, term()}
  defp backend_sign({backend, config}, message) when is_atom(backend) do
    with :ok <- Backend.expect_algorithm(backend, config, :ed25519) do
      backend.sign_payload(message, config)
    end
  end

  defp backend_sign({mod, fun, args}, message) do
    apply(mod, fun, [message | args])
  end

  @spec backend_address(Backend.t() | {module(), atom(), [term()]}) ::
          {:ok, <<_::256>>} | {:error, term()}
  defp backend_address({backend, config}) when is_atom(backend) do
    with :ok <- Backend.expect_algorithm(backend, config, :ed25519) do
      backend.public_key(config)
    end
  end

  defp backend_address({mod, _fun, args}) do
    apply(mod, :get_address, args)
  end
end
