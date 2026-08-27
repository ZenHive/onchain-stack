defmodule Cartouche.Solana.TransactionTest do
  use ExUnit.Case, async: true

  alias Cartouche.Solana.Keys
  alias Cartouche.Solana.SystemProgram
  alias Cartouche.Solana.Transaction
  alias Cartouche.Solana.Transaction.AccountMeta
  alias Cartouche.Solana.Transaction.Header
  alias Cartouche.Solana.Transaction.Instruction
  alias Cartouche.Solana.Transaction.Message

  doctest Transaction

  # ---------------------------------------------------------------------------
  # Compact-u16 encoding/decoding
  # ---------------------------------------------------------------------------

  describe "encode_compact_u16/1" do
    test "single-byte values (0-127)" do
      assert Transaction.encode_compact_u16(0) == <<0x00>>
      assert Transaction.encode_compact_u16(1) == <<0x01>>
      assert Transaction.encode_compact_u16(127) == <<0x7F>>
    end

    test "two-byte values (128-16383)" do
      assert Transaction.encode_compact_u16(128) == <<0x80, 0x01>>
      assert Transaction.encode_compact_u16(255) == <<0xFF, 0x01>>
      assert Transaction.encode_compact_u16(256) == <<0x80, 0x02>>
      assert Transaction.encode_compact_u16(16_383) == <<0xFF, 0x7F>>
    end

    test "three-byte values (16384-65535)" do
      assert Transaction.encode_compact_u16(16_384) == <<0x80, 0x80, 0x01>>
      assert Transaction.encode_compact_u16(65_535) == <<0xFF, 0xFF, 0x03>>
    end
  end

  describe "decode_compact_u16/1" do
    test "roundtrip for all boundary values" do
      values = [0, 1, 127, 128, 255, 256, 16_383, 16_384, 65_535]

      for v <- values do
        encoded = Transaction.encode_compact_u16(v)
        assert {^v, <<>>} = Transaction.decode_compact_u16(encoded)
      end
    end

    test "preserves trailing bytes" do
      assert {128, <<0xAB, 0xCD>>} = Transaction.decode_compact_u16(<<0x80, 0x01, 0xAB, 0xCD>>)
    end
  end

  # ---------------------------------------------------------------------------
  # build_message/3
  # ---------------------------------------------------------------------------

  describe "build_message/3" do
    # Deterministic test keys
    @fee_payer <<1::256>>
    @recipient <<2::256>>
    @authority <<3::256>>
    @program_a <<4::256>>
    @program_b <<5::256>>

    test "simple transfer: correct account ordering and header" do
      ix = %Instruction{
        program_id: <<0::256>>,
        accounts: [
          %AccountMeta{pubkey: @fee_payer, is_signer: true, is_writable: true},
          %AccountMeta{pubkey: @recipient, is_signer: false, is_writable: true}
        ],
        data: <<2::little-32, 1_000_000_000::little-64>>
      }

      msg = Transaction.build_message(@fee_payer, [ix], <<9::256>>)

      # Fee payer is first
      assert hd(msg.account_keys) == @fee_payer

      # Header: 1 signer, 0 readonly signed, 1 readonly unsigned (system program)
      assert msg.header.num_required_signatures == 1
      assert msg.header.num_readonly_signed_accounts == 0
      assert msg.header.num_readonly_unsigned_accounts == 1

      # 3 accounts total: fee_payer, recipient, system_program
      assert [_, _, _] = msg.account_keys

      # System program is last (readonly non-signer)
      assert List.last(msg.account_keys) == <<0::256>>

      # Blockhash preserved
      assert msg.recent_blockhash == <<9::256>>
    end

    test "deduplicates accounts and merges permissions" do
      # Same account referenced as non-signer in one ix, signer in another
      ix1 = %Instruction{
        program_id: @program_a,
        accounts: [
          %AccountMeta{pubkey: @authority, is_signer: false, is_writable: false}
        ],
        data: <<>>
      }

      ix2 = %Instruction{
        program_id: @program_a,
        accounts: [
          %AccountMeta{pubkey: @authority, is_signer: true, is_writable: true}
        ],
        data: <<>>
      }

      msg = Transaction.build_message(@fee_payer, [ix1, ix2], <<9::256>>)

      # authority should be promoted to writable signer
      # fee_payer = writable signer, authority = writable signer, program_a = readonly non-signer
      assert msg.header.num_required_signatures == 2
      assert msg.header.num_readonly_signed_accounts == 0
      assert msg.header.num_readonly_unsigned_accounts == 1

      # authority should be in the signers section (first 2 accounts)
      signer_keys = Enum.take(msg.account_keys, 2)
      assert @authority in signer_keys
    end

    test "fee payer is always first even if not in instructions" do
      ix = %Instruction{
        program_id: @program_a,
        accounts: [
          %AccountMeta{pubkey: @recipient, is_signer: false, is_writable: true}
        ],
        data: <<>>
      }

      msg = Transaction.build_message(@fee_payer, [ix], <<9::256>>)

      assert hd(msg.account_keys) == @fee_payer
      assert msg.header.num_required_signatures == 1
    end

    test "readonly signers are separated from writable signers" do
      ix = %Instruction{
        program_id: @program_a,
        accounts: [
          %AccountMeta{pubkey: @authority, is_signer: true, is_writable: false}
        ],
        data: <<>>
      }

      msg = Transaction.build_message(@fee_payer, [ix], <<9::256>>)

      # 2 signers total: fee_payer (writable), authority (readonly)
      assert msg.header.num_required_signatures == 2
      assert msg.header.num_readonly_signed_accounts == 1

      # fee_payer first (writable signer), then authority (readonly signer)
      assert Enum.at(msg.account_keys, 0) == @fee_payer
      assert Enum.at(msg.account_keys, 1) == @authority
    end

    test "multiple programs and complex account ordering" do
      ix1 = %Instruction{
        program_id: @program_a,
        accounts: [
          %AccountMeta{pubkey: @fee_payer, is_signer: true, is_writable: true},
          %AccountMeta{pubkey: @recipient, is_signer: false, is_writable: true}
        ],
        data: <<1>>
      }

      ix2 = %Instruction{
        program_id: @program_b,
        accounts: [
          %AccountMeta{pubkey: @authority, is_signer: true, is_writable: false},
          %AccountMeta{pubkey: @recipient, is_signer: false, is_writable: false}
        ],
        data: <<2>>
      }

      msg = Transaction.build_message(@fee_payer, [ix1, ix2], <<9::256>>)

      # Accounts: fee_payer (ws), authority (rs), recipient (wn - promoted by ix1),
      #           program_a (rn), program_b (rn)
      assert msg.header.num_required_signatures == 2
      assert msg.header.num_readonly_signed_accounts == 1
      assert msg.header.num_readonly_unsigned_accounts == 2

      # Compiled instructions reference correct indices
      [compiled1, compiled2] = msg.instructions
      fee_payer_idx = Enum.find_index(msg.account_keys, &(&1 == @fee_payer))
      recipient_idx = Enum.find_index(msg.account_keys, &(&1 == @recipient))
      authority_idx = Enum.find_index(msg.account_keys, &(&1 == @authority))

      assert compiled1.accounts == [fee_payer_idx, recipient_idx]
      assert compiled2.accounts == [authority_idx, recipient_idx]
    end
  end

  # ---------------------------------------------------------------------------
  # Serialization roundtrip
  # ---------------------------------------------------------------------------

  describe "serialize/deserialize roundtrip" do
    test "minimal transfer transaction" do
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>

      ix = SystemProgram.transfer(fee_payer, recipient, 500_000)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      # Sign with a known seed
      {_pub, seed} = Keys.from_seed(<<1::256>>)
      trx = Transaction.sign(msg, [seed])

      # Serialize
      bytes = Transaction.serialize(trx)
      assert is_binary(bytes)

      # Deserialize
      assert {:ok, decoded} = Transaction.deserialize(bytes)

      # Verify structure matches
      assert [_] = decoded.signatures
      assert decoded.message.header == trx.message.header
      assert decoded.message.account_keys == trx.message.account_keys
      assert decoded.message.recent_blockhash == trx.message.recent_blockhash
      assert decoded.message.instructions == trx.message.instructions
    end

    test "multi-signer transaction" do
      fee_payer = <<1::256>>
      new_account = <<2::256>>
      owner = <<3::256>>
      blockhash = <<99::256>>

      ix =
        SystemProgram.create_account(
          fee_payer,
          new_account,
          1_000_000,
          165,
          owner
        )

      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      # Two signers needed
      {_pub1, seed1} = Keys.from_seed(<<1::256>>)
      {_pub2, seed2} = Keys.from_seed(<<2::256>>)
      trx = Transaction.sign(msg, [seed1, seed2])

      bytes = Transaction.serialize(trx)
      assert {:ok, decoded} = Transaction.deserialize(bytes)

      assert [_, _] = decoded.signatures
      assert decoded.message.header.num_required_signatures == 2
      assert decoded.message == trx.message
    end

    test "message-only serialize/deserialize roundtrip" do
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>

      ix = SystemProgram.transfer(fee_payer, recipient, 42)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      msg_bytes = Transaction.serialize_message(msg)
      assert {:ok, decoded_msg, <<>>} = Transaction.deserialize_message(msg_bytes)

      assert decoded_msg == msg
    end
  end

  # ---------------------------------------------------------------------------
  # Malformed-input hardening (Task 56)
  # ---------------------------------------------------------------------------

  describe "deserialize/1 — malformed input (Task 56)" do
    test "returns {:error, _} on empty binary" do
      assert {:error, _} = Transaction.deserialize(<<>>)
    end

    test "returns {:error, _} on truncated compact-u16 (high-bit byte without continuation)" do
      assert {:error, _} = Transaction.deserialize(<<0x80>>)
    end

    test "returns {:error, _} when signature count exceeds available bytes" do
      # Compact-u16 says 1 signature, but no signature bytes follow
      assert {:error, _} = Transaction.deserialize(<<0x01>>)
    end

    test "returns {:error, _} on truncated message header" do
      # 0 sigs + truncated 3-byte header
      assert {:error, _} = Transaction.deserialize(<<0x00>>)
      assert {:error, _} = Transaction.deserialize(<<0x00, 0x01>>)
    end

    test "returns {:error, _} on truncated pubkey data" do
      # 0 sigs, 0/0/0 header, says 1 key, no key bytes
      assert {:error, _} = Transaction.deserialize(<<0x00, 0x00, 0x00, 0x00, 0x01>>)
    end

    test "returns {:error, _} on truncated blockhash" do
      # 0 sigs, 0/0/0 header, 0 keys, only 16 of the 32 blockhash bytes
      binary = <<0x00, 0x00, 0x00, 0x00, 0x00>> <> <<0::128>>
      assert {:error, _} = Transaction.deserialize(binary)
    end

    test "returns {:error, _} on truncated instruction header" do
      # 0 sigs, 0/0/0 header, 0 keys, full blockhash, says 1 ix, no ix body
      binary = <<0x00, 0x00, 0x00, 0x00, 0x00>> <> <<0::256>> <> <<0x01>>
      assert {:error, _} = Transaction.deserialize(binary)
    end

    test "returns {:error, _} on truncated instruction account data" do
      # 1 ix with program_id_idx=0, says 5 accounts, no account bytes
      binary = <<0x00, 0x00, 0x00, 0x00, 0x00>> <> <<0::256>> <> <<0x01, 0x00, 0x05>>
      assert {:error, _} = Transaction.deserialize(binary)
    end

    test "returns {:error, _} on truncated instruction data payload" do
      # 1 ix with program_id_idx=0, 0 accounts, says 5 data bytes, none follow
      binary = <<0x00, 0x00, 0x00, 0x00, 0x00>> <> <<0::256>> <> <<0x01, 0x00, 0x00, 0x05>>
      assert {:error, _} = Transaction.deserialize(binary)
    end

    test "returns {:error, _} on trailing bytes after a valid message" do
      # Minimal valid serialized transaction:
      # 0 sigs, 0/0/0 header, 0 keys, 32-byte zero blockhash, 0 instructions
      valid = <<0x00, 0x00, 0x00, 0x00, 0x00>> <> <<0::256>> <> <<0x00>>
      # Sanity: the minimal txn round-trips
      assert {:ok, _} = Transaction.deserialize(valid)
      # Trailing garbage breaks the contract
      assert {:error, _} = Transaction.deserialize(valid <> <<0xFF>>)
    end
  end

  # ---------------------------------------------------------------------------
  # Serialize-side malformed-input hardening
  # ---------------------------------------------------------------------------
  #
  # The wire format prefixes account-key and signature lists with compact-u16
  # counts. If a caller hands `serialize_message/1` or `serialize/1` a
  # `%Message{}` / `%Transaction{}` whose `account_keys` or `signatures` list
  # contains an entry that isn't exactly 32 / 64 bytes, the prefix lies and
  # downstream RPC parsers consume bytes from the next region (blockhash,
  # instructions) as remainder of the malformed key/sig — silent corruption.
  #
  # Both functions raise `FunctionClauseError` at the boundary so the failure
  # surfaces at the source instead of as an opaque RPC rejection later.

  describe "serialize_message/1 — account-key shape enforcement" do
    test "raises on under-32-byte account key" do
      msg = %Message{
        header: %Header{
          num_required_signatures: 1,
          num_readonly_signed_accounts: 0,
          num_readonly_unsigned_accounts: 0
        },
        account_keys: [<<0::248>>],
        recent_blockhash: <<0::256>>,
        instructions: []
      }

      assert_raise FunctionClauseError, fn -> Transaction.serialize_message(msg) end
    end

    test "raises on over-32-byte account key" do
      msg = %Message{
        header: %Header{
          num_required_signatures: 1,
          num_readonly_signed_accounts: 0,
          num_readonly_unsigned_accounts: 0
        },
        account_keys: [<<0::264>>],
        recent_blockhash: <<0::256>>,
        instructions: []
      }

      assert_raise FunctionClauseError, fn -> Transaction.serialize_message(msg) end
    end

    test "raises when one of several account keys is malformed" do
      msg = %Message{
        header: %Header{
          num_required_signatures: 1,
          num_readonly_signed_accounts: 0,
          num_readonly_unsigned_accounts: 0
        },
        account_keys: [<<1::256>>, <<2::248>>, <<3::256>>],
        recent_blockhash: <<0::256>>,
        instructions: []
      }

      assert_raise FunctionClauseError, fn -> Transaction.serialize_message(msg) end
    end

    test "accepts well-formed 32-byte account keys" do
      msg = %Message{
        header: %Header{
          num_required_signatures: 1,
          num_readonly_signed_accounts: 0,
          num_readonly_unsigned_accounts: 0
        },
        account_keys: [<<1::256>>, <<2::256>>],
        recent_blockhash: <<0::256>>,
        instructions: []
      }

      bytes = Transaction.serialize_message(msg)
      assert is_binary(bytes)
      assert {:ok, _, <<>>} = Transaction.deserialize_message(bytes)
    end
  end

  describe "serialize/1 — signature shape enforcement" do
    setup do
      msg = %Message{
        header: %Header{
          num_required_signatures: 1,
          num_readonly_signed_accounts: 0,
          num_readonly_unsigned_accounts: 0
        },
        account_keys: [<<1::256>>],
        recent_blockhash: <<0::256>>,
        instructions: []
      }

      {:ok, msg: msg}
    end

    test "raises on under-64-byte signature", %{msg: msg} do
      txn = %Transaction{signatures: [<<0::504>>], message: msg}
      assert_raise FunctionClauseError, fn -> Transaction.serialize(txn) end
    end

    test "raises on over-64-byte signature", %{msg: msg} do
      txn = %Transaction{signatures: [<<0::520>>], message: msg}
      assert_raise FunctionClauseError, fn -> Transaction.serialize(txn) end
    end

    test "raises when one of several signatures is malformed", %{msg: msg} do
      txn = %Transaction{
        signatures: [<<1::512>>, <<2::504>>, <<3::512>>],
        message: msg
      }

      assert_raise FunctionClauseError, fn -> Transaction.serialize(txn) end
    end

    test "accepts well-formed 64-byte signatures", %{msg: msg} do
      txn = %Transaction{signatures: [<<1::512>>], message: msg}
      bytes = Transaction.serialize(txn)
      assert is_binary(bytes)
      assert {:ok, decoded} = Transaction.deserialize(bytes)
      assert decoded.signatures == [<<1::512>>]
    end
  end

  # ---------------------------------------------------------------------------
  # Signing and verification
  # ---------------------------------------------------------------------------

  describe "sign/2" do
    test "produces valid Ed25519 signatures" do
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>

      ix = SystemProgram.transfer(fee_payer, recipient, 1_000_000)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      {pub, seed} = Keys.from_seed(<<1::256>>)
      trx = Transaction.sign(msg, [seed])

      # Verify the signature against the serialized message
      msg_bytes = Transaction.serialize_message(msg)
      [sig] = trx.signatures
      assert byte_size(sig) == 64
      assert :crypto.verify(:eddsa, :none, msg_bytes, sig, [pub, :ed25519])
    end

    test "multi-signer: each signature is valid for its key" do
      fee_payer = <<1::256>>
      new_account = <<2::256>>
      owner = <<3::256>>
      blockhash = <<99::256>>

      ix =
        SystemProgram.create_account(fee_payer, new_account, 1_000_000, 165, owner)

      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      {pub1, seed1} = Keys.from_seed(<<1::256>>)
      {pub2, seed2} = Keys.from_seed(<<2::256>>)
      trx = Transaction.sign(msg, [seed1, seed2])

      msg_bytes = Transaction.serialize_message(msg)
      [sig1, sig2] = trx.signatures
      assert :crypto.verify(:eddsa, :none, msg_bytes, sig1, [pub1, :ed25519])
      assert :crypto.verify(:eddsa, :none, msg_bytes, sig2, [pub2, :ed25519])
    end

    test "signing is deterministic" do
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>

      ix = SystemProgram.transfer(fee_payer, recipient, 100)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)
      {_pub, seed} = Keys.from_seed(<<1::256>>)

      trx1 = Transaction.sign(msg, [seed])
      trx2 = Transaction.sign(msg, [seed])
      assert trx1.signatures == trx2.signatures
    end
  end

  # ---------------------------------------------------------------------------
  # Partial signing (sponsored transactions)
  # ---------------------------------------------------------------------------

  describe "sign_partial/2" do
    test "fills specified positions and zero-fills the rest" do
      fee_payer = <<1::256>>
      new_account = <<2::256>>
      owner = <<3::256>>
      blockhash = <<99::256>>

      ix =
        SystemProgram.create_account(fee_payer, new_account, 1_000_000, 165, owner)

      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      # Only sign position 1 (new_account), leave position 0 (fee_payer) empty
      {_pub2, seed2} = Keys.from_seed(<<2::256>>)
      partial = Transaction.sign_partial(msg, %{1 => seed2})

      assert [_, _] = partial.signatures
      assert Enum.at(partial.signatures, 0) == <<0::512>>
      assert Enum.at(partial.signatures, 1) != <<0::512>>
      assert byte_size(Enum.at(partial.signatures, 1)) == 64
    end

    test "partial signature is valid for the signer's position" do
      fee_payer = <<1::256>>
      new_account = <<2::256>>
      owner = <<3::256>>
      blockhash = <<99::256>>

      ix =
        SystemProgram.create_account(fee_payer, new_account, 1_000_000, 165, owner)

      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      {pub2, seed2} = Keys.from_seed(<<2::256>>)
      partial = Transaction.sign_partial(msg, %{1 => seed2})

      msg_bytes = Transaction.serialize_message(msg)

      assert :crypto.verify(:eddsa, :none, msg_bytes, Enum.at(partial.signatures, 1), [
               pub2,
               :ed25519
             ])
    end

    test "signing all positions is equivalent to sign/2" do
      fee_payer = <<1::256>>
      new_account = <<2::256>>
      owner = <<3::256>>
      blockhash = <<99::256>>

      ix =
        SystemProgram.create_account(fee_payer, new_account, 1_000_000, 165, owner)

      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      {_pub1, seed1} = Keys.from_seed(<<1::256>>)
      {_pub2, seed2} = Keys.from_seed(<<2::256>>)

      full = Transaction.sign(msg, [seed1, seed2])
      partial_all = Transaction.sign_partial(msg, %{0 => seed1, 1 => seed2})

      assert full.signatures == partial_all.signatures
    end
  end

  describe "sign_partial/2 — zero-signer boundary (Task 57)" do
    test "returns empty signatures list when num_required_signatures == 0" do
      msg = %Message{
        header: %Header{
          num_required_signatures: 0,
          num_readonly_signed_accounts: 0,
          num_readonly_unsigned_accounts: 0
        },
        account_keys: [],
        recent_blockhash: <<0::256>>,
        instructions: []
      }

      partial = Transaction.sign_partial(msg, %{})
      assert partial.signatures == []
      assert partial.message == msg
    end
  end

  describe "add_signature/3" do
    test "replaces a zero-filled signature" do
      fee_payer = <<1::256>>
      new_account = <<2::256>>
      owner = <<3::256>>
      blockhash = <<99::256>>

      ix =
        SystemProgram.create_account(fee_payer, new_account, 1_000_000, 165, owner)

      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      # User signs position 1
      {_pub2, seed2} = Keys.from_seed(<<2::256>>)
      partial = Transaction.sign_partial(msg, %{1 => seed2})
      assert Enum.at(partial.signatures, 0) == <<0::512>>

      # Sponsor adds signature at position 0
      {_pub1, seed1} = Keys.from_seed(<<1::256>>)
      msg_bytes = Transaction.serialize_message(msg)
      sponsor_sig = :crypto.sign(:eddsa, :none, msg_bytes, [seed1, :ed25519])
      full = Transaction.add_signature(partial, 0, sponsor_sig)

      assert Enum.at(full.signatures, 0) == sponsor_sig
      assert Enum.at(full.signatures, 0) != <<0::512>>
      # Position 1 is unchanged
      assert Enum.at(full.signatures, 1) == Enum.at(partial.signatures, 1)
    end

    test "full sponsored transaction roundtrip: sign_partial -> serialize -> deserialize -> add_signature" do
      sponsor_pub = <<1::256>>
      user_pub = <<2::256>>
      recipient = <<3::256>>
      blockhash = <<99::256>>

      # User builds a transfer where sponsor pays fees
      ix = SystemProgram.transfer(user_pub, recipient, 500_000)
      msg = Transaction.build_message(sponsor_pub, [ix], blockhash)

      # User signs their position
      {pub2, seed2} = Keys.from_seed(<<2::256>>)
      partial = Transaction.sign_partial(msg, %{1 => seed2})

      # Serialize and "send to sponsor"
      bytes = Transaction.serialize(partial)

      # Sponsor deserializes
      {:ok, received} = Transaction.deserialize(bytes)

      # Sponsor adds their signature
      {pub1, seed1} = Keys.from_seed(<<1::256>>)
      msg_bytes = Transaction.serialize_message(received.message)
      sponsor_sig = :crypto.sign(:eddsa, :none, msg_bytes, [seed1, :ed25519])
      full = Transaction.add_signature(received, 0, sponsor_sig)

      # Verify both signatures are valid
      assert :crypto.verify(:eddsa, :none, msg_bytes, Enum.at(full.signatures, 0), [
               pub1,
               :ed25519
             ])

      assert :crypto.verify(:eddsa, :none, msg_bytes, Enum.at(full.signatures, 1), [
               pub2,
               :ed25519
             ])

      # Verify the full transaction serializes cleanly
      final_bytes = Transaction.serialize(full)
      assert {:ok, final} = Transaction.deserialize(final_bytes)
      assert final.signatures == full.signatures
      assert final.message == full.message
    end
  end

  # ---------------------------------------------------------------------------
  # Caller-error guards (Tasks 91 + 92)
  # ---------------------------------------------------------------------------

  describe "sign/2 — signer count mismatch (Task 91)" do
    test "raises ArgumentError when seed count is less than num_required_signatures" do
      msg = %Message{
        header: %Header{
          num_required_signatures: 2,
          num_readonly_signed_accounts: 0,
          num_readonly_unsigned_accounts: 0
        },
        account_keys: [<<1::256>>, <<2::256>>],
        recent_blockhash: <<0::256>>,
        instructions: []
      }

      {_pub, single_seed} = Keys.from_seed(<<1::256>>)

      assert_raise ArgumentError, ~r/signer count mismatch.*1.*2/i, fn ->
        Transaction.sign(msg, [single_seed])
      end
    end

    test "raises ArgumentError when seed count is greater than num_required_signatures" do
      msg = %Message{
        header: %Header{
          num_required_signatures: 1,
          num_readonly_signed_accounts: 0,
          num_readonly_unsigned_accounts: 0
        },
        account_keys: [<<1::256>>],
        recent_blockhash: <<0::256>>,
        instructions: []
      }

      {_pub1, seed1} = Keys.from_seed(<<1::256>>)
      {_pub2, seed2} = Keys.from_seed(<<2::256>>)

      assert_raise ArgumentError, ~r/signer count mismatch/i, fn ->
        Transaction.sign(msg, [seed1, seed2])
      end
    end

    test "succeeds when seed count exactly matches num_required_signatures" do
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>

      ix = SystemProgram.transfer(fee_payer, recipient, 42)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      {_pub, seed} = Keys.from_seed(<<1::256>>)

      trx = Transaction.sign(msg, [seed])
      assert length(trx.signatures) == msg.header.num_required_signatures
    end
  end

  describe "add_signature/3 — index bounds check (Task 92)" do
    test "raises ArgumentError when index equals length(transaction.signatures) (off-by-one)" do
      msg = %Message{
        header: %Header{
          num_required_signatures: 2,
          num_readonly_signed_accounts: 0,
          num_readonly_unsigned_accounts: 0
        },
        account_keys: [<<1::256>>, <<2::256>>],
        recent_blockhash: <<0::256>>,
        instructions: []
      }

      partial = Transaction.sign_partial(msg, %{})
      sig = <<7::512>>

      assert_raise ArgumentError, ~r/invalid signature slot.*index 2.*length 2/i, fn ->
        Transaction.add_signature(partial, length(partial.signatures), sig)
      end
    end

    test "raises ArgumentError on negative index" do
      msg = %Message{
        header: %Header{
          num_required_signatures: 2,
          num_readonly_signed_accounts: 0,
          num_readonly_unsigned_accounts: 0
        },
        account_keys: [<<1::256>>, <<2::256>>],
        recent_blockhash: <<0::256>>,
        instructions: []
      }

      partial = Transaction.sign_partial(msg, %{})
      sig = <<7::512>>

      assert_raise ArgumentError, ~r/invalid signature slot.*index -1/i, fn ->
        Transaction.add_signature(partial, -1, sig)
      end
    end

    test "raises ArgumentError on far-out-of-bounds positive index" do
      msg = %Message{
        header: %Header{
          num_required_signatures: 1,
          num_readonly_signed_accounts: 0,
          num_readonly_unsigned_accounts: 0
        },
        account_keys: [<<1::256>>],
        recent_blockhash: <<0::256>>,
        instructions: []
      }

      partial = Transaction.sign_partial(msg, %{})
      sig = <<7::512>>

      assert_raise ArgumentError, ~r/invalid signature slot.*index 99.*length 1/i, fn ->
        Transaction.add_signature(partial, 99, sig)
      end
    end

    test "succeeds for in-range index (regression: existing behavior preserved)" do
      fee_payer = <<1::256>>
      new_account = <<2::256>>
      owner = <<3::256>>
      blockhash = <<99::256>>

      ix = SystemProgram.create_account(fee_payer, new_account, 1_000_000, 165, owner)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)

      {_pub2, seed2} = Keys.from_seed(<<2::256>>)
      partial = Transaction.sign_partial(msg, %{1 => seed2})

      {_pub1, seed1} = Keys.from_seed(<<1::256>>)
      msg_bytes = Transaction.serialize_message(msg)
      sponsor_sig = :crypto.sign(:eddsa, :none, msg_bytes, [seed1, :ed25519])

      full = Transaction.add_signature(partial, 0, sponsor_sig)
      assert Enum.at(full.signatures, 0) == sponsor_sig
      assert Enum.at(full.signatures, 1) == Enum.at(partial.signatures, 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Known byte-level tests
  # ---------------------------------------------------------------------------

  describe "known serialization" do
    test "transfer instruction data layout" do
      ix = SystemProgram.transfer(<<1::256>>, <<2::256>>, 1_000_000_000)

      # instruction index 2 (u32 LE) + lamports (u64 LE)
      assert ix.data ==
               <<2, 0, 0, 0, 0, 202, 154, 59, 0, 0, 0, 0>>

      assert byte_size(ix.data) == 12
    end

    test "create_account instruction data layout" do
      ix =
        SystemProgram.create_account(
          <<1::256>>,
          <<2::256>>,
          1_461_600,
          165,
          <<3::256>>
        )

      <<index::little-32, lamports::little-64, space::little-64, owner::binary-32>> = ix.data
      assert index == 0
      assert lamports == 1_461_600
      assert space == 165
      assert owner == <<3::256>>
    end

    test "message serialization produces deterministic bytes" do
      # Build the same message twice with same inputs
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>

      ix = SystemProgram.transfer(fee_payer, recipient, 42)

      msg1 = Transaction.build_message(fee_payer, [ix], blockhash)
      msg2 = Transaction.build_message(fee_payer, [ix], blockhash)

      assert Transaction.serialize_message(msg1) == Transaction.serialize_message(msg2)
    end

    test "transfer message has expected structure in bytes" do
      fee_payer = <<1::256>>
      recipient = <<2::256>>
      blockhash = <<99::256>>

      ix = SystemProgram.transfer(fee_payer, recipient, 42)
      msg = Transaction.build_message(fee_payer, [ix], blockhash)
      bytes = Transaction.serialize_message(msg)

      # Header: 1 signer, 0 readonly signed, 1 readonly unsigned
      assert binary_part(bytes, 0, 3) == <<1, 0, 1>>

      # 3 account keys
      {3, _rest} = Transaction.decode_compact_u16(binary_part(bytes, 3, 1))

      # Verify total size:
      # 3 (header) + 1 (compact len) + 3*32 (keys) + 32 (blockhash) + 1 (compact len) +
      # 1 (program_id_idx) + 1 (compact acct len) + 2 (acct indices) + 1 (compact data len) + 12 (data)
      # = 3 + 1 + 96 + 32 + 1 + 1 + 1 + 2 + 1 + 12 = 150
      assert byte_size(bytes) == 150
    end
  end
end
