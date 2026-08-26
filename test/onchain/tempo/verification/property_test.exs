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

  property "deserialize round-trips every field of a spec-encoded envelope" do
    check all(fields <- field_map_gen(), max_runs: 40) do
      dummy = <<1::unsigned-big-size(256), 2::unsigned-big-size(256), 27>>
      hex = SpecEncoder.to_hex(SpecEncoder.signed_envelope(fields, dummy))

      assert {:ok, tx} = Transaction.deserialize(hex)
      assert tx.chain_id == fields.chain_id
      assert length(tx.calls) == length(fields.calls)
      assert Enum.at(tx.fields, 3) == quantity_bin(fields.gas_limit)
      assert Enum.at(tx.fields, 6) == quantity_bin(fields.nonce_key)
      assert Enum.at(tx.fields, 7) == quantity_bin(fields.nonce)
      assert Enum.at(tx.fields, 8) == quantity_bin(fields.valid_before)
      assert Enum.at(tx.fields, 9) == quantity_bin(fields.valid_after)
      assert hd(tx.calls).to == hd(fields.calls).to
      assert hd(tx.calls).value == hd(fields.calls).value
      assert hd(tx.calls).input == hd(fields.calls).input
    end
  end

  property "mutating any spec-order scalar field changes the canonical sender payload" do
    check all({fields, name, new_val} <- scalar_mutation_gen(), max_runs: 40) do
      original = SpecEncoder.sender_payload(fields)
      mutated = SpecEncoder.sender_payload(Map.put(fields, name, new_val))
      assert original != mutated
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

  property "RLP quantities never carry a leading zero byte" do
    check all(n <- StreamData.integer(1..0xFFFF_FFFF), max_runs: 40) do
      bin = quantity_bin(n)
      refute match?(<<0, _::binary>>, bin)
      assert :binary.decode_unsigned(bin) == n
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
          input <- StreamData.binary(min_length: 0, max_length: 32)
        ) do
      %{
        chain_id: chain_id,
        max_priority_fee_per_gas: prio,
        max_fee_per_gas: max_fee,
        gas_limit: gas,
        calls: [%{to: to, value: value, input: input}],
        access_list: [],
        nonce_key: nonce_key,
        nonce: nonce,
        valid_before: valid_before,
        valid_after: valid_after,
        fee_token: @token,
        fee_payer?: false
      }
    end
  end

  defp scalar_mutation_gen do
    gen all(
          fields <- field_map_gen(),
          name <- StreamData.member_of([:chain_id, :gas_limit, :nonce, :nonce_key, :valid_before, :valid_after]),
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
      StreamData.integer(256..65_535)
    ])
  end

  defp quantity_bin(0), do: <<>>
  defp quantity_bin(n) when is_integer(n) and n > 0, do: :binary.encode_unsigned(n)
end
