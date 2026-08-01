defmodule Onchain.TraceTest do
  use ExUnit.Case, async: true

  alias Onchain.Trace

  # --- Unit tests: input validation (no network calls) ---

  describe "trace_transaction/2 input validation" do
    test "rejects tx_hash without 0x prefix" do
      assert {:error, {:invalid_tx_hash, "abcd1234"}} = Trace.trace_transaction("abcd1234")
    end

    test "rejects tx_hash with invalid hex characters" do
      assert {:error, {:invalid_tx_hash, "0xZZZZ"}} = Trace.trace_transaction("0xZZZZ")
    end

    test "rejects non-binary input" do
      assert {:error, {:invalid_tx_hash, 12_345}} = Trace.trace_transaction(12_345)
    end

    test "rejects too-short hex string" do
      short_hash = "0x1234"
      assert {:error, {:invalid_tx_hash, ^short_hash}} = Trace.trace_transaction(short_hash)
    end

    test "rejects too-long hex string" do
      long_hash = "0x" <> String.duplicate("ab", 33)
      assert {:error, {:invalid_tx_hash, ^long_hash}} = Trace.trace_transaction(long_hash)
    end

    test "rejects invalid tracer type" do
      valid_hash = "0x" <> String.duplicate("ab", 32)
      assert {:error, {:invalid_tracer, "bogusTracer"}} = Trace.trace_transaction(valid_hash, tracer: "bogusTracer")
    end

    test "accepts valid 32-byte hash (passes input validation)" do
      valid_hash = "0x" <> String.duplicate("ab", 32)
      result = Trace.trace_transaction(valid_hash)
      refute match?({:error, {:invalid_tx_hash, _}}, result)
      refute match?({:error, {:invalid_tracer, _}}, result)
    end
  end

  describe "trace_call/3 input validation" do
    test "rejects missing :to param" do
      assert {:error, {:missing_param, :to}} = Trace.trace_call(%{data: "0x18160ddd"})
    end

    test "rejects missing :data param" do
      addr = "0x" <> String.duplicate("aa", 20)
      assert {:error, {:missing_param, :data}} = Trace.trace_call(%{to: addr})
    end

    test "rejects invalid :to address" do
      assert {:error, {:invalid_address, "0xshort"}} =
               Trace.trace_call(%{to: "0xshort", data: "0x18160ddd"})
    end

    test "rejects invalid :data (no 0x prefix)" do
      addr = "0x" <> String.duplicate("aa", 20)

      assert {:error, {:invalid_data, "18160ddd"}} =
               Trace.trace_call(%{to: addr, data: "18160ddd"})
    end

    test "rejects invalid block" do
      addr = "0x" <> String.duplicate("aa", 20)

      assert {:error, {:invalid_block, :foo}} =
               Trace.trace_call(%{to: addr, data: "0x18160ddd"}, :foo)
    end

    test "rejects invalid tracer type" do
      addr = "0x" <> String.duplicate("aa", 20)

      assert {:error, {:invalid_tracer, "bad"}} =
               Trace.trace_call(%{to: addr, data: "0x18160ddd"}, "latest", tracer: "bad")
    end

    test "rejects invalid :from address" do
      addr = "0x" <> String.duplicate("aa", 20)

      assert {:error, {:invalid_address, "0xshort"}} =
               Trace.trace_call(%{to: addr, data: "0x18160ddd", from: "0xshort"})
    end

    test "accepts valid call params (passes input validation)" do
      addr = "0x" <> String.duplicate("aa", 20)
      result = Trace.trace_call(%{to: addr, data: "0x18160ddd"})
      refute match?({:error, {:invalid_address, _}}, result)
      refute match?({:error, {:invalid_data, _}}, result)
      refute match?({:error, {:missing_param, _}}, result)
    end
  end

  describe "trace_call/3 block validation" do
    test "rejects negative integer block" do
      addr = "0x" <> String.duplicate("aa", 20)

      assert {:error, {:invalid_block, -1}} =
               Trace.trace_call(%{to: addr, data: "0x18160ddd"}, -1)
    end

    test "accepts integer block" do
      addr = "0x" <> String.duplicate("aa", 20)
      result = Trace.trace_call(%{to: addr, data: "0x18160ddd"}, 15_000_000)
      refute match?({:error, {:invalid_block, _}}, result)
    end

    test "accepts tag block" do
      addr = "0x" <> String.duplicate("aa", 20)
      result = Trace.trace_call(%{to: addr, data: "0x18160ddd"}, "finalized")
      refute match?({:error, {:invalid_block, _}}, result)
    end

    test "accepts hex block string" do
      addr = "0x" <> String.duplicate("aa", 20)
      result = Trace.trace_call(%{to: addr, data: "0x18160ddd"}, "0xe4e1c0")
      refute match?({:error, {:invalid_block, _}}, result)
    end
  end

  describe "storage_at/3 input validation" do
    test "rejects invalid address" do
      assert {:error, {:invalid_address, "0xshort"}} =
               Trace.storage_at("0xshort", "0x0000000000000000000000000000000000000000000000000000000000000000")
    end

    test "rejects slot without 0x prefix" do
      addr = "0x" <> String.duplicate("aa", 20)
      assert {:error, {:invalid_slot, "0"}} = Trace.storage_at(addr, "0")
    end

    test "rejects slot with invalid hex" do
      addr = "0x" <> String.duplicate("aa", 20)
      assert {:error, {:invalid_slot, "0xZZZZ"}} = Trace.storage_at(addr, "0xZZZZ")
    end

    test "rejects non-string slot" do
      addr = "0x" <> String.duplicate("aa", 20)
      assert {:error, {:invalid_slot, 0}} = Trace.storage_at(addr, 0)
    end

    test "rejects invalid block" do
      addr = "0x" <> String.duplicate("aa", 20)
      slot = "0x0000000000000000000000000000000000000000000000000000000000000000"
      assert {:error, {:invalid_block, :foo}} = Trace.storage_at(addr, slot, block: :foo)
    end

    test "accepts valid address and slot (passes input validation)" do
      addr = "0x" <> String.duplicate("aa", 20)
      slot = "0x0000000000000000000000000000000000000000000000000000000000000000"
      result = Trace.storage_at(addr, slot)
      refute match?({:error, {:invalid_address, _}}, result)
      refute match?({:error, {:invalid_slot, _}}, result)
    end
  end

  describe "storage_at/3 block validation" do
    test "accepts integer block" do
      addr = "0x" <> String.duplicate("aa", 20)
      slot = "0x0"
      result = Trace.storage_at(addr, slot, block: 15_000_000)
      refute match?({:error, {:invalid_block, _}}, result)
    end

    test "accepts tag block" do
      addr = "0x" <> String.duplicate("aa", 20)
      slot = "0x0"
      result = Trace.storage_at(addr, slot, block: "finalized")
      refute match?({:error, {:invalid_block, _}}, result)
    end
  end

  # --- Bang variant tests ---

  describe "trace_transaction!/2" do
    test "raises on invalid tx_hash" do
      assert_raise RuntimeError, ~r/trace_transaction failed/, fn ->
        Trace.trace_transaction!("no_prefix")
      end
    end
  end

  describe "trace_call!/3" do
    test "raises on missing params" do
      assert_raise RuntimeError, ~r/trace_call failed/, fn ->
        Trace.trace_call!(%{data: "0x18160ddd"})
      end
    end
  end

  describe "storage_at!/3" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/storage_at failed/, fn ->
        Trace.storage_at!("0xshort", "0x0")
      end
    end
  end

  # --- available?/1 (no input validation, so it always reaches the RPC layer;
  # point it at an unreachable local port to force a fast, deterministic
  # {:error, _} without depending on a live Ethereum node) ---

  describe "available?/1" do
    test "returns false when the RPC call errors" do
      refute Trace.available?(rpc_url: "http://127.0.0.1:1", timeout: 2_000)
    end
  end
end
