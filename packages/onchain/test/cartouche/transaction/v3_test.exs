defmodule Cartouche.Transaction.V3Test do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Test.Signer
  alias Cartouche.Transaction.V3

  doctest V3

  @sender ~h[0x0d3250c3d5facb74ac15834096397a3ef790ec99]
  @tx_hash ~h[0xbbc6c82f2d81479e2a7ffa61529fba4bd4671a8aefb69a261f6a9b07e46b7f79]
  @raw_mainnet_blob_tx Cartouche.Hex.decode_hex!(
                         "0x03f9073801820f0f85012a05f200850c086e94f4837a120094a8cb082a5a689e0d594d7da1e2d72a3d63adc1bd80b906a4701f58c5000000000000000000000000000000000000000000000000000000000007127561c3890e6e7acdcc8f32d3ef78fd8aa838eda2bd469d64dbd896d327ec7343050000000000000000000000000000000000000000000000000000000010a889f400000000000000000000000000000000000000000000000000000000000000012d686af59d517ebe205cd78f9edf02d5b99b6c6db0c2f6cc080cc52a390f36c0543d0c9227972a0e69cf46455ba305bb91408b815f59958cf72d7ee37ac8acc00000000000000000000000000000000000000000000000000000000065f5e8dddc3b2f9107f9e5d31540981e6a47cdb7556bdfd61930546fe210b9b2a7d211e200000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000712760000000000000000000000000000000000000000000000000000000065f5e9630000000000000000000000000000000000000000000000000000000010a88db34242c7f4ec2288aaa6d8df2d7f6f6cc4459916781cc837266e8f0456d88d8b0d0000000000000000000000000000000000000000000000000000000000000001a7a537d88c1e999de32dc93d9fafddf28ae5558615366b5212341e3613436d3138a9e77f0e86ddf424f60d5b24a014ec1b3bc6cfac046fd7d754b48ff037e1780c5ba22b2dd7e3df9f48e7446742a5a1ec714a261a66168a12436602426812bf00000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000480000000000000000000000000000000000000000000000000000000000000031800000000000000000000000000000000000000000000800b000000000000000000000000000000000000000000000000000000000000000461c3890e6e7acdcc8f32d3ef78fd8aa838eda2bd469d64dbd896d327ec734305000006ce000000000000000000000000000000000000800b000000000000000000000000000000000000000000000000000000000000000300000000000000000000000065f5e96300000000000000000000000065f5e9f2000106ce00000000000000000000000000000000000080010000000000000000000000000000000000000000000000000000000000000005a7a537d88c1e999de32dc93d9fafddf28ae5558615366b5212341e3613436d31000106ce000000000000000000000000000000000000800100000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000001000106ce00000000000000000000000000000000000080110000000000000000000000000000000000000000000000000000000000000007a1e154b2acff09f593d0eb054b916f5450c65c2a64a8a0b3788198060bba4429000106ce000000000000000000000000000000000000801100000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000000106ce00000000000000000000000000000000000080080000000000000000000000000000000000000000000000000000000000000000a7617a951a783edf04ba87c0b7944f8ce74206aabdfcc7527618c118fca91553000106ce00000000000000000000000000000000000080080000000000000000000000000000000000000000000000000000000000000001aa6bfca14be7385ac9bdae7be5a71d2bf908a6c282d55222815a592c25512f65000106ce0000000000000000000000000000000000008008000000000000000000000000000000000000000000000000000000000000000238cf0f95ceb91d1ff44b69824701426427c4e928bab602e02a3dbac67a5a9d7e0000000000000000000000000000000000000000000000000000000000000000000000000000009101a4c0081e5e8061f31bad9c81f28a50955924a27e7f2f9e8b0b5c210dafe9aa974d4d532d4759c00cc23f5c1946a66c01a51be543454fd9aa44ec538b5853d072cc666d30654acefbcb9286ef8ebc8dc1b81e16c39056e0cafb7392ea1d15ab048b072278f87a5b54cbf5eb66c4e51f074a7448546a1ed680f1a7ce6317eea04014c72d621414369c05045f4f0709d755000000000000000000000000000000c001e1a001908125950e083b4c461ec9bb659dbac852ca402a01a571c1798757c9526a4c80a0cbe8ed587ca96033da54b83ba8d39172ac8d5064f0e1570dbf58f6189f192762a028a80b2784ff3d163f33190ce755503f55503497c87966ede3b0e3f17bde34a7"
                       )

  describe "encode/1 and decode/1" do
    test "constructs unsigned transactions with default chain and nil fee pass-through" do
      tx = V3.new(1, nil, nil, 100_000, <<1::160>>, 0, <<>>, [], nil, [<<1, 0::248>>])

      assert tx.chain_id == Cartouche.Application.chain_id()
      assert tx.max_priority_fee_per_gas == nil
      assert tx.max_fee_per_gas == nil
      assert tx.max_fee_per_blob_gas == nil
      assert tx.signature_y_parity == nil
      assert tx.signature_r == nil
      assert tx.signature_s == nil
    end

    test "round-trips a representative signed blob transaction" do
      tx = representative_tx()

      assert {:ok, decoded} = tx |> V3.encode() |> V3.decode()
      assert decoded == tx
    end

    test "encodes unsigned payload without signature fields for signing" do
      assert "0x03F84F0101843B9ACA0085174876E800830186A09400000000000000000000000000000000000000010283010203C001E1A00100000000000000000000000000000000000000000000000000000000000000" =
               representative_tx()
               |> Map.merge(%{signature_y_parity: nil, signature_r: nil, signature_s: nil})
               |> V3.encode()
               |> Cartouche.Hex.encode_big_hex()
    end

    test "decodes non-empty access lists" do
      tx = Map.put(representative_tx(), :access_list, [{<<2::160>>, [<<22::256>>]}])

      assert {:ok, decoded} = tx |> V3.encode() |> V3.decode()
      assert decoded.access_list == [{<<2::160>>, [<<22::256>>]}]
    end
  end

  describe "sign/2 and recover_signer/1" do
    test "signs with the existing signer process and recovers the signer" do
      signer = Signer.start_signer()

      {:ok, signed} =
        representative_tx()
        |> Map.merge(%{signature_y_parity: nil, signature_r: nil, signature_s: nil})
        |> V3.sign(signer)

      assert signed.signature_y_parity in [true, false]
      assert byte_size(signed.signature_r) == 32
      assert byte_size(signed.signature_s) == 32

      {:ok, recovered} = V3.recover_signer(signed)
      assert Cartouche.Hex.to_address(recovered) == "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
    end

    test "reports missing signature on unsigned transactions" do
      assert {:error, "transaction missing signature"} =
               representative_tx()
               |> Map.merge(%{signature_y_parity: nil, signature_r: nil, signature_s: nil})
               |> V3.get_signature()
    end

    test "normalizes packed EIP-155-style recovery bits" do
      tx = Map.merge(representative_tx(), %{signature_y_parity: nil, signature_r: nil, signature_s: nil})

      assert %V3{signature_y_parity: true} = V3.add_signature(tx, <<1::256, 2::256, 38::8>>)
    end
  end

  describe "hash/1" do
    test "hashes signed typed transaction bytes" do
      tx = representative_tx()

      assert V3.hash(tx) == Cartouche.Hash.keccak(V3.encode(tx))
    end
  end

  describe "mainnet EIP-4844 vector" do
    test "decodes, hashes, re-encodes, and recovers the sender" do
      assert {:ok, tx} = V3.decode(@raw_mainnet_blob_tx)

      assert tx.chain_id == 1
      assert tx.nonce == 0xF0F
      assert tx.max_priority_fee_per_gas == 0x12A05F200
      assert tx.max_fee_per_gas == 0xC086E94F4
      assert tx.gas_limit == 0x7A1200
      assert tx.destination == ~h[0xa8cb082a5a689e0d594d7da1e2d72a3d63adc1bd]
      assert tx.amount == 0
      assert tx.access_list == []
      assert tx.max_fee_per_blob_gas == 1
      assert tx.blob_versioned_hashes == [~h[0x01908125950e083b4c461ec9bb659dbac852ca402a01a571c1798757c9526a4c]]
      assert tx.signature_y_parity == false
      assert tx.signature_r == ~h[0xcbe8ed587ca96033da54b83ba8d39172ac8d5064f0e1570dbf58f6189f192762]
      assert tx.signature_s == ~h[0x28a80b2784ff3d163f33190ce755503f55503497c87966ede3b0e3f17bde34a7]

      assert V3.encode(tx) == @raw_mainnet_blob_tx
      assert V3.hash(tx) == @tx_hash
      assert {:ok, @sender} = V3.recover_signer(tx)
    end
  end

  describe "decode/1 malformed input rejection" do
    test "rejects non-v3 typed transactions" do
      assert {:error, "invalid v3 transaction"} = V3.decode(<<0x02, 0xC0>>)
    end

    test "rejects malformed RLP field count" do
      assert {:error, "invalid v3 transaction"} = V3.decode(<<0x03>> <> ExRLP.encode([1, 2, 3]))
    end

    test "rejects contract-creation destination" do
      malformed =
        representative_tx()
        |> Map.put(:destination, <<>>)
        |> V3.encode()

      assert {:error, "invalid v3 transaction"} = V3.decode(malformed)
    end

    test "rejects non-list access_list" do
      bytes =
        <<0x03>> <>
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
            [<<1, 0::248>>],
            1,
            <<1::256>>,
            <<2::256>>
          ])

      assert {:error, "invalid v3 transaction"} = V3.decode(bytes)
    end

    test "rejects non-list blob_versioned_hashes" do
      bytes =
        <<0x03>> <>
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
            <<"not a list">>,
            1,
            <<1::256>>,
            <<2::256>>
          ])

      assert {:error, "invalid v3 transaction"} = V3.decode(bytes)
    end

    test "rejects malformed access-list entries" do
      bytes =
        <<0x03>> <>
          ExRLP.encode([
            1,
            1,
            1_000_000_000,
            100_000_000_000,
            100_000,
            <<1::160>>,
            2,
            <<>>,
            [[<<1::160>>, <<"not a list">>]],
            1,
            [<<1, 0::248>>],
            1,
            <<1::256>>,
            <<2::256>>
          ])

      assert {:error, "invalid v3 transaction"} = V3.decode(bytes)
    end

    test "encode and decode reject non-word blob versioned hashes symmetrically" do
      malformed = Map.put(representative_tx(), :blob_versioned_hashes, [<<1, 2, 3>>])

      assert_raise ArgumentError,
                   "blob_versioned_hashes must be a non-empty list of 32-byte hashes prefixed with 0x01",
                   fn -> V3.encode(malformed) end

      assert {:error, "invalid v3 transaction"} = V3.decode(encoded_with_blob_hashes([<<1, 2, 3>>]))
    end

    test "encode and decode reject blob hashes whose leading byte is not 0x01" do
      malformed = Map.put(representative_tx(), :blob_versioned_hashes, [<<0, 0::248>>])

      assert_raise ArgumentError,
                   "blob_versioned_hashes must be a non-empty list of 32-byte hashes prefixed with 0x01",
                   fn -> V3.encode(malformed) end

      assert {:error, "invalid v3 transaction"} = V3.decode(encoded_with_blob_hashes([<<0, 0::248>>]))
    end

    test "encode and decode reject empty blob versioned hash lists symmetrically" do
      malformed = Map.put(representative_tx(), :blob_versioned_hashes, [])
      encode = Function.capture(V3, :encode, 1)

      assert_raise ArgumentError,
                   "blob_versioned_hashes must be a non-empty list of 32-byte hashes prefixed with 0x01",
                   fn -> encode.(malformed) end

      assert {:error, "invalid v3 transaction"} = V3.decode(encoded_with_blob_hashes([]))
    end

    test "encode and decode reject malformed access-list storage keys symmetrically" do
      malformed = Map.put(representative_tx(), :access_list, [{<<1::160>>, [<<1, 2, 3>>]}])
      encode = Function.capture(V3, :encode, 1)

      assert_raise ArgumentError,
                   "access_list entries must contain a 20-byte address and 32-byte storage keys",
                   fn -> encode.(malformed) end

      <<0x03, payload::binary>> = V3.encode(representative_tx())
      fields = payload |> ExRLP.decode() |> List.replace_at(8, [[<<1::160>>, [<<1, 2, 3>>]]])
      assert {:error, "invalid v3 transaction"} = V3.decode(<<0x03>> <> ExRLP.encode(fields))
    end

    test "encode rejects a non-list access list" do
      malformed = Map.put(representative_tx(), :access_list, :not_a_list)
      encode = Function.capture(V3, :encode, 1)

      assert_raise ArgumentError,
                   "access_list entries must contain a 20-byte address and 32-byte storage keys",
                   fn -> encode.(malformed) end
    end

    test "rejects signatures wider than 32 bytes" do
      malformed =
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
            [<<1, 0::248>>],
            1,
            <<1, 0::256>>,
            <<2::256>>
          ])

      assert {:error, "invalid v3 transaction"} = V3.decode(malformed)
    end
  end

  defp representative_tx do
    1
    |> V3.new(
      {1, :gwei},
      {100, :gwei},
      100_000,
      <<1::160>>,
      {2, :wei},
      <<1, 2, 3>>,
      [],
      {1, :wei},
      [<<1, 0::248>>],
      :mainnet
    )
    |> V3.add_signature(true, <<0x01::256>>, <<0x02::256>>)
  end

  defp encoded_with_blob_hashes(blob_versioned_hashes) do
    <<0x03, payload::binary>> = V3.encode(representative_tx())
    fields = payload |> ExRLP.decode() |> List.replace_at(10, blob_versioned_hashes)
    <<0x03>> <> ExRLP.encode(fields)
  end
end
