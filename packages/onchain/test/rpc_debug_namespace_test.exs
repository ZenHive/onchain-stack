defmodule Cartouche.RPC.DebugNamespaceTest do
  @moduledoc """
  Live coverage for `Cartouche.RPC.debug_trace_call/2`.

  Carries its own `:debug_namespace` tag instead of `:integration`, and is
  excluded by default in `test/test_helper.exs`. Opt in explicitly:

      mix test --only debug_namespace

  ## Why this is not part of the `:integration` suite

  The archive node this stack points at serves the `trace_*` namespace but has
  `debug_*` disabled as a deliberate security decision: `debug_traceCall` and
  `debug_traceTransaction` do unbounded work per request, so they are a DoS
  vector on any endpoint that is reachable beyond the host itself (ours is
  reached through an SSH tunnel, not loopback-only). With the namespace off the
  node answers `-32601 Method not found`, so this test cannot pass there and
  would otherwise sit permanently red inside `mix integration` — which trains
  everyone to stop reading a red suite.

  It is not merged into the integration module with an extra tag because
  `ExUnit.Filters.eval/4` checks `include` before `exclude`: under
  `--only integration` a test tagged both would still run. A separate module
  with a distinct moduletag is the only shape that actually keeps it out.

  Re-enabling `debug_*` on a node (a second, loopback-only port or an IPC
  endpoint is the usual way) is all this needs to go green again.

  The decode path stays covered without a live node: opcode/atom handling is
  unit-tested in `test/debug_trace_atom_safety_test.exs`.
  """
  use ExUnit.Case, async: true

  import Cartouche.Test.Live, only: [live_opts: 0]

  alias Cartouche.Transaction.V1

  @moduletag :debug_namespace

  setup_all do
    Cartouche.Test.Live.assert_node_available!()
    :ok
  end

  # Anchors mirror `Cartouche.RPC.IntegrationTest` — mainnet is immutable, so
  # these assertions are deterministic forever.
  @weth9 <<0xC02AAA39B223FE8D0A0E5C4F27EAD9083C756CC2::160>>
  @weth9_anchor_block 18_000_000
  @weth9_total_supply 0x2B30B5DBA159D35B4FEC1
  @weth9_total_supply_selector <<0x18, 0x16, 0x0D, 0xDD>>

  test "debug_traceCall WETH9.totalSupply() at block 18,000,000" do
    trx = V1.new(0, {0, :gwei}, 100_000, @weth9, 0, @weth9_total_supply_selector)
    opts = Keyword.put(live_opts(), :block_number, @weth9_anchor_block)

    assert {:ok, %Cartouche.DebugTrace{} = dt} = Cartouche.RPC.debug_trace_call(trx, opts)
    assert dt.failed == false
    assert is_integer(dt.gas)
    assert dt.gas > 0
    assert is_binary(dt.return_value)
    assert byte_size(dt.return_value) == 32
    assert :binary.decode_unsigned(dt.return_value) == @weth9_total_supply
    # struct_logs shape only — opcode coverage is unit-tested via
    # `test/debug_trace_atom_safety_test.exs`. The cons-pattern match below
    # both type-checks and pins non-emptiness in one line.
    assert is_list(dt.struct_logs)
    assert [%Cartouche.DebugTrace.StructLog{} | _] = dt.struct_logs
  end
end
