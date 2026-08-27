defmodule Cartouche.Signer do
  @moduledoc """
  Cartouche.Signer is a GenServer which can sign messages. The runtime carrier
  is a `{backend_module, config}` pair implementing `Cartouche.Signer.Backend`
  (for instance `Cartouche.Signer.Curvy` with a local key, or
  `Cartouche.Signer.CloudKMS` with GCP Cloud KMS coordinates). A legacy
  `{module, function, args}` MFA is also accepted so existing call sites
  (`Cartouche.Signer.sign_direct/4`, and `start_link/1` handed a 3-tuple)
  keep working. In either case, start the GenServer and call
  `Cartouche.Signer.sign(MySigner, "message")` to get a 65-byte Ethereum
  signature.

  This library never emits a 65-byte Ethereum signature with `s > n/2`
  (EIP-2). Low-s canonicalization is applied at the emission funnel, not by
  the configured backend: both the `{backend, config}` path and the legacy
  MFA path pass through `Cartouche.Recover.normalize_low_s/1` before the
  recovery-bit search and EIP-155 packing. The MFA carrier is kept because
  `sign_direct/4` is the production signing route in the downstream `onchain`
  repo; migrating that call site is a separate task. It cannot bypass the
  invariant.

  Note: we also enforce that a given signer process knows its public key,
  such that we can verify signatures recovery bits. That is, since CloudKMS
  and other signing tools don't return a recovery bit, necessary for Ethereum,
  we test all 4 possible bits to make sure a signature recovers to the correct
  signer address, but we need to know what that address should be to accomplish
  this task.

  Additionally, chain_id is used to return EIP-155 compliant signatures.
  """
  use Descripex, namespace: "/ethereum/signer"
  use GenServer
  use Cartouche.Hex

  import Cartouche.Hash, only: [keccak: 1]

  alias Cartouche.Signer.Backend
  alias Cartouche.Signer.Default

  require Logger

  api(:child_spec, "Build the supervisor child specification for a signer process.",
    params: [
      init_arg: [
        kind: :value,
        description: "Initialization argument passed by a supervisor when starting Cartouche.Signer."
      ]
    ],
    returns: %{
      type: :supervisor_child_spec,
      description: "Supervisor child spec map that starts Cartouche.Signer."
    }
  )

  api(:start_link, "Start a signer process backed by the provided signer backend carrier.",
    params: [
      signer_options: [
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
  Starts a new Cartouche.Signer process.
  """
  @spec start_link(mfa: Backend.t() | {module(), atom(), [any()]}, name: GenServer.name() | nil) ::
          GenServer.on_start()
  def start_link(mfa: mfa, name: name) do
    Logger.info("Starting Cartouche.Signer #{name}...")
    chain_id = Cartouche.Application.chain_id()

    GenServer.start_link(
      __MODULE__,
      %{mfa: mfa, name: name, chain_id: chain_id},
      name: name
    )
  end

  @doc false
  @impl true
  def init(state) do
    {:ok, state}
  end

  api(:sign, "Sign a message with a running signer process.",
    params: [
      message: [kind: :value, description: "Message bytes or string to sign."],
      name: [kind: :value, default: Default, description: "Signer GenServer name or pid."],
      opts: [kind: :value, default: [], description: "Keyword options for signing."]
    ],
    opts: [
      chain_id: [
        kind: :value,
        description:
          "Chain id used to produce an EIP-155-compliant signature; defaults to the signer's configured chain id."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, signature}` with the 65-byte Ethereum signature, or `{:error, reason}` when signing or recovery fails."
    },
    composes_with: [:sign_direct]
  )

  @doc """
  Signs a message using this signing key.

  ## Examples

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, sig} = Cartouche.Signer.sign("test", signer_proc)
      iex> Cartouche.Recover.recover_eth("test", sig)
      ...> |> Cartouche.Hex.to_address()
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, <<_r::256, _s::256, v::binary>>} = Cartouche.Signer.sign("test", signer_proc, chain_id: 0x05f5e0ff)
      iex> :binary.decode_unsigned(v)
      0x05f5e0ff * 2 + 35 + 1
  """
  @spec sign(String.t(), GenServer.server(), Keyword.t()) ::
          {:ok, binary()} | {:error, term()}
  def sign(message, name \\ Default, opts \\ []) do
    chain_id = Keyword.get(opts, :chain_id, GenServer.call(name, :get_chain_id))
    GenServer.call(name, {:sign, {message, chain_id}})
  end

  api(:address, "Get the Ethereum address controlled by a signer process.",
    params: [
      name: [kind: :value, default: Default, description: "Signer GenServer name or pid."]
    ],
    returns: %{type: :ethereum_address, description: "20-byte Ethereum address for the signer."}
  )

  @doc """
  Gets the address for this signer.

  ## Examples

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> Cartouche.Signer.address(signer_proc) |> Cartouche.Hex.to_address()
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  """
  @spec address(GenServer.server()) :: Cartouche.address()
  def address(name \\ Default) do
    GenServer.call(name, :get_address)
  end

  api(:chain_id, "Get the chain id configured for a signer process.",
    params: [
      name: [kind: :value, default: Default, description: "Signer GenServer name or pid."]
    ],
    returns: %{type: :integer, description: "Configured Ethereum chain id."}
  )

  @doc """
  Gets the chain id for this signer.

  ## Examples

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> Cartouche.Signer.chain_id(signer_proc)
      5
  """
  @spec chain_id(GenServer.server()) :: integer()
  def chain_id(name \\ Default) do
    GenServer.call(name, :get_chain_id)
  end

  @doc false
  @impl true
  def handle_call({:sign, {message, chain_id}}, _from, %{address: address, mfa: mfa} = state) do
    {:reply, backend_sign(mfa, message, address, chain_id), state}
  end

  # Note absence of address in state, find it and set it and then sign. Address will be cached on next signing.
  def handle_call({:sign, {message, chain_id}}, _from, %{name: name, mfa: mfa} = state) do
    case backend_address(mfa) do
      {:ok, address} ->
        Logger.info("Cartouche.Signer #{name} signing with address #{to_address(address)}")

        {:reply, backend_sign(mfa, message, address, chain_id), Map.put(state, :address, address)}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  # Reads address from state, or finds and memoize address on first call.
  def handle_call(:get_address, _from, %{address: address} = state) do
    {:reply, address, state}
  end

  def handle_call(:get_address, _from, %{name: name, mfa: mfa} = state) do
    {:ok, address} = backend_address(mfa)
    Logger.info("Cartouche.Signer #{name} signing with address #{to_address(address)}")
    {:reply, address, Map.put(state, :address, address)}
  end

  def handle_call(:get_chain_id, _from, %{chain_id: chain_id} = state) do
    {:reply, chain_id, state}
  end

  api(:sign_direct, "Sign a message directly with a signing MFA and known signer address.",
    params: [
      message: [kind: :value, description: "Message bytes or string to sign."],
      address: [kind: :value, description: "20-byte Ethereum address expected to recover from the signature."],
      signer_mfa: [
        kind: :value,
        description: "`{module, function, args}` tuple that performs the raw secp256k1 signature."
      ],
      chain_id_or_name: [
        kind: :value,
        description:
          "Ethereum chain id integer, configured chain atom such as `:sepolia`, or `nil` to use the application-configured chain, used for EIP-155 `v` calculation."
      ]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, signature}` with the 65-byte Ethereum signature, or `{:error, reason}` when signing or recovery fails."
    }
  )

  @doc """
  Directly sign a message, not using a signer process.

  This is mostly used internally, but can be used safely externally as well.
  The returned 65-byte signature is always low-s (EIP-2), regardless of
  whether the MFA backend normalized.
  """
  @spec sign_direct(String.t(), binary(), {module(), atom(), [any()]}, integer() | atom() | nil) ::
          {:ok, binary()} | {:error, String.t()}
  def sign_direct(message, address, {mod, fun, args}, chain_id_or_name) do
    with {:ok, %Curvy.Signature{crv: :secp256k1, recid: nil} = signature} <-
           apply(mod, fun, [message] ++ args) do
      emit_signature(keccak(message), signature, address, chain_id_or_name)
    end
  end

  # --- Backend dispatch (pure-payload contract) ---
  #
  # The runtime carries a backend as either the new `{backend_module, config}`
  # pair (pure-payload `Cartouche.Signer.Backend`) or, for back-compat, a legacy
  # `{module, function, args}` MFA whose `sign` keccaks internally.

  # Resolve the signer's Ethereum address from the backend carrier.
  @spec backend_address(Backend.t() | {module(), atom(), [any()]}) ::
          {:ok, binary()} | {:error, term()}
  defp backend_address({backend, config}) when is_atom(backend) do
    with :ok <- Backend.expect_algorithm(backend, config, :secp256k1),
         {:ok, public_key} <- backend.public_key(config) do
      {:ok, Cartouche.Address.from_public_key(public_key)}
    end
  end

  defp backend_address({mod, _fun, args}) do
    apply(mod, :get_address, args)
  end

  # Sign through the backend carrier. New carriers take the pure-payload path:
  # the caller keccaks the message, the backend signs that digest, low-s is
  # normalized, and the recid is searched against the SAME digest.
  @spec backend_sign(
          Backend.t() | {module(), atom(), [any()]},
          String.t(),
          binary(),
          integer() | atom() | nil
        ) :: {:ok, binary()} | {:error, term()}
  defp backend_sign({backend, config}, message, address, chain_id_or_name) when is_atom(backend) do
    with :ok <- Backend.expect_algorithm(backend, config, :secp256k1),
         digest = keccak(message),
         {:ok, raw_signature} <- backend.sign_payload(digest, config) do
      emit_signature(digest, raw_signature, address, chain_id_or_name)
    end
  end

  defp backend_sign({_mod, _fun, _args} = mfa, message, address, chain_id_or_name) do
    sign_direct(message, address, mfa, chain_id_or_name)
  end

  # Sole 65-byte emission funnel. Low-s is applied here, before recid search,
  # so a high-s backend cannot produce a malleable signature and flipping s
  # cannot leave a stale recovery bit.
  @spec emit_signature(<<_::256>>, Curvy.Signature.t(), binary(), integer() | atom() | nil) ::
          {:ok, binary()} | {:error, term()}
  defp emit_signature(digest, raw_signature, address, chain_id_or_name) do
    signature = Cartouche.Recover.normalize_low_s(raw_signature)

    with {:ok, recid} <- Cartouche.Recover.find_recid_from_digest(digest, signature, address) do
      {:ok, encode_eip155(signature, recid, chain_id_or_name)}
    end
  end

  # Assemble the 65-byte EIP-155 signature from a recovered secp256k1 signature.
  # A `nil` chain id defaults to the application chain, mirroring how `V1.new`/
  # `V2.new` already resolve the transaction's `v` field — so the default-signer
  # path (no `chain_id:` option) signs for the configured chain instead of crashing.
  @spec encode_eip155(Curvy.Signature.t(), 0..1, integer() | atom() | nil) :: binary()
  defp encode_eip155(%Curvy.Signature{r: r, s: s}, recid, chain_id_or_name) do
    chain_id = Cartouche.Chain.chain_id_value(chain_id_or_name)
    v = if chain_id == 0, do: 27 + recid, else: chain_id * 2 + 35 + recid

    Hex.encode_bytes(r, 32) <> Hex.encode_bytes(s, 32) <> :binary.encode_unsigned(v)
  end
end
