defmodule Onchain.RPC.BatchTest do
  use ExUnit.Case, async: false

  alias Onchain.RPC

  # Req function plug (`fun(conn) -> conn`). It runs inside the test process that
  # issues the batch request, so Process.get here reads that process's queued
  # response. Injected via `config :onchain, Onchain.RPC, plug:` — onchain's own
  # transport seam (Onchain.HTTP.req_options/3), not cartouche's removed one.
  defmodule StubClient do
    @moduledoc false

    @stub_key :onchain_rpc_batch_stub_response

    def call(conn) do
      case Process.get(@stub_key) do
        nil ->
          raise "StubClient: no response queued"

        response_fun when is_function(response_fun, 1) ->
          body = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
          Req.Test.json(conn, response_fun.(body))
      end
    end

    @spec queue_response((term() -> term())) :: :ok
    def queue_response(response_fun) when is_function(response_fun, 1) do
      Process.put(@stub_key, response_fun)
      :ok
    end
  end

  setup_all do
    previous = Application.get_env(:onchain, RPC)
    Application.put_env(:onchain, RPC, plug: &StubClient.call/1)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:onchain, RPC)
        config -> Application.put_env(:onchain, RPC, config)
      end
    end)

    :ok
  end

  describe "batch/2" do
    test "sends one JSON-RPC array request and returns results in request order" do
      StubClient.queue_response(fn body ->
        assert [
                 %{"id" => 1, "jsonrpc" => "2.0", "method" => "eth_blockNumber", "params" => []},
                 %{"id" => 2, "jsonrpc" => "2.0", "method" => "eth_chainId", "params" => []}
               ] = body

        [
          %{"id" => 2, "jsonrpc" => "2.0", "result" => "0x1"},
          %{"id" => 1, "jsonrpc" => "2.0", "result" => "0x2a"}
        ]
      end)

      assert {:ok, ["0x2a", "0x1"]} =
               RPC.batch(
                 [
                   {"eth_blockNumber", []},
                   {"eth_chainId", []}
                 ],
                 rpc_url: "http://stub.invalid"
               )
    end

    test "normalizes JSON-RPC error responses" do
      StubClient.queue_response(fn _body ->
        [
          %{
            "id" => 1,
            "jsonrpc" => "2.0",
            "error" => %{"code" => -32_000, "message" => "execution reverted"}
          }
        ]
      end)

      assert {:error, {:rpc_error, %{code: -32_000, message: "execution reverted"}}} =
               RPC.batch(
                 [{"eth_call", [%{"to" => "0x" <> String.duplicate("ab", 20)}, "latest"]}],
                 rpc_url: "http://stub.invalid"
               )
    end

    # Same node refusal, same tag, whichever entry point the caller used: batch/2
    # shares Onchain.RPC's classifier with call/3 rather than re-deriving it.
    test "an item-level -32601 is classified as {:method_not_found, map}" do
      StubClient.queue_response(fn _body ->
        [
          %{"id" => 1, "jsonrpc" => "2.0", "result" => "0x1"},
          %{
            "id" => 2,
            "jsonrpc" => "2.0",
            "error" => %{"code" => -32_601, "message" => "Method not found"}
          }
        ]
      end)

      assert {:error, {:method_not_found, %{code: -32_601, message: "Method not found"}}} =
               RPC.batch(
                 [{"eth_blockNumber", []}, {"eth_thisMethodDoesNotExistAnywhere", []}],
                 rpc_url: "http://stub.invalid"
               )
    end

    test "an item-level Free-tier trace refusal is {:namespace_unavailable, map}" do
      message =
        "trace_block is not available on the Free tier - upgrade to Pay As You Go, or Enterprise for access."

      StubClient.queue_response(fn _body ->
        [
          %{
            "id" => 1,
            "jsonrpc" => "2.0",
            "error" => %{"code" => -32_600, "message" => message}
          }
        ]
      end)

      assert {:error, {:namespace_unavailable, %{code: -32_600, message: ^message}}} =
               RPC.batch([{"trace_block", ["0x1312d00"]}], rpc_url: "http://stub.invalid")
    end

    test "a top-level batch error is classified the same way as an item-level one" do
      message = "Unable to complete request at this time."

      StubClient.queue_response(fn _body ->
        %{
          "id" => nil,
          "jsonrpc" => "2.0",
          "error" => %{"code" => -32_001, "message" => message}
        }
      end)

      assert {:error, {:unavailable, %{code: -32_001, message: ^message}}} =
               RPC.batch(
                 [{"eth_feeHistory", ["0x1", "0x1312d00", [50]]}],
                 rpc_url: "http://stub.invalid"
               )
    end

    test "returns error when batch body contains a non-map response item" do
      StubClient.queue_response(fn _body ->
        [1]
      end)

      assert {:error, {:rpc_error, %{message: "missing batch response"}}} =
               RPC.batch(
                 [{"eth_blockNumber", []}],
                 rpc_url: "http://stub.invalid"
               )
    end

    test "honors a per-call :req_options transport override (regression: to_rpc_opts dropped it)" do
      # Remove the app-config seam so the ONLY way the stub plug reaches Req is
      # the per-call `req_options:` (Onchain.HTTP.req_options/3 level 4). Before
      # the fix, to_rpc_opts/1 stripped :req_options and this hit the network.
      previous = Application.get_env(:onchain, RPC)
      Application.delete_env(:onchain, RPC)
      on_exit(fn -> if previous, do: Application.put_env(:onchain, RPC, previous) end)

      StubClient.queue_response(fn _body ->
        [%{"id" => 1, "jsonrpc" => "2.0", "result" => "0x2a"}]
      end)

      assert {:ok, ["0x2a"]} =
               RPC.batch(
                 [{"eth_blockNumber", []}],
                 rpc_url: "http://stub.invalid",
                 req_options: [plug: &StubClient.call/1]
               )
    end
  end
end
