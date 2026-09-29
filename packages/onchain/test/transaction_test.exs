defmodule Cartouche.TransactionTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Signer.Default
  alias Cartouche.Test.Signer
  alias Cartouche.Transaction
  alias Cartouche.Transaction.Call
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2
  alias Cartouche.Transaction.V3
  alias Cartouche.Transaction.V4
  alias Cartouche.Transaction.V_2930

  doctest Call
  doctest Transaction
  doctest V1
  doctest V2
  doctest V3
  doctest V4
  doctest V_2930

  describe "Call.new/3" do
    test "defaults optional eth_call fields when omitted" do
      assert %Call{destination: <<1::160>>, data: <<0x12, 0x34>>, from: nil, gas: nil, value: nil} =
               Call.new(<<1::160>>, <<0x12, 0x34>>)
    end

    test "builds eth_call params without transaction-only fields" do
      call = Call.new(<<1::160>>, <<0x12, 0x34>>, from: <<2::160>>, gas: 21_000, value: 7)

      assert %Call{
               destination: <<1::160>>,
               data: <<0x12, 0x34>>,
               from: <<2::160>>,
               gas: 21_000,
               value: 7
             } = call

      refute Map.has_key?(call, :nonce)
      refute Map.has_key?(call, :chain_id)
      refute Map.has_key?(call, :signature_r)
    end
  end

  describe "V2.new/9 (no signature)" do
    test "chain_id: nil falls back to Application.chain_id()" do
      trx = V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<>>, [])
      assert trx.chain_id == Cartouche.Application.chain_id()
      assert trx.signature_y_parity == nil
      assert trx.signature_r == nil
      assert trx.signature_s == nil
    end

    test "explicit chain_id is parsed" do
      trx = V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<>>, [], :mainnet)
      assert trx.chain_id == 1
    end
  end

  describe "V2.new/12 (signed)" do
    test "max_priority_fee_per_gas: nil and max_fee_per_gas: nil pass through as nil" do
      trx =
        V2.new(
          1,
          nil,
          nil,
          100_000,
          <<1::160>>,
          {2, :wei},
          <<>>,
          [],
          true,
          <<1::256>>,
          <<2::256>>,
          :goerli
        )

      assert trx.max_priority_fee_per_gas == nil
      assert trx.max_fee_per_gas == nil
      assert trx.signature_y_parity == true
    end

    test "signed constructor without chain_id falls back to Application.chain_id()" do
      trx =
        V2.new(
          1,
          {1, :gwei},
          {100, :gwei},
          100_000,
          <<1::160>>,
          {2, :wei},
          <<>>,
          [],
          true,
          <<1::256>>,
          <<2::256>>
        )

      assert trx.chain_id == Cartouche.Application.chain_id()
    end
  end

  describe "build_trx_v2/9" do
    test "default chain_id falls back to Application.chain_id()" do
      trx =
        Transaction.build_trx_v2(
          <<1::160>>,
          5,
          <<0x12, 0x34>>,
          {1, :gwei},
          {100, :gwei},
          100_000,
          0,
          []
        )

      assert trx.chain_id == Cartouche.Application.chain_id()
      assert trx.data == <<0x12, 0x34>>
    end

    test "ABI-tuple call_data is encoded" do
      trx =
        Transaction.build_trx_v2(
          <<1::160>>,
          5,
          {"baz(uint256,address)", [50, :binary.decode_unsigned(<<1::160>>)]},
          {1, :gwei},
          {100, :gwei},
          100_000,
          0,
          [],
          :goerli
        )

      assert is_binary(trx.data)
      # 4-byte selector + two 32-byte words = 68 bytes
      assert byte_size(trx.data) == 68
    end

    test "raw binary call_data is preserved verbatim" do
      data = <<0x12, 0x34>>

      trx =
        Transaction.build_trx_v2(
          <<1::160>>,
          5,
          data,
          {1, :gwei},
          {100, :gwei},
          100_000,
          0,
          [],
          :goerli
        )

      assert trx.data == data
    end
  end

  describe "build_trx/7" do
    test "raw binary call_data is preserved with default chain_id" do
      trx = Transaction.build_trx(<<1::160>>, 5, <<0x12, 0x34>>, {50, :gwei}, 100_000, 0)

      assert trx.v == Cartouche.Application.chain_id()
      assert trx.data == <<0x12, 0x34>>
    end

    test "ABI-tuple call_data is encoded" do
      trx =
        Transaction.build_trx(
          <<1::160>>,
          5,
          {"baz(uint256,address)", [50, :binary.decode_unsigned(<<1::160>>)]},
          {50, :gwei},
          100_000,
          0,
          :goerli
        )

      assert trx.v == 5
      assert byte_size(trx.data) == 68
    end
  end

  describe "build_signed_trx/7" do
    test "default signer path defaults the nil chain id to the application chain" do
      Signer.start_signer(Default)

      {:ok, signed} = Transaction.build_signed_trx(<<1::160>>, 5, <<>>, {50, :gwei}, 100_000, 0)

      {:ok, recovered} = V1.recover_signer(signed, :goerli)
      assert recovered == Cartouche.Signer.address(Default)
    end

    test "callback can transform the unsigned transaction before signing" do
      signer_proc = Signer.start_signer()

      {:ok, signed} =
        Transaction.build_signed_trx(<<1::160>>, 5, <<0x12>>, {50, :gwei}, 100_000, 0,
          signer: signer_proc,
          chain_id: :goerli,
          callback: fn trx -> {:ok, %{trx | data: <<0x34>>}} end
        )

      assert signed.data == <<0x34>>
      {:ok, recovered} = V1.recover_signer(signed, :goerli)
      assert Cartouche.Hex.to_address(recovered) == "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
    end
  end

  describe "build_signed_trx_v2/9" do
    test "default signer path defaults the nil chain id to the application chain" do
      Signer.start_signer(Default)

      {:ok, signed} =
        Transaction.build_signed_trx_v2(<<1::160>>, 5, <<>>, {1, :gwei}, {100, :gwei}, 100_000, 0, [])

      {:ok, recovered} = V2.recover_signer(signed)
      assert recovered == Cartouche.Signer.address(Default)
    end

    test "happy path: signature recovers to signer's address" do
      signer_proc = Signer.start_signer()

      {:ok, signed} =
        Transaction.build_signed_trx_v2(
          <<1::160>>,
          5,
          <<>>,
          {1, :gwei},
          {100, :gwei},
          100_000,
          0,
          [],
          signer: signer_proc,
          chain_id: :goerli
        )

      assert signed.signature_y_parity in [true, false]
      assert byte_size(signed.signature_r) == 32
      assert byte_size(signed.signature_s) == 32

      {:ok, recovered} = V2.recover_signer(signed)
      assert Cartouche.Hex.to_address(recovered) == "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
    end

    test "callback returning {:error, _} short-circuits the with-pipeline" do
      signer_proc = Signer.start_signer()

      assert {:error, :nope} =
               Transaction.build_signed_trx_v2(
                 <<1::160>>,
                 5,
                 <<>>,
                 {1, :gwei},
                 {100, :gwei},
                 100_000,
                 0,
                 [],
                 signer: signer_proc,
                 chain_id: :goerli,
                 callback: fn _trx -> {:error, :nope} end
               )
    end
  end

  describe "V2.encode/1 access_list shapes" do
    test "unsigned bare-address shorthand is canonicalized and round-trips" do
      transaction =
        V2.new(
          1,
          {1, :gwei},
          {100, :gwei},
          100_000,
          <<1::160>>,
          {2, :wei},
          <<1, 2, 3>>,
          [<<2::160>>, <<3::160>>],
          :goerli
        )

      encoded = V2.encode(transaction)

      assert transaction.access_list == [{<<2::160>>, []}, {<<3::160>>, []}]

      assert Cartouche.Hex.encode_big_hex(encoded) ==
               "0x02F85A0501843B9ACA0085174876E800830186A09400000000000000000000000000000000000000010283010203EED6940000000000000000000000000000000000000002C0D6940000000000000000000000000000000000000003C0"

      <<0x02, payload::binary>> = encoded
      assert Enum.at(ExRLP.decode(payload), 8) == [[<<2::160>>, []], [<<3::160>>, []]]
      assert {:ok, ^transaction} = V2.decode(encoded)
    end

    test "signed bare-address shorthand emits two-element access-list entries" do
      transaction =
        V2.new(
          1,
          {1, :gwei},
          {100, :gwei},
          100_000,
          <<1::160>>,
          {2, :wei},
          <<1, 2, 3>>,
          [<<2::160>>, <<3::160>>],
          true,
          <<0x01::256>>,
          <<0x02::256>>,
          :goerli
        )

      encoded = V2.encode(transaction)

      assert Cartouche.Hex.encode_big_hex(encoded) ==
               "0x02F85D0501843B9ACA0085174876E800830186A09400000000000000000000000000000000000000010283010203EED6940000000000000000000000000000000000000002C0D6940000000000000000000000000000000000000003C0010102"

      <<0x02, payload::binary>> = encoded
      assert Enum.at(ExRLP.decode(payload), 8) == [[<<2::160>>, []], [<<3::160>>, []]]
      assert {:ok, ^transaction} = V2.decode(encoded)
    end

    test "unsigned encode accepts tuple access list entries (signing-digest path)" do
      # Regression: signing derives the digest from the UNSIGNED encoding, so tuple
      # entries — the canonical {address, [storage_keys]} shape — must normalize there
      # too, not only in the signed branch. Previously this raised (ExRLP can't encode
      # a tuple), breaking signing of any EIP-1559 tx with a non-empty access list.
      unsigned =
        V2.new(
          1,
          {1, :gwei},
          {100, :gwei},
          100_000,
          <<1::160>>,
          {2, :wei},
          <<1, 2, 3>>,
          [{<<2::160>>, [<<22::256>>]}],
          :goerli
        )

      encoded = V2.encode(unsigned)
      assert <<0x02, _rest::binary>> = encoded
      # round-trips: the digest bytes are well-formed RLP, not a hand-pinned golden
      assert {:ok, decoded} = V2.decode(encoded)
      assert decoded.access_list == [{<<2::160>>, [<<22::256>>]}]
    end

    test "mixed tuple and bare-address inputs are canonicalized before encoding" do
      transaction =
        V2.new(
          1,
          {1, :gwei},
          {100, :gwei},
          100_000,
          <<1::160>>,
          {2, :wei},
          <<1, 2, 3>>,
          [{<<2::160>>, [<<22::256>>]}, <<3::160>>],
          true,
          <<0x01::256>>,
          <<0x02::256>>,
          :goerli
        )

      encoded = V2.encode(transaction)

      assert transaction.access_list == [{<<2::160>>, [<<22::256>>]}, {<<3::160>>, []}]

      assert Cartouche.Hex.encode_big_hex(encoded) ==
               "0x02F87F0501843B9ACA0085174876E800830186A09400000000000000000000000000000000000000010283010203F84FF7940000000000000000000000000000000000000002E1A00000000000000000000000000000000000000000000000000000000000000016D6940000000000000000000000000000000000000003C0010102"

      assert {:ok, ^transaction} = V2.decode(encoded)
    end

    test "encode rejects noncanonical bare-address structs" do
      transaction =
        V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<>>, [])

      for access_list <- [[<<2::160>>], [{<<2::160>>, [<<1, 2>>]}]] do
        assert_raise ArgumentError,
                     "access_list entries must contain a 20-byte address and 32-byte storage keys",
                     fn -> V2.encode(%{transaction | access_list: access_list}) end
      end
    end
  end

  describe "V2.decode/1" do
    test "round-trips signed transactions" do
      transaction =
        1
        |> V2.new({1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [
          {<<2::160>>, [<<22::256>>]}
        ])
        |> V2.add_signature(<<1::256, 2::256, 1>>)

      assert {:ok, ^transaction} = transaction |> V2.encode() |> V2.decode()
    end

    test "round-trips unsigned transactions" do
      transaction = V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [])

      assert {:ok, ^transaction} = transaction |> V2.encode() |> V2.decode()
    end

    test "malformed RLP body returns {:error, \"invalid v2 transaction\"}" do
      bad_body = <<0x02>> <> ExRLP.encode([<<1>>, <<2>>, <<3>>])
      assert {:error, "invalid v2 transaction"} = V2.decode(bad_body)
      assert {:error, "invalid v2 transaction"} = V2.decode(<<0x02, 0xFF>>)
      assert {:error, "invalid v2 transaction"} = V2.decode(<<0x04, 0xC0>>)
    end

    test "rejects non-list access_list" do
      bytes =
        <<0x02>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<>>,
            <<"not a list">>,
            1,
            <<1::256>>,
            <<2::256>>
          ])

      assert {:error, "invalid v2 transaction"} = V2.decode(bytes)
    end

    test "rejects malformed access_list entries" do
      bytes =
        <<0x02>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<>>,
            [<<"not a pair">>],
            1,
            <<1::256>>,
            <<2::256>>
          ])

      assert {:error, "invalid v2 transaction"} = V2.decode(bytes)
    end

    test "rejects malformed typed payloads" do
      bad_destination =
        <<0x02>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<0, 1::160>>,
            2,
            <<>>,
            [],
            1,
            <<1::256>>,
            <<2::256>>
          ])

      bad_y_parity =
        <<0x02>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<>>,
            [],
            2,
            <<1::256>>,
            <<2::256>>
          ])

      assert {:error, "invalid v2 transaction"} = V2.decode(bad_destination)
      assert {:error, "invalid v2 transaction"} = V2.decode(bad_y_parity)
    end

    test "rejects short destination and access-list widths" do
      short_destination =
        <<0x02>> <>
          ExRLP.encode([1, 1, 1_000_000_000, 100_000_000_000, 100_000, <<1>>, 2, <<>>, []])

      short_access_address =
        <<0x02>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<>>,
            [[<<2>>, [<<22::256>>]]]
          ])

      short_storage_key =
        <<0x02>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<>>,
            [[<<2::160>>, [<<22>>]]]
          ])

      assert {:error, "invalid v2 transaction"} = V2.decode(short_destination)
      assert {:error, "invalid v2 transaction"} = V2.decode(short_access_address)
      assert {:error, "invalid v2 transaction"} = V2.decode(short_storage_key)
    end

    test "rejects malformed scalar, data, and signature fields without raising" do
      bad_scalar =
        <<0x02>> <>
          ExRLP.encode([
            [],
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<>>,
            [],
            1,
            <<1::256>>,
            <<2::256>>
          ])

      bad_data =
        <<0x02>> <>
          ExRLP.encode([1, 1, 1_000_000_000, 100_000_000_000, 100_000, <<1::160>>, 2, [<<>>], []])

      bad_signature =
        <<0x02>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<>>,
            [],
            1,
            <<1, 0::256>>,
            <<2::256>>
          ])

      bad_y_parity_shape =
        <<0x02>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<>>,
            [],
            [],
            <<1::256>>,
            <<2::256>>
          ])

      assert {:error, "invalid v2 transaction"} = V2.decode(bad_scalar)
      assert {:error, "invalid v2 transaction"} = V2.decode(bad_data)
      assert {:error, "invalid v2 transaction"} = V2.decode(bad_signature)
      assert {:error, "invalid v2 transaction"} = V2.decode(bad_y_parity_shape)
    end
  end

  describe "V3.decode/1" do
    test "round-trips signed transactions" do
      transaction = V3.add_signature(v3_transaction(), true, <<1::256>>, <<2::256>>)

      assert {:ok, ^transaction} = transaction |> V3.encode() |> V3.decode()
    end

    test "round-trips unsigned transactions" do
      transaction = v3_transaction()

      assert {:ok, ^transaction} = transaction |> V3.encode() |> V3.decode()
    end

    test "malformed RLP and wrong type bytes return errors" do
      assert {:error, "invalid v3 transaction"} = V3.decode(<<0x03, 0xFF>>)
      assert {:error, "invalid v3 transaction"} = V3.decode(<<0x02, 0xC0>>)
      assert {:error, "invalid v3 transaction"} = V3.decode(<<0x03>> <> ExRLP.encode([1, 2, 3]))
    end

    test "rejects malformed access lists and blob versioned hashes" do
      malformed_access_list =
        <<0x03>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [[<<2::160>>, [<<1, 2>>]]],
            1,
            [<<1, 0::248>>]
          ])

      malformed_blob_hash =
        <<0x03>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [],
            1,
            [<<1, 2>>]
          ])

      assert {:error, "invalid v3 transaction"} = V3.decode(malformed_access_list)
      assert {:error, "invalid v3 transaction"} = V3.decode(malformed_blob_hash)
    end

    test "rejects malformed containers, entries, scalars, and signatures without raising" do
      base_fields = [
        1,
        1,
        1_000_000_000,
        100_000_000_000,
        100_000,
        <<1::160>>,
        2,
        <<1, 2, 3>>,
        [],
        1,
        [<<1, 0::248>>]
      ]

      invalid_cases = [
        List.replace_at(base_fields, 0, []),
        List.replace_at(base_fields, 7, [<<1, 2, 3>>]),
        List.replace_at(base_fields, 8, <<>>),
        List.replace_at(base_fields, 8, [[<<2::160>>]]),
        List.replace_at(base_fields, 10, <<>>),
        base_fields ++ [2, <<1::256>>, <<2::256>>],
        base_fields ++ [[], <<1::256>>, <<2::256>>]
      ]

      for fields <- invalid_cases do
        assert {:error, "invalid v3 transaction"} = V3.decode(<<0x03>> <> ExRLP.encode(fields))
      end
    end

    test "signs and decodes packed signatures with both y-parity values" do
      signer_proc = Signer.start_signer()

      assert {:ok, %V3{} = signed} = V3.sign(v3_transaction(), signer_proc)
      assert byte_size(signed.signature_r) == 32
      assert byte_size(signed.signature_s) == 32

      false_parity = V3.add_signature(v3_transaction(), <<1::256, 2::256, 0>>)
      true_parity = V3.add_signature(v3_transaction(), <<1::256, 2::256, 1>>)

      assert false_parity.signature_y_parity == false
      assert true_parity.signature_y_parity == true
    end
  end

  describe "V4 encode/decode" do
    test "new/10 defaults chain id and preserves nil fee fields before encoding" do
      transaction =
        V4.new(
          1,
          nil,
          nil,
          100_000,
          <<1::160>>,
          {2, :wei},
          <<1, 2, 3>>,
          nil,
          [signed_authorization(1, <<2::160>>, 7)]
        )

      assert transaction.chain_id == Cartouche.Application.chain_id()
      assert transaction.max_priority_fee_per_gas == nil
      assert transaction.max_fee_per_gas == nil
    end

    test "round-trips a representative authorization-list transaction" do
      transaction = v4_transaction([signed_authorization(1, <<2::160>>, 7)])

      assert {:ok, ^transaction} = transaction |> V4.encode() |> V4.decode()
    end

    test "round-trips unsigned transactions without signature fields" do
      transaction =
        V4.new(
          1,
          {1, :gwei},
          {100, :gwei},
          100_000,
          <<1::160>>,
          {2, :wei},
          <<1, 2, 3>>,
          [],
          [signed_authorization(1, <<2::160>>, 7)],
          :mainnet
        )

      assert {:ok, ^transaction} = transaction |> V4.encode() |> V4.decode()
    end

    test "round-trips access-list storage keys" do
      transaction =
        [signed_authorization(1, <<2::160>>, 7)]
        |> v4_transaction()
        |> Map.put(:access_list, [{<<3::160>>, [<<4::256>>]}])

      assert {:ok, ^transaction} = transaction |> V4.encode() |> V4.decode()
    end

    test "encode and decode reject empty authorization lists symmetrically" do
      transaction = v4_transaction([])

      assert_raise ArgumentError, "authorization_list must not be empty", fn -> V4.encode(transaction) end

      assert {:error, "authorization_list must not be empty"} =
               [] |> encoded_v4_with_authorizations() |> V4.decode()
    end

    test "encode rejects nil authorization lists with the named boundary error" do
      transaction =
        1
        |> V4.new({1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [], nil, :mainnet)
        |> V4.add_signature(<<1::256, 2::256, 1>>)

      assert_raise ArgumentError, "authorization_list must not be empty", fn -> V4.encode(transaction) end
    end

    test "encode and decode reject malformed access-list storage keys symmetrically" do
      transaction =
        [signed_authorization(1, <<2::160>>, 7)]
        |> v4_transaction()
        |> Map.put(:access_list, [{<<3::160>>, [<<1, 2>>]}])

      encode = Function.capture(V4, :encode, 1)

      assert_raise ArgumentError,
                   "access_list entries must contain a 20-byte address and 32-byte storage keys",
                   fn -> encode.(transaction) end

      <<0x04, payload::binary>> = V4.encode(v4_transaction([signed_authorization(1, <<2::160>>, 7)]))
      fields = payload |> ExRLP.decode() |> List.replace_at(8, [[<<3::160>>, [<<1, 2>>]]])
      assert {:error, "invalid v4 transaction"} = V4.decode(<<0x04>> <> ExRLP.encode(fields))
    end

    test "supports multiple authorization entries including chain_id 0" do
      authorizations = [
        signed_authorization(1, <<2::160>>, 7),
        signed_authorization(0, <<3::160>>, 8)
      ]

      transaction = v4_transaction(authorizations)

      assert {:ok, %{authorization_list: ^authorizations}} = transaction |> V4.encode() |> V4.decode()
    end

    test "decode rejects malformed typed payloads" do
      bad_body = <<0x04>> <> ExRLP.encode([<<1>>, <<2>>, <<3>>])
      assert {:error, "invalid v4 transaction"} = V4.decode(bad_body)
      assert {:error, "invalid v4 transaction"} = V4.decode(<<0x02, 0xC0>>)
      assert {:error, "invalid v4 transaction"} = V4.decode(<<0x04, 0xFF>>)
    end

    test "decode rejects malformed unsigned typed payloads" do
      bad_access_list =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [[<<2::160>>, [<<1, 2>>]]],
            [encode_authorization_for_test(signed_authorization(1, <<2::160>>, 7))]
          ])

      bad_destination =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1, 2>>,
            2,
            <<1, 2, 3>>,
            [],
            [encode_authorization_for_test(signed_authorization(1, <<2::160>>, 7))]
          ])

      assert {:error, "invalid v4 transaction"} = V4.decode(bad_access_list)
      assert {:error, "invalid v4 transaction"} = V4.decode(bad_destination)
    end

    test "decode rejects malformed authorization entries" do
      malformed_authorization = [<<1>>, <<2::160>>, <<7>>, <<0>>, <<1, 0::256>>, <<2::256>>]

      encoded =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [],
            [malformed_authorization],
            1,
            1,
            2
          ])

      assert {:error, "invalid v4 transaction"} = V4.decode(encoded)
    end

    test "decode rejects malformed access-list entries" do
      encoded =
        1
        |> signed_authorization(<<2::160>>, 7)
        |> List.wrap()
        |> v4_transaction()
        |> V4.encode()

      <<0x04, encoded_payload::binary>> = encoded

      [
        chain_id,
        nonce,
        max_priority_fee_per_gas,
        max_fee_per_gas,
        gas_limit,
        destination,
        amount,
        data,
        _access_list,
        authorization_list,
        y_parity,
        r,
        s
      ] = ExRLP.decode(encoded_payload)

      malformed_access_list = [[<<1, 2>>, [<<1::256>>]]]

      bad_body =
        <<0x04>> <>
          ExRLP.encode([
            chain_id,
            nonce,
            max_priority_fee_per_gas,
            max_fee_per_gas,
            gas_limit,
            destination,
            amount,
            data,
            malformed_access_list,
            authorization_list,
            y_parity,
            r,
            s
          ])

      assert {:error, "invalid v4 transaction"} = V4.decode(bad_body)
    end

    test "decode rejects malformed access-list and authorization-list containers" do
      bad_access_list =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            <<>>,
            [encode_authorization_for_test(signed_authorization(1, <<2::160>>, 7))],
            1,
            1,
            2
          ])

      bad_authorization_list =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [],
            <<>>,
            1,
            1,
            2
          ])

      assert {:error, "invalid v4 transaction"} = V4.decode(bad_access_list)
      assert {:error, "invalid v4 transaction"} = V4.decode(bad_authorization_list)
    end

    test "decode rejects malformed storage-key lists, y-parity values, and entry shapes" do
      malformed_storage =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [[<<2::160>>, [<<1, 2>>]]],
            [encode_authorization_for_test(signed_authorization(1, <<2::160>>, 7))],
            1,
            1,
            2
          ])

      malformed_y_parity =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [],
            [encode_authorization_for_test(signed_authorization(1, <<2::160>>, 7))],
            2,
            1,
            2
          ])

      malformed_access_entry =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [[<<2::160>>]],
            [encode_authorization_for_test(signed_authorization(1, <<2::160>>, 7))],
            1,
            1,
            2
          ])

      malformed_authorization_entry =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [],
            [[<<1>>, <<2::160>>]],
            1,
            1,
            2
          ])

      assert {:error, "invalid v4 transaction"} = V4.decode(malformed_storage)
      assert {:error, "invalid v4 transaction"} = V4.decode(malformed_y_parity)
      assert {:error, "invalid v4 transaction"} = V4.decode(malformed_access_entry)
      assert {:error, "invalid v4 transaction"} = V4.decode(malformed_authorization_entry)
    end

    test "decode rejects non-binary data payloads" do
      encoded =
        <<0x04>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            [<<1, 2, 3>>],
            [],
            [encode_authorization_for_test(signed_authorization(1, <<2::160>>, 7))],
            1,
            1,
            2
          ])

      assert {:error, "invalid v4 transaction"} = V4.decode(encoded)
    end

    test "decode returns errors for malformed RLP and wrong typed envelopes" do
      assert {:error, "invalid v4 transaction"} = V4.decode(<<0x04, 0xFF>>)
      assert {:error, "invalid v4 transaction"} = V4.decode(<<0x03, 0xC0>>)
    end
  end

  describe "V4 signatures and hashes" do
    test "default signer path signs with the configured signer chain id" do
      Signer.start_signer(Default)
      transaction = v4_transaction([signed_authorization(1, <<2::160>>, 7)])

      assert {:ok, %V4{signature_r: <<_::256>>, signature_s: <<_::256>>}} = V4.sign(transaction)

      assert {:ok, {1, <<2::160>>, 7, _y_parity, <<_::256>>, <<_::256>>}} =
               V4.sign_authorization({1, <<2::160>>, 7})
    end

    test "sign/2 signs the outer transaction and recovers the signer" do
      signer_proc = Signer.start_signer()

      {:ok, signed} =
        [signed_authorization(1, <<2::160>>, 7)]
        |> v4_transaction()
        |> V4.sign(signer_proc)

      assert byte_size(signed.signature_r) == 32
      assert byte_size(signed.signature_s) == 32

      {:ok, recovered} = V4.recover_signer(signed)
      assert Cartouche.Hex.to_address(recovered) == "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
    end

    test "hash/1 returns the keccak of encoded bytes" do
      transaction =
        [signed_authorization(1, <<2::160>>, 7)]
        |> v4_transaction()
        |> V4.add_signature(<<1::256, 2::256, 1>>)

      assert V4.hash(transaction) == transaction |> V4.encode() |> Cartouche.Hash.keccak()
      assert V4.hash(V4.encode(transaction)) == V4.hash(transaction)
    end

    test "encodes signatures with binary-safe leading-zero trimming" do
      transaction =
        [signed_authorization(1, <<2::160>>, 7)]
        |> v4_transaction()
        |> Map.merge(%{signature_r: <<0, 0xFF, 1::240>>, signature_s: <<0, 0xFE, 2::240>>})

      <<0x04, payload::binary>> = V4.encode(transaction)
      decoded_fields = ExRLP.decode(payload)

      assert [<<0xFF, 1::240>>, <<0xFE, 2::240>>] = Enum.slice(decoded_fields, 11, 2)
    end

    test "authorization_hash/1 accepts signed and unsigned authorization tuples" do
      unsigned = {1, <<2::160>>, 7}
      signed = signed_authorization(1, <<2::160>>, 7)

      assert V4.authorization_hash(unsigned) == V4.authorization_hash(signed)
    end

    test "sign_authorization/2 signs an authorization tuple and recovers authority" do
      signer_proc = Signer.start_signer()

      {:ok, authorization} = V4.sign_authorization({0, <<2::160>>, 7}, signer_proc)
      assert {0, <<2::160>>, 7, _y_parity, <<_::256>>, <<_::256>>} = authorization

      {:ok, recovered} = V4.recover_authority(authorization)
      assert Cartouche.Hex.to_address(recovered) == "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
    end

    test "missing signatures return explicit errors" do
      transaction = v4_transaction([signed_authorization(1, <<2::160>>, 7)])
      authorization = {1, <<2::160>>, 7, nil, nil, nil}

      assert {:error, "transaction missing signature"} =
               transaction
               |> Map.merge(%{signature_y_parity: nil, signature_r: nil, signature_s: nil})
               |> V4.get_signature()

      assert {:error, "transaction missing signature"} =
               transaction
               |> Map.merge(%{signature_y_parity: nil, signature_r: nil, signature_s: nil})
               |> V4.recover_signer()

      assert {:error, "authorization missing signature"} = V4.get_authorization_signature(authorization)
      assert {:error, "authorization missing signature"} = V4.recover_authority(authorization)
    end

    test "rejects packed signatures without recovery bytes" do
      transaction = v4_transaction([signed_authorization(1, <<2::160>>, 7)])
      authorization = {1, <<2::160>>, 7, nil, nil, nil}

      assert_raise FunctionClauseError, fn -> V4.add_signature(transaction, <<1::256, 2::256>>) end

      assert_raise FunctionClauseError, fn ->
        V4.add_authorization_signature(authorization, <<1::256, 2::256>>)
      end
    end

    test "get_signature/1 32-byte packing is r <> s <> <<y_parity>>" do
      transaction = v4_transaction([signed_authorization(1, <<2::160>>, 7)])

      assert V4.get_signature(transaction) == {:ok, <<1::256, 2::256, 1>>}

      assert V4.get_authorization_signature(signed_authorization(1, <<2::160>>, 7)) ==
               {:ok, <<1::256, 2::256, 0>>}
    end

    test "get_signature/1 raises on short r or s instead of emitting a malformed packed signature" do
      transaction =
        [signed_authorization(1, <<2::160>>, 7)]
        |> v4_transaction()
        |> Map.put(:signature_r, <<1, 2, 3>>)

      assert_raise ArgumentError, fn -> V4.get_signature(transaction) end

      assert_raise ArgumentError, fn ->
        V4.get_authorization_signature({1, <<2::160>>, 7, false, <<1>>, <<2::256>>})
      end
    end
  end

  describe "V4 mainnet vector" do
    test "decodes a real mainnet EIP-7702 transaction and validates signatures" do
      raw =
        ~h[0x04f90235018208f685012a05f20085013351f4d0830490c594f827725498e6fcf62d331566965f5254bcda081f80b9016408c1284c00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000104039a40f2bccd543a5eaaaca3a5749d912087ef66220000000000000000000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000106545ff956995f0000b25750fa55b302c9a3997f64d24c0b14afdd316500006401da7d6fa850c02ec58ac50ae3c7137b47cb8ae7990007d00003001101033d007224df0a5cf63f33a4e5f25b392097f16bfc0006545ff956995f0208f60469f93ef30141d79dad548078b26c02aaf2a3ae4c2e723245701f0f71f77349bddf24e0aed1c9096d5005a0b468cd4ac1a34793d4fa10a2ac04af8685b6f3e82298a9e5ae44771b010200023d007224df0a5cf63f33a4e5f25b392097f16bfc0026f20202010200000000000000000000000000000000000000000000000000000000c0f85ef85c019400000000000000000000000000000000000000008208f780a007359171ab176f57c49420481d6a4ba45593d0bd4c16e6273ff88684e7821c9ca05b2fc15416887a236607e4f277e053db645cae48bf810b43c654f2cff6ab575c01a0e8375ec8c35be742c2e2b637ddc4a5c83fe3e2fa345b38debef51d38c1e50530a02e695872ee3a3a6a3ad0b44d185b98beeae8bfbb9864f9e2db5406e195b4e4c6]

      assert {:ok, transaction} = V4.decode(raw)

      assert transaction.chain_id == 1
      assert transaction.nonce == 2294
      assert transaction.max_priority_fee_per_gas == 5_000_000_000
      assert transaction.max_fee_per_gas == 5_155_976_400
      assert transaction.gas_limit == 299_205
      assert transaction.destination == ~h[0xf827725498e6fcf62d331566965f5254bcda081f]
      assert transaction.amount == 0
      assert transaction.access_list == []
      assert transaction.signature_y_parity == true

      assert [
               {
                 1,
                 ~h[0x0000000000000000000000000000000000000000],
                 2295,
                 false,
                 ~h[0x07359171ab176f57c49420481d6a4ba45593d0bd4c16e6273ff88684e7821c9c],
                 ~h[0x5b2fc15416887a236607e4f277e053db645cae48bf810b43c654f2cff6ab575c]
               } = authorization
             ] = transaction.authorization_list

      assert V4.encode(transaction) == raw
      assert V4.hash(transaction) == ~h[0xb418e774d8492b01ebc5966b2a80d873d4651351b4813e954fdbdda713081ab8]

      assert {:ok, outer_signer} = V4.recover_signer(transaction)
      assert Cartouche.Hex.to_address(outer_signer) == "0x52ceD5DD182f7CD50B8eC4A2ad0c50824DA39A66"

      assert {:ok, authority} = V4.recover_authority(authorization)
      assert Cartouche.Hex.to_address(authority) == "0x52ceD5DD182f7CD50B8eC4A2ad0c50824DA39A66"
    end
  end

  describe "Cartouche.Transaction.decode/1" do
    test "dispatches legacy transactions through V1" do
      transaction = V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)

      assert {:ok, ^transaction} = transaction |> V1.encode() |> Transaction.decode()
    end

    test "dispatches typed transactions through V_2930, V2, V3, and V4" do
      v2 = V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [])
      v3 = v3_transaction()
      v4 = v4_transaction([signed_authorization(1, <<2::160>>, 7)])

      assert {:ok, v2930} = Transaction.decode(v2930_raw())
      assert v2930.__struct__ == V_2930
      assert v2930.chain_id == 1
      assert v2930.gas_price == 5_004_995_121
      assert v2930.destination == ~h[0xc02953f316c5c18808e2d3961424f952788d69f5]

      assert {:ok, ^v2} = v2 |> V2.encode() |> Transaction.decode()
      assert {:ok, ^v3} = v3 |> V3.encode() |> Transaction.decode()
      assert {:ok, ^v4} = v4 |> V4.encode() |> Transaction.decode()
    end

    test "returns tagged errors for empty bytes and unknown typed envelopes" do
      assert {:error, :empty_transaction} = Transaction.decode(<<>>)
      assert {:error, :unknown_envelope_type} = Transaction.decode(<<0x05, 0xC0>>)
      assert {:error, :unknown_envelope_type} = Transaction.decode(:not_binary)
      assert {:error, _} = Transaction.decode(<<0x02, 0xFF>>)
    end
  end

  describe "V_2930.decode/1" do
    test "decodes unsigned type-1 payloads with access-list entries" do
      address = <<2::160>>
      storage_key = <<3::256>>

      assert {:ok, transaction} =
               [access_list: [[address, [storage_key]]]]
               |> v2930_payload()
               |> v2930_encode()
               |> V_2930.decode()

      assert transaction.signature_y_parity == nil
      assert transaction.signature_r == nil
      assert transaction.signature_s == nil
      assert transaction.access_list == [{address, [storage_key]}]
    end

    test "decodes signed type-1 payloads with y parity 1" do
      assert {:ok, transaction} =
               [signature_y_parity: <<1>>, signature_r: <<1>>, signature_s: <<2>>]
               |> v2930_signed_payload()
               |> v2930_encode()
               |> V_2930.decode()

      assert transaction.signature_y_parity == true
      assert transaction.signature_r == <<1::256>>
      assert transaction.signature_s == <<2::256>>
    end

    test "rejects malformed type-1 payloads without raising" do
      assert {:error, "invalid v2930 transaction"} = V_2930.decode(:not_binary)
      assert {:error, "invalid v2930 transaction"} = V_2930.decode(<<0x01, 0xC1>>)

      assert {:error, "invalid v2930 transaction"} =
               [<<1>>]
               |> v2930_encode()
               |> V_2930.decode()

      assert {:error, "invalid v2930 transaction"} =
               [chain_id: []]
               |> v2930_payload()
               |> v2930_encode()
               |> V_2930.decode()

      assert {:error, "invalid v2930 transaction"} =
               [data: []]
               |> v2930_payload()
               |> v2930_encode()
               |> V_2930.decode()

      assert {:error, "invalid v2930 transaction"} =
               [access_list: <<>>]
               |> v2930_payload()
               |> v2930_encode()
               |> V_2930.decode()

      assert {:error, "invalid v2930 transaction"} =
               [access_list: [[<<1::160>>]]]
               |> v2930_payload()
               |> v2930_encode()
               |> V_2930.decode()

      assert {:error, "invalid v2930 transaction"} =
               [access_list: [[<<1::160>>, [<<1>>]]]]
               |> v2930_payload()
               |> v2930_encode()
               |> V_2930.decode()

      assert {:error, "invalid v2930 transaction"} =
               [signature_r: []]
               |> v2930_signed_payload()
               |> v2930_encode()
               |> V_2930.decode()

      assert {:error, "invalid v2930 transaction"} =
               [signature_y_parity: <<2>>]
               |> v2930_signed_payload()
               |> v2930_encode()
               |> V_2930.decode()

      assert {:error, "invalid v2930 transaction"} =
               [signature_y_parity: []]
               |> v2930_signed_payload()
               |> v2930_encode()
               |> V_2930.decode()
    end
  end

  describe "V_2930.encode/1" do
    test "round-trips signed transactions" do
      transaction = V_2930.add_signature(v2930_transaction(), true, <<1::256>>, <<2::256>>)

      assert {:ok, ^transaction} = transaction |> V_2930.encode() |> V_2930.decode()
    end

    test "round-trips unsigned transactions" do
      transaction = v2930_transaction()

      assert {:ok, ^transaction} = transaction |> V_2930.encode() |> V_2930.decode()
    end

    test "encode rejects malformed access-list storage keys that decode already rejects" do
      transaction = %{v2930_transaction() | access_list: [{<<1::160>>, [<<1, 2, 3>>]}]}
      encode = Function.capture(V_2930, :encode, 1)

      assert_raise ArgumentError,
                   "access_list entries must contain a 20-byte address and 32-byte storage keys",
                   fn -> encode.(transaction) end
    end

    test "new/8 defaults chain id and leaves signature fields unset" do
      transaction = V_2930.new(1, {1, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [])

      assert transaction.chain_id == Cartouche.Application.chain_id()
      assert transaction.signature_y_parity == nil
      assert transaction.signature_r == nil
      assert transaction.signature_s == nil
    end

    test "emits 0x01 || rlp([chainId, nonce, gasPrice, gasLimit, to, value, data, accessList, yParity, r, s])" do
      access_key = <<22::256>>
      transaction = V_2930.add_signature(v2930_transaction(), false, <<1::256>>, <<2::256>>)

      <<0x01, payload::binary>> = V_2930.encode(transaction)

      assert [
               chain_id,
               nonce,
               gas_price,
               gas_limit,
               destination,
               amount,
               data,
               access_list,
               y_parity,
               signature_r,
               signature_s
             ] = ExRLP.decode(payload)

      assert :binary.decode_unsigned(chain_id) == 5
      assert :binary.decode_unsigned(nonce) == 1
      assert :binary.decode_unsigned(gas_price) == 1_000_000_000
      assert :binary.decode_unsigned(gas_limit) == 100_000
      assert destination == <<1::160>>
      assert :binary.decode_unsigned(amount) == 2
      assert data == <<1, 2, 3>>
      assert access_list == [[<<2::160>>, [access_key]]]
      assert :binary.decode_unsigned(y_parity) == 0
      assert :binary.decode_unsigned(signature_r) == 1
      assert :binary.decode_unsigned(signature_s) == 2
    end

    test "unsigned encode omits yParity, r, and s" do
      <<0x01, payload::binary>> = V_2930.encode(v2930_transaction())

      assert [_, _, _, _, _, _, _, _] = ExRLP.decode(payload)
    end

    test "round-trips a mainnet type-1 vector through encode" do
      raw = v2930_raw()

      assert {:ok, transaction} = V_2930.decode(raw)
      assert V_2930.encode(transaction) == raw
    end
  end

  describe "V_2930 signatures" do
    test "sign/2 then recover_signer/1 recovers the signer identity" do
      signer_proc = Signer.start_signer()

      assert {:ok, %V_2930{} = signed} = V_2930.sign(v2930_transaction(), signer_proc)
      assert byte_size(signed.signature_r) == 32
      assert byte_size(signed.signature_s) == 32

      {:ok, recovered} = V_2930.recover_signer(signed)
      assert Cartouche.Hex.to_address(recovered) == "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
    end

    test "default signer path signs with the configured signer" do
      Signer.start_signer(Default)
      transaction = v2930_transaction()

      assert {:ok, %V_2930{signature_r: <<_::256>>, signature_s: <<_::256>>}} = V_2930.sign(transaction)
    end

    test "add_signature/4 and add_signature/2 attach the same fields" do
      explicit = V_2930.add_signature(v2930_transaction(), true, <<1::256>>, <<2::256>>)
      packed = V_2930.add_signature(v2930_transaction(), <<1::256, 2::256, 1>>)
      false_parity = V_2930.add_signature(v2930_transaction(), <<1::256, 2::256, 0>>)

      assert explicit == packed
      assert explicit.signature_y_parity == true
      assert false_parity.signature_y_parity == false
    end

    test "missing signatures return explicit errors" do
      transaction = v2930_transaction()

      assert {:error, "transaction missing signature"} = V_2930.get_signature(transaction)
      assert {:error, "transaction missing signature"} = V_2930.recover_signer(transaction)
    end

    test "hash/1 returns the keccak of encoded bytes" do
      transaction = V_2930.add_signature(v2930_transaction(), true, <<1::256>>, <<2::256>>)

      assert V_2930.hash(transaction) == transaction |> V_2930.encode() |> Cartouche.Hash.keccak()
    end
  end

  describe "Cartouche.Transaction.encode/1" do
    test "delegates V1 structs to V1.encode/1 (untyped legacy RLP)" do
      transaction = V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)

      encoded = Transaction.encode(transaction)

      assert encoded == V1.encode(transaction)
      assert <<first, _::binary>> = encoded
      assert first >= 0x80
    end

    test "delegates V_2930 structs to V_2930.encode/1 with the 0x01 envelope byte" do
      transaction = v2930_transaction()

      encoded = Transaction.encode(transaction)

      assert encoded == V_2930.encode(transaction)
      assert <<0x01, _::binary>> = encoded
    end

    test "delegates V2 structs to V2.encode/1 with the 0x02 envelope byte" do
      transaction = V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [], :goerli)

      encoded = Transaction.encode(transaction)

      assert encoded == V2.encode(transaction)
      assert <<0x02, _::binary>> = encoded
    end

    test "delegates V3 structs to V3.encode/1 with the 0x03 envelope byte" do
      transaction = v3_transaction()

      encoded = Transaction.encode(transaction)

      assert encoded == V3.encode(transaction)
      assert <<0x03, _::binary>> = encoded
    end

    test "delegates V4 structs to V4.encode/1 with the 0x04 envelope byte" do
      transaction = v4_transaction([signed_authorization(1, <<2::160>>, 7)])

      encoded = Transaction.encode(transaction)

      assert encoded == V4.encode(transaction)
      assert <<0x04, _::binary>> = encoded
    end

    test "round-trips decode(encode(tx)) for every supported version" do
      v1 = V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)
      v2930 = v2930_transaction()
      v2 = V2.new(1, {1, :gwei}, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, [], :goerli)
      v3 = v3_transaction()
      v4 = v4_transaction([signed_authorization(1, <<2::160>>, 7)])

      assert {:ok, ^v1} = v1 |> Transaction.encode() |> Transaction.decode()
      assert {:ok, ^v2930} = v2930 |> Transaction.encode() |> Transaction.decode()
      assert {:ok, ^v2} = v2 |> Transaction.encode() |> Transaction.decode()
      assert {:ok, ^v3} = v3 |> Transaction.encode() |> Transaction.decode()
      assert {:ok, ^v4} = v4 |> Transaction.encode() |> Transaction.decode()
    end
  end

  describe "V1 (Task 53 — r/s/v unification + decode→recover_signer round-trip)" do
    test "round-trips signed transactions" do
      signer_proc = Signer.start_signer()

      {:ok, transaction} =
        Transaction.build_signed_trx(<<1::160>>, 5, <<>>, {50, :gwei}, 100_000, 0,
          signer: signer_proc,
          chain_id: :goerli
        )

      assert {:ok, ^transaction} = transaction |> V1.encode() |> V1.decode()
    end

    test "round-trips unsigned transactions" do
      transaction = V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan)

      assert {:ok, ^transaction} = transaction |> V1.encode() |> V1.decode()
    end

    test "decode/1 returns {:error, \"invalid legacy transaction\"} on malformed RLP" do
      bad_body = ExRLP.encode([<<1>>, <<2>>, <<3>>])
      assert {:error, "invalid legacy transaction"} = V1.decode(bad_body)
      assert {:error, "invalid legacy transaction"} = V1.decode(<<0xFF>>)
      assert {:error, "invalid legacy transaction"} = V1.decode(:not_binary)
    end

    test "decode → recover_signer round-trip recovers the original signer" do
      signer_proc = Signer.start_signer()

      {:ok, signed} =
        Transaction.build_signed_trx(<<1::160>>, 5, <<>>, {50, :gwei}, 100_000, 0,
          signer: signer_proc,
          chain_id: :goerli
        )

      {:ok, decoded} = V1.decode(V1.encode(signed))
      {:ok, recovered} = V1.recover_signer(decoded, 5)
      assert Cartouche.Hex.to_address(recovered) == "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
    end

    test "decode of unsigned RLP yields r=0, s=0; recover_signer reports missing signature" do
      encoded = V1.encode(V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, :kovan))
      {:ok, decoded} = V1.decode(encoded)
      assert decoded.r == 0
      assert decoded.s == 0
      assert {:error, "transaction missing signature"} = V1.recover_signer(decoded, :kovan)
    end

    test "decode/1 rejects RLP with r or s wider than 32 bytes" do
      adversarial =
        ExRLP.encode([
          <<1>>,
          <<100_000_000_000::40>>,
          <<100_000::24>>,
          <<1::160>>,
          <<2>>,
          <<1, 2, 3>>,
          <<42>>,
          <<1, 0::256>>,
          <<2::256>>
        ])

      assert {:error, "invalid legacy transaction"} = V1.decode(adversarial)
    end

    test "decode/1 rejects malformed scalar fields without raising" do
      adversarial =
        ExRLP.encode([
          [],
          <<100_000_000_000::40>>,
          <<100_000::24>>,
          <<1::160>>,
          <<2>>,
          <<1, 2, 3>>,
          <<42>>,
          <<1::256>>,
          <<2::256>>
        ])

      assert {:error, "invalid legacy transaction"} = V1.decode(adversarial)
    end

    test "decode/1 rejects malformed to and data fields without raising" do
      malformed_to =
        ExRLP.encode([
          <<1>>,
          <<100_000_000_000::40>>,
          <<100_000::24>>,
          [<<1::160>>],
          <<2>>,
          <<1, 2, 3>>,
          <<42>>,
          <<1::256>>,
          <<2::256>>
        ])

      malformed_data =
        ExRLP.encode([
          <<1>>,
          <<100_000_000_000::40>>,
          <<100_000::24>>,
          <<1::160>>,
          <<2>>,
          [<<1, 2, 3>>],
          <<42>>,
          <<1::256>>,
          <<2::256>>
        ])

      short_to =
        ExRLP.encode([
          <<1>>,
          <<100_000_000_000::40>>,
          <<100_000::24>>,
          <<1>>,
          <<2>>,
          <<1, 2, 3>>,
          <<42>>,
          <<1::256>>,
          <<2::256>>
        ])

      assert {:error, "invalid legacy transaction"} = V1.decode(malformed_to)
      assert {:error, "invalid legacy transaction"} = V1.decode(malformed_data)
      assert {:error, "invalid legacy transaction"} = V1.decode(short_to)
    end
  end

  defp v4_transaction(authorization_list) do
    1
    |> V4.new(
      {1, :gwei},
      {100, :gwei},
      100_000,
      <<1::160>>,
      {2, :wei},
      <<1, 2, 3>>,
      [],
      authorization_list,
      :mainnet
    )
    |> V4.add_signature(<<1::256, 2::256, 1>>)
  end

  defp encoded_v4_with_authorizations(authorization_list) do
    <<0x04, payload::binary>> = V4.encode(v4_transaction([signed_authorization(1, <<2::160>>, 7)]))
    fields = payload |> ExRLP.decode() |> List.replace_at(9, authorization_list)
    <<0x04>> <> ExRLP.encode(fields)
  end

  defp v2930_transaction do
    V_2930.new(
      1,
      {1, :gwei},
      100_000,
      <<1::160>>,
      {2, :wei},
      <<1, 2, 3>>,
      [{<<2::160>>, [<<22::256>>]}],
      :goerli
    )
  end

  defp v2930_raw do
    ~h[0x01f86e018085012a522a31830186a094c02953f316c5c18808e2d3961424f952788d69f587470d07cc2d276080c080a0db55cfd6a6b449e82e05bf465b64d679b7e6030dacab412b7867d83cacabe07da07e1452c5ba57f8ab8a34aa6405e44bd6536d6fd1ff0b44d3360f05832d824c39]
  end

  defp v2930_payload(overrides) do
    [
      Keyword.get(overrides, :chain_id, <<1>>),
      Keyword.get(overrides, :nonce, <<>>),
      Keyword.get(overrides, :gas_price, <<1>>),
      Keyword.get(overrides, :gas_limit, <<0x52, 0x08>>),
      Keyword.get(overrides, :destination, <<1::160>>),
      Keyword.get(overrides, :amount, <<>>),
      Keyword.get(overrides, :data, <<>>),
      Keyword.get(overrides, :access_list, [])
    ]
  end

  defp v2930_signed_payload(overrides) do
    v2930_payload(overrides) ++
      [
        Keyword.get(overrides, :signature_y_parity, <<>>),
        Keyword.get(overrides, :signature_r, <<1>>),
        Keyword.get(overrides, :signature_s, <<2>>)
      ]
  end

  defp v2930_encode(fields), do: <<0x01>> <> ExRLP.encode(fields)

  defp v3_transaction do
    V3.new(
      1,
      {1, :gwei},
      {100, :gwei},
      100_000,
      <<1::160>>,
      {2, :wei},
      <<1, 2, 3>>,
      [{<<2::160>>, [<<22::256>>]}],
      {1, :wei},
      [<<1, 0::248>>],
      :goerli
    )
  end

  defp signed_authorization(chain_id, address, nonce) do
    {chain_id, address, nonce, false, <<1::256>>, <<2::256>>}
  end

  defp encode_authorization_for_test({chain_id, address, nonce, y_parity, r, s}) do
    [chain_id, address, nonce, if(y_parity, do: 1, else: 0), r, s]
  end
end
