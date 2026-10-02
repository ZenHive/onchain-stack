defmodule Onchain.Tempo.Verification.AllSignaturesTest do
  use ExUnit.Case, async: true

  alias Onchain.Tempo.Codec
  alias Onchain.Tempo.Transaction

  @fixture "priv/verification/0x76/all_signatures.json"
  @external_resource @fixture
  @vectors @fixture |> File.read!() |> Jason.decode!()

  # spec-tags: TEMPO-2, TEMPO-4, TEMPO-5, TEMPO-6
  test "every signature and key type matches the independent ox oracle" do
    assert @vectors["oracle"]["version"] == "1.8.5"

    for {name, vector} <- @vectors["cases"] do
      assert {:ok, tx} = Transaction.deserialize(vector["serialized"]), name
      refute Map.has_key?(tx, :fields)
      assert {:ok, raw} = Transaction.serialize(tx)
      assert raw == vector["serialized"], name
      assert {:ok, signing_hash} = Transaction.signing_hash(tx)
      assert Codec.hex(signing_hash) == vector["signing_hash"], name
      assert {:ok, hash} = Transaction.hash(tx)
      assert Codec.hex(hash) == vector["tx_hash"], name
      assert {:ok, sender} = Transaction.sender(tx)
      assert Codec.hex(sender) == vector["sender"], name

      assert {:ok, cosigned} =
               Transaction.cosign_fee_payer(
                 tx,
                 Codec.bytes(@vectors["fee_payer_private_key"]),
                 Codec.bytes(@vectors["fee_token"])
               )

      assert cosigned.raw == vector["cosigned"], name
      assert {:ok, ^sender} = Transaction.sender(cosigned)
      assert {:ok, cosigned_raw} = Transaction.serialize(cosigned)
      assert cosigned_raw == cosigned.raw

      if tx.key_authorization do
        assert {:ok, key_hash} = Transaction.key_authorization_hash(tx.key_authorization)
        assert Codec.hex(key_hash) == vector["key_hash"], name
        assert {:ok, original} = Transaction.signing_hash(tx)
        assert {:ok, changed} = Transaction.signing_hash(%{tx | key_authorization: nil})
        refute original == changed
        changed_request = Codec.request(%{tx | key_authorization: nil, fee_token: Codec.bytes(@vectors["fee_token"])})
        assert {:ok, changed_hash} = Codec.run("fee_hash", Map.put(changed_request, "sender", Codec.hex(sender)))
        refute changed_hash == vector["fee_payer_hash"]
      end
    end
  end

  # spec-tags: TEMPO-4, TEMPO-5
  test "recovery validates inner signatures instead of trusting keychain user addresses" do
    for name <- ["p256", "webAuthn", "keychain_v1_p256", "keychain_v2_webAuthn"] do
      assert {:ok, tx} = Transaction.deserialize(@vectors["cases"][name]["serialized"])
      tampered = %{tx | signature: corrupt_signature(tx.signature)}
      assert {:error, _} = Transaction.sender(tampered)

      assert {:error, _} =
               Transaction.cosign_fee_payer(
                 tampered,
                 Codec.bytes(@vectors["fee_payer_private_key"]),
                 Codec.bytes(@vectors["fee_token"])
               )
    end
  end

  defp corrupt_signature({:keychain, version, user, inner}), do: {:keychain, version, user, corrupt_signature(inner)}
  defp corrupt_signature({tag, signature}), do: {tag, %{signature | s: <<0::256>>}}

  # spec-tags: TEMPO-6
  test "every upstream TempoTransaction field is represented exactly once" do
    vector = @vectors["cases"]["p256"]
    assert {:ok, decoded} = Codec.run("decode", %{"raw" => vector["serialized"]})

    upstream =
      decoded["transaction"]
      |> Map.keys()
      |> Enum.map(fn
        "gas" -> "gas_limit"
        "aaAuthorizationList" -> "tempo_authorization_list"
        key -> Macro.underscore(key)
      end)
      |> Enum.sort()

    public =
      Transaction.__struct__()
      |> Map.from_struct()
      |> Map.drop([:signature, :raw])
      |> Map.keys()
      |> Enum.map(&Atom.to_string/1)
      |> Enum.sort()

    assert public == upstream
  end

  # spec-tags: TEMPO-5
  test "truncation, unknown tags and invalid P256 and WebAuthn lengths return errors" do
    raw = Codec.bytes(@vectors["cases"]["p256"]["serialized"])

    for size <- 0..(byte_size(raw) - 1) do
      assert {:error, _} = Transaction.deserialize(Codec.hex(binary_part(raw, 0, size)))
    end

    <<0x76, body::binary>> = raw
    fields = ExRLP.decode(body)

    for signature <- [
          <<255, 0>>,
          <<1>>,
          <<1, 0::1024>>,
          <<1, 0::1040>>,
          <<2>>,
          <<2, 0::1016>>,
          <<2, 0::20_000>>,
          <<3>>,
          <<4>>
        ] do
      malformed = <<0x76>> <> ExRLP.encode(List.replace_at(fields, -1, signature))
      assert {:error, _} = Transaction.deserialize(Codec.hex(malformed))
    end
  end
end
