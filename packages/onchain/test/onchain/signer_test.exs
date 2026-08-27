defmodule Onchain.SignerTest do
  use ExUnit.Case, async: true

  alias Cartouche.Transaction.V2
  alias Onchain.Signer

  # Deterministic test keypair from cartouche docs
  @test_key_hex "0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf"
  @test_key_binary Base.decode16!(
                     "800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf",
                     case: :mixed
                   )
  @test_address "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"
  @test_chain_id 11_155_111
  @dummy_to "0x" <> String.duplicate("ab", 20)

  # --- address_from_key ---

  describe "address_from_key/1" do
    test "derives correct address from binary key" do
      assert {:ok, @test_address} = Signer.address_from_key(@test_key_binary)
    end

    test "derives correct address from hex key with 0x prefix" do
      assert {:ok, @test_address} = Signer.address_from_key(@test_key_hex)
    end

    test "derives correct address from bare hex key" do
      bare = String.replace_prefix(@test_key_hex, "0x", "")
      assert {:ok, @test_address} = Signer.address_from_key(bare)
    end

    test "returns checksummed address (EIP-55)" do
      {:ok, address} = Signer.address_from_key(@test_key_binary)
      assert address =~ ~r/^0x[0-9a-fA-F]{40}$/
      # Verify mixed case (checksummed, not all lowercase)
      refute address == String.downcase(address)
    end

    test "returns error on wrong-length binary" do
      assert {:error, {:invalid_private_key, _}} = Signer.address_from_key(<<1, 2, 3>>)
    end

    test "returns error on non-binary" do
      assert {:error, {:invalid_private_key, 12_345}} = Signer.address_from_key(12_345)
    end

    test "returns error on wrong-length hex" do
      assert {:error, {:invalid_private_key, _}} = Signer.address_from_key("0xdeadbeef")
    end

    test "returns error on zero key (malformed but 32 bytes)" do
      zero_key = <<0::256>>
      assert {:error, {:invalid_private_key, ^zero_key}} = Signer.address_from_key(zero_key)
    end
  end

  # --- build_transaction ---

  describe "build_transaction/3" do
    test "builds V2 struct with correct fields" do
      assert {:ok, %V2{} = trx} =
               Signer.build_transaction(@dummy_to, <<>>, nonce: 0, chain_id: @test_chain_id)

      assert trx.nonce == 0
      assert trx.chain_id == @test_chain_id
      assert trx.data == <<>>
      assert trx.amount == 0
      assert trx.gas_limit == 100_000
      assert trx.access_list == []
      # Signature fields should be nil (unsigned)
      assert is_nil(trx.signature_y_parity)
      assert is_nil(trx.signature_r)
      assert is_nil(trx.signature_s)
    end

    test "accepts integer gas params (wei)" do
      assert {:ok, %V2{} = trx} =
               Signer.build_transaction(@dummy_to, <<>>,
                 nonce: 1,
                 chain_id: @test_chain_id,
                 max_fee_per_gas: 50_000_000_000,
                 max_priority_fee_per_gas: 1_000_000_000
               )

      assert trx.max_fee_per_gas == 50_000_000_000
      assert trx.max_priority_fee_per_gas == 1_000_000_000
    end

    test "accepts {n, :gwei} gas params" do
      assert {:ok, %V2{} = trx} =
               Signer.build_transaction(@dummy_to, <<>>,
                 nonce: 1,
                 chain_id: @test_chain_id,
                 max_fee_per_gas: {50, :gwei},
                 max_priority_fee_per_gas: {1, :gwei}
               )

      assert trx.max_fee_per_gas == 50_000_000_000
      assert trx.max_priority_fee_per_gas == 1_000_000_000
    end

    test "accepts custom value" do
      assert {:ok, %V2{} = trx} =
               Signer.build_transaction(@dummy_to, <<>>,
                 nonce: 0,
                 chain_id: @test_chain_id,
                 value: 1_000_000
               )

      assert trx.amount == 1_000_000
    end

    test "returns error on missing :nonce" do
      assert {:error, {:missing_option, :nonce}} =
               Signer.build_transaction(@dummy_to, <<>>, chain_id: @test_chain_id)
    end

    test "returns error on missing :chain_id" do
      assert {:error, {:missing_option, :chain_id}} =
               Signer.build_transaction(@dummy_to, <<>>, nonce: 0)
    end

    test "returns error on invalid address" do
      assert {:error, {:invalid_address, _}} =
               Signer.build_transaction("0xshort", <<>>, nonce: 0, chain_id: @test_chain_id)
    end

    test "accepts 20-byte binary address" do
      addr_bin = <<0xAB::8, 0::152>>

      assert {:ok, %V2{}} =
               Signer.build_transaction(addr_bin, <<>>, nonce: 0, chain_id: @test_chain_id)
    end

    test "accepts raw binary calldata" do
      raw = <<0xA9, 0x05, 0x9C, 0xBB>>

      assert {:ok, %V2{} = trx} =
               Signer.build_transaction(@dummy_to, raw, nonce: 0, chain_id: @test_chain_id)

      assert trx.data == raw
    end

    test "accepts ABI-encoded calldata via Hex.decode!" do
      # ABI.encode_call returns hex; callers decode to raw binary before passing
      {:ok, hex_calldata} = Onchain.ABI.encode_call("totalSupply()", [])
      raw_calldata = Onchain.Hex.decode!(hex_calldata)

      assert {:ok, %V2{} = trx} =
               Signer.build_transaction(@dummy_to, raw_calldata, nonce: 0, chain_id: @test_chain_id)

      assert byte_size(trx.data) == 4
    end

    test "rejects hex string calldata with helpful error" do
      {:ok, hex_calldata} = Onchain.ABI.encode_call("totalSupply()", [])

      assert {:error, {:hex_calldata, ^hex_calldata, msg}} =
               Signer.build_transaction(@dummy_to, hex_calldata, nonce: 0, chain_id: @test_chain_id)

      assert msg =~ "Hex.decode!"
      assert msg =~ "{:raw, binary}"
    end

    test "rejects empty 0x calldata with helpful error" do
      assert {:error, {:hex_calldata, "0x", msg}} =
               Signer.build_transaction(@dummy_to, "0x", nonce: 0, chain_id: @test_chain_id)

      assert msg =~ "Hex.decode!"
    end

    test "accepts ambiguous raw bytes via {:raw, binary}" do
      raw = "0xAB"

      assert {:ok, %V2{} = trx} =
               Signer.build_transaction(@dummy_to, {:raw, raw}, nonce: 0, chain_id: @test_chain_id)

      assert trx.data == raw
    end

    test "returns error on non-binary calldata" do
      assert {:error, {:invalid_calldata, 12_345}} =
               Signer.build_transaction(@dummy_to, 12_345, nonce: 0, chain_id: @test_chain_id)
    end

    test "returns error on invalid {:raw, value} calldata" do
      assert {:error, {:invalid_calldata, {:raw, 12_345}}} =
               Signer.build_transaction(@dummy_to, {:raw, 12_345}, nonce: 0, chain_id: @test_chain_id)
    end
  end

  # --- sign_transaction ---

  describe "sign_transaction/3" do
    setup do
      {:ok, trx} =
        Signer.build_transaction(@dummy_to, <<>>, nonce: 0, chain_id: @test_chain_id)

      %{unsigned: trx}
    end

    test "populates signature fields", %{unsigned: trx} do
      assert {:ok, %V2{} = signed} = Signer.sign_transaction(trx, @test_key_binary, @test_chain_id)

      assert is_boolean(signed.signature_y_parity)
      assert byte_size(signed.signature_r) == 32
      assert byte_size(signed.signature_s) == 32
    end

    test "recoverable signer matches test address", %{unsigned: trx} do
      {:ok, signed} = Signer.sign_transaction(trx, @test_key_binary, @test_chain_id)
      {:ok, recovered_bin} = V2.recover_signer(signed)
      recovered_addr = Onchain.Address.checksum!(recovered_bin)

      assert recovered_addr == @test_address
    end

    test "accepts hex private key", %{unsigned: trx} do
      assert {:ok, %V2{}} = Signer.sign_transaction(trx, @test_key_hex, @test_chain_id)
    end

    test "returns error on invalid private key", %{unsigned: trx} do
      assert {:error, {:invalid_private_key, _}} =
               Signer.sign_transaction(trx, <<1, 2, 3>>, @test_chain_id)
    end

    test "returns error on zero key (malformed but 32 bytes)", %{unsigned: trx} do
      zero_key = <<0::256>>

      assert {:error, {:invalid_private_key, ^zero_key}} =
               Signer.sign_transaction(trx, zero_key, @test_chain_id)
    end
  end

  # --- encode_transaction ---

  describe "encode_transaction/1" do
    setup do
      {:ok, trx} =
        Signer.build_transaction(@dummy_to, <<>>, nonce: 0, chain_id: @test_chain_id)

      {:ok, signed} = Signer.sign_transaction(trx, @test_key_binary, @test_chain_id)
      %{signed: signed, unsigned: trx}
    end

    test "returns 0x-prefixed hex", %{signed: signed} do
      assert {:ok, hex} = Signer.encode_transaction(signed)
      assert String.starts_with?(hex, "0x")
      # Verify it's valid hex after 0x
      bare = String.replace_prefix(hex, "0x", "")
      assert Regex.match?(~r/^[0-9a-f]+$/, bare)
    end

    test "returns error on unsigned transaction", %{unsigned: unsigned} do
      assert {:error, {:encode_error, :unsigned_transaction}} = Signer.encode_transaction(unsigned)
    end

    test "encoded transaction is decodable back via V2.decode", %{signed: signed} do
      {:ok, hex} = Signer.encode_transaction(signed)
      raw = Onchain.Hex.decode!(hex)
      assert {:ok, %V2{}} = V2.decode(raw)
    end
  end

  # --- full roundtrip ---

  describe "full roundtrip" do
    test "build → sign → encode → decode → recover_signer → matches test address" do
      {:ok, unsigned} =
        Signer.build_transaction(@dummy_to, <<>>, nonce: 42, chain_id: @test_chain_id)

      {:ok, signed} = Signer.sign_transaction(unsigned, @test_key_binary, @test_chain_id)
      {:ok, hex} = Signer.encode_transaction(signed)

      # Decode back
      raw = Onchain.Hex.decode!(hex)
      {:ok, decoded} = V2.decode(raw)

      # Recover signer
      {:ok, recovered_bin} = V2.recover_signer(decoded)
      recovered_addr = Onchain.Address.checksum!(recovered_bin)

      assert recovered_addr == @test_address
    end

    test "roundtrip with ABI-encoded calldata preserves correct data" do
      {:ok, hex_calldata} = Onchain.ABI.encode_call("totalSupply()", [])
      raw_calldata = Onchain.Hex.decode!(hex_calldata)

      {:ok, unsigned} =
        Signer.build_transaction(@dummy_to, raw_calldata, nonce: 1, chain_id: @test_chain_id)

      {:ok, signed} = Signer.sign_transaction(unsigned, @test_key_binary, @test_chain_id)
      {:ok, encoded_hex} = Signer.encode_transaction(signed)

      # Decode and verify data is raw binary (4-byte selector), not hex string
      raw = Onchain.Hex.decode!(encoded_hex)
      {:ok, decoded} = V2.decode(raw)
      assert byte_size(decoded.data) == 4
    end
  end

  # --- send_transaction ---

  describe "send_transaction/3" do
    test "returns error on missing :private_key" do
      assert {:error, {:missing_option, :private_key}} =
               Signer.send_transaction(@dummy_to, <<>>,
                 nonce: 0,
                 chain_id: @test_chain_id,
                 rpc_url: "http://localhost:1"
               )
    end

    test "returns error on missing :chain_id" do
      assert {:error, {:missing_option, :chain_id}} =
               Signer.send_transaction(@dummy_to, <<>>,
                 nonce: 0,
                 private_key: @test_key_hex,
                 rpc_url: "http://localhost:1"
               )
    end

    # Auto-estimate path (no :gas_limit) must reject malformed calldata with the
    # same error tuple build_transaction/3 returns, NOT crash in the estimate's
    # hex encoder. rpc_url is unreachable: reaching eth_estimateGas would surface a
    # connection error, so the calldata error proves no RPC was attempted.
    test "rejects non-binary calldata before estimating gas (no :gas_limit)" do
      assert {:error, {:invalid_calldata, :not_binary}} =
               Signer.send_transaction(@dummy_to, :not_binary,
                 nonce: 0,
                 chain_id: @test_chain_id,
                 private_key: @test_key_hex,
                 rpc_url: "http://localhost:1"
               )
    end

    test "rejects 0x-string calldata before estimating gas (no :gas_limit)" do
      assert {:error, {:hex_calldata, "0xabcd", _msg}} =
               Signer.send_transaction(@dummy_to, "0xabcd",
                 nonce: 0,
                 chain_id: @test_chain_id,
                 private_key: @test_key_hex,
                 rpc_url: "http://localhost:1"
               )
    end
  end

  # --- bang variants ---

  describe "bang variants" do
    test "address_from_key! raises on invalid input" do
      assert_raise RuntimeError, ~r/address_from_key failed/, fn ->
        Signer.address_from_key!(<<1, 2, 3>>)
      end
    end

    test "build_transaction! raises on invalid address" do
      assert_raise RuntimeError, ~r/build_transaction failed/, fn ->
        Signer.build_transaction!("0xshort", <<>>, nonce: 0, chain_id: @test_chain_id)
      end
    end

    test "build_transaction! raises on missing required option" do
      assert_raise RuntimeError, ~r/build_transaction failed/, fn ->
        Signer.build_transaction!(@dummy_to, <<>>, chain_id: @test_chain_id)
      end
    end

    test "sign_transaction! raises on invalid key" do
      {:ok, trx} =
        Signer.build_transaction(@dummy_to, <<>>, nonce: 0, chain_id: @test_chain_id)

      assert_raise RuntimeError, ~r/sign_transaction failed/, fn ->
        Signer.sign_transaction!(trx, <<1, 2, 3>>, @test_chain_id)
      end
    end

    test "encode_transaction! raises on unsigned transaction" do
      {:ok, trx} =
        Signer.build_transaction(@dummy_to, <<>>, nonce: 0, chain_id: @test_chain_id)

      assert_raise RuntimeError, ~r/encode_transaction failed/, fn ->
        Signer.encode_transaction!(trx)
      end
    end

    test "send_transaction! raises on missing option" do
      assert_raise RuntimeError, ~r/send_transaction failed/, fn ->
        Signer.send_transaction!(@dummy_to, <<>>, nonce: 0, rpc_url: "http://localhost:1")
      end
    end

    test "address_from_key! returns the checksummed address on success" do
      assert "0x" <> _rest = Signer.address_from_key!(@test_key_binary)
    end

    test "build_transaction! returns a V2 struct on success" do
      assert %V2{} = Signer.build_transaction!(@dummy_to, <<>>, nonce: 0, chain_id: @test_chain_id)
    end

    test "sign_transaction! returns a signed V2 struct on success" do
      trx = Signer.build_transaction!(@dummy_to, <<>>, nonce: 0, chain_id: @test_chain_id)
      assert %V2{} = Signer.sign_transaction!(trx, @test_key_binary, @test_chain_id)
    end

    test "encode_transaction! returns a 0x hex string on success" do
      trx = Signer.build_transaction!(@dummy_to, <<>>, nonce: 0, chain_id: @test_chain_id)
      signed = Signer.sign_transaction!(trx, @test_key_binary, @test_chain_id)
      assert "0x" <> _rest = Signer.encode_transaction!(signed)
    end
  end
end
