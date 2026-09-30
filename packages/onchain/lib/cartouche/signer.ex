defmodule Cartouche.Signer do
  @moduledoc """
  Cartouche.Signer is a GenServer which can sign messages. The runtime carrier
  is a `{backend_module, config}` pair implementing `Cartouche.Signer.Backend`
  (for instance `Cartouche.Signer.Secp256k1` with a local key, or
  `Cartouche.Signer.CloudKMS` with GCP Cloud KMS coordinates). A legacy
  `{module, function, args}` MFA is also accepted so existing call sites
  (`Cartouche.Signer.sign_direct/4`, and `start_link/1` handed a 3-tuple)
  keep working. In either case, start the GenServer and call
  `Cartouche.Signer.sign(MySigner, "message")` to get a packed
  `r || s || v` Ethereum signature (`Cartouche.signature()`).

  The packed form is 65 bytes when EIP-155 `v` fits in one byte and longer
  otherwise. At chain id 110, `v` is 255 or 256 depending on recovery parity,
  producing 65 or 66 bytes respectively. Chain binding for legacy transactions
  lives in that trailing `v` because `Transaction.V1.add_signature/2` copies
  it into the RLP `v` field; emitting a parity-only byte here would silently
  drop EIP-155 replay protection. Typed transactions already take y-parity
  from whatever width they receive.

  This library never emits a packed Ethereum signature with `s > n/2`
  (EIP-2). Low-s canonicalization is applied at the emission funnel, not by
  the configured backend: both the `{backend, config}` path and the legacy
  MFA path pass through `Cartouche.Recover.normalize_low_s/1` before the
  recovery-bit search and EIP-155 packing. The MFA carrier remains available
  for existing callers and cannot bypass the invariant.

  Note: we also enforce that a given signer process knows its public key,
  such that we can verify signatures recovery bits. That is, since CloudKMS
  and other signing tools don't return a recovery bit, necessary for Ethereum,
  we test all 4 possible bits to make sure a signature recovers to the correct
  signer address, but we need to know what that address should be to accomplish
  this task.

  Additionally, chain_id is used to return EIP-155 compliant signatures.

  For stateless EIP-1559 writes, `build_transaction/3`, `sign_transaction/3`,
  and `encode_transaction/1` build and sign with an explicitly supplied private
  key through the same backend carrier. `send_transaction/3` also estimates gas
  when omitted and broadcasts the encoded transaction. Signing returns the
  complete signed `%Cartouche.Transaction.V2{}`; encoding is a separate step.
  """
  use Descripex, namespace: "/ethereum/signer"
  use GenServer
  use Cartouche.Hex

  import Cartouche.Hash, only: [keccak: 1]

  alias Cartouche.Signer.Backend
  alias Cartouche.Signer.Default
  alias Cartouche.Signer.Secp256k1
  alias Cartouche.Transaction.V2
  alias Onchain.RPC

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
        "`{:ok, signature}` with the packed `r || s || v` Ethereum signature (`Cartouche.signature()`), or `{:error, reason}` when signing or recovery fails."
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
          {:ok, Cartouche.signature()} | {:error, term()}
  def sign(message, name \\ Default, opts \\ []) do
    chain_id = Keyword.get(opts, :chain_id, GenServer.call(name, :get_chain_id))
    GenServer.call(name, {:sign, {message, chain_id}})
  end

  @doc false
  @spec sign_digest(<<_::256>>, binary(), GenServer.server(), Keyword.t()) ::
          {:ok, Cartouche.signature()} | {:error, term()}
  def sign_digest(<<_::256>> = digest, payload, name, opts) do
    chain_id = Keyword.get(opts, :chain_id, GenServer.call(name, :get_chain_id))
    GenServer.call(name, {:sign, {{:digest, digest, payload}, chain_id}})
  end

  api(:sign_message, "Sign a message the way a wallet's personal_sign / ethers signMessage does.",
    params: [
      message: [kind: :value, description: "Message bytes or string; the EIP-191 envelope is added here."],
      name: [kind: :value, default: Default, description: "Signer GenServer name or pid."],
      opts: [kind: :value, default: [], description: "Keyword options forwarded to `sign/3`; `:chain_id` is fixed to 0."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, signature}` as a 65-byte `r || s || v` with `v` in 27/28, verifiable with `Cartouche.Recover.recover_personal_sign/2`, or `{:error, reason}`."
    },
    composes_with: [:sign]
  )

  @doc """
  Signs a message as `personal_sign` / ethers `signMessage` / viem `signMessage` do.

  Two differences from `sign/3`, both of which trip callers coming from
  JavaScript libraries: the EIP-191 `"\\x19Ethereum Signed Message:\\n"` prefix is
  applied before hashing, and `v` is 27/28 rather than the EIP-155 form.
  `sign/3` remains the primitive for transaction and EIP-712 digests, which
  must **not** carry the prefix.

  ## Examples

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, sig} = Cartouche.Signer.sign_message("hello", signer_proc)
      iex> Cartouche.Recover.recover_personal_sign("hello", sig) |> Cartouche.Hex.to_address()
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> {:ok, <<_r::256, _s::256, v>>} = Cartouche.Signer.sign_message("hello", signer_proc)
      iex> v in [27, 28]
      true
  """
  @spec sign_message(binary(), GenServer.server(), Keyword.t()) ::
          {:ok, Cartouche.signature()} | {:error, term()}
  def sign_message(message, name \\ Default, opts \\ []) do
    sign(Cartouche.Recover.prefix_eth(message), name, Keyword.put(opts, :chain_id, 0))
  end

  api(:sign_typed_data, "Sign EIP-712 typed data the way eth_signTypedData_v4 / ethers signTypedData does.",
    params: [
      typed: [kind: :value, description: "`%Cartouche.Typed{}` with domain, types and value."],
      name: [kind: :value, default: Default, description: "Signer GenServer name or pid."],
      opts: [kind: :value, default: [], description: "Keyword options forwarded to `sign/3`; `:chain_id` is fixed to 0."]
    ],
    returns: %{
      type: :ok_error_tuple,
      description:
        "`{:ok, signature}` as a 65-byte `r || s || v` with `v` in 27/28 over the `0x1901` payload, verifiable with `Cartouche.Recover.recover_eth/2` on `Cartouche.Typed.encode/1`, or `{:error, reason}`."
    },
    composes_with: [:sign]
  )

  @doc """
  Signs EIP-712 typed data as `eth_signTypedData_v4` / ethers `signTypedData` /
  viem `signTypedData` do.

  Encodes the `0x1901 || domainSeparator || hashStruct` payload with
  `Cartouche.Typed.encode/1` and signs it with `v` in 27/28. No EIP-191
  prefix is involved — that is `sign_message/3`. `sign/3` with the encoded
  payload gives the same digest with an EIP-155 `v` instead.

  ## Examples

      iex> signer_proc = Cartouche.Test.Signer.start_signer()
      iex> typed = %Cartouche.Typed{
      ...>   domain: %Cartouche.Typed.Domain{name: "Complex Array", version: "1"},
      ...>   types: %{"Array" => %Cartouche.Typed.Type{fields: [{"a", {:uint, 256}}, {"b", {:uint, 256}}, {"c", :string}, {"d", :bool}]}},
      ...>   value: %{"a" => 55, "b" => 66, "c" => "Hello", "d" => true}
      ...> }
      iex> {:ok, sig} = Cartouche.Signer.sign_typed_data(typed, signer_proc)
      iex> Cartouche.Recover.recover_eth(Cartouche.Typed.encode(typed), sig) |> Cartouche.Hex.to_address()
      "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
      iex> <<_r::256, _s::256, v>> = sig
      iex> v in [27, 28]
      true
  """
  @spec sign_typed_data(Cartouche.Typed.t(), GenServer.server(), Keyword.t()) ::
          {:ok, Cartouche.signature()} | {:error, term()}
  def sign_typed_data(%Cartouche.Typed{} = typed, name \\ Default, opts \\ []) do
    sign_digest(
      Cartouche.Typed.Native.signing_hash(typed),
      Cartouche.Typed.encode(typed),
      name,
      Keyword.put(opts, :chain_id, 0)
    )
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

  api(:sign_direct, "Sign a message directly with a backend carrier or MFA and known signer address.",
    params: [
      message: [kind: :value, description: "Message bytes or string to sign."],
      address: [kind: :value, description: "20-byte Ethereum address expected to recover from the signature."],
      signer_mfa: [
        kind: :value,
        description:
          "`{backend_module, config}` implementing `Cartouche.Signer.Backend`, or a legacy `{module, function, args}` MFA."
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
        "`{:ok, signature}` with the packed `r || s || v` Ethereum signature (`Cartouche.signature()`), or `{:error, reason}` when signing or recovery fails."
    }
  )

  @doc """
  Directly sign a message, not using a signer process.

  This is mostly used internally, but can be used safely externally as well.
  The returned packed `r || s || v` signature is always low-s (EIP-2), regardless of
  whether the backend normalized. Width follows `Cartouche.signature()`:
  65 bytes when EIP-155 `v` fits in one byte, longer when it does not.

  Backend carriers must use `:secp256k1` and receive the message's keccak digest
  through `sign_payload/2`. Legacy MFAs receive the original message.
  """
  @spec sign_direct(binary(), binary(), Backend.t() | {module(), atom(), [any()]}, integer() | atom() | nil) ::
          {:ok, Cartouche.signature()} | {:error, term()}
  def sign_direct(message, address, {backend, _config} = carrier, chain_id_or_name) when is_atom(backend) do
    backend_sign(carrier, message, address, chain_id_or_name)
  end

  def sign_direct(message, address, {mod, fun, args}, chain_id_or_name) do
    with {:ok, %Cartouche.Signature{} = signature} <-
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
          binary() | {:digest, binary(), binary()},
          binary(),
          integer() | atom() | nil
        ) :: {:ok, Cartouche.signature()} | {:error, term()}
  defp backend_sign({backend, config}, message, address, chain_id_or_name) when is_atom(backend) do
    with :ok <- Backend.expect_algorithm(backend, config, :secp256k1),
         digest = payload_digest(message),
         {:ok, raw_signature} <- backend.sign_payload(digest, config) do
      emit_signature(digest, raw_signature, address, chain_id_or_name)
    end
  end

  defp backend_sign({_mod, _fun, _args} = mfa, message, address, chain_id_or_name) do
    sign_direct(original_payload(message), address, mfa, chain_id_or_name)
  end

  @spec payload_digest(binary() | {:digest, binary(), binary()}) :: binary()
  defp payload_digest({:digest, digest, _payload}), do: digest
  defp payload_digest(payload), do: keccak(payload)

  @spec original_payload(binary() | {:digest, binary(), binary()}) :: binary()
  defp original_payload({:digest, _digest, payload}), do: payload
  defp original_payload(payload), do: payload

  # Sole packed-signature emission funnel. Low-s is applied here, before recid search,
  # so a high-s backend cannot produce a malleable signature and flipping s
  # cannot leave a stale recovery bit.
  @spec emit_signature(<<_::256>>, Cartouche.Signature.t(), binary(), integer() | atom() | nil) ::
          {:ok, Cartouche.signature()} | {:error, term()}
  defp emit_signature(digest, raw_signature, address, chain_id_or_name) do
    signature = Cartouche.Recover.normalize_low_s(raw_signature)

    with {:ok, recid} <- Cartouche.Recover.find_recid_from_digest(digest, signature, address) do
      {:ok, encode_eip155(signature, recid, chain_id_or_name)}
    end
  end

  # Assemble the packed EIP-155 signature from a recovered secp256k1 signature.
  # A `nil` chain id defaults to the application chain, mirroring how `V1.new`/
  # `V2.new` already resolve the transaction's `v` field — so the default-signer
  # path (no `chain_id:` option) signs for the configured chain instead of crashing.
  #
  # Trailing `v` is `chain_id*2+35+recid` encoded with `:binary.encode_unsigned/1`,
  # so `v` above 255 yields signatures longer than 65 bytes. That is deliberate: V1's
  # RLP `v` field *is* the chain binding, and `V1.add_signature/2` copies these
  # bytes into it. A parity-only 65-byte form would write 0/1 or 27/28 into V1.v
  # and silently drop EIP-155 replay protection. Typed transactions already
  # extract y-parity from whatever width they receive.
  @spec encode_eip155(Cartouche.Signature.t(), 0..1, integer() | atom() | nil) :: Cartouche.signature()
  defp encode_eip155(%Cartouche.Signature{r: r, s: s}, recid, chain_id_or_name) do
    chain_id = Cartouche.Chain.chain_id_value(chain_id_or_name)
    v = if chain_id == 0, do: 27 + recid, else: chain_id * 2 + 35 + recid

    Hex.encode_bytes(r, 32) <> Hex.encode_bytes(s, 32) <> :binary.encode_unsigned(v)
  end

  @default_gas_limit 100_000
  @default_max_fee_per_gas {30, :gwei}
  @default_max_priority_fee_per_gas {2, :gwei}

  # Safety headroom (1.25× = 5/4) applied to an eth_estimateGas result when
  # :gas_limit is auto-estimated, so a transaction is not sized exactly at the node
  # estimate (which would OOG-revert if on-chain accounting drifts up before
  # inclusion). Expressed as a num/den pair so apply_headroom/1 can use integer math.
  @gas_headroom_numerator 5
  @gas_headroom_denominator 4

  # --- address_from_key ---

  api(:address_from_key, "Derive checksummed Ethereum address from a private key.",
    params: [
      private_key: [
        kind: :value,
        description: "32-byte binary or hex string (with or without 0x)"
      ]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, {:invalid_private_key, term()}}",
      description: "EIP-55 checksummed address",
      example: "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
    }
  )

  @spec address_from_key(binary()) :: {:ok, String.t()} | {:error, {:invalid_private_key, term()}}
  def address_from_key(private_key) do
    with {:ok, key_bin} <- decode_private_key(private_key),
         {:ok, addr_bin} <- safe_get_address(key_bin, private_key) do
      Onchain.Address.checksum(addr_bin)
    end
  end

  api(:address_from_key!, "Derive checksummed Ethereum address from a private key. Raises on error.",
    params: [
      private_key: [
        kind: :value,
        description: "32-byte binary or hex string (with or without 0x)"
      ]
    ],
    returns: %{type: :string, description: "EIP-55 checksummed address"}
  )

  @spec address_from_key!(binary()) :: String.t()
  def address_from_key!(private_key) do
    case address_from_key(private_key) do
      {:ok, address} -> address
      {:error, reason} -> raise "address_from_key failed: #{inspect(reason)}"
    end
  end

  # --- build_transaction ---

  api(:build_transaction, "Build an unsigned EIP-1559 transaction.",
    params: [
      to: [kind: :value, description: "Destination address (hex string or 20-byte binary)"],
      calldata: [
        kind: :value,
        description:
          "Raw binary calldata (use Hex.decode!/1 on ABI.encode_call output), {:raw, binary} for literal bytes that start with 0x, or <<>> for plain ETH transfer"
      ],
      opts: [
        kind: :value,
        description:
          "Required: :nonce, :chain_id. Optional: :gas_limit, :max_fee_per_gas, :max_priority_fee_per_gas, :value, :access_list. Gas params accept integers (wei) or {n, :gwei} tuples."
      ]
    ],
    returns: %{
      type: "{:ok, %Cartouche.Transaction.V2{}} | {:error, term()}",
      description: "Unsigned EIP-1559 transaction struct"
    }
  )

  @spec build_transaction(binary(), binary() | {:raw, binary()}, keyword()) ::
          {:ok, V2.t()} | {:error, term()}
  def build_transaction(to, calldata, opts) do
    with {:ok, calldata_bin} <- normalize_calldata(calldata) do
      build_transaction_validated(to, calldata_bin, opts)
    end
  end

  @doc false
  # Validates calldata shape and unwraps it to a raw binary, returning the same
  # error tuples build_transaction/3 has always returned. Shared with the
  # send_transaction/3 auto-estimate path so that path rejects bad calldata with
  # an identical {:error, _} instead of crashing in the estimate's hex encoder
  # before build_transaction/3 ever runs.
  @spec normalize_calldata(binary() | {:raw, binary()}) :: {:ok, binary()} | {:error, term()}
  defp normalize_calldata({:raw, calldata}) when is_binary(calldata), do: {:ok, calldata}
  defp normalize_calldata({:raw, calldata}), do: {:error, {:invalid_calldata, {:raw, calldata}}}

  defp normalize_calldata(<<"0x", _rest::binary>> = calldata) do
    {:error,
     {:hex_calldata, calldata,
      "use Hex.decode!/1 to convert hex calldata to binary; if you need literal bytes starting with 0x, pass {:raw, binary}"}}
  end

  defp normalize_calldata(calldata) when is_binary(calldata), do: {:ok, calldata}
  defp normalize_calldata(calldata), do: {:error, {:invalid_calldata, calldata}}

  # Builds the transaction after calldata shape has been validated and normalized.
  @spec build_transaction_validated(binary(), binary(), keyword()) :: {:ok, V2.t()} | {:error, term()}
  defp build_transaction_validated(to, calldata, opts) do
    with {:ok, nonce} <- fetch_required(opts, :nonce),
         {:ok, chain_id} <- fetch_required(opts, :chain_id),
         {:ok, to_bin} <- Onchain.Address.validate(to) do
      gas_limit = Keyword.get(opts, :gas_limit, @default_gas_limit)
      max_fee = Keyword.get(opts, :max_fee_per_gas, @default_max_fee_per_gas)
      max_priority = Keyword.get(opts, :max_priority_fee_per_gas, @default_max_priority_fee_per_gas)
      value = Keyword.get(opts, :value, 0)
      access_list = Keyword.get(opts, :access_list, [])

      trx =
        V2.new(
          nonce,
          max_priority,
          max_fee,
          gas_limit,
          to_bin,
          value,
          calldata,
          access_list,
          chain_id
        )

      {:ok, trx}
    end
  end

  api(:build_transaction!, "Build an unsigned EIP-1559 transaction. Raises on error.",
    params: [
      to: [kind: :value, description: "Destination address (hex string or 20-byte binary)"],
      calldata: [
        kind: :value,
        description:
          "Raw binary calldata (use Hex.decode!/1 on ABI.encode_call output), {:raw, binary} for literal bytes that start with 0x, or <<>> for plain ETH transfer"
      ],
      opts: [
        kind: :value,
        description:
          "Required: :nonce, :chain_id. Optional: :gas_limit, :max_fee_per_gas, :max_priority_fee_per_gas, :value, :access_list. Gas params accept integers (wei) or {n, :gwei} tuples."
      ]
    ],
    returns: %{type: "%Cartouche.Transaction.V2{}", description: "Unsigned EIP-1559 transaction struct"}
  )

  @spec build_transaction!(binary(), binary() | {:raw, binary()}, keyword()) :: V2.t()
  def build_transaction!(to, calldata, opts) do
    case build_transaction(to, calldata, opts) do
      {:ok, trx} -> trx
      {:error, reason} -> raise "build_transaction failed: #{inspect(reason)}"
    end
  end

  # --- sign_transaction ---

  api(:sign_transaction, "Sign a transaction with a private key.",
    params: [
      unsigned_trx: [kind: :value, description: "Unsigned %Cartouche.Transaction.V2{} struct"],
      private_key: [kind: :value, description: "32-byte binary or hex string (with or without 0x)"],
      chain_id: [kind: :value, description: "Chain ID integer (1 = mainnet, 11155111 = Sepolia)"]
    ],
    returns: %{
      type: "{:ok, %Cartouche.Transaction.V2{}} | {:error, {:sign_error, term()}}",
      description: "Signed transaction with signature fields populated"
    }
  )

  @spec sign_transaction(V2.t(), binary(), pos_integer()) ::
          {:ok, V2.t()} | {:error, {:sign_error, term()} | {:invalid_private_key, term()}}
  def sign_transaction(unsigned_trx, private_key, chain_id) do
    with {:ok, key_bin} <- decode_private_key(private_key),
         {:ok, addr_bin} <- safe_get_address(key_bin, private_key) do
      encoded = V2.encode(unsigned_trx)

      case sign_direct(encoded, addr_bin, {Secp256k1, key_bin}, chain_id) do
        {:ok, signature} ->
          {:ok, V2.add_signature(unsigned_trx, signature)}

        {:error, reason} ->
          {:error, {:sign_error, reason}}
      end
    end
  end

  api(:sign_transaction!, "Sign a transaction with a private key. Raises on error.",
    params: [
      unsigned_trx: [kind: :value, description: "Unsigned %Cartouche.Transaction.V2{} struct"],
      private_key: [kind: :value, description: "32-byte binary or hex string (with or without 0x)"],
      chain_id: [kind: :value, description: "Chain ID integer (1 = mainnet, 11155111 = Sepolia)"]
    ],
    returns: %{type: "%Cartouche.Transaction.V2{}", description: "Signed transaction with signature fields populated"}
  )

  @spec sign_transaction!(V2.t(), binary(), pos_integer()) :: V2.t()
  def sign_transaction!(unsigned_trx, private_key, chain_id) do
    case sign_transaction(unsigned_trx, private_key, chain_id) do
      {:ok, trx} -> trx
      {:error, reason} -> raise "sign_transaction failed: #{inspect(reason)}"
    end
  end

  # --- encode_transaction ---

  api(:encode_transaction, "Encode a signed transaction to 0x-prefixed hex for broadcast.",
    params: [
      signed_trx: [kind: :value, description: "Signed %Cartouche.Transaction.V2{} struct"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, {:encode_error, :unsigned_transaction}}",
      description: "0x-prefixed hex string ready for eth_sendRawTransaction",
      example: "0x02f8..."
    }
  )

  @spec encode_transaction(V2.t()) ::
          {:ok, String.t()} | {:error, {:encode_error, :unsigned_transaction}}
  def encode_transaction(%V2{signature_y_parity: v, signature_r: r, signature_s: s})
      when is_nil(v) or is_nil(r) or is_nil(s) do
    {:error, {:encode_error, :unsigned_transaction}}
  end

  def encode_transaction(%V2{} = signed_trx) do
    {:ok, signed_trx |> V2.encode() |> Onchain.Hex.encode()}
  end

  api(:encode_transaction!, "Encode a signed transaction to 0x-prefixed hex for broadcast. Raises on error.",
    params: [
      signed_trx: [kind: :value, description: "Signed %Cartouche.Transaction.V2{} struct"]
    ],
    returns: %{type: :string, description: "0x-prefixed hex string ready for broadcast"}
  )

  @spec encode_transaction!(V2.t()) :: String.t()
  def encode_transaction!(%V2{} = trx) do
    case encode_transaction(trx) do
      {:ok, hex} -> hex
      {:error, reason} -> raise "encode_transaction failed: #{inspect(reason)}"
    end
  end

  # --- send_transaction ---

  api(:send_transaction, "Build, sign, encode, and broadcast a transaction in one call.",
    params: [
      to: [kind: :value, description: "Destination address (hex string or 20-byte binary)"],
      calldata: [
        kind: :value,
        description:
          "Raw binary calldata (use Hex.decode!/1 on ABI.encode_call output), {:raw, binary} for literal bytes that start with 0x, or <<>> for plain ETH transfer"
      ],
      opts: [
        kind: :value,
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :gas_limit, :max_fee_per_gas, :max_priority_fee_per_gas, :value, :access_list. When :gas_limit is omitted it is auto-estimated via eth_estimateGas (1.25× headroom) from the signer's address; a failed estimate returns {:error, _} rather than falling back to a default."
      ]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Transaction hash hex string"
    }
  )

  @spec send_transaction(binary(), binary() | {:raw, binary()}, keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def send_transaction(to, calldata, opts) do
    with {:ok, private_key} <- fetch_required(opts, :private_key),
         {:ok, chain_id} <- fetch_required(opts, :chain_id),
         {:ok, calldata_bin} <- normalize_calldata(calldata) do
      rpc_opts = Keyword.take(opts, [:rpc_url, :timeout])

      with {:ok, opts} <- resolve_gas_limit(opts, to, calldata_bin, private_key, rpc_opts),
           {:ok, unsigned} <- build_transaction(to, calldata_bin, opts),
           {:ok, signed} <- sign_transaction(unsigned, private_key, chain_id),
           {:ok, raw_hex} <- encode_transaction(signed) do
        RPC.eth_send_raw_transaction(raw_hex, rpc_opts)
      end
    end
  end

  api(:send_transaction!, "Build, sign, encode, and broadcast a transaction in one call. Raises on error.",
    params: [
      to: [kind: :value, description: "Destination address (hex string or 20-byte binary)"],
      calldata: [
        kind: :value,
        description:
          "Raw binary calldata (use Hex.decode!/1 on ABI.encode_call output), {:raw, binary} for literal bytes that start with 0x, or <<>> for plain ETH transfer"
      ],
      opts: [
        kind: :value,
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :gas_limit, :max_fee_per_gas, :max_priority_fee_per_gas, :value, :access_list. When :gas_limit is omitted it is auto-estimated via eth_estimateGas (1.25× headroom) from the signer's address; a failed estimate returns {:error, _} rather than falling back to a default."
      ]
    ],
    returns: %{type: :string, description: "Transaction hash hex string"}
  )

  @spec send_transaction!(binary(), binary() | {:raw, binary()}, keyword()) :: String.t()
  def send_transaction!(to, calldata, opts) do
    case send_transaction(to, calldata, opts) do
      {:ok, tx_hash} -> tx_hash
      {:error, reason} -> raise "send_transaction failed: #{inspect(reason)}"
    end
  end

  # --- Private helpers ---

  @doc false
  # Resolves :gas_limit into opts. An explicit :gas_limit is honored verbatim with
  # no RPC call. When omitted, estimates via eth_estimateGas (from the signer's own
  # address) and applies apply_headroom/1 (1.25×) headroom. A failed estimate
  # propagates as an error — never a silent fallback to @default_gas_limit.
  @spec resolve_gas_limit(keyword(), binary(), binary(), binary(), keyword()) ::
          {:ok, keyword()} | {:error, term()}
  defp resolve_gas_limit(opts, to, calldata, private_key, rpc_opts) do
    if Keyword.has_key?(opts, :gas_limit) do
      {:ok, opts}
    else
      with {:ok, from} <- address_from_key(private_key),
           {:ok, estimated} <- RPC.eth_estimate_gas(estimate_params(from, to, calldata, opts), rpc_opts) do
        {:ok, Keyword.put(opts, :gas_limit, apply_headroom(estimated))}
      end
    end
  end

  @doc false
  # Builds the atom-keyed tx-params map for eth_estimateGas. Calldata arrives already
  # normalized to a raw binary (see normalize_calldata/1) and is hex-encoded here;
  # <<>> (plain ETH transfer) yields "0x". :value is normalized to integer wei via
  # Cartouche.Wei.to_wei/1 so a {n, :wei | :gwei | :eth} tuple (which build_transaction
  # accepts on the explicit-gas_limit path) is estimated identically, not crashed.
  # :access_list is forwarded so the estimate covers the exact transaction that will
  # be submitted (EIP-2930 entries change intrinsic gas); an empty list is omitted.
  # Fee fields are intentionally NOT forwarded: passing maxFeePerGas/gasPrice to
  # eth_estimateGas can trigger node-side balance checks that fail the estimate, and
  # the GASPRICE-opcode-dependent estimation divergence it would avoid is rare.
  @spec estimate_params(String.t(), binary(), binary(), keyword()) :: map()
  defp estimate_params(from, to, calldata, opts) do
    %{
      from: from,
      to: to,
      data: Onchain.Hex.encode(calldata),
      value: Cartouche.Wei.to_wei(Keyword.get(opts, :value, 0)),
      access_list: Keyword.get(opts, :access_list, [])
    }
  end

  # Applies the safety headroom with integer math (ceil(gas * num / den)). gas is
  # always integral, so this avoids float arithmetic — an absurd node estimate (e.g.
  # a malformed RPC returning hundreds of hex digits) would overflow `gas * 1.25`.
  @spec apply_headroom(non_neg_integer()) :: non_neg_integer()
  defp apply_headroom(gas) do
    div(gas * @gas_headroom_numerator + @gas_headroom_denominator - 1, @gas_headroom_denominator)
  end

  # Normalizes a private key input to a 32-byte binary.
  # Accepts: 32-byte binary, hex string (64 chars, with/without 0x).
  @spec decode_private_key(term()) :: {:ok, binary()} | {:error, term()}
  defp decode_private_key(input), do: Onchain.PrivateKey.decode(input)

  @spec safe_get_address(binary(), term()) :: {:ok, binary()} | {:error, term()}
  defp safe_get_address(key_bin, original_input) do
    case Secp256k1.get_address(key_bin) do
      {:ok, address} -> {:ok, address}
      {:error, _} -> {:error, {:invalid_private_key, original_input}}
    end
  end

  # Returns {:ok, value} for present keys, {:error, {:missing_option, key}} for absent ones.
  # Used instead of Keyword.fetch!/2 so non-bang functions return error tuples.
  @spec fetch_required(keyword(), atom()) :: {:ok, term()} | {:error, {:missing_option, atom()}}
  defp fetch_required(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_option, key}}
    end
  end
end
