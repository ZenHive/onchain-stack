defmodule Cartouche.Transaction.BeforeAlloyTest do
  use ExUnit.Case, async: true

  alias Cartouche.Transaction
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2
  alias Cartouche.Transaction.V3
  alias Cartouche.Transaction.V4
  alias Cartouche.Transaction.V_2930

  @fixture Path.expand("../../support/fixtures/transactions_before_alloy.etf", __DIR__)
  @external_resource @fixture
  @records @fixture |> File.read!() |> :erlang.binary_to_term()
  @modules [V1, V_2930, V2, V3, V4]
  @operations [
    :encode,
    :decode,
    :from_json,
    :hash,
    :hash_struct,
    :encode_type,
    :domain_seperator,
    :encode_data_value,
    :authorization_signing_payload,
    :authorization_hash
  ]
  @widths [
    nonce: 64,
    gas_limit: 64,
    chain_id: 64,
    gas_price: 128,
    max_priority_fee_per_gas: 128,
    max_fee_per_gas: 128,
    max_fee_per_blob_gas: 128,
    value: 256,
    amount: 256
  ]

  test "all captured calls retain their outcome, except explicitly rejected wire inputs" do
    results =
      for {record, index} <- Enum.with_index(@records), elem(record, 1) in @operations do
        {module, function, args, kind, expected} = record
        actual = outcome(fn -> apply(module, function, args) end)
        change = changed_contract(module, function, args, expected)

        matches =
          case change do
            {:encode_bound, field, width} ->
              match?({:exception, :error, %ArgumentError{}}, actual) and
                elem(actual, 2).message =~ "#{field} must be in 0..2^#{width}-1"

            :encode_invalid ->
              match?({:exception, :error, %ArgumentError{}}, actual)

            :decode_invalid ->
              actual == {:return_from, {:error, invalid(module)}}

            nil when kind == :return_from ->
              actual == {:return_from, expected}

            nil ->
              exception_matches?(actual, expected)
          end

        {matches, index, change, {module, function, args}, expected, actual}
      end

    counts = Enum.frequencies_by(results, &elem(&1, 2))
    {bounds, rest} = Enum.split_with(counts, &match?({{:encode_bound, _, _}, _}, &1))
    assert Enum.sum(for {_key, count} <- bounds, do: count) == 618
    assert Map.new(rest) == %{nil => 536, encode_invalid: 1, decode_invalid: 620}
    mismatches = Enum.reject(results, &elem(&1, 0))

    assert mismatches == [],
           "#{length(mismatches)} mismatches; first 8: #{inspect(Enum.take(mismatches, 8), limit: :infinity)}"
  end

  test "captured transaction bytes, signing hashes, transaction hashes and round trips" do
    for {module, :encode, [tx], :return_from, bytes} <- @records, module in @modules do
      case changed_contract(module, :encode, [tx], bytes) do
        nil ->
          assert Transaction.encode(tx) == bytes
          assert Cartouche.Hash.keccak(Transaction.encode(tx)) == Cartouche.Hash.keccak(bytes)
          assert {:ok, decoded} = Transaction.decode(bytes)
          assert Transaction.encode(decoded) == bytes
          if unsigned?(tx), do: assert(Transaction.Native.signing_hash(tx) == Cartouche.Hash.keccak(bytes))

        _ ->
          assert_raise ArgumentError, fn -> Transaction.encode(tx) end
          assert {:error, _} = Transaction.decode(bytes)
      end
    end
  end

  defp changed_contract(module, function, [tx], _)
       when module in @modules and function in [:encode, :hash] and is_map(tx) do
    case bound(tx) do
      nil -> if module == V3 and tx.destination == <<>>, do: :encode_invalid
      {field, width} -> {:encode_bound, field, width}
    end
  end

  defp changed_contract(module, :decode, [bytes], {:ok, tx}) when module in @modules do
    if bound(tx) || noncanonical?(bytes), do: :decode_invalid
  end

  defp changed_contract(_, _, _, _), do: nil

  defp bound(tx) do
    fields = if match?(%V1{}, tx), do: Map.put(tx, :chain_id, legacy_chain_id(tx)), else: tx

    Enum.find(@widths, fn {field, width} ->
      case Map.fetch(fields, field) do
        {:ok, value} -> not is_integer(value) or value < 0 or value >= Integer.pow(2, width)
        :error -> false
      end
    end)
  end

  defp legacy_chain_id(%V1{r: 0, s: 0, v: v}), do: v
  defp legacy_chain_id(%V1{v: v}) when v >= 35, do: div(v - 35, 2)
  defp legacy_chain_id(_), do: 0

  # Independent wire inspection, confined to the test oracle. Leading-zero RLP
  # integers accepted by the old decoder are rejected by alloy's canonical decoder.
  defp noncanonical?(<<type, body::binary>>) when type in 1..4 do
    fields = ExRLP.decode(body)
    excluded = if type == 1, do: [4, 6, 7], else: [5, 7, 8, 10]

    scalar_zero? =
      fields |> Enum.with_index() |> Enum.any?(fn {value, index} -> index not in excluded and leading_zero?(value) end)

    auth_zero? =
      type == 4 and
        Enum.any?(Enum.at(fields, 9), fn auth ->
          auth |> Enum.with_index() |> Enum.any?(fn {value, index} -> index != 1 and leading_zero?(value) end)
        end)

    scalar_zero? or auth_zero?
  end

  defp noncanonical?(bytes) do
    bytes
    |> ExRLP.decode()
    |> Enum.with_index()
    |> Enum.any?(fn {value, index} -> index not in [3, 5] and leading_zero?(value) end)
  end

  defp leading_zero?(<<0, _::binary>>), do: true
  defp leading_zero?(_), do: false

  defp invalid(V1), do: "invalid legacy transaction"
  defp invalid(V_2930), do: "invalid v2930 transaction"
  defp invalid(V2), do: "invalid v2 transaction"
  defp invalid(V3), do: "invalid v3 transaction"
  defp invalid(V4), do: "invalid v4 transaction"
  defp unsigned?(%V1{r: r, s: s}), do: r == 0 and s == 0
  defp unsigned?(tx), do: is_nil(tx.signature_y_parity) or is_nil(tx.signature_r) or is_nil(tx.signature_s)

  defp exception_matches?({:exception, kind, reason}, {kind, expected}) do
    Exception.normalize(kind, reason).__struct__ == Exception.normalize(kind, expected).__struct__
  end

  defp exception_matches?(_, _), do: false

  defp outcome(fun) do
    {:return_from, fun.()}
  catch
    kind, reason -> {:exception, kind, reason}
  end
end
