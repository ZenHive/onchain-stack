defmodule Onchain.LogTest do
  use ExUnit.Case, async: true

  import Onchain.TypeEvasion, only: [untyped: 1]

  alias Onchain.Log

  # Known keccak256 hashes for common events
  @transfer_topic "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
  @approval_topic "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925"

  # Encodes values as ABI event data by stripping the 4-byte function selector
  defp encode_event_data(types_sig, values) do
    {:ok, encoded} = Onchain.ABI.encode_call(types_sig, values)
    "0x" <> hex = encoded
    "0x" <> String.slice(hex, 8, String.length(hex) - 8)
  end

  describe "event_topic/1" do
    test "returns correct keccak256 hash for Transfer event" do
      assert {:ok, @transfer_topic} = Log.event_topic("Transfer(address,address,uint256)")
    end

    test "returns correct keccak256 hash for Approval event" do
      assert {:ok, @approval_topic} = Log.event_topic("Approval(address,address,uint256)")
    end

    test "returns error for invalid signature without parens" do
      assert {:error, {:invalid_signature, "Transfer"}} = Log.event_topic("Transfer")
    end

    test "returns error for non-string input" do
      assert {:error, {:invalid_signature, 123}} = Log.event_topic(123)
    end
  end

  describe "event_topic!/1" do
    test "returns hash directly" do
      assert @transfer_topic = Log.event_topic!("Transfer(address,address,uint256)")
    end

    test "raises on invalid signature" do
      assert_raise RuntimeError, ~r/event_topic failed/, fn ->
        Log.event_topic!("bad")
      end
    end
  end

  describe "decode_event/2" do
    test "decodes a Transfer event with indexed from/to and non-indexed value" do
      # Construct a log matching Transfer(address indexed from, address indexed to, uint256 value)
      from_addr = "0x000000000000000000000000A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
      to_addr = "0x000000000000000000000000dAC17F958D2ee523a2206206994597C13D831ec7"

      data = encode_event_data("transfer(uint256)", [1_000_000])

      log = %{
        topics: [@transfer_topic, from_addr, to_addr],
        data: data
      }

      signature = "Transfer(address indexed from, address indexed to, uint256 value)"

      assert {:ok, decoded} = Log.decode_event(log, signature)
      assert is_map(decoded)
      assert decoded.value == 1_000_000
      # Addresses should be checksummed
      assert decoded.from == Onchain.Address.checksum!("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")
      assert decoded.to == Onchain.Address.checksum!("0xdAC17F958D2ee523a2206206994597C13D831ec7")
    end

    test "decodes event with only indexed params (no data)" do
      addr_topic = "0x000000000000000000000000A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
      signature = "OwnerChanged(address indexed newOwner)"
      {:ok, owner_changed_topic} = Log.event_topic("OwnerChanged(address)")

      log = %{
        topics: [owner_changed_topic, addr_topic],
        data: "0x"
      }

      assert {:ok, decoded} = Log.decode_event(log, signature)
      assert decoded.newOwner == Onchain.Address.checksum!("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")
    end

    test "returns error for invalid log format" do
      assert {:error, {:decode_error, :invalid_log_format}} =
               Log.decode_event("not a map", "Transfer(address,uint256)")
    end

    test "returns error when topics list is empty" do
      log = %{topics: [], data: "0x"}

      assert {:error, {:decode_error, :missing_event_topic}} =
               Log.decode_event(log, "Transfer(address indexed from, uint256 value)")
    end

    test "returns error when topic0 does not match signature" do
      wrong_topic = "0x0000000000000000000000000000000000000000000000000000000000000001"

      log = %{
        topics: [wrong_topic],
        data: "0x"
      }

      assert {:error, {:decode_error, {:topic_mismatch, _}}} =
               Log.decode_event(log, "Transfer(address indexed from, uint256 value)")
    end

    test "returns raw hash for indexed dynamic types (string, bytes, arrays)" do
      signature = "TextChanged(string indexed key, string value)"
      {:ok, topic0} = Log.event_topic("TextChanged(string,string)")
      # Indexed string is stored as keccak256(value) — raw 32-byte hash
      key_hash = "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"

      data = encode_event_data("f(string)", ["hello"])

      log = %{topics: [topic0, key_hash], data: data}

      assert {:ok, decoded} = Log.decode_event(log, signature)
      # Indexed string returns the raw topic hash (keccak of original value)
      assert decoded.key == key_hash
      assert decoded.value == "hello"
    end
  end

  describe "decode_event!/2" do
    test "returns decoded map directly on success" do
      {:ok, topic0} = Log.event_topic("Deposit(uint256)")
      data = encode_event_data("f(uint256)", [99])

      log = %{topics: [topic0], data: data}

      assert %{uint256: 99} = Log.decode_event!(log, "Deposit(uint256)")
    end

    test "raises on invalid log" do
      assert_raise RuntimeError, ~r/decode_event failed/, fn ->
        Log.decode_event!(untyped("bad"), "Transfer(address,uint256)")
      end
    end
  end

  describe "decode_event/2 — empty params event" do
    test "decodes event with no parameters" do
      {:ok, topic0} = Log.event_topic("EmptyEvent()")

      log = %{topics: [topic0], data: "0x"}

      assert {:ok, decoded} = Log.decode_event(log, "EmptyEvent()")
      assert decoded == %{}
    end
  end

  describe "decode_event/2 — nameless param (type-only)" do
    test "decodes event with unnamed param using type as name" do
      {:ok, topic0} = Log.event_topic("Deposit(uint256)")

      data = encode_event_data("f(uint256)", [42])

      log = %{topics: [topic0], data: data}

      assert {:ok, decoded} = Log.decode_event(log, "Deposit(uint256)")
      assert decoded.uint256 == 42
    end
  end

  describe "decode_event/2 — nil and empty data with non-indexed params" do
    test "returns missing_data_field error when data is nil" do
      {:ok, topic0} = Log.event_topic("ValueSet(uint256)")

      log = %{topics: [topic0], data: nil}

      assert {:error, {:decode_error, :missing_data_field}} =
               Log.decode_event(log, "ValueSet(uint256 value)")
    end

    test "returns empty_data_field error when data is 0x with non-indexed params" do
      {:ok, topic0} = Log.event_topic("ValueSet(uint256)")

      log = %{topics: [topic0], data: "0x"}

      assert {:error, {:decode_error, :empty_data_field}} =
               Log.decode_event(log, "ValueSet(uint256 value)")
    end
  end

  describe "decode_event/2 — non-indexed address param" do
    test "checksums non-indexed address values" do
      # Event with a non-indexed address param (decoded from data, not topic)
      {:ok, topic0} = Log.event_topic("Withdrawal(address)")

      # ABI-encode an address as a non-indexed param (padded to 32 bytes)
      addr_hex = "dAC17F958D2ee523a2206206994597C13D831ec7"
      padded = String.duplicate("0", 24) <> String.downcase(addr_hex)
      data = "0x" <> padded

      log = %{topics: [topic0], data: data}

      assert {:ok, decoded} = Log.decode_event(log, "Withdrawal(address recipient)")
      # Non-indexed address should be checksummed
      assert decoded.recipient == Onchain.Address.checksum!("0x" <> addr_hex)
    end
  end

  describe "decode_event/2 — indexed array type" do
    test "returns raw topic hash for indexed uint256[] param" do
      {:ok, topic0} = Log.event_topic("BatchUpdate(uint256[])")
      ids_hash = "0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"

      log = %{topics: [topic0, ids_hash], data: "0x"}

      assert {:ok, decoded} = Log.decode_event(log, "BatchUpdate(uint256[] indexed ids)")
      # Indexed dynamic types return the raw topic hash (keccak of ABI-encoded value)
      assert decoded.ids == ids_hash
    end
  end

  describe "decode_event/2 — indexed reference-type compliance" do
    # Solidity stores keccak256(value) in the topic for indexed reference types
    # (string, bytes, all arrays — fixed or dynamic, tuples). The original value
    # is not recoverable from a log; the raw 32-byte topic hash must be returned.
    # Spec rule confirmed against hieroglyph 1.0.0 fix to ABI.Event.decode_event/4.

    test "returns raw topic hash for indexed bytes param" do
      {:ok, topic0} = Log.event_topic("BytesEvent(bytes)")
      key_hash = "0x1111111111111111111111111111111111111111111111111111111111111111"

      log = %{topics: [topic0, key_hash], data: "0x"}

      assert {:ok, decoded} = Log.decode_event(log, "BytesEvent(bytes indexed key)")
      assert decoded.key == key_hash
    end

    test "returns raw topic hash for indexed fixed-size array (uint256[3]) param" do
      {:ok, topic0} = Log.event_topic("SlotEvent(uint256[3])")
      slots_hash = "0x2222222222222222222222222222222222222222222222222222222222222222"

      log = %{topics: [topic0, slots_hash], data: "0x"}

      assert {:ok, decoded} = Log.decode_event(log, "SlotEvent(uint256[3] indexed slots)")
      assert decoded.slots == slots_hash
    end

    test "returns raw topic hash for indexed dynamic array of static elements (bytes32[])" do
      {:ok, topic0} = Log.event_topic("HashesEvent(bytes32[])")
      hashes_hash = "0x3333333333333333333333333333333333333333333333333333333333333333"

      log = %{topics: [topic0, hashes_hash], data: "0x"}

      assert {:ok, decoded} = Log.decode_event(log, "HashesEvent(bytes32[] indexed hashes)")
      assert decoded.hashes == hashes_hash
    end

    test "interleaves static-indexed + reference-indexed correctly" do
      {:ok, topic0} = Log.event_topic("MixedEvent(address,bytes,uint256)")
      from_topic = "0x000000000000000000000000A0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
      key_hash = "0x4444444444444444444444444444444444444444444444444444444444444444"

      data = encode_event_data("f(uint256)", [99])

      log = %{topics: [topic0, from_topic, key_hash], data: data}

      signature = "MixedEvent(address indexed from, bytes indexed key, uint256 amount)"
      assert {:ok, decoded} = Log.decode_event(log, signature)
      assert decoded.from == Onchain.Address.checksum!("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48")
      assert decoded.key == key_hash
      assert decoded.amount == 99
    end
  end

  describe "decode_event/2 — signature trust boundary (atom-table DoS defence)" do
    # Minimal well-formed log; parse_event_signature runs before any topic check, so a
    # rejected signature short-circuits with {:error, {:invalid_signature, _}}.
    @valid_log %{topics: ["0x" <> String.duplicate("0", 64)], data: "0x"}

    test "rejects a signature with more than the param-count cap" do
      params = Enum.map_join(1..33, ", ", fn i -> "uint256 p#{i}" end)
      signature = "Big(#{params})"

      assert {:error, {:invalid_signature, ^signature}} = Log.decode_event(@valid_log, signature)
    end

    test "accepts a signature exactly at the param-count cap" do
      params = Enum.map_join(1..32, ", ", fn i -> "uint256 p#{i}" end)
      signature = "AtCap(#{params})"

      # Parses past the cap (fails later on topic mismatch, not on :invalid_signature).
      assert {:error, {:decode_error, _}} = Log.decode_event(@valid_log, signature)
    end

    test "rejects a param name with non-identifier characters" do
      assert {:error, {:invalid_signature, "a-b"}} =
               Log.decode_event(@valid_log, "Evt(uint256 a-b)")
    end

    test "rejects a param name exceeding the length cap" do
      long = String.duplicate("a", 65)

      assert {:error, {:invalid_signature, ^long}} =
               Log.decode_event(@valid_log, "Evt(uint256 #{long})")
    end

    test "rejects a malformed segment that would otherwise mint a garbage atom" do
      # 4+ tokens hit the catch-all branch; the whole segment (with spaces) fails the
      # identifier check rather than being interned verbatim.
      assert {:error, {:invalid_signature, "address indexed from extra"}} =
               Log.decode_event(@valid_log, "Evt(address indexed from extra)")
    end

    test "accepts a Solidity $-identifier param name" do
      # `$` is valid in a Solidity identifier (per the language grammar), so a
      # developer-authored signature using it must parse past the trust-boundary
      # check (failing later on topic mismatch, not on :invalid_signature).
      assert {:error, {:decode_error, _}} = Log.decode_event(@valid_log, "Evt(uint256 $amount)")
    end
  end

  describe "decode_event/3 — strict decode" do
    @dirty_word <<1>> <> :binary.copy(<<0>>, 30) <> <<1>>
    @dirty_hex Onchain.Hex.encode(@dirty_word)
    @trailing_hex Onchain.Hex.encode(<<10::256, 0::256>>)
    @overlong_hex Onchain.Hex.encode(<<32::256, 0xFFFFFFFF::256>>)

    test "canonical log still decodes with strict: true" do
      {:ok, topic0} = Log.event_topic("Deposit(uint256)")
      data = encode_event_data("f(uint256)", [99])
      log = %{topics: [topic0], data: data}

      assert {:ok, %{uint256: 99}} = Log.decode_event(log, "Deposit(uint256)", strict: true)
    end

    test "rejects non-zero high padding on a non-indexed uint8" do
      {:ok, topic0} = Log.event_topic("Tiny(uint8)")
      log = %{topics: [topic0], data: @dirty_hex}
      padding = {:non_canonical_padding, %{type: {:uint, 8}}}

      assert {:error, {:decode_error, {:strict_violation, ^padding}}} =
               Log.decode_event(log, "Tiny(uint8 value)", strict: true)
    end

    test "rejects non-zero high padding on an indexed uint8" do
      {:ok, topic0} = Log.event_topic("Tiny(uint8)")
      log = %{topics: [topic0, @dirty_hex], data: "0x"}
      padding = {:non_canonical_padding, %{type: {:uint, 8}}}

      assert {:error, {:decode_error, {:strict_violation, ^padding}}} =
               Log.decode_event(log, "Tiny(uint8 indexed value)", strict: true)
    end

    test "rejects trailing bytes after the declared payload" do
      {:ok, topic0} = Log.event_topic("Deposit(uint256)")
      log = %{topics: [topic0], data: @trailing_hex}

      assert {:error, {:decode_error, {:strict_violation, {:trailing_bytes, 32}}}} =
               Log.decode_event(log, "Deposit(uint256 value)", strict: true)
    end

    test "rejects a string length prefix that exceeds available data" do
      {:ok, topic0} = Log.event_topic("Note(string)")
      log = %{topics: [topic0], data: @overlong_hex}
      detail = {:length_out_of_bounds, %{type: :string, length: 4_294_967_295, available: 0}}

      assert {:error, {:decode_error, {:strict_violation, ^detail}}} =
               Log.decode_event(log, "Note(string value)", strict: true)
    end

    test "bang variant raises on strict_violation" do
      {:ok, topic0} = Log.event_topic("Tiny(uint8)")
      log = %{topics: [topic0], data: @dirty_hex}

      assert_raise RuntimeError, ~r/strict_violation/, fn ->
        Log.decode_event!(log, "Tiny(uint8 value)", strict: true)
      end
    end
  end
end
