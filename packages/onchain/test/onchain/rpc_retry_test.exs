defmodule Onchain.RPC.RetryTest do
  use ExUnit.Case, async: false

  alias Onchain.RPC

  @stub_rpc_url "http://stub.invalid"
  @no_backoff_ms 0

  # Req function plug driven by a queue of responses in the calling test's process
  # dictionary. A `{:transport_error, reason}` entry simulates a connection-level
  # failure (Req.Test.transport_error/2 -> %Req.TransportError{}); a 1-arity fun
  # builds a JSON-RPC response map from the decoded request body. Injected via
  # cartouche's `config :cartouche, Cartouche.RPC, plug:` single-call seam.
  defmodule StubClient do
    @moduledoc false

    @stub_key :onchain_rpc_retry_stub_responses

    @type stub_response :: {:transport_error, term()} | (map() -> map())

    def call(conn) do
      body = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

      case Process.get(@stub_key) do
        nil ->
          raise "StubClient: no responses queued"

        [] ->
          raise "StubClient: responses exhausted"

        [response | remaining] ->
          Process.put(@stub_key, remaining)
          emit(conn, response, body)
      end
    end

    @spec queue_responses([stub_response()]) :: :ok
    def queue_responses(responses) when is_list(responses) do
      Process.put(@stub_key, responses)
      :ok
    end

    defp emit(conn, {:transport_error, reason}, _body), do: Req.Test.transport_error(conn, reason)

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

  describe "retry policy" do
    test "does not retry by default" do
      StubClient.queue_responses([{:transport_error, :closed}, rpc_success("0x1")])

      assert_rpc_error_message(
        RPC.call("eth_blockNumber", [], rpc_url: @stub_rpc_url),
        "closed"
      )
    end

    test "retries opted-in RPC errors and returns a later success" do
      StubClient.queue_responses([{:transport_error, :closed}, rpc_success("0x2a")])

      assert {:ok, "0x2a"} =
               RPC.call("eth_blockNumber", [],
                 rpc_url: @stub_rpc_url,
                 retry: [max_retries: 1, backoff_ms: @no_backoff_ms]
               )
    end

    test "returns the final RPC error after retries are exhausted" do
      StubClient.queue_responses([{:transport_error, :closed}, {:transport_error, :timeout}])

      "eth_blockNumber"
      |> RPC.call([],
        rpc_url: @stub_rpc_url,
        retry: [max_retries: 1, backoff_ms: @no_backoff_ms]
      )
      |> assert_rpc_error_message("timeout")
    end

    test "does not retry JSON-RPC application errors" do
      StubClient.queue_responses([rpc_error_response(-32_000, "execution reverted"), rpc_success("0x1")])

      assert {:error, {:rpc_error, %{code: -32_000, message: "execution reverted"}}} =
               RPC.call("eth_blockNumber", [],
                 rpc_url: @stub_rpc_url,
                 retry: [max_retries: 1, backoff_ms: @no_backoff_ms]
               )
    end
  end

  defp assert_rpc_error_message(result, expected_message) do
    assert {:error, {:rpc_error, %{message: message}}} = result
    assert message =~ expected_message
  end

  defp rpc_success(result) do
    fn body -> %{"id" => body["id"], "jsonrpc" => "2.0", "result" => result} end
  end

  defp rpc_error_response(code, message) do
    fn body ->
      %{"id" => body["id"], "jsonrpc" => "2.0", "error" => %{"code" => code, "message" => message}}
    end
  end
end
