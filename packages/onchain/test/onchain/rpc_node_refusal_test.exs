defmodule Onchain.RPC.NodeRefusalTest do
  use ExUnit.Case, async: false

  alias Onchain.RPC

  @stub_rpc_url "http://stub.invalid"
  @call_address "0x" <> String.duplicate("aa", 20)
  @call_data "0x18160ddd"
  @block 20_000_000

  # Observed live on Alchemy mainnet, 2026-08-25, with eth_blockNumber succeeding
  # on the same URL in the same session.
  @alchemy_unsupported_access_list "Unsupported method: eth_getBlockAccessList on ETH_MAINNET"
  @alchemy_base_fee_unavailable "eth_baseFee is not available on the ETH_MAINNET. For more information see our docs: https://docs.alchemy.com/alchemy/documentation/apis/ethereum"
  @alchemy_trace_tier "trace_block is not available on the Free tier - upgrade to Pay As You Go, or Enterprise for access."
  @alchemy_unable "Unable to complete request at this time."

  defmodule StubClient do
    @moduledoc false

    @stub_key :onchain_rpc_node_refusal_stub_responses

    def call(conn) do
      body = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

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
      :ok
    end

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
    previous = Application.get_env(:cartouche, Cartouche.RPC)
    Application.put_env(:cartouche, Cartouche.RPC, plug: &StubClient.call/1)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:cartouche, Cartouche.RPC)
        config -> Application.put_env(:cartouche, Cartouche.RPC, config)
      end
    end)

    :ok
  end

  describe "method not implemented" do
    test "JSON-RPC -32601 becomes {:method_not_found, map}" do
      StubClient.queue_responses([rpc_error(-32_601, "Method not found")])

      assert {:error, {:method_not_found, %{code: -32_601, message: "Method not found"}}} =
               RPC.call("eth_thisMethodDoesNotExistAnywhere", [], rpc_url: @stub_rpc_url)
    end

    test "Alchemy -32600 Unsupported method becomes {:method_not_found, map}" do
      StubClient.queue_responses([rpc_error(-32_600, @alchemy_unsupported_access_list)])

      assert {:error, {:method_not_found, %{code: -32_600, message: @alchemy_unsupported_access_list}}} =
               RPC.call("eth_getBlockAccessList", ["0x1312d00"], rpc_url: @stub_rpc_url)
    end

    test "Alchemy -32600 eth_baseFee not available becomes {:method_not_found, map}" do
      StubClient.queue_responses([rpc_error(-32_600, @alchemy_base_fee_unavailable)])

      assert {:error, {:method_not_found, %{code: -32_600, message: @alchemy_base_fee_unavailable}}} =
               RPC.call("eth_baseFee", [], rpc_url: @stub_rpc_url)
    end
  end

  describe "namespace disabled on the provider plan" do
    test "Alchemy Free-tier trace refusal becomes {:namespace_unavailable, map}" do
      StubClient.queue_responses([rpc_error(-32_600, @alchemy_trace_tier)])

      assert {:error, {:namespace_unavailable, %{code: -32_600, message: @alchemy_trace_tier}}} =
               RPC.call("trace_block", ["0x1312d00"], rpc_url: @stub_rpc_url)
    end
  end

  describe "node could not complete the request" do
    test "Alchemy -32001 unable-to-complete becomes {:unavailable, map}" do
      StubClient.queue_responses([rpc_error(-32_001, @alchemy_unable)])

      assert {:error, {:unavailable, %{code: -32_001, message: @alchemy_unable}}} =
               RPC.fee_history(1, newest_block: @block, rpc_url: @stub_rpc_url)
    end
  end

  describe "unrecognized codes pass through unchanged" do
    test "execution-reverted -32000 keeps {:rpc_error, map} byte-identical" do
      StubClient.queue_responses([rpc_error(-32_000, "execution reverted")])

      expected = {:error, {:rpc_error, %{code: -32_000, message: "execution reverted"}}}

      assert ^expected = RPC.call("eth_blockNumber", [], rpc_url: @stub_rpc_url)
    end

    test "bare -32600 Invalid Request is not classified as method_not_found" do
      StubClient.queue_responses([rpc_error(-32_600, "Invalid Request")])

      expected = {:error, {:rpc_error, %{code: -32_600, message: "Invalid Request"}}}

      assert ^expected = RPC.call("eth_blockNumber", [], rpc_url: @stub_rpc_url)
    end

    test "reth -32602 Invalid params is not classified as a capability refusal" do
      # Observed on reth v2.5.1 for eth_getStorageValues with empty params —
      # the same code genuine bad-params errors use, so it must not be unified
      # with method-not-found.
      StubClient.queue_responses([rpc_error(-32_602, "Invalid params")])

      expected = {:error, {:rpc_error, %{code: -32_602, message: "Invalid params"}}}

      assert ^expected = RPC.call("eth_getStorageValues", [], rpc_url: @stub_rpc_url)
    end
  end

  describe "shared do_rpc path" do
    test "codegen'd wrapper, hand-written wrapper, and call/3 return the same classified term" do
      error = rpc_error(-32_601, "Method not found")
      expected = {:error, {:method_not_found, %{code: -32_601, message: "Method not found"}}}

      StubClient.queue_responses([error])
      assert ^expected = RPC.block_number(rpc_url: @stub_rpc_url)

      StubClient.queue_responses([error])
      assert ^expected = RPC.eth_call(@call_address, @call_data, rpc_url: @stub_rpc_url)

      StubClient.queue_responses([error])
      assert ^expected = RPC.call("eth_blockNumber", [], rpc_url: @stub_rpc_url)
    end
  end

  describe "HTTP 400 JSON-RPC body (Alchemy wire shape)" do
    test "unwraps the JSON-RPC error from a non-2xx response and classifies it" do
      StubClient.queue_responses([
        {:http, 400, rpc_error(-32_600, @alchemy_unsupported_access_list)}
      ])

      assert {:error, {:method_not_found, %{code: -32_600, message: @alchemy_unsupported_access_list}}} =
               RPC.get_block_access_list(@block, rpc_url: @stub_rpc_url)
    end

    test "HTTP 503 unable-to-complete is classified as {:unavailable, map}" do
      StubClient.queue_responses([{:http, 503, rpc_error(-32_001, @alchemy_unable)}])

      assert {:error, {:unavailable, %{code: -32_001, message: @alchemy_unable}}} =
               RPC.call("eth_feeHistory", ["0x1", "0x1312d00", [50]], rpc_url: @stub_rpc_url)
    end

    test "HTTP 400 with an unrecognized code keeps {:rpc_error, %Req.Response{}}" do
      StubClient.queue_responses([{:http, 400, rpc_error(-32_000, "execution reverted")}])

      assert {:error, {:rpc_error, %Req.Response{status: 400, body: body}}} =
               RPC.call("eth_call", [], rpc_url: @stub_rpc_url)

      assert body =~ "execution reverted"
    end
  end

  defp rpc_error(code, message) do
    fn body ->
      %{"id" => body["id"], "jsonrpc" => "2.0", "error" => %{"code" => code, "message" => message}}
    end
  end
end
