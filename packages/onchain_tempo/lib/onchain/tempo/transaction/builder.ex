defmodule Onchain.Tempo.Transaction.Builder do
  @moduledoc "Builds and signs Tempo transactions using tempo-primitives for encoding."
  alias Onchain.Signer.Secp256k1
  alias Onchain.Tempo.Codec
  alias Onchain.Tempo.TIP20
  alias Onchain.Tempo.Transaction

  # Default fee parameters for testnet transfers.
  # Moderato base fee is 20 gwei minimum — use 25 gwei for headroom.
  @default_max_fee_per_gas 25_000_000_000
  @default_max_priority_fee_per_gas 1_000_000_000

  # Gas-limit safety headroom applied to an eth_estimateGas result (5/4 = 1.25×),
  # so a transaction is not sized exactly at the node's estimate. A cold TIP-20
  # transfer on Moderato measures ~560k–810k (the chain charges a protocol fee on
  # the transfer path), so a static default went stale twice — estimate per tx.
  @gas_headroom_numerator 5
  @gas_headroom_denominator 4

  @doc """
  Build and sign a TIP-20 transfer transaction (0x76).

  ## Options (required)

    * `:private_key` — hex-encoded secp256k1 private key (with or without 0x prefix)
    * `:token` — TIP-20 token address (hex)
    * `:recipient` — transfer recipient address (hex)
    * `:amount` — transfer amount in base units (integer)
    * `:chain_id` — Tempo chain ID (integer)
    * `:rpc_url` — RPC endpoint for nonce fetching

  ## Options (optional)

    * `:fee_token` — token address for fee payment (hex); defaults to `:token` value
    * `:nonce_key` — 2D nonce lane (integer, default 0)
    * `:nonce` — explicit nonce (skips RPC fetch if provided)
    * `:gas_limit` — explicit gas limit; when omitted, gas is auto-estimated per
      call via `eth_estimateGas`, summed, with a 1.25× safety headroom
    * `:valid_before` — Unix timestamp (default 0 = no expiry)
    * `:valid_after` — Unix timestamp (default 0)
    * `:key_authorization` — typed `Transaction.key_authorization()` with a primitive signature

  ## Returns

    * `{:ok, hex_string}` — `"0x76..."` hex-encoded signed transaction
    * `{:error, reason}` — on signing or RPC failure
  """
  @spec build_signed_transfer(keyword()) :: {:ok, String.t()} | {:error, term()}
  def build_signed_transfer(opts) do
    with {:ok, private_key} <- require_opt(opts, :private_key, &decode_key/1),
         {:ok, token} <- require_opt(opts, :token, &decode_address(:token, &1)),
         {:ok, recipient} <- require_opt(opts, :recipient, &decode_address(:recipient, &1)),
         {:ok, amount} <- require_opt(opts, :amount, &validate_uint(:amount, &1)),
         {:ok, chain_id} <- require_opt(opts, :chain_id, &validate_uint(:chain_id, &1)),
         {:ok, rpc_url} <- require_opt(opts, :rpc_url, &validate_non_empty_binary(:rpc_url, &1)),
         {:ok, fee_token} <- optional_opt(opts, :fee_token, token, &decode_address(:fee_token, &1)),
         {:ok, nonce_key} <- optional_opt(opts, :nonce_key, 0, &validate_uint(:nonce_key, &1)),
         {:ok, valid_before} <- optional_opt(opts, :valid_before, 0, &validate_uint(:valid_before, &1)),
         {:ok, valid_after} <- optional_opt(opts, :valid_after, 0, &validate_uint(:valid_after, &1)),
         {:ok, sender_address} <- Secp256k1.get_address(private_key),
         {:ok, nonce} <- resolve_nonce(opts, sender_address, rpc_url),
         call = transfer_call(token, recipient, amount),
         {:ok, gas_limit} <- resolve_gas_limit(opts, [call], sender_address, rpc_url) do
      transaction = %Transaction{
        raw: nil,
        chain_id: chain_id,
        max_priority_fee_per_gas: @default_max_priority_fee_per_gas,
        max_fee_per_gas: @default_max_fee_per_gas,
        gas_limit: gas_limit,
        calls: [call],
        access_list: [],
        nonce_key: nonce_key,
        nonce: nonce,
        valid_before: optional_quantity(valid_before),
        valid_after: optional_quantity(valid_after),
        fee_token: fee_token,
        fee_payer_signature: nil,
        tempo_authorization_list: [],
        key_authorization: Keyword.get(opts, :key_authorization)
      }

      Codec.sign(transaction, private_key)
    end
  end

  @doc """
  Build and sign a 0x76 transaction with arbitrary calls.

  ## Options (required)

    * `:private_key` — hex-encoded secp256k1 private key (with or without 0x prefix)
    * `:calls` — non-empty list of `Transaction.call()` maps
    * `:chain_id` — Tempo chain ID (integer)
    * `:rpc_url` — RPC endpoint for nonce fetching
    * `:fee_token` — TIP-20 token address (hex) used for fee payment

  ## Options (optional)

    * `:nonce_key` — 2D nonce lane (integer, default 0)
    * `:nonce` — explicit nonce (skips RPC fetch if provided)
    * `:gas_limit` — explicit gas limit; when omitted, gas is auto-estimated per
      call via `eth_estimateGas`, summed, with a 1.25× safety headroom
    * `:valid_before` — Unix timestamp (default 0 = no expiry)
    * `:valid_after` — Unix timestamp (default 0)
    * `:key_authorization` — typed `Transaction.key_authorization()` with a primitive signature

  ## Returns

    * `{:ok, hex_string}` — `"0x76..."` hex-encoded signed transaction
    * `{:error, reason}` — on signing or RPC failure
  """
  @spec build_signed_multicall(keyword()) :: {:ok, String.t()} | {:error, term()}
  def build_signed_multicall(opts) do
    with {:ok, private_key} <- require_opt(opts, :private_key, &decode_key/1),
         {:ok, calls} <- require_opt(opts, :calls, &validate_calls/1),
         {:ok, chain_id} <- require_opt(opts, :chain_id, &validate_uint(:chain_id, &1)),
         {:ok, rpc_url} <- require_opt(opts, :rpc_url, &validate_non_empty_binary(:rpc_url, &1)),
         {:ok, fee_token} <- require_opt(opts, :fee_token, &decode_address(:fee_token, &1)),
         {:ok, nonce_key} <- optional_opt(opts, :nonce_key, 0, &validate_uint(:nonce_key, &1)),
         {:ok, valid_before} <- optional_opt(opts, :valid_before, 0, &validate_uint(:valid_before, &1)),
         {:ok, valid_after} <- optional_opt(opts, :valid_after, 0, &validate_uint(:valid_after, &1)),
         {:ok, sender_address} <- Secp256k1.get_address(private_key),
         {:ok, nonce} <- resolve_nonce(opts, sender_address, rpc_url),
         {:ok, gas_limit} <- resolve_gas_limit(opts, calls, sender_address, rpc_url) do
      transaction = %Transaction{
        raw: nil,
        chain_id: chain_id,
        max_priority_fee_per_gas: @default_max_priority_fee_per_gas,
        max_fee_per_gas: @default_max_fee_per_gas,
        gas_limit: gas_limit,
        calls: calls,
        access_list: [],
        nonce_key: nonce_key,
        nonce: nonce,
        valid_before: optional_quantity(valid_before),
        valid_after: optional_quantity(valid_after),
        fee_token: fee_token,
        fee_payer_signature: nil,
        tempo_authorization_list: [],
        key_authorization: Keyword.get(opts, :key_authorization)
      }

      Codec.sign(transaction, private_key)
    end
  end

  @doc """
  Build and sign a TIP-20 transfer with fee payer placeholder.

  Same as `build_signed_transfer/1` but sets `fee_payer_signature` to
  `:placeholder` and `fee_token` to `nil`. That encodes as the `0x00` fee-payer
  marker and an empty fee token, signaling the server should co-sign as fee payer.

  Accepts the same options as `build_signed_transfer/1`. The `:fee_token` option
  is ignored (always empty for fee payer mode).
  """
  @spec build_fee_payer_transfer(keyword()) :: {:ok, String.t()} | {:error, term()}
  def build_fee_payer_transfer(opts) do
    with {:ok, private_key} <- require_opt(opts, :private_key, &decode_key/1),
         {:ok, token} <- require_opt(opts, :token, &decode_address(:token, &1)),
         {:ok, recipient} <- require_opt(opts, :recipient, &decode_address(:recipient, &1)),
         {:ok, amount} <- require_opt(opts, :amount, &validate_uint(:amount, &1)),
         {:ok, chain_id} <- require_opt(opts, :chain_id, &validate_uint(:chain_id, &1)),
         {:ok, rpc_url} <- require_opt(opts, :rpc_url, &validate_non_empty_binary(:rpc_url, &1)),
         {:ok, nonce_key} <- optional_opt(opts, :nonce_key, 0, &validate_uint(:nonce_key, &1)),
         {:ok, valid_before} <- optional_opt(opts, :valid_before, 0, &validate_uint(:valid_before, &1)),
         {:ok, valid_after} <- optional_opt(opts, :valid_after, 0, &validate_uint(:valid_after, &1)),
         {:ok, sender_address} <- Secp256k1.get_address(private_key),
         {:ok, nonce} <- resolve_nonce(opts, sender_address, rpc_url),
         call = transfer_call(token, recipient, amount),
         {:ok, gas_limit} <- resolve_gas_limit(opts, [call], sender_address, rpc_url) do
      transaction = %Transaction{
        raw: nil,
        chain_id: chain_id,
        max_priority_fee_per_gas: @default_max_priority_fee_per_gas,
        max_fee_per_gas: @default_max_fee_per_gas,
        gas_limit: gas_limit,
        calls: [call],
        access_list: [],
        nonce_key: nonce_key,
        nonce: nonce,
        valid_before: optional_quantity(valid_before),
        valid_after: optional_quantity(valid_after),
        fee_token: nil,
        fee_payer_signature: :placeholder,
        tempo_authorization_list: [],
        key_authorization: Keyword.get(opts, :key_authorization)
      }

      Codec.sign(transaction, private_key)
    end
  end

  @doc """
  Build and sign a fee-payer transaction with arbitrary calls.

  Accepts a `:calls` list of `Transaction.call()` maps. Sets fee payer
  placeholder and empty fee token, same as `build_fee_payer_transfer/1`.
  """
  @spec build_fee_payer_multicall(keyword()) :: {:ok, String.t()} | {:error, term()}
  def build_fee_payer_multicall(opts) do
    with {:ok, private_key} <- require_opt(opts, :private_key, &decode_key/1),
         {:ok, calls} <- require_opt(opts, :calls, &validate_calls/1),
         {:ok, chain_id} <- require_opt(opts, :chain_id, &validate_uint(:chain_id, &1)),
         {:ok, rpc_url} <- require_opt(opts, :rpc_url, &validate_non_empty_binary(:rpc_url, &1)),
         {:ok, nonce_key} <- optional_opt(opts, :nonce_key, 0, &validate_uint(:nonce_key, &1)),
         {:ok, valid_before} <- optional_opt(opts, :valid_before, 0, &validate_uint(:valid_before, &1)),
         {:ok, valid_after} <- optional_opt(opts, :valid_after, 0, &validate_uint(:valid_after, &1)),
         {:ok, sender_address} <- Secp256k1.get_address(private_key),
         {:ok, nonce} <- resolve_nonce(opts, sender_address, rpc_url),
         {:ok, gas_limit} <- resolve_gas_limit(opts, calls, sender_address, rpc_url) do
      transaction = %Transaction{
        raw: nil,
        chain_id: chain_id,
        max_priority_fee_per_gas: @default_max_priority_fee_per_gas,
        max_fee_per_gas: @default_max_fee_per_gas,
        gas_limit: gas_limit,
        calls: calls,
        access_list: [],
        nonce_key: nonce_key,
        nonce: nonce,
        valid_before: optional_quantity(valid_before),
        valid_after: optional_quantity(valid_after),
        fee_token: nil,
        fee_payer_signature: :placeholder,
        tempo_authorization_list: [],
        key_authorization: Keyword.get(opts, :key_authorization)
      }

      Codec.sign(transaction, private_key)
    end
  end

  defp optional_quantity(0), do: nil
  defp optional_quantity(value), do: value

  defp require_opt(opts, key, transform) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when not is_nil(value) -> transform.(value)
      _ -> {:error, "missing required option: #{key}"}
    end
  end

  defp optional_opt(opts, key, default, transform) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> transform.(value)
      :error -> {:ok, default}
    end
  end

  # Fetches nonce from RPC unless explicitly provided.
  defp resolve_nonce(opts, sender_address, rpc_url) do
    case Keyword.fetch(opts, :nonce) do
      :error ->
        sender_hex = "0x" <> Base.encode16(sender_address, case: :lower)
        Onchain.RPC.get_transaction_count(sender_hex, rpc_url: rpc_url)

      {:ok, nonce} ->
        validate_uint(:nonce, nonce)
    end
  end

  # Resolves the gas limit. An explicit `:gas_limit` is honored verbatim with no
  # RPC. When omitted, every call is sized via `eth_estimateGas` (from the sender's
  # address), the estimates are summed, and a safety headroom is applied. A failed
  # estimate propagates as an error — never a silent fallback to a static default.
  defp resolve_gas_limit(opts, calls, sender_address, rpc_url) do
    case Keyword.fetch(opts, :gas_limit) do
      {:ok, gas_limit} -> validate_uint(:gas_limit, gas_limit)
      :error -> estimate_gas(calls, sender_address, rpc_url)
    end
  end

  # Sums per-call `eth_estimateGas` results and applies the headroom multiplier.
  # Independent per-call estimation over-counts the shared intrinsic base (safe —
  # never under-estimates a batch); callers with state-dependent batches that an
  # isolated estimate would revert must pass an explicit `:gas_limit`.
  defp estimate_gas(calls, sender_address, rpc_url) do
    from_hex = hex(sender_address)

    calls
    |> Enum.reduce_while({:ok, 0}, fn %{to: to, value: value, input: input}, {:ok, acc} ->
      params = %{
        from: from_hex,
        to: hex(to),
        data: hex(input),
        value: value
      }

      case Onchain.RPC.eth_estimate_gas(params, rpc_url: rpc_url) do
        {:ok, gas} -> {:cont, {:ok, acc + gas}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, total} -> {:ok, apply_headroom(total)}
      {:error, _} = error -> error
    end
  end

  # Raw bytes -> the `0x`-prefixed lowercase hex string the JSON-RPC wire format
  # expects. Extracted so the prefix concatenation happens here rather than
  # three times inside the estimate loop.
  defp hex(binary), do: "0x" <> Base.encode16(binary, case: :lower)

  # Applies the gas safety headroom via integer ceil math (integer math avoids
  # float-precision loss on a large node estimate): ceil(gas * numerator / denominator).
  defp apply_headroom(gas) do
    div(gas * @gas_headroom_numerator + @gas_headroom_denominator - 1, @gas_headroom_denominator)
  end

  defp decode_key("0x" <> hex), do: decode_key(hex)

  defp decode_key(hex) when byte_size(hex) == 64 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, <<_::binary-size(32)>> = bin} -> {:ok, bin}
      :error -> {:error, "invalid private_key: expected 32-byte hex string"}
    end
  end

  defp decode_key(bin) when is_binary(bin) and byte_size(bin) == 32, do: {:ok, bin}
  defp decode_key(_), do: {:error, "invalid private_key: expected 32-byte hex string"}

  defp decode_address(key, "0x" <> hex), do: decode_address(key, hex)

  defp decode_address(key, hex) when is_binary(hex) and byte_size(hex) == 40 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, <<_::binary-size(20)>> = bin} -> {:ok, bin}
      :error -> {:error, "invalid #{key}: expected 20-byte hex address"}
    end
  end

  defp decode_address(_key, bin) when is_binary(bin) and byte_size(bin) == 20, do: {:ok, bin}
  defp decode_address(key, _), do: {:error, "invalid #{key}: expected 20-byte hex address"}

  defp validate_uint(_key, value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp validate_uint(key, _value), do: {:error, "invalid #{key}: expected non-negative integer"}

  defp validate_non_empty_binary(_key, value) when is_binary(value) and byte_size(value) > 0, do: {:ok, value}
  defp validate_non_empty_binary(key, _value), do: {:error, "invalid #{key}: expected non-empty string"}

  @spec transfer_call(binary(), binary(), non_neg_integer()) :: Transaction.call()
  defp transfer_call(token, recipient, amount) do
    %{to: token, value: 0, input: TIP20.transfer_calldata(recipient, amount)}
  end

  defp validate_calls([_ | _] = calls) do
    if Enum.all?(
         calls,
         &match?(
           %{to: to, value: value, input: input}
           when is_binary(to) and byte_size(to) == 20 and is_integer(value) and value >= 0 and is_binary(input),
           &1
         )
       ) do
      {:ok, calls}
    else
      {:error, "invalid calls: each call must have a 20-byte to, non-negative value, and binary input"}
    end
  end

  defp validate_calls(_), do: {:error, "invalid calls: expected non-empty list"}
end
