defmodule Onchain.Tempo.Transaction do
  @moduledoc """
  Tempo Transaction (EIP-2718 type 0x76) — RLP deserialization, payment call
  matching, and fee payer co-signing (0x78 domain).

  A Tempo Transaction is an RLP-encoded envelope prefixed with `0x76`:

      0x76 || rlp([chain_id, max_priority_fee_per_gas, max_fee_per_gas, gas_limit,
                    calls, access_list, nonce_key, nonce, valid_before, valid_after,
                    fee_token, fee_payer_signature, aa_authorization_list,
                    key_authorization?, sender_signature])

  Each `call` is `rlp([to, value, input])`.

  This module extracts the fields needed for payment verification (`chain_id`,
  `calls`) and preserves the full serialized hex as `raw` for broadcast
  passthrough. When fee payer mode is enabled, it co-signs the transaction
  with a server-side key using the 0x78 domain separator.

  ## Dependencies

  Uses `ExRLP` (available transitively via `cartouche` → `onchain`) for RLP
  decoding. Signing uses `Cartouche.Signer.Curvy` and `Cartouche.Recover`
  directly because Tempo 0x76 is a non-standard transaction type.
  """

  alias Cartouche.Recover
  alias Cartouche.Signer.Curvy, as: CurvySigner
  alias Curvy.Signature, as: CurvySig
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
          fields: [term()],
          raw: String.t()
        }

  @typedoc "A single call within the transaction's batch."
  @type call :: %{to: binary(), value: non_neg_integer(), input: binary()}

  # EIP-2718 type byte for Tempo Transactions.
  @tempo_tx_type 0x76

  # RLP field index for `calls` in the 0x76 envelope (see spec).
  @calls_index 4

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
         {:ok, rlp_body} <- strip_type_prefix(binary),
         {:ok, fields} <- rlp_decode(rlp_body),
         {:ok, chain_id} <- extract_chain_id(fields),
         {:ok, calls} <- extract_calls(fields) do
      {:ok, %__MODULE__{chain_id: chain_id, calls: calls, fields: fields, raw: hex}}
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

  # 0x76 RLP field indices.
  @fee_token_index 10
  @fee_payer_sig_index 11

  # Fee payer signing domain prefix (distinct from 0x76 sender domain).
  @fee_payer_domain 0x78

  @doc """
  Check if the transaction has a fee payer signature placeholder (`0x00`).

  Per spec, clients set `fee_payer_signature` to `0x00` when requesting
  server-side fee sponsorship.
  """
  @spec has_fee_payer_placeholder?(t()) :: boolean()
  def has_fee_payer_placeholder?(%__MODULE__{fields: fields}) do
    fee_payer_sig = Enum.at(fields, @fee_payer_sig_index)
    fee_payer_sig == <<0x00>>
  end

  @doc """
  Check if the transaction's `fee_token` field is empty (RLP null).

  Clients leave `fee_token` empty when `feePayer: true`, allowing the
  server to choose the fee payment token.
  """
  @spec fee_token_empty?(t()) :: boolean()
  def fee_token_empty?(%__MODULE__{fields: fields}) do
    fee_token = Enum.at(fields, @fee_token_index)
    fee_token == <<>> or fee_token == []
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
  @dialyzer {:nowarn_function, cosign_fee_payer: 3}
  @spec cosign_fee_payer(t(), binary(), binary()) :: {:ok, t()} | {:error, String.t()}
  def cosign_fee_payer(%__MODULE__{fields: fields} = tx, fee_payer_key, fee_token)
      when is_binary(fee_payer_key) and byte_size(fee_payer_key) == 32 and is_binary(fee_token) and
             byte_size(fee_token) == 20 do
    sender_sig_raw = List.last(fields)
    {base_fields, has_key_auth} = split_base_fields(fields)

    client_signing_payload = <<@tempo_tx_type>> <> rlp_encode(base_fields)

    with {:ok, sender_address} <- recover_sender(client_signing_payload, sender_sig_raw) do
      fp_preimage_fields = build_fee_payer_preimage_fields(base_fields, fee_token, sender_address, has_key_auth)
      fp_signing_payload = <<@fee_payer_domain>> <> rlp_encode(fp_preimage_fields)

      with {:ok, fp_sig} <- CurvySigner.sign(fp_signing_payload, fee_payer_key),
           {:ok, fp_address} <- CurvySigner.get_address(fee_payer_key),
           {:ok, fp_recid} <- Recover.find_recid(fp_signing_payload, fp_sig, fp_address) do
        fp_sig_tuple = [
          if(fp_recid == 1, do: <<1>>, else: <<>>),
          :binary.encode_unsigned(fp_sig.r),
          :binary.encode_unsigned(fp_sig.s)
        ]

        signed_fields =
          base_fields
          |> List.replace_at(@fee_token_index, fee_token)
          |> List.replace_at(@fee_payer_sig_index, fp_sig_tuple)
          |> Kernel.++([sender_sig_raw])

        signed_raw = <<@tempo_tx_type>> <> rlp_encode(signed_fields)
        new_hex = "0x" <> Base.encode16(signed_raw, case: :lower)

        {:ok, %{tx | raw: new_hex, fields: signed_fields}}
      end
    end
  end

  # --- Simulation support ---

  # 0x76 RLP field indices used to reconstruct an `eth_simulateV1` call request.
  @chain_id_index 0
  @max_priority_fee_index 1
  @max_fee_index 2
  @gas_limit_index 3
  @nonce_key_index 6
  @nonce_index 7
  @valid_before_index 8

  # Field count of a full transaction without the optional key_authorization
  # field (14 = 13 base fields + sender_signature).
  @min_field_count_without_key_auth 14

  @doc """
  Recover the sender's 20-byte address from a parsed transaction.

  Handles both self-signed and fee-payer co-signed transactions. For a
  co-signed transaction the sender signed over placeholder `fee_token` (`<<>>`)
  and `fee_payer_signature` (`<<0x00>>`) — the fee payer fills those in
  afterward — so they are reset before the signing payload is reconstructed.

  Returns `{:ok, address_binary}` or `{:error, reason}`.
  """
  @dialyzer {:nowarn_function, sender: 1}
  @spec sender(t()) :: {:ok, binary()} | {:error, String.t()}
  def sender(%__MODULE__{fields: fields}) when is_list(fields) and length(fields) >= @min_field_count_without_key_auth do
    # One traversal splits off the trailing sender signature; the guard already
    # proved the list is non-empty, so the `[sig]` tail always matches.
    {base_fields, [sender_sig_raw]} = Enum.split(fields, -1)
    signing_payload = <<@tempo_tx_type>> <> rlp_encode(reset_fee_payer_placeholders(base_fields))
    recover_sender(signing_payload, sender_sig_raw)
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

  # Resets the fee-token and fee-payer-signature positions to the placeholders
  # the sender signed over, but only for a co-signed transaction (fee-payer
  # signature is the decoded `[recid, r, s]` list). Self-signed transactions
  # (fee-payer signature is `<<>>`) are left untouched.
  defp reset_fee_payer_placeholders(base_fields) do
    if is_list(Enum.at(base_fields, @fee_payer_sig_index)) do
      base_fields
      |> List.replace_at(@fee_token_index, <<>>)
      |> List.replace_at(@fee_payer_sig_index, <<0x00>>)
    else
      base_fields
    end
  end

  defp pop_tail_call([]), do: {:error, "Cannot simulate a transaction with no calls"}
  defp pop_tail_call(calls), do: {:ok, {Enum.take(calls, length(calls) - 1), List.last(calls)}}

  defp build_simulate_request(sender_addr, head_calls, tail, fields) do
    %{
      "from" => to_hex_data(sender_addr),
      "to" => to_hex_data(tail.to),
      "value" => to_hex_quantity(tail.value),
      "input" => to_hex_data(tail.input),
      "calls" => Enum.map(head_calls, &call_to_request/1),
      "gas" => field_quantity(fields, @gas_limit_index),
      "nonce" => field_quantity(fields, @nonce_index),
      "maxFeePerGas" => field_quantity(fields, @max_fee_index),
      "maxPriorityFeePerGas" => field_quantity(fields, @max_priority_fee_index),
      "chainId" => field_quantity(fields, @chain_id_index),
      "type" => "0x76",
      "feeToken" => to_hex_data(field_bytes(fields, @fee_token_index))
    }
    |> maybe_put_quantity("nonceKey", field_int(fields, @nonce_key_index))
    |> maybe_put_quantity("validBefore", field_int(fields, @valid_before_index))
  end

  defp call_to_request(%{to: to, value: value, input: input}) do
    %{"to" => to_hex_data(to), "value" => to_hex_quantity(value), "input" => to_hex_data(input)}
  end

  defp field_bytes(fields, idx) do
    case Enum.at(fields, idx) do
      bin when is_binary(bin) -> bin
      _ -> <<>>
    end
  end

  defp field_int(fields, idx), do: decode_unsigned(field_bytes(fields, idx))
  defp field_quantity(fields, idx), do: to_hex_quantity(field_int(fields, idx))

  defp maybe_put_quantity(map, _key, 0), do: map
  defp maybe_put_quantity(map, key, value), do: Map.put(map, key, to_hex_quantity(value))

  defp to_hex_data(bin) when is_binary(bin), do: "0x" <> Base.encode16(bin, case: :lower)

  defp to_hex_quantity(0), do: "0x0"
  defp to_hex_quantity(n) when is_integer(n) and n > 0, do: "0x" <> String.downcase(Integer.to_string(n, 16))

  # --- Private: fee payer helpers ---

  # Splits the fields list into base fields (everything before sender_signature)
  # and a flag indicating if key_authorization is present.
  defp split_base_fields(fields) do
    total = length(fields)
    base = Enum.take(fields, total - 1)
    has_key_auth = total > @min_field_count_without_key_auth
    {base, has_key_auth}
  end

  # Builds the RLP field list for the fee payer signing preimage (0x78 domain).
  defp build_fee_payer_preimage_fields(base_fields, fee_token, sender_address, _has_key_auth) do
    base_fields
    |> List.replace_at(@fee_token_index, fee_token)
    |> List.replace_at(@fee_payer_sig_index, sender_address)
  end

  # Recovers the sender's 20-byte Ethereum address from the signing payload and raw signature bytes.
  @dialyzer {:nowarn_function, recover_sender: 2}
  defp recover_sender(signing_payload, <<r::unsigned-big-size(256), s::unsigned-big-size(256), v::8>>) do
    recid = if v >= 27, do: v - 27, else: v
    sig = %CurvySig{crv: :secp256k1, r: r, s: s, recid: recid}
    {:ok, Recover.recover_eth(signing_payload, sig)}
  rescue
    # Narrowed to the failure modes a malformed *signature* actually produces:
    # RuntimeError ("Recovery ID not in range 0..3"), FunctionClauseError
    # (r/s off the curve, from Curvy.Key.from_point/2), plus the ArgumentError /
    # ErlangError the crypto NIFs raise on bad operands. Anything else is a bug
    # in our own code and must crash rather than be relabelled a recovery
    # failure — a bare rescue here previously turned an UndefinedFunctionError
    # into "Failed to recover sender: ...".
    e in [RuntimeError, FunctionClauseError, ArgumentError, ErlangError, MatchError] ->
      {:error, "Failed to recover sender: #{Exception.message(e)}"}
  end

  defp recover_sender(_signing_payload, _sig_bytes) do
    {:error, "Invalid sender signature format: expected 65 bytes (r, s, v)"}
  end

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

  # --- Private: type prefix ---

  defp strip_type_prefix(<<@tempo_tx_type, rlp_body::binary>>), do: {:ok, rlp_body}

  defp strip_type_prefix(<<prefix, _::binary>>) do
    {:error, "Not a Tempo transaction: expected 0x76 type prefix, got 0x#{Integer.to_string(prefix, 16)}"}
  end

  defp strip_type_prefix(<<>>), do: {:error, "Empty transaction data"}

  # --- Private: RLP ---

  @dialyzer {:nowarn_function, [rlp_decode: 1, rlp_encode: 1]}
  defp rlp_decode(binary) do
    {:ok, ExRLP.decode(binary)}
  rescue
    # ExRLP raises DecodeError for most malformed input and MatchError for
    # truncated multi-byte length prefixes; ArgumentError / FunctionClauseError
    # cover the remaining binary-primitive failures. Narrowed deliberately so a
    # bug in our own decode path surfaces instead of being reported as
    # untrusted-input corruption.
    _ in [ExRLP.DecodeError, MatchError, ArgumentError, FunctionClauseError] ->
      {:error, "Failed to RLP-decode transaction"}
  end

  defp rlp_encode(data), do: ExRLP.encode(data)

  # --- Private: field extraction ---

  defp extract_chain_id([chain_id_bin | _]) when is_binary(chain_id_bin) do
    {:ok, decode_unsigned(chain_id_bin)}
  end

  defp extract_chain_id(_), do: {:error, "Missing or invalid chain_id field"}

  defp extract_calls(fields) when is_list(fields) and length(fields) > @calls_index do
    raw_calls = Enum.at(fields, @calls_index)

    if is_list(raw_calls) do
      if raw_calls == [] do
        {:error, "Calls list cannot be empty"}
      else
        parse_all_calls(raw_calls, [], 0)
      end
    else
      {:error, "Invalid calls field: expected a list"}
    end
  end

  defp extract_calls(_), do: {:error, "Transaction too short: missing calls field"}

  defp parse_all_calls([], acc, _idx), do: {:ok, Enum.reverse(acc)}

  defp parse_all_calls([raw | rest], acc, idx) do
    case parse_call(raw) do
      {:ok, call} -> parse_all_calls(rest, [call | acc], idx + 1)
      :error -> {:error, "Malformed call at index #{idx}: expected [to, value, input]"}
    end
  end

  defp parse_call([to, value, input]) when is_binary(to) and is_binary(value) and is_binary(input) do
    {:ok, %{to: to, value: decode_unsigned(value), input: input}}
  end

  defp parse_call([to, value]) when is_binary(to) and is_binary(value) do
    {:ok, %{to: to, value: decode_unsigned(value), input: <<>>}}
  end

  defp parse_call(_), do: :error

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

  defp decode_unsigned(<<>>), do: 0
  defp decode_unsigned(bin) when is_binary(bin), do: :binary.decode_unsigned(bin)

  defp parse_amount(amount) when is_binary(amount) do
    case Integer.parse(amount) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "Invalid amount: not a valid integer"}
    end
  end

  defp strip_0x("0x" <> rest), do: rest
  defp strip_0x(hex), do: hex
end
