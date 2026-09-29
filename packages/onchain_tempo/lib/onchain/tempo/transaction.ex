defmodule Onchain.Tempo.Transaction do
  @moduledoc "Tempo transaction decoding, payment matching, and fee payer co-signing."

  alias Cartouche.Signer.Secp256k1, as: Secp256k1Signer
  alias Onchain.Tempo.Codec
  alias Onchain.Tempo.TIP20

  @enforce_keys [:chain_id, :calls, :raw]
  defstruct [:chain_id, :calls, :fields, :raw]

  @typedoc """
  A parsed Tempo Transaction with verification-relevant fields.

  `raw` is the full serialized transaction as a hex string ("0x76...") with
  0x prefix, suitable for direct JSON-RPC broadcast.
  """
  @type t :: %__MODULE__{
          chain_id: non_neg_integer(),
          calls: [call()],
          fields: map(),
          raw: String.t()
        }

  @typedoc "A single call within the transaction's batch."
  @type call :: %{to: binary(), value: non_neg_integer(), input: binary()}

  # Calldata sizes used in pattern match guards (4-byte selector + ABI-encoded args).
  # transfer: 4 + 32 (address) + 32 (uint256) = 68 → 64 bytes after selector
  # transferWithMemo: 4 + 32 + 32 + 32 (bytes32) = 100 → 96 bytes after selector

  # Selectors from TIP20 — cached as module attributes for compile-time pattern matching.
  @transfer_selector TIP20.transfer_selector()
  @transfer_with_memo_selector TIP20.transfer_with_memo_selector()
  @approve_selector TIP20.approve_selector()
  @swap_exact_amount_out_selector TIP20.swap_exact_amount_out_selector()
  @stablecoin_dex_address TIP20.stablecoin_dex_address()

  # Allowed call patterns for fee-payer sponsored transactions.
  # Each inner list is an ordered list of function selectors that must match exactly.
  # Matches mppx callScopes (fee-payer.ts:21-26).
  @call_scopes [
    [@transfer_selector],
    [@transfer_with_memo_selector],
    [@approve_selector, @swap_exact_amount_out_selector, @transfer_selector],
    [@approve_selector, @swap_exact_amount_out_selector, @transfer_with_memo_selector]
  ]

  @doc """
  Deserialize a hex-encoded Tempo Transaction (0x76 prefix).

  Returns `{:ok, %Transaction{}}` with `chain_id`, parsed `calls`, and the
  original hex string as `raw` (for broadcast). Returns `{:error, reason}`
  on invalid input.

  ## Examples

      iex> Onchain.Tempo.Transaction.deserialize("0x76" <> valid_rlp_hex)
      {:ok, %Onchain.Tempo.Transaction{chain_id: 42431, calls: [...], raw: "0x76..."}}

      iex> Onchain.Tempo.Transaction.deserialize("0x02" <> rlp_hex)
      {:error, "Not a Tempo transaction: expected 0x76 type prefix"}
  """
  @spec deserialize(String.t()) :: {:ok, t()} | {:error, String.t()}
  def deserialize(hex) when is_binary(hex) do
    with {:ok, binary} <- decode_hex(hex),
         {:ok, %{"transaction" => transaction} = fields} <- Codec.run("decode", %{"raw" => Codec.hex(binary)}) do
      calls = native_calls(transaction["calls"])
      {:ok, %__MODULE__{chain_id: Codec.integer(transaction["chainId"]), calls: calls, fields: fields, raw: hex}}
    end
  end

  def deserialize(_), do: {:error, "Invalid input: expected a hex string"}

  @doc """
  Find a matching payment call (transfer or transferWithMemo) in the transaction.

  Searches `tx.calls` for one targeting `currency` with the correct selector,
  then ABI-decodes and verifies recipient, amount, and optional memo.

  ## Options

    * `:amount` — (required) expected amount as string
    * `:recipient` — (required) expected recipient as hex address
    * `:memo` — (optional) bytes32 hex memo; when set, MUST match transferWithMemo
  """
  @spec find_payment_call(t(), String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def find_payment_call(%__MODULE__{calls: calls}, currency, opts) do
    expected_amount = Keyword.fetch!(opts, :amount)
    expected_recipient = Keyword.fetch!(opts, :recipient)
    memo = Keyword.get(opts, :memo)

    currency_bytes = normalize_address(currency)
    recipient_bytes = normalize_address(expected_recipient)

    with {:ok, amount_int} <- parse_amount(expected_amount) do
      result =
        Enum.find_value(calls, fn call ->
          match_call(call, currency_bytes, recipient_bytes, amount_int, memo)
        end)

      case result do
        nil when is_binary(memo) ->
          {:error, "No matching transferWithMemo call found in transaction"}

        nil ->
          {:error, "No matching transfer call found in transaction"}

        match ->
          {:ok, match}
      end
    end
  end

  @doc """
  Validate that a transaction's calls match an allowed fee-payer pattern.

  Fee-payer sponsored transactions are restricted to specific call sequences
  to prevent clients from bundling rogue calls that the server would pay gas for.

  Allowed patterns (matching mppx `callScopes`):
    * `[transfer]`
    * `[transferWithMemo]`
    * `[approve, swapExactAmountOut, transfer]`
    * `[approve, swapExactAmountOut, transferWithMemo]`

  When `approve` is present, the spender must be the stablecoin DEX.
  When `swapExactAmountOut` is present, the call target must be the stablecoin DEX.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec validate_call_scope(t()) :: :ok | {:error, String.t()}
  def validate_call_scope(%__MODULE__{calls: calls}) do
    selectors = Enum.map(calls, &extract_selector/1)

    if Enum.any?(@call_scopes, &(&1 == selectors)) do
      with :ok <- validate_approve_spender(calls, selectors) do
        validate_swap_target(calls, selectors)
      end
    else
      {:error, "disallowed call pattern in fee-payer transaction"}
    end
  end

  # --- Fee payer support ---

  @doc """
  Check if the transaction has a fee payer signature placeholder (`0x00`).

  Per spec, clients set `fee_payer_signature` to `0x00` when requesting
  server-side fee sponsorship.
  """
  @spec has_fee_payer_placeholder?(t()) :: boolean()
  def has_fee_payer_placeholder?(%__MODULE__{fields: fields}) do
    fields["placeholder"] == true
  end

  @doc """
  Check if the transaction's `fee_token` field is empty (RLP null).

  Clients leave `fee_token` empty when `feePayer: true`, allowing the
  server to choose the fee payment token.
  """
  @spec fee_token_empty?(t()) :: boolean()
  def fee_token_empty?(%__MODULE__{fields: fields}) do
    is_nil(fields["transaction"]["feeToken"])
  end

  @doc """
  Co-sign a client's transaction as fee payer and return the updated hex.

  Takes the client-signed 0x76 transaction, adds the server's fee payer
  signature (domain 0x78), injects the fee token, and returns a new
  0x76 hex string ready for broadcast.

  ## Parameters

    * `tx` — deserialized transaction with fee payer placeholder
    * `fee_payer_key` — 32-byte binary private key for fee sponsorship
    * `fee_token` — 20-byte binary TIP-20 token address for fee payment

  ## Returns

    * `{:ok, updated_tx}` — transaction with new `raw` hex for broadcast
    * `{:error, reason}` — on signing or recovery failure
  """
  @spec cosign_fee_payer(t(), binary(), binary()) :: {:ok, t()} | {:error, String.t()}
  def cosign_fee_payer(%__MODULE__{fields: fields} = tx, fee_payer_key, fee_token)
      when is_binary(fee_payer_key) and byte_size(fee_payer_key) == 32 and is_binary(fee_token) and
             byte_size(fee_token) == 20 do
    transaction = Map.put(fields["transaction"], "feeToken", Codec.hex(fee_token))

    with {:ok, sender_address} <- sender(tx),
         {:ok, hash} <- Codec.run("fee_hash", %{"transaction" => transaction, "sender" => Codec.hex(sender_address)}),
         {:ok, sig} <- Secp256k1Signer.sign_payload(Codec.bytes(hash), fee_payer_key),
         transaction =
           Map.put(transaction, "feePayerSignature", %{
             "r" => Codec.quantity(sig.r),
             "s" => Codec.quantity(sig.s),
             "yParity" => Codec.quantity(sig.recid)
           }),
         {:ok, raw} <- Codec.run("serialize", %{"transaction" => transaction, "signature" => fields["signature"]}) do
      deserialize(raw)
    end
  end

  @doc """
  Recover the sender's 20-byte address from a parsed transaction.

  Handles both self-signed and fee-payer co-signed transactions. For a
  co-signed transaction the sender signed over placeholder `fee_token` (`<<>>`)
  and `fee_payer_signature` (`<<0x00>>`) — the fee payer fills those in
  afterward — so they are reset before the signing payload is reconstructed.

  High-s encodings are accepted: `s` and the recovery bit are flipped together
  to BIP-62 low-s form before recovery, so a complement-s envelope returns the
  same address. The original `raw` is not rewritten.

  Returns `{:ok, address_binary}` or `{:error, reason}`.
  """
  @spec sender(t()) :: {:ok, binary()} | {:error, String.t()}
  def sender(%__MODULE__{fields: %{"transaction" => _, "signature" => _} = fields}) do
    with {:ok, address} <- Codec.run("sender", fields), do: {:ok, Codec.bytes(address)}
  end

  def sender(_), do: {:error, "Transaction missing fields required to recover sender"}

  @doc """
  Build an `eth_simulateV1` call request (a `TempoTransactionRequest`) from a
  co-signed transaction.

  Mirrors mpp-rs's `build_simulate_payload`: the recovered sender becomes `from`,
  and the LAST sub-call is folded into `to`/`value`/`input` (so the node does not
  read an empty `to` as a contract CREATE) while the remaining N-1 calls stay in
  `calls`. All numeric fields are hex-quantity strings; `nonceKey` and
  `validBefore` are omitted when zero.

  The single-call wire format is integration-verified against Moderato; the
  multi-call path mirrors the same per-call `{to, value, input}` shape.

  Returns `{:ok, request_map}` or `{:error, reason}`.
  """
  @spec simulate_request(t()) :: {:ok, map()} | {:error, String.t()}
  def simulate_request(%__MODULE__{calls: calls, fields: fields} = tx) do
    with {:ok, sender_addr} <- sender(tx),
         {:ok, {head_calls, tail}} <- pop_tail_call(calls) do
      {:ok, build_simulate_request(sender_addr, head_calls, tail, fields)}
    end
  end

  # --- Private: simulation helpers ---

  defp pop_tail_call([]), do: {:error, "Cannot simulate a transaction with no calls"}
  defp pop_tail_call(calls), do: {:ok, {Enum.take(calls, length(calls) - 1), List.last(calls)}}

  defp build_simulate_request(sender_addr, head_calls, tail, fields) do
    transaction = fields["transaction"]

    %{
      "from" => to_hex_data(sender_addr),
      "to" => to_hex_data(tail.to),
      "value" => to_hex_quantity(tail.value),
      "input" => to_hex_data(tail.input),
      "calls" => Enum.map(head_calls, &call_to_request/1),
      "gas" => transaction["gas"],
      "nonce" => transaction["nonce"],
      "maxFeePerGas" => transaction["maxFeePerGas"],
      "maxPriorityFeePerGas" => transaction["maxPriorityFeePerGas"],
      "chainId" => transaction["chainId"],
      "type" => "0x76",
      "feeToken" => transaction["feeToken"] || "0x"
    }
    |> maybe_put_quantity("nonceKey", Codec.integer(transaction["nonceKey"]))
    |> maybe_put_quantity("validBefore", optional_integer(transaction["validBefore"]))
  end

  defp call_to_request(%{to: to, value: value, input: input}) do
    %{"to" => to_hex_data(to), "value" => to_hex_quantity(value), "input" => to_hex_data(input)}
  end

  defp optional_integer(nil), do: 0
  defp optional_integer(value), do: Codec.integer(value)

  defp maybe_put_quantity(map, _key, 0), do: map
  defp maybe_put_quantity(map, key, value), do: Map.put(map, key, to_hex_quantity(value))

  defp to_hex_data(bin) when is_binary(bin), do: "0x" <> Base.encode16(bin, case: :lower)

  defp to_hex_quantity(0), do: "0x0"
  defp to_hex_quantity(n) when is_integer(n) and n > 0, do: "0x" <> String.downcase(Integer.to_string(n, 16))

  # --- Private: call scope validation ---

  # Extracts the 4-byte function selector from a call's input.
  defp extract_selector(%{input: <<selector::binary-size(4), _::binary>>}), do: selector
  defp extract_selector(%{input: _}), do: <<>>

  # Validates that the approve spender is the stablecoin DEX.
  defp validate_approve_spender(calls, selectors) do
    case Enum.find_index(selectors, &(&1 == @approve_selector)) do
      nil ->
        :ok

      idx ->
        call = Enum.at(calls, idx)
        validate_approve_input(call.input)
    end
  end

  # Extracts the spender address from approve calldata and validates it's the DEX.
  defp validate_approve_input(<<_selector::binary-size(4), _pad::binary-size(12), spender::binary-size(20), _::binary>>) do
    if addresses_equal?(spender, @stablecoin_dex_address), do: :ok, else: {:error, "approve spender is not the DEX"}
  end

  defp validate_approve_input(_), do: {:error, "malformed approve calldata"}

  # Validates that the swapExactAmountOut call targets the stablecoin DEX.
  defp validate_swap_target(calls, selectors) do
    case Enum.find_index(selectors, &(&1 == @swap_exact_amount_out_selector)) do
      nil ->
        :ok

      idx ->
        call = Enum.at(calls, idx)

        if addresses_equal?(call.to, @stablecoin_dex_address) do
          :ok
        else
          {:error, "buy target is not the DEX"}
        end
    end
  end

  # --- Private: hex decoding ---

  defp decode_hex("0x" <> hex), do: decode_hex_string(hex)
  defp decode_hex(hex), do: decode_hex_string(hex)

  defp decode_hex_string(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, "Invalid hex encoding"}
    end
  end

  defp native_calls(calls) do
    Enum.map(calls, fn call ->
      %{
        to: if(call["to"], do: Codec.bytes(call["to"]), else: <<>>),
        value: Codec.integer(call["value"]),
        input: Codec.bytes(call["input"])
      }
    end)
  end

  # --- Private: call matching ---

  defp match_call(%{to: to, input: input} = call, currency_bytes, recipient_bytes, amount_int, memo) do
    if addresses_equal?(to, currency_bytes) do
      case match_input(input, recipient_bytes, amount_int, memo) do
        nil -> nil
        match -> Map.put(match, :call, call)
      end
    end
  end

  defp match_input(<<@transfer_with_memo_selector, calldata::binary-size(96)>>, recipient_bytes, amount_int, memo)
       when byte_size(calldata) == 96 do
    <<_pad::binary-size(12), to::binary-size(20)>> = binary_part(calldata, 0, 32)
    <<amount::unsigned-big-size(256)>> = binary_part(calldata, 32, 32)
    <<memo_bytes::binary-size(32)>> = binary_part(calldata, 64, 32)

    cond do
      !addresses_equal?(to, recipient_bytes) -> nil
      amount != amount_int -> nil
      is_binary(memo) and !memo_matches?(memo_bytes, memo) -> nil
      true -> build_match(to, amount, memo_bytes)
    end
  end

  defp match_input(<<@transfer_selector, calldata::binary-size(64)>>, recipient_bytes, amount_int, memo)
       when byte_size(calldata) == 64 do
    if is_binary(memo) do
      nil
    else
      <<_pad::binary-size(12), to::binary-size(20), amount::unsigned-big-size(256)>> = calldata

      if addresses_equal?(to, recipient_bytes) and amount == amount_int do
        build_match(to, amount, nil)
      end
    end
  end

  defp match_input(_, _, _, _), do: nil

  defp build_match(to, amount, memo_bytes) do
    base = %{recipient: "0x" <> Base.encode16(to, case: :lower), amount: amount}

    if is_binary(memo_bytes) do
      Map.put(base, :memo, "0x" <> Base.encode16(memo_bytes, case: :lower))
    else
      base
    end
  end

  # --- Private: address utilities ---

  defp normalize_address("0x" <> hex), do: normalize_hex_address(hex)
  defp normalize_address(hex) when byte_size(hex) == 40, do: normalize_hex_address(hex)
  defp normalize_address(bin) when byte_size(bin) == 20, do: bin
  defp normalize_address(_), do: <<>>

  defp normalize_hex_address(hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, <<addr::binary-size(20)>>} -> addr
      _ -> <<>>
    end
  end

  # Constant-time address comparison (both must be 20 bytes).
  defp addresses_equal?(a, b) when byte_size(a) == 20 and byte_size(b) == 20 do
    :crypto.hash_equals(a, b)
  end

  defp addresses_equal?(_, _), do: false

  # --- Private: memo comparison ---

  defp memo_matches?(memo_bytes, expected_memo) when is_binary(memo_bytes) and byte_size(memo_bytes) == 32 do
    expected_hex = expected_memo |> strip_0x() |> String.downcase()
    actual_hex = Base.encode16(memo_bytes, case: :lower)
    expected_hex == actual_hex
  end

  defp memo_matches?(_, _), do: false

  # --- Private: numeric utilities ---

  defp parse_amount(amount) when is_binary(amount) do
    case Integer.parse(amount) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "Invalid amount: not a valid integer"}
    end
  end

  defp strip_0x("0x" <> rest), do: rest
  defp strip_0x(hex), do: hex
end
