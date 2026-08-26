defmodule Onchain.Tempo.Verification.SpecEncoder do
  @moduledoc false

  # Independent of Onchain.Tempo.Transaction field-index attributes.
  # Order is the provider spec's named RLP list
  # (docs.tempo.xyz protocol/transactions/spec-tempo-transaction).
  @sender_type 0x76
  @fee_payer_type 0x78

  @spec_order [
    :chain_id,
    :max_priority_fee_per_gas,
    :max_fee_per_gas,
    :gas_limit,
    :calls,
    :access_list,
    :nonce_key,
    :nonce,
    :valid_before,
    :valid_after,
    :fee_token,
    :fee_payer_signature,
    :aa_authorization_list
  ]

  @type field_map :: %{optional(atom()) => term()}

  @spec sender_payload(field_map()) :: binary()
  def sender_payload(fields) when is_map(fields) do
    <<@sender_type>> <> ExRLP.encode(rlp_items(fields, :sender))
  end

  @spec fee_payer_payload(field_map(), binary()) :: binary()
  def fee_payer_payload(fields, sender) when is_map(fields) and byte_size(sender) == 20 do
    items =
      fields
      |> Map.put(:fee_payer_signature, sender)
      |> rlp_items(:fee_payer)

    <<@fee_payer_type>> <> ExRLP.encode(items)
  end

  @spec signed_envelope(field_map(), binary()) :: binary()
  def signed_envelope(fields, signature) when is_binary(signature) do
    <<@sender_type>> <> ExRLP.encode(rlp_items(fields, :sender) ++ [signature])
  end

  @spec to_hex(binary()) :: String.t()
  def to_hex(bin) when is_binary(bin), do: "0x" <> Base.encode16(bin, case: :lower)

  @spec secp256k1_sig(non_neg_integer(), non_neg_integer(), 0 | 1) :: binary()
  def secp256k1_sig(r, s, y_parity) when y_parity in [0, 1] do
    <<r::unsigned-big-size(256), s::unsigned-big-size(256), y_parity + 27::8>>
  end

  @spec fee_payer_tuple(0 | 1, non_neg_integer(), non_neg_integer()) :: [binary()]
  def fee_payer_tuple(y_parity, r, s) when y_parity in [0, 1] do
    [if(y_parity == 1, do: <<1>>, else: <<>>), quantity(r), quantity(s)]
  end

  @spec spec_order() :: [atom()]
  def spec_order, do: @spec_order

  @spec sender_type() :: 0x76
  def sender_type, do: @sender_type

  @spec fee_payer_type() :: 0x78
  def fee_payer_type, do: @fee_payer_type

  defp rlp_items(fields, mode) do
    Enum.map(@spec_order, &encode_named(&1, fields, mode))
  end

  defp encode_named(:calls, fields, _mode), do: encode_calls(Map.get(fields, :calls, []))
  defp encode_named(:access_list, fields, _mode), do: Map.get(fields, :access_list, [])

  defp encode_named(:aa_authorization_list, fields, _mode) do
    Map.get(fields, :aa_authorization_list, [])
  end

  defp encode_named(:fee_token, fields, :sender) do
    case {Map.get(fields, :fee_payer?), Map.get(fields, :fee_token, <<>>)} do
      {true, _} -> <<>>
      {_, token} -> token_bytes(token)
    end
  end

  defp encode_named(:fee_token, fields, :fee_payer), do: token_bytes(Map.get(fields, :fee_token, <<>>))

  defp encode_named(:fee_payer_signature, fields, :sender) do
    if Map.get(fields, :fee_payer?), do: <<0x00>>, else: <<>>
  end

  defp encode_named(:fee_payer_signature, fields, :fee_payer) do
    Map.fetch!(fields, :fee_payer_signature)
  end

  defp encode_named(name, fields, _mode), do: quantity(Map.get(fields, name, 0))

  defp encode_calls(calls) do
    Enum.map(calls, fn
      %{to: to, value: value, input: input} -> [to, quantity(value), input]
      [to, value, input] -> [to, value, input]
    end)
  end

  defp token_bytes(<<>>), do: <<>>
  defp token_bytes(token) when is_binary(token), do: token

  defp quantity(0), do: <<>>
  defp quantity(n) when is_integer(n) and n > 0, do: :binary.encode_unsigned(n)
  defp quantity(bin) when is_binary(bin), do: bin
end
