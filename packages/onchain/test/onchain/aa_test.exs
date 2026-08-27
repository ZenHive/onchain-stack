defmodule Onchain.AATest do
  use ExUnit.Case, async: true

  alias Onchain.AA
  alias Onchain.AA.UserOperation
  alias Onchain.Hex

  # Deterministic test keypair (shared with signer tests, from cartouche docs).
  @test_key_hex "0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf"
  @test_address "0x63Cc7c25e0cdb121aBb0fE477a6b9901889F99A7"

  # Reference vectors cross-checked against viem's getUserOperationHash test
  # (entryPoint 0x1234…7890, chainId 1, identical unpacked inputs). The two
  # versions hash the same inputs to different digests — that is the v0.6/v0.7
  # wire-format trap this module exists to handle.
  @ref_entry_point "0x1234567890123456789012345678901234567890"
  @ref_chain_id 1
  @ref_v06_hash "0xe331591ab320e956b5e93f04e1dcf706bc128bc7b510602d2e0553f8be25fcba"
  @ref_v07_hash "0x1903d62bb5dc75af6fed866aa46d8e80063d9e288aa7f2caad0ff1fcae22e40d"
  @eip191_prefix "\x19Ethereum Signed Message:\n32"

  defp ref_op do
    {:ok, op} =
      AA.new(%{
        sender: "0x1234567890123456789012345678901234567890",
        nonce: 0,
        call_data: "0x",
        call_gas_limit: 6_942_069,
        verification_gas_limit: 6_942_069,
        pre_verification_gas: 6_942_069,
        max_fee_per_gas: 69_420,
        max_priority_fee_per_gas: 69,
        signature: "0x"
      })

    op
  end

  describe "entry_point/1" do
    test "returns canonical addresses per version" do
      assert AA.entry_point(:v0_6) == "0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789"
      assert AA.entry_point(:v0_7) == "0x0000000071727De22E5E9d8BAf0edAc6f37da032"
    end
  end

  describe "new/1" do
    test "builds from a map with defaults applied" do
      assert {:ok, %UserOperation{} = op} =
               AA.new(%{sender: "0x1234567890123456789012345678901234567890"})

      assert op.nonce == 0
      assert op.call_data == "0x"
      assert op.init_code == "0x"
      assert op.paymaster_and_data == "0x"
      assert op.signature == "0x"
      assert op.factory == nil
      assert op.paymaster == nil
    end

    test "accepts a keyword list" do
      assert {:ok, %UserOperation{nonce: 7}} =
               AA.new(sender: "0x1234567890123456789012345678901234567890", nonce: 7)
    end

    test "normalizes the sender to lowercase hex" do
      {:ok, op} = AA.new(%{sender: @test_address})
      assert op.sender == String.downcase(@test_address)
    end

    test "normalizes hex byte fields to lowercase 0x form" do
      {:ok, op} =
        AA.new(%{
          sender: "0x1234567890123456789012345678901234567890",
          call_data: "AABB",
          init_code: "0xCCDD"
        })

      assert op.call_data == "0xaabb"
      assert op.init_code == "0xccdd"
    end

    test "requires sender" do
      assert {:error, {:missing_field, :sender}} = AA.new(%{nonce: 1})
    end

    test "rejects an invalid sender" do
      assert {:error, {:invalid_field, :sender, "0xnope"}} = AA.new(%{sender: "0xnope"})
    end

    test "rejects unknown fields" do
      assert {:error, {:unknown_fields, [:gas_price]}} =
               AA.new(%{sender: "0x1234567890123456789012345678901234567890", gas_price: 1})
    end

    test "rejects negative numeric fields" do
      assert {:error, {:invalid_field, :nonce, -1}} =
               AA.new(%{sender: "0x1234567890123456789012345678901234567890", nonce: -1})
    end

    test "rejects odd-length hex byte fields" do
      assert {:error, {:invalid_field, :call_data, "0xabc"}} =
               AA.new(%{sender: "0x1234567890123456789012345678901234567890", call_data: "0xabc"})
    end

    test "rejects a non-binary hex field" do
      assert {:error, {:invalid_field, :call_data, 123}} =
               AA.new(%{sender: "0x1234567890123456789012345678901234567890", call_data: 123})
    end

    test "rejects a list that is not a keyword list" do
      assert {:error, {:invalid_fields, ["nope"]}} = AA.new(["nope"])
    end

    test "rejects input that is neither a map nor a list" do
      assert {:error, {:invalid_fields, 123}} = AA.new(123)
    end

    # nil is the "field absent" signal for the v0.7 optional fields, distinct from
    # a zero or "0x" that would encode as present-but-empty.
    test "passes explicit nil through for optional factory/paymaster fields" do
      {:ok, op} =
        AA.new(%{
          sender: "0x1234567890123456789012345678901234567890",
          factory_data: nil,
          paymaster_data: nil,
          paymaster_verification_gas_limit: nil,
          paymaster_post_op_gas_limit: nil
        })

      assert op.factory_data == nil
      assert op.paymaster_data == nil
      assert op.paymaster_verification_gas_limit == nil
      assert op.paymaster_post_op_gas_limit == nil
    end
  end

  describe "user_op_hash/4 — reference vectors" do
    test "v0.7 matches the EntryPoint spec vector" do
      assert {:ok, @ref_v07_hash} =
               AA.user_op_hash(ref_op(), @ref_entry_point, @ref_chain_id, version: :v0_7)
    end

    test "v0.6 matches the EntryPoint spec vector" do
      assert {:ok, @ref_v06_hash} =
               AA.user_op_hash(ref_op(), @ref_entry_point, @ref_chain_id, version: :v0_6)
    end

    test "defaults to v0.7" do
      assert {:ok, @ref_v07_hash} = AA.user_op_hash(ref_op(), @ref_entry_point, @ref_chain_id)
    end

    test "the same op hashes differently across versions" do
      {:ok, v06} = AA.user_op_hash(ref_op(), @ref_entry_point, @ref_chain_id, version: :v0_6)
      {:ok, v07} = AA.user_op_hash(ref_op(), @ref_entry_point, @ref_chain_id, version: :v0_7)
      refute v06 == v07
    end

    test "hash changes with chain id" do
      {:ok, mainnet} = AA.user_op_hash(ref_op(), @ref_entry_point, 1)
      {:ok, sepolia} = AA.user_op_hash(ref_op(), @ref_entry_point, 11_155_111)
      refute mainnet == sepolia
    end

    test "hash changes with entry point" do
      {:ok, a} = AA.user_op_hash(ref_op(), @ref_entry_point, @ref_chain_id)
      {:ok, b} = AA.user_op_hash(ref_op(), AA.entry_point(:v0_7), @ref_chain_id)
      refute a == b
    end
  end

  describe "user_op_hash/4 — v0.7 factory/paymaster derivation" do
    test "factory + factory_data equals the concatenated init_code" do
      factory = "0x00000000000000000000000000000000000000aa"
      factory_data = "0xdeadbeef"

      {:ok, split} =
        AA.new(%{sender: "0x1234567890123456789012345678901234567890", factory: factory, factory_data: factory_data})

      {:ok, combined} =
        AA.new(%{sender: "0x1234567890123456789012345678901234567890", init_code: factory <> "deadbeef"})

      {:ok, split_hash} = AA.user_op_hash(split, @ref_entry_point, @ref_chain_id)
      {:ok, combined_hash} = AA.user_op_hash(combined, @ref_entry_point, @ref_chain_id)
      assert split_hash == combined_hash
    end

    test "paymaster fields pack into paymaster_and_data" do
      paymaster = "0x00000000000000000000000000000000000000bb"

      {:ok, split} =
        AA.new(%{
          sender: "0x1234567890123456789012345678901234567890",
          paymaster: paymaster,
          paymaster_verification_gas_limit: 0x1111,
          paymaster_post_op_gas_limit: 0x2222,
          paymaster_data: "0xcafe"
        })

      # paymaster(20) ‖ verGas(16) ‖ postOp(16) ‖ data
      packed =
        paymaster <>
          "00000000000000000000000000001111" <>
          "00000000000000000000000000002222" <>
          "cafe"

      {:ok, combined} =
        AA.new(%{sender: "0x1234567890123456789012345678901234567890", paymaster_and_data: packed})

      {:ok, split_hash} = AA.user_op_hash(split, @ref_entry_point, @ref_chain_id)
      {:ok, combined_hash} = AA.user_op_hash(combined, @ref_entry_point, @ref_chain_id)
      assert split_hash == combined_hash
    end
  end

  # A v0.7 op may set `factory`/`paymaster` while leaving their sub-fields nil — a
  # paymaster needing no calldata and no gas overrides is the common case. Those
  # nils are encoded as fixed-width zero words, not omitted, so getting them wrong
  # shifts every following byte and yields a userOpHash for a *different*
  # operation than the one submitted. The packed-equivalent comparison pins the
  # widths against an independently written byte string rather than against the
  # encoder's own output.
  describe "user_op_hash/4 — v0.7 absent optional sub-fields" do
    @paymaster "0x00000000000000000000000000000000000000bb"
    @factory "0x00000000000000000000000000000000000000aa"
    @zero_uint128 String.duplicate("0", 32)

    test "nil paymaster gas limits and data encode as two zero words and no data" do
      {:ok, split} =
        AA.new(%{
          sender: "0x1234567890123456789012345678901234567890",
          paymaster: @paymaster,
          paymaster_verification_gas_limit: nil,
          paymaster_post_op_gas_limit: nil,
          paymaster_data: nil
        })

      # paymaster(20) ‖ verGas(16 zero bytes) ‖ postOp(16 zero bytes) ‖ no data
      packed = @paymaster <> @zero_uint128 <> @zero_uint128
      assert byte_size(Hex.decode!(packed)) == 52

      {:ok, combined} =
        AA.new(%{sender: "0x1234567890123456789012345678901234567890", paymaster_and_data: packed})

      {:ok, split_hash} = AA.user_op_hash(split, @ref_entry_point, @ref_chain_id)
      {:ok, combined_hash} = AA.user_op_hash(combined, @ref_entry_point, @ref_chain_id)
      assert split_hash == combined_hash
    end

    test "nil factory_data encodes as an initCode of the factory address alone" do
      {:ok, split} =
        AA.new(%{
          sender: "0x1234567890123456789012345678901234567890",
          factory: @factory,
          factory_data: nil
        })

      {:ok, combined} =
        AA.new(%{sender: "0x1234567890123456789012345678901234567890", init_code: @factory})

      {:ok, split_hash} = AA.user_op_hash(split, @ref_entry_point, @ref_chain_id)
      {:ok, combined_hash} = AA.user_op_hash(combined, @ref_entry_point, @ref_chain_id)
      assert split_hash == combined_hash
    end

    test "to_rpc_params renders absent sub-fields as zero quantities and empty bytes" do
      {:ok, op} =
        AA.new(%{
          sender: "0x1234567890123456789012345678901234567890",
          factory: @factory,
          factory_data: nil,
          paymaster: @paymaster,
          paymaster_verification_gas_limit: nil,
          paymaster_post_op_gas_limit: nil,
          paymaster_data: nil
        })

      {:ok, params} = AA.to_rpc_params(op, version: :v0_7)

      assert params["factory"] == @factory
      assert params["factoryData"] == "0x"
      assert params["paymaster"] == @paymaster
      assert params["paymasterVerificationGasLimit"] == "0x0"
      assert params["paymasterPostOpGasLimit"] == "0x0"
      assert params["paymasterData"] == "0x"
    end

    # new/1 normalizes hex on the way in, so a malformed init_code can only reach
    # the encoder on a hand-built struct — which the public struct permits.
    test "a hand-built struct with malformed init_code is rejected, not decoded" do
      op = %UserOperation{sender: "0x1234567890123456789012345678901234567890", init_code: "0xzz"}

      assert {:error, {:invalid_field, :init_code, "0xzz"}} =
               AA.user_op_hash(op, @ref_entry_point, @ref_chain_id)
    end
  end

  describe "user_op_hash/4 — errors" do
    test "rejects an unknown version" do
      assert {:error, {:invalid_version, :v9}} =
               AA.user_op_hash(ref_op(), @ref_entry_point, 1, version: :v9)
    end

    test "rejects a non-positive chain id" do
      assert {:error, {:invalid_chain_id, 0}} = AA.user_op_hash(ref_op(), @ref_entry_point, 0)
    end

    test "rejects an invalid entry point" do
      assert {:error, {:invalid_address, :entry_point, "0xbad"}} =
               AA.user_op_hash(ref_op(), "0xbad", 1)
    end
  end

  describe "sign_user_operation/5" do
    test "eip191 signature recovers to the signer (both versions)" do
      for version <- [:v0_6, :v0_7] do
        {:ok, signed} =
          AA.sign_user_operation(ref_op(), @test_key_hex, @ref_entry_point, @ref_chain_id, version: version)

        assert %UserOperation{signature: sig} = signed
        assert byte_size(Hex.decode!(sig)) == 65
        assert recover_signer(signed, version, :eip191) == String.downcase(@test_address)
      end
    end

    test "raw scheme signs the userOpHash directly and recovers" do
      {:ok, signed} =
        AA.sign_user_operation(ref_op(), @test_key_hex, @ref_entry_point, @ref_chain_id, scheme: :raw)

      assert recover_signer(signed, :v0_7, :raw) == String.downcase(@test_address)
    end

    test "produces v in {27, 28}" do
      {:ok, signed} = AA.sign_user_operation(ref_op(), @test_key_hex, @ref_entry_point, @ref_chain_id)
      <<_r::256, _s::256, v::8>> = Hex.decode!(signed.signature)
      assert v in [27, 28]
    end

    test "rejects an invalid private key" do
      assert {:error, {:invalid_private_key, "0xdeadbeef"}} =
               AA.sign_user_operation(ref_op(), "0xdeadbeef", @ref_entry_point, @ref_chain_id)
    end

    # Well-formed 32 bytes, so it clears decode_private_key/1 and only fails deeper,
    # inside the signer — the path safe_get_address/2's narrowed rescue guards.
    test "rejects a 32-byte key whose scalar is outside the curve order" do
      zero_key = <<0::256>>

      assert {:error, {:invalid_private_key, ^zero_key}} =
               AA.sign_user_operation(ref_op(), zero_key, @ref_entry_point, @ref_chain_id)
    end

    test "rejects a non-binary private key" do
      assert {:error, {:invalid_private_key, 123}} =
               AA.sign_user_operation(ref_op(), 123, @ref_entry_point, @ref_chain_id)
    end

    test "rejects an invalid signature scheme" do
      assert {:error, {:invalid_scheme, :wat}} =
               AA.sign_user_operation(ref_op(), @test_key_hex, @ref_entry_point, @ref_chain_id, scheme: :wat)
    end
  end

  describe "to_rpc_params/2" do
    test "v0.6 carries initCode and paymasterAndData with hex-quantity numbers" do
      {:ok, params} = AA.to_rpc_params(ref_op(), version: :v0_6)

      assert params["sender"] == "0x1234567890123456789012345678901234567890"
      assert params["nonce"] == "0x0"
      assert params["callGasLimit"] == "0x69ed75"
      assert params["initCode"] == "0x"
      assert params["paymasterAndData"] == "0x"
      assert params["signature"] == "0x"
      refute Map.has_key?(params, "factory")
    end

    test "v0.7 omits initCode/paymasterAndData and factory/paymaster when unset" do
      {:ok, params} = AA.to_rpc_params(ref_op(), version: :v0_7)

      refute Map.has_key?(params, "initCode")
      refute Map.has_key?(params, "paymasterAndData")
      refute Map.has_key?(params, "factory")
      refute Map.has_key?(params, "paymaster")
      assert params["maxPriorityFeePerGas"] == "0x45"
    end

    test "v0.7 includes factory and paymaster fields when set" do
      {:ok, op} =
        AA.new(%{
          sender: "0x1234567890123456789012345678901234567890",
          factory: "0x00000000000000000000000000000000000000aa",
          factory_data: "0xbeef",
          paymaster: "0x00000000000000000000000000000000000000bb",
          paymaster_verification_gas_limit: 1000,
          paymaster_post_op_gas_limit: 2000,
          paymaster_data: "0xfeed"
        })

      {:ok, params} = AA.to_rpc_params(op, version: :v0_7)

      assert params["factory"] == "0x00000000000000000000000000000000000000aa"
      assert params["factoryData"] == "0xbeef"
      assert params["paymaster"] == "0x00000000000000000000000000000000000000bb"
      assert params["paymasterVerificationGasLimit"] == "0x3e8"
      assert params["paymasterPostOpGasLimit"] == "0x7d0"
      assert params["paymasterData"] == "0xfeed"
    end

    test "v0.7 unpacks init_code into factory + factoryData for bundler RPC" do
      factory = "0x00000000000000000000000000000000000000aa"

      {:ok, op} =
        AA.new(%{sender: "0x1234567890123456789012345678901234567890", init_code: factory <> "deadbeef"})

      {:ok, params} = AA.to_rpc_params(op, version: :v0_7)

      assert params["factory"] == factory
      assert params["factoryData"] == "0xdeadbeef"
      refute Map.has_key?(params, "initCode")
    end

    test "v0.7 unpacks paymaster_and_data into paymaster fields for bundler RPC" do
      paymaster = "0x00000000000000000000000000000000000000bb"

      packed =
        paymaster <>
          "00000000000000000000000000001111" <>
          "00000000000000000000000000002222" <>
          "cafe"

      {:ok, op} =
        AA.new(%{sender: "0x1234567890123456789012345678901234567890", paymaster_and_data: packed})

      {:ok, params} = AA.to_rpc_params(op, version: :v0_7)

      assert params["paymaster"] == paymaster
      assert params["paymasterVerificationGasLimit"] == "0x1111"
      assert params["paymasterPostOpGasLimit"] == "0x2222"
      assert params["paymasterData"] == "0xcafe"
      refute Map.has_key?(params, "paymasterAndData")
    end

    test "v0.7 rejects a malformed factory address instead of emitting it" do
      {:ok, op} =
        AA.new(%{
          sender: "0x1234567890123456789012345678901234567890",
          factory: "0xbeef"
        })

      assert {:error, {:invalid_address, :factory, "0xbeef"}} =
               AA.to_rpc_params(op, version: :v0_7)
    end

    test "v0.7 rejects a malformed paymaster address instead of emitting it" do
      {:ok, op} =
        AA.new(%{
          sender: "0x1234567890123456789012345678901234567890",
          paymaster: "0xbeef"
        })

      assert {:error, {:invalid_address, :paymaster, "0xbeef"}} =
               AA.to_rpc_params(op, version: :v0_7)
    end

    test "v0.7 rejects short init_code consistently for hash and RPC" do
      {:ok, op} =
        AA.new(%{
          sender: "0x1234567890123456789012345678901234567890",
          init_code: "0xdeadbeef"
        })

      assert {:error, {:invalid_field, :init_code, "0xdeadbeef"}} =
               AA.user_op_hash(op, @ref_entry_point, @ref_chain_id, version: :v0_7)

      assert {:error, {:invalid_field, :init_code, "0xdeadbeef"}} =
               AA.to_rpc_params(op, version: :v0_7)
    end

    test "v0.7 rejects short paymaster_and_data consistently for hash and RPC" do
      {:ok, op} =
        AA.new(%{
          sender: "0x1234567890123456789012345678901234567890",
          paymaster_and_data: "0xdeadbeef"
        })

      assert {:error, {:invalid_field, :paymaster_and_data, "0xdeadbeef"}} =
               AA.user_op_hash(op, @ref_entry_point, @ref_chain_id, version: :v0_7)

      assert {:error, {:invalid_field, :paymaster_and_data, "0xdeadbeef"}} =
               AA.to_rpc_params(op, version: :v0_7)
    end
  end

  describe "bundler RPC argument validation" do
    test "get_user_operation_by_hash rejects a malformed hash" do
      assert {:error, {:invalid_user_op_hash, "0xshort"}} =
               AA.get_user_operation_by_hash("0xshort")
    end

    test "get_user_operation_receipt rejects a malformed hash" do
      assert {:error, {:invalid_user_op_hash, 123}} = AA.get_user_operation_receipt(123)
    end

    # Valid hex, wrong width — the length check is separate from the hex check, and
    # only this shape reaches it. A short hash must never be padded into a lookup.
    test "rejects a well-formed hex hash that is not 32 bytes" do
      short = "0x" <> String.duplicate("ab", 16)

      assert {:error, {:invalid_user_op_hash, ^short}} = AA.get_user_operation_by_hash(short)
    end
  end

  # Mirrors a SimpleAccount's signature validation: recover the EOA owner from
  # the digest the account would check.
  defp recover_signer(%UserOperation{signature: sig} = op, version, scheme) do
    {:ok, hash_hex} = AA.user_op_hash(op, @ref_entry_point, @ref_chain_id, version: version)
    hash_bin = Hex.decode!(hash_hex)

    digest =
      case scheme do
        :eip191 -> Cartouche.Hash.keccak(@eip191_prefix <> hash_bin)
        :raw -> hash_bin
      end

    <<r::256, s::256, v::8>> = Hex.decode!(sig)
    curvy_sig = %Curvy.Signature{crv: :secp256k1, r: r, s: s, recid: v - 27}

    curvy_sig
    |> Curvy.recover_key(digest, hash: :keccak)
    |> Curvy.Key.to_pubkey(compressed: false)
    |> Cartouche.Address.from_public_key()
    |> Hex.encode()
  end
end
