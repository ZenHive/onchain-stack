defmodule Onchain.Trace.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Trace

  @moduletag :integration
  @moduletag :trace

  # USDC contract on mainnet
  @usdc_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

  # First ever ETH transfer on mainnet (block 46147, 2015) — requires archive node
  @known_tx_hash "0x5c504ed432cb51138bcf09aa5e8a410dd4a1e204ef84bfed1be16dfba1b22060"

  defp rpc_opts do
    [rpc_url: Onchain.RPCCase.rpc_url!()]
  end

  describe "available?/1" do
    test "returns a boolean" do
      result = Trace.available?(rpc_opts())
      assert is_boolean(result)
    end
  end

  describe "storage_at/3" do
    test "reads slot 0 of USDC contract" do
      assert {:ok, value} = Trace.storage_at(@usdc_address, "0x0", rpc_opts())
      assert is_binary(value)
      assert String.starts_with?(value, "0x")
    end

    test "reads slot at specific block" do
      assert {:ok, value} =
               Trace.storage_at(@usdc_address, "0x0", Keyword.put(rpc_opts(), :block, 17_000_000))

      assert is_binary(value)
      assert String.starts_with?(value, "0x")
    end
  end

  describe "trace_transaction/2" do
    setup do
      if !Trace.available?(rpc_opts()) do
        flunk("""
        Trace APIs not available on this RPC endpoint!

        debug_traceTransaction requires a node with debug APIs enabled.
        Options:
          - Local reth node: reth node --http --http.api debug,trace,eth,net,web3
          - Local geth node: geth --http --http.api debug,eth,net,web3
          - Alchemy Growth plan (supports debug_traceTransaction)

        Set ETHEREUM_API_URL or ETH_RPC_URL to a trace-capable endpoint.
        """)
      end

      :ok
    end

    test "traces a known transaction with callTracer" do
      assert {:ok, trace} = Trace.trace_transaction(@known_tx_hash, rpc_opts())
      assert is_map(trace)
      # callTracer returns a call tree with these standard fields
      assert Map.has_key?(trace, "type") or Map.has_key?(trace, "from")
    end

    test "traces a transaction with prestateTracer" do
      assert {:ok, trace} =
               Trace.trace_transaction(@known_tx_hash, Keyword.put(rpc_opts(), :tracer, "prestateTracer"))

      assert is_map(trace)
    end
  end

  describe "trace_call/3" do
    setup do
      if !Trace.available?(rpc_opts()) do
        flunk("""
        Trace APIs not available on this RPC endpoint!

        debug_traceCall requires a node with debug APIs enabled.
        Options:
          - Local reth node: reth node --http --http.api debug,trace,eth,net,web3
          - Local geth node: geth --http --http.api debug,eth,net,web3
          - Alchemy Growth plan (supports debug_traceCall)

        Set ETHEREUM_API_URL or ETH_RPC_URL to a trace-capable endpoint.
        """)
      end

      :ok
    end

    test "traces a USDC totalSupply call" do
      # totalSupply() selector = 0x18160ddd
      call_params = %{to: @usdc_address, data: "0x18160ddd"}
      assert {:ok, trace} = Trace.trace_call(call_params, "latest", rpc_opts())
      assert is_map(trace)
    end

    test "traces with prestateTracer" do
      call_params = %{to: @usdc_address, data: "0x18160ddd"}

      assert {:ok, trace} =
               Trace.trace_call(call_params, "latest", Keyword.put(rpc_opts(), :tracer, "prestateTracer"))

      assert is_map(trace)
    end
  end
end
