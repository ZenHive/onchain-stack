defmodule Onchain.Tempo.Verification.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Onchain.Tempo.TestHelpers

  alias Onchain.Tempo.TIP20
  alias Onchain.Tempo.Transaction
  alias Onchain.Tempo.Transaction.Builder
  alias Onchain.Tempo.Verification.SpecEncoder

  @moduletag :verification

  @token Base.decode16!("20c0000000000000000000000000000000000000", case: :lower)
  @recipient Base.decode16!("70997970c51812dc3a010c7d01b50e0d17dc79c8", case: :lower)
  @priv "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

  test "every named 0x76 field is present in the spec order used for canonical encoding" do
    assert SpecEncoder.spec_order() == [
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
  end

  property "deserialize round-trips every named 0x76 field of a spec-encoded envelope" do
    check all(fields <- field_map_gen(), max_runs: 40) do
      dummy = SpecEncoder.secp256k1_sig(1, 2, 0)
      hex = SpecEncoder.to_hex(SpecEncoder.signed_envelope(fields, dummy))

      assert {:ok, tx} = Transaction.deserialize(hex)
      assert_round_tripped(tx, fields, dummy)
    end
  end

  test "unsigned spec envelope has one RLP item per named field and omits optional key_authorization" do
    fields = %{
      chain_id: 1,
      max_priority_fee_per_gas: 0,
      max_fee_per_gas: 1,
      gas_limit: 21_000,
      calls: [%{to: @token, value: 0, input: <<>>}],
      access_list: [],
      nonce_key: 0,
      nonce: 0,
      valid_before: 0,
      valid_after: 0,
      fee_token: @token,
      fee_payer?: false,
      aa_authorization_list: []
    }

    <<0x76, rlp::binary>> = SpecEncoder.sender_payload(fields)
    items = ExRLP.decode(rlp)
    assert is_list(items)
    assert items != []
    assert length(items) == length(SpecEncoder.spec_order())
  end

  property "mutating any spec-order scalar field changes the canonical sender payload" do
    check all({fields, name, new_val} <- scalar_mutation_gen(), max_runs: 40) do
      original = SpecEncoder.sender_payload(fields)
      mutated = SpecEncoder.sender_payload(Map.put(fields, name, new_val))
      assert original != mutated
    end
  end

  property "distinct access lists, fee-payer markers and call payloads produce distinct encodings" do
    check all(fields <- field_map_gen(), max_runs: 20) do
      other_access = [[<<1::160>>, [<<2::256>>]]]

      if fields.access_list != other_access do
        refute SpecEncoder.sender_payload(fields) ==
                 SpecEncoder.sender_payload(Map.put(fields, :access_list, other_access))
      end

      refute SpecEncoder.sender_payload(fields) ==
               SpecEncoder.sender_payload(Map.put(fields, :fee_payer?, not fields.fee_payer?))

      other_call = %{to: <<3::160>>, value: 1, input: <<4>>}

      if hd(fields.calls) != other_call do
        refute SpecEncoder.sender_payload(fields) ==
                 SpecEncoder.sender_payload(Map.put(fields, :calls, [other_call]))
      end

      if fields.aa_authorization_list != [[<<0xAA>>]] do
        refute SpecEncoder.sender_payload(fields) ==
                 SpecEncoder.sender_payload(Map.put(fields, :aa_authorization_list, [[<<0xAA>>]]))
      end
    end
  end

  property "sender domain 0x76 and fee-payer domain 0x78 never share a preimage" do
    check all(fields <- field_map_gen(), max_runs: 20) do
      sender = :crypto.strong_rand_bytes(20)
      left = SpecEncoder.sender_payload(Map.put(fields, :fee_payer?, true))
      right = SpecEncoder.fee_payer_payload(Map.put(fields, :fee_payer?, true), sender)
      assert <<0x76, _::binary>> = left
      assert <<0x78, _::binary>> = right
      assert left != right
    end
  end

  property "Builder signed envelopes deserialize and recover the secp256k1 signer" do
    check all({nonce, gas, amount, nonce_key} <- builder_params_gen(), max_runs: 15) do
      {:ok, hex} =
        Builder.build_signed_transfer(
          private_key: @priv,
          token: @token,
          recipient: @recipient,
          amount: amount,
          chain_id: 42_431,
          rpc_url: "http://localhost",
          nonce: nonce,
          nonce_key: nonce_key,
          gas_limit: gas,
          fee_token: @token,
          valid_before: 0,
          valid_after: 0
        )

      assert String.starts_with?(hex, "0x76")
      assert {:ok, tx} = Transaction.deserialize(hex)
      assert {:ok, sender} = Transaction.sender(tx)
      {:ok, expected} = Cartouche.Signer.Curvy.get_address(Base.decode16!(String.trim_leading(@priv, "0x"), case: :lower))
      assert sender == expected
      assert tx.chain_id == 42_431
      assert Enum.at(tx.fields, 3) == quantity_bin(gas)
      assert Enum.at(tx.fields, 6) == quantity_bin(nonce_key)
      assert Enum.at(tx.fields, 7) == quantity_bin(nonce)
    end
  end

  property "spec-encoded RLP quantities are canonical (zero is empty, no leading zero)" do
    check all(fields <- field_map_gen(), max_runs: 40) do
      <<0x76, rlp::binary>> = SpecEncoder.sender_payload(fields)
      items = ExRLP.decode(rlp)

      Enum.each([0, 1, 2, 3, 6, 7, 8, 9], fn idx ->
        bin = Enum.at(items, idx)
        assert is_binary(bin)
        refute match?(<<0, _::binary>>, bin)
      end)
    end
  end

  property "deserialize never raises on malformed input" do
    check all(
            payload <-
              StreamData.one_of([
                StreamData.binary(max_length: 48),
                StreamData.map(StreamData.binary(max_length: 48), fn bin ->
                  "0x" <> Base.encode16(bin, case: :lower)
                end),
                StreamData.member_of(["", "0x", "0x76", "0x76ff", "0x02aa", "not-hex", "0x76zz"]),
                StreamData.integer(0..32)
              ]),
            max_runs: 40
          ) do
      result = Transaction.deserialize(payload)
      assert match?({:error, msg} when is_binary(msg), result) or match?({:ok, %Transaction{}}, result)
    end
  end

  test "malformed inputs are rejected without raising" do
    assert {:error, _} = Transaction.deserialize("0x02aa")
    assert {:error, _} = Transaction.deserialize("0x76ff")
    assert {:error, _} = Transaction.deserialize("0x")
    assert {:error, _} = Transaction.deserialize("not-hex")
    assert {:error, _} = Transaction.deserialize(123)
    assert {:error, msg} = Transaction.deserialize(build_tempo_tx(calls: []))
    assert msg =~ "empty"
  end

  test "boundary-sized integers encode and decode" do
    fields = %{
      chain_id: 1,
      max_priority_fee_per_gas: 1,
      max_fee_per_gas: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
      gas_limit: 0xFFFFFFFFFFFFFFFF,
      calls: [%{to: <<1::160>>, value: 1, input: <<>>}],
      nonce_key: 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
      nonce: 0xFFFFFFFFFFFFFFFF,
      valid_before: 4_102_444_800,
      valid_after: 1,
      fee_token: <<0xFF::160>>,
      fee_payer?: false
    }

    hex =
      SpecEncoder.to_hex(
        SpecEncoder.signed_envelope(fields, <<3::unsigned-big-size(256), 4::unsigned-big-size(256), 28>>)
      )

    assert {:ok, tx} = Transaction.deserialize(hex)
    assert tx.chain_id == 1
    assert :binary.decode_unsigned(Enum.at(tx.fields, 2)) == fields.max_fee_per_gas
    assert :binary.decode_unsigned(Enum.at(tx.fields, 3)) == fields.gas_limit
    assert :binary.decode_unsigned(Enum.at(tx.fields, 6)) == fields.nonce_key
    assert :binary.decode_unsigned(Enum.at(tx.fields, 7)) == fields.nonce
    assert :binary.decode_unsigned(Enum.at(tx.fields, 8)) == fields.valid_before
    assert Enum.at(tx.fields, 10) == fields.fee_token
  end

  test "empty vs 20-byte fee_token and 0x00 vs empty fee-payer marker are distinct encodings" do
    base = %{
      chain_id: 42_431,
      max_priority_fee_per_gas: 1,
      max_fee_per_gas: 1,
      gas_limit: 21_000,
      calls: [%{to: @token, value: 0, input: TIP20.transfer_calldata(@recipient, 1)}],
      nonce_key: 0,
      nonce: 0,
      valid_before: 0,
      valid_after: 0
    }

    self_paid = SpecEncoder.sender_payload(Map.merge(base, %{fee_token: @token, fee_payer?: false}))
    placeholder = SpecEncoder.sender_payload(Map.put(base, :fee_payer?, true))
    refute self_paid == placeholder
    assert :binary.part(placeholder, 0, 1) == <<0x76>>
  end

  defp field_map_gen do
    gen all(
          chain_id <- uint_gen(),
          prio <- uint_gen(),
          max_fee <- StreamData.integer(1..1_000_000_000_000),
          gas <- StreamData.integer(21_000..2_000_000),
          nonce <- uint_gen(),
          nonce_key <- uint_gen(),
          valid_before <- uint_gen(),
          valid_after <- uint_gen(),
          to <- StreamData.binary(length: 20),
          value <- uint_gen(),
          input <- StreamData.binary(min_length: 0, max_length: 32),
          fee_payer? <- StreamData.boolean(),
          access_list <- access_list_gen(),
          aa <- aa_list_gen()
        ) do
      %{
        chain_id: chain_id,
        max_priority_fee_per_gas: prio,
        max_fee_per_gas: max_fee,
        gas_limit: gas,
        calls: [%{to: to, value: value, input: input}],
        access_list: access_list,
        nonce_key: nonce_key,
        nonce: nonce,
        valid_before: valid_before,
        valid_after: valid_after,
        fee_token: @token,
        fee_payer?: fee_payer?,
        aa_authorization_list: aa
      }
    end
  end

  defp access_list_gen do
    StreamData.one_of([
      StreamData.constant([]),
      gen all(
            addr <- StreamData.binary(length: 20),
            key <- StreamData.binary(length: 32)
          ) do
        [[addr, [key]]]
      end
    ])
  end

  defp aa_list_gen do
    StreamData.one_of([
      StreamData.constant([]),
      StreamData.constant([[<<0xAA, 0xBB>>]])
    ])
  end

  defp scalar_mutation_gen do
    gen all(
          fields <- field_map_gen(),
          name <-
            StreamData.member_of([
              :chain_id,
              :max_priority_fee_per_gas,
              :max_fee_per_gas,
              :gas_limit,
              :nonce,
              :nonce_key,
              :valid_before,
              :valid_after
            ]),
          new_val <- uint_gen(),
          new_val != Map.fetch!(fields, name)
        ) do
      {fields, name, new_val}
    end
  end

  defp builder_params_gen do
    gen all(
          nonce <- StreamData.integer(0..50),
          gas <- StreamData.member_of([21_000, 100_000, 500_000]),
          amount <- StreamData.integer(1..1_000_000),
          nonce_key <- StreamData.integer(0..3)
        ) do
      {nonce, gas, amount, nonce_key}
    end
  end

  defp uint_gen do
    StreamData.one_of([
      StreamData.constant(0),
      StreamData.integer(1..255),
      StreamData.integer(256..65_535),
      StreamData.constant(0xFFFFFFFFFFFFFFFF)
    ])
  end

  defp assert_round_tripped(tx, fields, dummy) do
    q = &quantity_bin/1
    assert tx.chain_id == fields.chain_id
    assert Enum.at(tx.fields, 0) == q.(fields.chain_id)
    assert Enum.at(tx.fields, 1) == q.(fields.max_priority_fee_per_gas)
    assert Enum.at(tx.fields, 2) == q.(fields.max_fee_per_gas)
    assert Enum.at(tx.fields, 3) == q.(fields.gas_limit)
    assert length(tx.calls) == length(fields.calls)
    assert hd(tx.calls).to == hd(fields.calls).to
    assert hd(tx.calls).value == hd(fields.calls).value
    assert hd(tx.calls).input == hd(fields.calls).input
    assert Enum.at(tx.fields, 5) == fields.access_list
    assert Enum.at(tx.fields, 6) == q.(fields.nonce_key)
    assert Enum.at(tx.fields, 7) == q.(fields.nonce)
    assert Enum.at(tx.fields, 8) == q.(fields.valid_before)
    assert Enum.at(tx.fields, 9) == q.(fields.valid_after)
    expected_token = if fields.fee_payer?, do: <<>>, else: fields.fee_token
    assert Enum.at(tx.fields, 10) == expected_token
    expected_fp = if fields.fee_payer?, do: <<0x00>>, else: <<>>
    assert Enum.at(tx.fields, 11) == expected_fp
    assert Enum.at(tx.fields, 12) == fields.aa_authorization_list
    assert List.last(tx.fields) == dummy
  end

  defp quantity_bin(0), do: <<>>
  defp quantity_bin(n) when is_integer(n) and n > 0, do: :binary.encode_unsigned(n)
end
