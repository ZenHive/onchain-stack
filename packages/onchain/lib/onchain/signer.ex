defmodule Onchain.Signer do
  @moduledoc """
  EIP-1559 transaction building, signing, encoding, and broadcasting.

  Stateless pipeline — no GenServer, no application config. Private key is
  always passed explicitly. Uses `Cartouche.Signer.sign_direct/4` for signing
  and `Cartouche.Transaction.V2` for transaction construction.

  ## Pipeline

  `build_transaction/3` → `sign_transaction/3` → `encode_transaction/1` → `RPC.eth_send_raw_transaction/2`

  Or use `send_transaction/3` for the full pipeline in one call.

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `address_from_key/1` | Derive checksummed address from private key |
  | `build_transaction/3` | Build unsigned EIP-1559 transaction |
  | `sign_transaction/3` | Sign transaction with private key |
  | `encode_transaction/1` | Encode signed transaction to hex |
  | `send_transaction/3` | Full pipeline: build → sign → encode → broadcast |
  """

  use Descripex, namespace: "/signer"

  alias Cartouche.Signer.Curvy
  alias Cartouche.Transaction.V2
  alias Onchain.Address
  alias Onchain.Hex
  alias Onchain.RPC

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
      Address.checksum(addr_bin)
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
  defp build_transaction_validated(to, calldata, opts) do
    with {:ok, nonce} <- fetch_required(opts, :nonce),
         {:ok, chain_id} <- fetch_required(opts, :chain_id),
         {:ok, to_bin} <- Address.validate(to) do
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
      mfa = {Curvy, :sign, [key_bin]}

      case Cartouche.Signer.sign_direct(encoded, addr_bin, mfa, chain_id) do
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
    {:ok, signed_trx |> V2.encode() |> Hex.encode()}
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
      data: Hex.encode(calldata),
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
  defp decode_private_key(input), do: Onchain.PrivateKey.decode(input)

  # Wraps Curvy.get_address/1 to catch crashes from malformed keys (e.g. <<0::256>>).
  # Returns {:error, {:invalid_private_key, original_input}} instead of crashing.
  #
  # Verified against Cartouche.Signer.Curvy: a scalar outside [1, n-1] fails the
  # `<<0>>` pubkey-prefix match (MatchError); a non-32-byte or non-binary key has no
  # matching `Curvy.Key.from_privkey/2` clause (FunctionClauseError). Every other
  # exception — a typo'd call, a missing dep — propagates as the bug it is.
  defp safe_get_address(key_bin, original_input) do
    Curvy.get_address(key_bin)
  rescue
    _ in [FunctionClauseError, MatchError] -> {:error, {:invalid_private_key, original_input}}
  end

  # Returns {:ok, value} for present keys, {:error, {:missing_option, key}} for absent ones.
  # Used instead of Keyword.fetch!/2 so non-bang functions return error tuples.
  defp fetch_required(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_option, key}}
    end
  end
end
