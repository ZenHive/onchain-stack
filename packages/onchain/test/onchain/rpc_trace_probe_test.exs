defmodule Onchain.RPC.TraceProbeTest do
  use ExUnit.Case, async: false

  alias Onchain.RPC

  @stub_rpc_url "http://stub.invalid"
  @zero_address "0x0000000000000000000000000000000000000000"
  @alchemy_trace_call "trace_call is not available on the Free tier - upgrade to Pay As You Go, or Enterprise for access."
  @alchemy_debug "debug_traceCall is not available on the Free tier - upgrade to Pay As You Go, or Enterprise for access."
  @infura_trace_call "The method trace_call does not exist/is not available"
  @unable "Unable to complete request at this time."

  defmodule StubClient do
    @moduledoc false

    @stub_key :onchain_rpc_trace_probe_stub_responses
    @seen_key :onchain_rpc_trace_probe_seen_requests

    def call(conn) do
      body = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
      Process.put(@seen_key, Process.get(@seen_key, []) ++ [body])

      case Process.get(@stub_key) do
        [response | remaining] ->
          Process.put(@stub_key, remaining)
          emit(conn, response, body)

        _ ->
          raise "StubClient: no responses queued"
      end
    end

    def queue_responses(responses) when is_list(responses) do
      Process.put(@stub_key, responses)
      Process.put(@seen_key, [])
      :ok
    end

    def seen_requests, do: Process.get(@seen_key, [])

    defp emit(conn, {:http, status, response_fun}, body) when is_function(response_fun, 1) do
      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(response_fun.(body))
    end

    defp emit(conn, response_fun, body) when is_function(response_fun, 1) do
      Req.Test.json(conn, response_fun.(body))
    end
  end

  setup do
    previous = Application.get_env(:cartouche, RPC)
    Application.put_env(:cartouche, RPC, plug: &StubClient.call/1)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:cartouche, RPC)
        config -> Application.put_env(:cartouche, RPC, config)
      end
    end)

    :ok
  end

  test "trace_available?/1 is true only when trace_call returns a result" do
    StubClient.queue_responses([result(%{"output" => "0x", "trace" => []})])

    assert RPC.trace_available?(rpc_url: @stub_rpc_url)
    assert [%{"method" => "trace_call", "params" => [call, ["trace"], "latest"]}] = StubClient.seen_requests()
    assert call["to"] == @zero_address
    assert call["data"] == "0x"
  end

  test "debug_trace_available?/1 issues one cheap debug_traceCall" do
    StubClient.queue_responses([result(%{"failed" => false, "gas" => 0, "structLogs" => []})])

    assert RPC.debug_trace_available?(rpc_url: @stub_rpc_url)

    assert [%{"method" => "debug_traceCall", "params" => [call, "latest"]}] = StubClient.seen_requests()
    assert call["to"] == @zero_address
    assert call["data"] == "0x"
  end

  test "a classified namespace refusal makes the probe false without a second string match" do
    StubClient.queue_responses([
      {:http, 400, rpc_error(-32_600, @alchemy_trace_call)},
      {:http, 400, rpc_error(-32_600, @alchemy_trace_call)}
    ])

    opts = [rpc_url: @stub_rpc_url]

    assert {:error, {:namespace_unavailable, %{code: -32_600, message: @alchemy_trace_call}}} =
             RPC.send_rpc("trace_call", [], opts)

    refute RPC.trace_available?(opts)
  end

  test "Infura -32601 and an unable-to-complete refusal are false" do
    StubClient.queue_responses([rpc_error(-32_601, @infura_trace_call)])
    refute RPC.trace_available?(rpc_url: @stub_rpc_url)

    StubClient.queue_responses([{:http, 503, rpc_error(-32_001, @unable)}])
    refute RPC.trace_available?(rpc_url: @stub_rpc_url)
  end

  test "Alchemy's debug_traceCall tier refusal makes debug_trace_available?/1 false" do
    StubClient.queue_responses([
      {:http, 400, rpc_error(-32_600, @alchemy_debug)},
      {:http, 400, rpc_error(-32_600, @alchemy_debug)}
    ])

    opts = [rpc_url: @stub_rpc_url]

    assert {:error, {:namespace_unavailable, %{code: -32_600, message: @alchemy_debug}}} =
             RPC.send_rpc("debug_traceCall", [], opts)

    refute RPC.debug_trace_available?(opts)
  end

  test "an unrecognized JSON-RPC error and a missing URL are false" do
    StubClient.queue_responses([rpc_error(-32_602, "Invalid params")])
    refute RPC.trace_available?(rpc_url: @stub_rpc_url)

    refute RPC.trace_available?(rpc_url: "")
    refute RPC.debug_trace_available?(rpc_url: "")
  end

  test "a caller-supplied :decode is not applied to the probe" do
    StubClient.queue_responses([result(%{"output" => "0x", "trace" => []})])

    assert RPC.trace_available?(rpc_url: @stub_rpc_url, decode: fn _ -> raise "decode must not run" end)
  end

  defp result(value) do
    fn body -> %{"id" => body["id"], "jsonrpc" => "2.0", "result" => value} end
  end

  defp rpc_error(code, message) do
    fn body ->
      %{"id" => body["id"], "jsonrpc" => "2.0", "error" => %{"code" => code, "message" => message}}
    end
  end
end
