defmodule Onchain.Tempo.Verification.NativeTest do
  use ExUnit.Case, async: true

  alias Onchain.Hash
  alias Onchain.Tempo.Codec
  alias Onchain.Tempo.Native
  alias Onchain.Tempo.Transaction
  alias Onchain.Tempo.Transaction.Builder
  alias Onchain.Tempo.Verification.Vectors

  @token "0x20c0000000000000000000000000000000000000"
  @fixture "priv/verification/0x76/tempo_primitives_key_authorization.json"

  test "all legacy vectors retain unsigned bytes, hashes, signed bytes and cosigned bytes" do
    capture = load("priv/verification/0x76/legacy_capture.json")
    fee_key = Codec.bytes(Vectors.keys()["fee_payer_private_key"])

    for {_name, vector} <- capture["cases"] do
      assert {:ok, tx} = Transaction.deserialize(vector["serialized"])
      assert {:ok, prepared} = Codec.run("prepare", Codec.request(tx))
      assert prepared["payload"] == vector["unsigned"]
      assert prepared["hash"] == vector["signing_hash"]
      assert Codec.hex(Hash.keccak(Codec.bytes(tx.raw))) == vector["tx_hash"]
      assert {:ok, raw} = Codec.run("serialize", Codec.request(tx))
      assert raw == vector["serialized"]
      assert {:ok, cosigned} = Transaction.cosign_fee_payer(tx, fee_key, Codec.bytes(@token))
      assert cosigned.raw == vector["cosigned"]
    end
  end

  # spec-tags: TEMPO-2, TEMPO-3
  test "key authorization matches pinned primitives bytes and the spec's signing domains" do
    vector = load(@fixture)
    keys = Vectors.keys()
    assert vector["oracle"]["version"] == "1.11.0"

    assert {:ok, raw} =
             Builder.build_fee_payer_transfer(
               private_key: keys["sender_private_key"],
               token: @token,
               recipient: keys["fee_payer_address"],
               amount: 1_000_000,
               chain_id: 42_431,
               rpc_url: "http://localhost",
               nonce: 7,
               gas_limit: 500_000,
               key_authorization: elem(Transaction.deserialize(vector["serialized"]), 1).key_authorization
             )

    assert raw == vector["serialized"]
    assert {:ok, tx} = Transaction.deserialize(raw)
    assert {:ok, prepared} = Codec.run("prepare", Codec.request(tx))
    assert prepared == %{"payload" => vector["unsigned"], "hash" => vector["signing_hash"]}
    assert {:ok, sender} = Transaction.sender(tx)
    assert Codec.hex(sender) == vector["sender"]

    <<0x76, body::binary>> = Codec.bytes(raw)
    fields = body |> ExRLP.decode() |> Enum.drop(-1)
    assert Enum.count_until(fields, 15) == 14
    assert is_list(List.last(fields))
    assert Codec.hex(<<0x76>> <> ExRLP.encode(fields)) == vector["unsigned"]
    fp_fields = fields |> List.replace_at(10, Codec.bytes(@token)) |> List.replace_at(11, sender)
    preimage = <<0x78>> <> ExRLP.encode(fp_fields)
    assert Codec.hex(preimage) == vector["fee_payer_preimage"]
    assert Codec.hex(Hash.keccak(preimage)) == vector["fee_payer_hash"]
    refute Codec.hex(Hash.keccak(<<0x78>> <> ExRLP.encode(Enum.drop(fp_fields, -1)))) == vector["fee_payer_hash"]

    assert {:ok, cosigned} =
             Transaction.cosign_fee_payer(tx, Codec.bytes(keys["fee_payer_private_key"]), Codec.bytes(@token))

    assert cosigned.raw == vector["cosigned"]
    assert {:ok, ^sender} = Transaction.sender(cosigned)
    assert {:ok, payer} = Codec.run("fee_payer", Map.put(Codec.request(cosigned), "sender", Codec.hex(sender)))
    assert payer == vector["fee_payer"]
    assert {:ok, hash} = Codec.run("fee_hash", Map.put(Codec.request(cosigned), "sender", Codec.hex(sender)))
    assert hash == vector["fee_payer_hash"]

    changed = put_in(Codec.request(tx), ["transaction", "keyAuthorization"], nil)
    assert {:ok, changed_payload} = Codec.run("prepare", changed)
    refute changed_payload["hash"] == prepared["hash"]
  end

  # spec-tags: TEMPO-4
  test "key hashes accept all supported access key types" do
    vector = load(@fixture)
    assert {:ok, tx} = Transaction.deserialize(vector["serialized"])

    for key_type <- [:secp256k1, :p256, :webauthn] do
      assert {:ok, hash} = Transaction.key_authorization_hash(%{tx.key_authorization | key_type: key_type})
      assert byte_size(hash) == 32
    end
  end

  test "native numeric widths reject overflow without truncating fields" do
    assert {:ok, tx} = Transaction.deserialize(Vectors.case!("self_paid_transfer")["serialized"])

    for {field, bits} <- [{"chainId", 64}, {"gas", 64}, {"nonce", 64}, {"maxFeePerGas", 128}, {"nonceKey", 256}] do
      fields = put_in(Codec.request(tx), ["transaction", field], Codec.quantity(Bitwise.bsl(1, bits)))
      assert {:error, reason} = Codec.run("prepare", fields)
      assert is_binary(reason)
    end
  end

  test "native boundary reports malformed requests and unknown operations as tagged errors" do
    assert {:error, _} = Native.transaction_json("{")
    assert {:error, "missing operation"} = Native.transaction_json("{}")
    assert {:error, "missing raw"} = Codec.run("decode", %{})
    assert {:ok, tx} = Transaction.deserialize(Vectors.case!("self_paid_transfer")["serialized"])
    assert {:error, "unknown operation"} = Codec.run("unknown", Codec.request(tx))

    for raw <- ["0x76", "0x76c0", tx.raw <> "00"] do
      assert {:error, reason} = Transaction.deserialize(raw)
      assert is_binary(reason)
    end
  end

  defp load(path), do: path |> File.read!() |> Jason.decode!()
end
