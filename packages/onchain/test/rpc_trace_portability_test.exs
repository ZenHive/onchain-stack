defmodule Onchain.RPCTracePortabilityTest do
  use ExUnit.Case, async: true

  import Onchain.Test.Live

  @moduletag :integration

  # Simple mainnet transfer. The archive trace is one call frame; hosted
  # endpoints refuse the method before they look at the hash.
  @tx "0x4a1e3e3a2aa4aa79a777d0ae3e2c3a6de158226134123f6c14334964c6ec70cf"
  @probe_call %{"to" => "0x0000000000000000000000000000000000000000", "data" => "0x"}

  # Observed 2026-10-02. Keep each message verbatim: a looser match would also
  # accept a broken credential or an unrelated JSON-RPC error.
  @alchemy_trace_transaction "trace_transaction is not available on the Free tier - upgrade to Pay As You Go, or Enterprise for access."
  @alchemy_trace_call "trace_call is not available on the Free tier - upgrade to Pay As You Go, or Enterprise for access."
  @alchemy_trace_call_many "trace_callMany is not available on the Free tier - upgrade to Pay As You Go, or Enterprise for access."
  @alchemy_debug_trace_call "debug_traceCall is not available on the Free tier - upgrade to Pay As You Go, or Enterprise for access."

  @infura_trace_transaction "The method trace_transaction does not exist/is not available"
  @infura_trace_call "The method trace_call does not exist/is not available"
  @infura_trace_call_many "The method trace_callMany does not exist/is not available"
  @infura_debug_trace_call "The method debug_traceCall does not exist/is not available"

  test "the trace probes succeed on the archive node and pin both hosted refusals" do
    assert_portability!(&probe/1,
      archive: &archive_answer?/1,
      alchemy: &alchemy_answer?/1,
      infura: &infura_answer?/1
    )
  end

  defp probe(opts) do
    %{
      trace_transaction: call("trace_transaction", [@tx], opts),
      trace_call: call("trace_call", [@probe_call, ["trace"], "latest"], opts),
      trace_call_many: call("trace_callMany", [[[@probe_call, ["trace"]]], "latest"], opts),
      debug_trace_call: call("debug_traceCall", [@probe_call, "latest"], opts),
      trace_available: Onchain.RPC.trace_available?(opts),
      debug_trace_available: Onchain.RPC.debug_trace_available?(opts)
    }
  end

  # Alchemy's free tier answers a burst of these methods with HTTP 429
  # ("compute units per second") and a JSON-RPC body whose code is 429.
  # That is capacity, not the capability refusal. Wait and try again; the
  # predicate still requires the verbatim refusal and never skips.
  defp call(method, params, opts, attempts \\ 4) do
    case Onchain.RPC.send_rpc(method, params, opts) do
      {:error, %Req.Response{status: 429}} when attempts > 0 ->
        Process.sleep(1_000)
        call(method, params, opts, attempts - 1)

      other ->
        other
    end
  end

  defp archive_answer?(%{
         trace_available: true,
         debug_trace_available: true,
         trace_transaction: {:ok, transactions},
         trace_call: {:ok, call},
         trace_call_many: {:ok, calls},
         debug_trace_call: {:ok, debug}
       })
       when is_list(transactions) and is_map(call) and is_list(calls) and is_map(debug), do: true

  defp archive_answer?(_answer), do: false

  defp alchemy_answer?(answer) do
    answer.trace_available == false and answer.debug_trace_available == false and
      refused?(answer.trace_transaction, :namespace_unavailable, -32_600, @alchemy_trace_transaction) and
      refused?(answer.trace_call, :namespace_unavailable, -32_600, @alchemy_trace_call) and
      refused?(answer.trace_call_many, :namespace_unavailable, -32_600, @alchemy_trace_call_many) and
      refused?(answer.debug_trace_call, :namespace_unavailable, -32_600, @alchemy_debug_trace_call)
  end

  defp infura_answer?(answer) do
    answer.trace_available == false and answer.debug_trace_available == false and
      refused?(answer.trace_transaction, :method_not_found, -32_601, @infura_trace_transaction) and
      refused?(answer.trace_call, :method_not_found, -32_601, @infura_trace_call) and
      refused?(answer.trace_call_many, :method_not_found, -32_601, @infura_trace_call_many) and
      refused?(answer.debug_trace_call, :method_not_found, -32_601, @infura_debug_trace_call)
  end

  defp refused?({:error, {tag, %{code: code, message: message}}}, tag, code, message), do: true
  defp refused?(_answer, _tag, _code, _message), do: false
end
