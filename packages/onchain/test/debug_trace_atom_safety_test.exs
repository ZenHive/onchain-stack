defmodule Cartouche.DebugTraceAtomSafetyTest do
  use ExUnit.Case, async: false

  alias Cartouche.DebugTrace.StructLog

  @base_struct_log %{
    "depth" => 1,
    "gas" => 1,
    "gasCost" => 1,
    "op" => "STOP",
    "pc" => 0,
    "stack" => []
  }

  test "atom_count does not grow across many novel-looking opcodes" do
    # Warm up: first hits to assert_raise / inspect / exception-formatting
    # paths may intern atoms one-time inside ExUnit / Logger / JIT machinery.
    # Measure baseline AFTER warmup, then prove the per-iteration delta is zero.
    for _ <- 1..50 do
      params = %{@base_struct_log | "op" => "WARMUP_#{:erlang.unique_integer()}"}
      assert_raise ArgumentError, fn -> StructLog.deserialize(params) end
    end

    :erlang.garbage_collect()
    before = :erlang.system_info(:atom_count)
    iterations = 1000

    for i <- 1..iterations do
      params = %{@base_struct_log | "op" => "FAKE_OPCODE_#{i}_#{:erlang.unique_integer()}"}
      assert_raise ArgumentError, fn -> StructLog.deserialize(params) end
    end

    delta = :erlang.system_info(:atom_count) - before

    # If decode_op were minting atoms, delta would be ≥ iterations (1000+).
    # Allow a small slack for incidental atoms (test scheduler, Logger) that
    # may still be created during the loop. The meaningful signal is delta ≪ iterations.
    assert delta < div(iterations, 10),
           "atom_count grew by #{delta} over #{iterations} iterations — " <>
             "decode_op may be minting atoms from RPC input"
  end
end
