defmodule Cartouche.Transaction.PropertyTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Cartouche.Recover
  alias Cartouche.Signer
  alias Cartouche.Signer.Curvy
  alias Cartouche.Test.HighSSignerBackend
  alias Cartouche.Transaction
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2
  alias Cartouche.Transaction.V3
  alias Cartouche.Transaction.V4
  alias Cartouche.Transaction.V_2930

  @private_key Base.decode16!("800509FA3E80882AD0BE77C27505BDC91380F800D51ED80897D22F9FCC75F4BF")
  @signer_address Base.decode16!("63CC7C25E0CDB121ABB0FE477A6B9901889F99A7")
  @secp256k1_n 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
  @secp256k1_half_n div(@secp256k1_n, 2)
  @uint64_max 0xFFFFFFFFFFFFFFFF
  @uint256_max 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
  @max_address :binary.copy(<<0xFF>>, 20)
  @max_word :binary.copy(<<0xFF>>, 32)
  @max_access_list [{@max_address, [@max_word]}]
  @blob_versioned_hash <<0x01>> <> :binary.copy(<<0xFF>>, 31)
  @property_runs 40

  setup do
    %{signer: start_signer!({Curvy, @private_key})}
  end

  for version <- [:v1, :v2930, :v2, :v3, :v4] do
    property "INV-TX-ENVELOPE: #{version} round-trips, recovers its signer, and separates chain domains",
             %{signer: signer} do
      check all(
              transaction <- envelope_generator(unquote(version)),
              y_parity <- StreamData.boolean(),
              r <- signature_word_generator(),
              s <- signature_word_generator(),
              max_runs: @property_runs
            ) do
        assert_round_trip(transaction)

        transaction
        |> add_arbitrary_signature(unquote(version), y_parity, r, s)
        |> assert_round_trip()

        assert_signing_invariants(unquote(version), transaction, signer)
      end
    end
  end

  property "INV-SIGN-LOW-S: every 65-byte signing route canonicalizes s", %{signer: pure_signer} do
    legacy_signer = start_signer!({Curvy, :sign, [@private_key]})
    high_s_signer = start_signer!({HighSSignerBackend, @private_key})

    check all(message <- StreamData.binary(max_length: 128), max_runs: @property_runs) do
      digest = Cartouche.Hash.keccak(message)
      assert {:ok, high_s} = HighSSignerBackend.sign_payload(digest, @private_key)
      assert high_s.s > @secp256k1_half_n

      signatures = [
        Signer.sign(message, pure_signer, chain_id: 0),
        Signer.sign(message, legacy_signer, chain_id: 0),
        Signer.sign(message, high_s_signer, chain_id: 0),
        Signer.sign_direct(message, @signer_address, {Curvy, :sign, [@private_key]}, 0)
      ]

      Enum.each(signatures, fn result ->
        assert {:ok, <<_r::256, s::256, _v::8>> = signature} = result
        assert s <= @secp256k1_half_n
        assert Recover.recover_eth(message, signature) == @signer_address
      end)
    end
  end

  test "the generated corpus includes every required field boundary" do
    for scalar <- [0, 1, @uint256_max], access_list <- [[], @max_access_list] do
      for {version, transaction} <- boundary_envelopes(scalar, access_list) do
        assert transaction.data == <<>>
        assert_round_trip(transaction)

        signed = add_arbitrary_signature(transaction, version, true, @max_word, @max_word)
        assert_round_trip(signed)
        assert_full_width_signature(version, signed)
      end
    end
  end

  defp assert_round_trip(transaction) do
    module = transaction.__struct__
    encoded = module.encode(transaction)

    assert {:ok, ^transaction} = module.decode(encoded)
    assert {:ok, ^transaction} = Transaction.decode(encoded)
  end

  defp assert_signing_invariants(version, transaction, signer) do
    chain_id = transaction_chain_id(transaction)
    signed = sign_transaction(version, transaction, signer)

    assert_round_trip(signed)
    assert {:ok, @signer_address} = recover_signer(version, signed, chain_id)
    assert_low_s(signed)
    assert_eip155_formula(version, signed, chain_id)

    assert {:ok, other_chain_signer} = recover_signer(version, signed, chain_id + 1)
    refute other_chain_signer == @signer_address
  end

  defp sign_transaction(:v1, transaction, signer) do
    assert {:ok, signature} = Signer.sign(V1.encode(transaction), signer, chain_id: transaction.v)
    V1.add_signature(transaction, signature)
  end

  defp sign_transaction(:v2, transaction, signer) do
    assert {:ok, signature} = Signer.sign(V2.encode(transaction), signer, chain_id: transaction.chain_id)
    V2.add_signature(transaction, signature)
  end

  defp sign_transaction(_version, transaction, signer) do
    module = transaction.__struct__
    assert {:ok, signed} = module.sign(transaction, signer)
    signed
  end

  defp recover_signer(:v1, transaction, chain_id), do: V1.recover_signer(transaction, chain_id)

  defp recover_signer(_version, transaction, chain_id) do
    transaction = Map.replace!(transaction, :chain_id, chain_id)
    module = transaction.__struct__
    module.recover_signer(transaction)
  end

  defp assert_low_s(transaction) do
    module = transaction.__struct__
    assert {:ok, <<_r::256, s::256, _v::binary>>} = module.get_signature(transaction)
    assert s <= @secp256k1_half_n
  end

  defp assert_eip155_formula(:v1, transaction, chain_id) do
    parity = transaction.v - (chain_id * 2 + 35)
    assert parity in [0, 1]
  end

  defp assert_eip155_formula(_version, _transaction, _chain_id), do: :ok

  defp add_arbitrary_signature(%V1{} = transaction, :v1, y_parity, r, s) do
    parity = if(y_parity, do: 1, else: 0)

    V1.add_signature(
      transaction,
      <<r::binary-size(32), s::binary-size(32), transaction.v * 2 + 35 + parity>>
    )
  end

  defp add_arbitrary_signature(%V4{} = transaction, :v4, y_parity, r, s) do
    V4.add_signature(transaction, r <> s <> if(y_parity, do: <<1>>, else: <<0>>))
  end

  defp add_arbitrary_signature(transaction, _version, y_parity, r, s) do
    module = transaction.__struct__
    module.add_signature(transaction, y_parity, r, s)
  end

  defp assert_full_width_signature(:v1, %V1{r: r, s: s}) do
    assert r == @uint256_max
    assert s == @uint256_max
  end

  defp assert_full_width_signature(_version, transaction) do
    assert byte_size(transaction.signature_r) == 32
    assert byte_size(transaction.signature_s) == 32
  end

  defp transaction_chain_id(%V1{v: chain_id}), do: chain_id
  defp transaction_chain_id(transaction), do: transaction.chain_id

  defp envelope_generator(version) do
    gen all(
          fields <- envelope_fields_generator(),
          authorization <- authorization_generator()
        ) do
      build_envelope(version, fields, authorization)
    end
  end

  defp envelope_fields_generator do
    StreamData.fixed_map(%{
      chain_id: StreamData.integer(1..100),
      nonce: uint256_generator(),
      fee_a: uint256_generator(),
      fee_b: uint256_generator(),
      gas_limit: uint256_generator(),
      amount: uint256_generator(),
      destination: address_generator(),
      data: data_generator(),
      access_list: access_list_generator()
    })
  end

  defp uint256_generator do
    StreamData.frequency([
      {1, StreamData.member_of([0, 1, @uint256_max])},
      {4, StreamData.integer(0..@uint256_max)}
    ])
  end

  defp uint64_generator do
    StreamData.frequency([
      {1, StreamData.member_of([0, 1, @uint64_max])},
      {4, StreamData.integer(0..@uint64_max)}
    ])
  end

  defp address_generator do
    StreamData.frequency([
      {1, StreamData.constant(@max_address)},
      {4, StreamData.binary(length: 20)}
    ])
  end

  defp signature_word_generator do
    StreamData.frequency([
      {1, StreamData.member_of([<<0::256>>, <<1::256>>, @max_word])},
      {4, StreamData.binary(length: 32)}
    ])
  end

  defp data_generator do
    StreamData.frequency([
      {1, StreamData.constant(<<>>)},
      {4, StreamData.binary(max_length: 64)}
    ])
  end

  defp access_list_generator do
    StreamData.frequency([
      {1, StreamData.constant([])},
      {1, StreamData.constant(@max_access_list)},
      {4, StreamData.list_of(access_entry_generator(), max_length: 4)}
    ])
  end

  defp access_entry_generator do
    gen all(
          address <- address_generator(),
          storage_keys <- StreamData.list_of(signature_word_generator(), max_length: 4)
        ) do
      {address, storage_keys}
    end
  end

  defp authorization_generator do
    gen all(
          chain_id <- uint256_generator(),
          address <- address_generator(),
          nonce <- uint64_generator(),
          y_parity <- StreamData.boolean(),
          r <- signature_word_generator(),
          s <- signature_word_generator()
        ) do
      {chain_id, address, nonce, y_parity, r, s}
    end
  end

  defp build_envelope(:v1, fields, _authorization) do
    V1.new(
      fields.nonce,
      fields.fee_a,
      fields.gas_limit,
      fields.destination,
      fields.amount,
      fields.data,
      fields.chain_id
    )
  end

  defp build_envelope(:v2930, fields, _authorization) do
    V_2930.new(
      fields.nonce,
      fields.fee_a,
      fields.gas_limit,
      fields.destination,
      fields.amount,
      fields.data,
      fields.access_list,
      fields.chain_id
    )
  end

  defp build_envelope(:v2, fields, _authorization) do
    V2.new(
      fields.nonce,
      fields.fee_a,
      fields.fee_b,
      fields.gas_limit,
      fields.destination,
      fields.amount,
      fields.data,
      fields.access_list,
      fields.chain_id
    )
  end

  defp build_envelope(:v3, fields, _authorization) do
    V3.new(
      fields.nonce,
      fields.fee_a,
      fields.fee_b,
      fields.gas_limit,
      fields.destination,
      fields.amount,
      fields.data,
      fields.access_list,
      fields.fee_a,
      [@blob_versioned_hash],
      fields.chain_id
    )
  end

  defp build_envelope(:v4, fields, authorization) do
    V4.new(
      min(fields.nonce, @uint64_max),
      fields.fee_a,
      fields.fee_b,
      min(fields.gas_limit, @uint64_max),
      fields.destination,
      fields.amount,
      fields.data,
      fields.access_list,
      [authorization],
      fields.chain_id
    )
  end

  defp boundary_envelopes(scalar, access_list) do
    fields = %{
      chain_id: 1,
      nonce: scalar,
      fee_a: scalar,
      fee_b: scalar,
      gas_limit: scalar,
      amount: scalar,
      destination: @max_address,
      data: <<>>,
      access_list: access_list
    }

    authorization = {1, @max_address, min(scalar, @uint64_max), true, @max_word, @max_word}

    for version <- [:v1, :v2930, :v2, :v3, :v4] do
      {version, build_envelope(version, fields, authorization)}
    end
  end

  defp start_signer!(mfa) do
    start_supervised!(%{
      id: {Signer, make_ref()},
      start: {Signer, :start_link, [[mfa: mfa, name: nil]]}
    })
  end
end
