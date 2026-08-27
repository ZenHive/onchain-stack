defmodule Onchain.Tempo.Verification.DifferentialTest do
  use ExUnit.Case, async: true

  alias Cartouche.Hash
  alias Cartouche.Signer.Curvy
  alias Onchain.Tempo.TIP20
  alias Onchain.Tempo.Transaction
  alias Onchain.Tempo.Transaction.Builder
  alias Onchain.Tempo.Verification.SpecEncoder
  alias Onchain.Tempo.Verification.Vectors

  @moduletag :verification

  @token Base.decode16!("20c0000000000000000000000000000000000000", case: :lower)
  @recipient Base.decode16!("70997970c51812dc3a010c7d01b50e0d17dc79c8", case: :lower)
  @transfer_data TIP20.transfer_calldata(@recipient, 1_000_000)

  test "oracle metadata pins ox 1.7.2 TxEnvelopeTempo" do
    meta = Vectors.oracle_meta()
    assert meta["package"] == "ox"
    assert meta["version"] == "1.7.2"
    assert meta["import"] =~ "TxEnvelopeTempo"
  end

  test "self-paid bytes, keccak hash and recovered sender match ox" do
    vec = Vectors.case!("self_paid_transfer")
    keys = Vectors.keys()

    fields = self_paid_fields()
    unsigned = SpecEncoder.sender_payload(fields)
    assert SpecEncoder.to_hex(unsigned) == vec["unsigned"]
    assert "0x" <> Base.encode16(Hash.keccak(unsigned), case: :lower) == vec["sign_payload"]

    {:ok, hex} =
      Builder.build_signed_transfer(
        private_key: keys["sender_private_key"],
        token: @token,
        recipient: @recipient,
        amount: 1_000_000,
        chain_id: 42_431,
        rpc_url: "http://localhost",
        nonce: 0,
        gas_limit: 500_000,
        fee_token: @token
      )

    assert String.downcase(hex) == String.downcase(vec["serialized"])
    assert {:ok, tx} = Transaction.deserialize(vec["serialized"])
    assert {:ok, sender} = Transaction.sender(tx)
    assert "0x" <> Base.encode16(sender, case: :lower) == String.downcase(vec["sender"])
    assert tx_hash(vec["serialized"]) == vec["tx_hash"]
  end

  test "fee-payer placeholder, 0x78 preimage and co-sign match ox" do
    vec = Vectors.case!("fee_payer_placeholder")
    keys = Vectors.keys()
    fee_key = decode_key(keys["fee_payer_private_key"])

    fields = Map.merge(self_paid_fields(), %{nonce: 7, fee_payer?: true, fee_token: <<>>})
    unsigned = SpecEncoder.sender_payload(fields)
    assert SpecEncoder.to_hex(unsigned) == vec["unsigned"]
    assert "0x" <> Base.encode16(Hash.keccak(unsigned), case: :lower) == vec["sign_payload"]

    {:ok, expected_sender} = Curvy.get_address(decode_key(keys["sender_private_key"]))
    fp_payload = SpecEncoder.fee_payer_payload(Map.put(fields, :fee_token, @token), expected_sender)
    assert <<0x78, _::binary>> = fp_payload
    assert "0x" <> Base.encode16(Hash.keccak(fp_payload), case: :lower) == vec["fee_payer_sign_payload"]

    {:ok, hex} =
      Builder.build_fee_payer_transfer(
        private_key: keys["sender_private_key"],
        token: @token,
        recipient: @recipient,
        amount: 1_000_000,
        chain_id: 42_431,
        rpc_url: "http://localhost",
        nonce: 7,
        gas_limit: 500_000
      )

    assert String.downcase(hex) == String.downcase(vec["serialized"])
    {:ok, tx} = Transaction.deserialize(hex)
    {:ok, cosigned} = Transaction.cosign_fee_payer(tx, fee_key, @token)
    assert String.downcase(cosigned.raw) == String.downcase(vec["cosigned"])
    {:ok, sender} = Transaction.sender(cosigned)
    assert sender == expected_sender
  end

  test "ox boundary, access-list and multicall envelopes deserialize with matching identities" do
    for name <- ["boundary_numeric", "access_list", "multicall"] do
      vec = Vectors.case!(name)
      assert {:ok, tx} = Transaction.deserialize(vec["serialized"])
      assert {:ok, sender} = Transaction.sender(tx)
      assert "0x" <> Base.encode16(sender, case: :lower) == String.downcase(vec["sender"])
      assert tx_hash(vec["serialized"]) == vec["tx_hash"]
      refute Enum.empty?(tx.calls)
    end
  end

  test "spec encoder reproduces ox unsigned bytes for the self-paid and fee-payer cases" do
    assert SpecEncoder.to_hex(SpecEncoder.sender_payload(self_paid_fields())) ==
             Vectors.case!("self_paid_transfer")["unsigned"]

    placeholder = Map.merge(self_paid_fields(), %{nonce: 7, fee_payer?: true, fee_token: <<>>})

    assert SpecEncoder.to_hex(SpecEncoder.sender_payload(placeholder)) ==
             Vectors.case!("fee_payer_placeholder")["unsigned"]
  end

  defp self_paid_fields do
    %{
      chain_id: 42_431,
      max_priority_fee_per_gas: 1_000_000_000,
      max_fee_per_gas: 25_000_000_000,
      gas_limit: 500_000,
      calls: [%{to: @token, value: 0, input: @transfer_data}],
      access_list: [],
      nonce_key: 0,
      nonce: 0,
      valid_before: 0,
      valid_after: 0,
      fee_token: @token,
      fee_payer?: false
    }
  end

  defp tx_hash("0x" <> hex) do
    {:ok, bin} = Base.decode16(hex, case: :mixed)
    "0x" <> Base.encode16(Hash.keccak(bin), case: :lower)
  end

  defp decode_key("0x" <> hex), do: Base.decode16!(hex, case: :lower)
end
