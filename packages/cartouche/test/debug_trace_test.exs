defmodule Cartouche.DebugTraceTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.DebugTrace.StructLog

  doctest Cartouche.DebugTrace
  doctest StructLog

  @base_struct_log %{
    "depth" => 1,
    "gas" => 1,
    "gasCost" => 1,
    "op" => "STOP",
    "pc" => 0,
    "stack" => []
  }

  describe "StructLog.deserialize/1 — opcode whitelist" do
    test "PUSH family boundaries (PUSH0, PUSH1, PUSH32)" do
      for op <- ~w(PUSH0 PUSH1 PUSH32) do
        result = StructLog.deserialize(%{@base_struct_log | "op" => op})
        assert result.op == String.to_existing_atom(op)
      end
    end

    test "DUP family boundaries (DUP1, DUP16)" do
      for op <- ~w(DUP1 DUP16) do
        result = StructLog.deserialize(%{@base_struct_log | "op" => op})
        assert result.op == String.to_existing_atom(op)
      end
    end

    test "SWAP family boundaries (SWAP1, SWAP16)" do
      for op <- ~w(SWAP1 SWAP16) do
        result = StructLog.deserialize(%{@base_struct_log | "op" => op})
        assert result.op == String.to_existing_atom(op)
      end
    end

    test "LOG family boundaries (LOG0, LOG4)" do
      for op <- ~w(LOG0 LOG4) do
        result = StructLog.deserialize(%{@base_struct_log | "op" => op})
        assert result.op == String.to_existing_atom(op)
      end
    end

    test "KECCAK256 and SHA3 both decode (legacy Geth alias preserved)" do
      assert StructLog.deserialize(%{@base_struct_log | "op" => "KECCAK256"}).op == :KECCAK256
      assert StructLog.deserialize(%{@base_struct_log | "op" => "SHA3"}).op == :SHA3
    end

    test "DIFFICULTY and PREVRANDAO both decode (current Geth still emits DIFFICULTY for 0x44)" do
      assert StructLog.deserialize(%{@base_struct_log | "op" => "DIFFICULTY"}).op == :DIFFICULTY
      assert StructLog.deserialize(%{@base_struct_log | "op" => "PREVRANDAO"}).op == :PREVRANDAO
    end

    test "Cancun additions decode (BLOBHASH, BLOBBASEFEE, TLOAD, TSTORE, MCOPY)" do
      for op <- ~w(BLOBHASH BLOBBASEFEE TLOAD TSTORE MCOPY) do
        result = StructLog.deserialize(%{@base_struct_log | "op" => op})
        assert result.op == String.to_existing_atom(op)
      end
    end

    test "Osaka addition decodes (CLZ, EIP-7939)" do
      assert StructLog.deserialize(%{@base_struct_log | "op" => "CLZ"}).op == :CLZ
    end

    test "raises ArgumentError on unknown opcode with offending string in message" do
      params = %{@base_struct_log | "op" => "FAKEOPCODE"}

      assert_raise ArgumentError, ~r/unknown EVM opcode: "FAKEOPCODE"/, fn ->
        StructLog.deserialize(params)
      end
    end

    test "raises ArgumentError on out-of-range PUSH (PUSH33 is not a real opcode)" do
      params = %{@base_struct_log | "op" => "PUSH33"}

      assert_raise ArgumentError, ~r/unknown EVM opcode: "PUSH33"/, fn ->
        StructLog.deserialize(params)
      end
    end

    test "raises ArgumentError on nil op" do
      params = %{@base_struct_log | "op" => nil}

      assert_raise ArgumentError, ~r/expected binary opcode string/, fn ->
        StructLog.deserialize(params)
      end
    end
  end
end
