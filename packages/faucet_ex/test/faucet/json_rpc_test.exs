defmodule Faucet.JSONRPCTest do
  use ExUnit.Case, async: true

  alias Faucet.JSONRPC

  defp opts(stub), do: [req_options: [plug: {Req.Test, stub}, retry: false]]

  test "posts a JSON-RPC 2.0 envelope and returns the result" do
    Req.Test.stub(:rpc_ok, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert %{"jsonrpc" => "2.0", "id" => 1, "method" => "eth_chainId", "params" => []} = Jason.decode!(body)
      Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => "0x1"})
    end)

    assert {:ok, "0x1"} = JSONRPC.call("http://node", "eth_chainId", [], opts(:rpc_ok))
  end

  test "surfaces node errors, unexpected statuses and transport failures" do
    Req.Test.stub(
      :rpc_err,
      &Req.Test.json(&1, %{"jsonrpc" => "2.0", "id" => 1, "error" => %{"code" => -32_000, "message" => "rate limited"}})
    )

    assert {:error, {:rpc_error, %{"message" => "rate limited"}}} = JSONRPC.call("http://node", "m", [], opts(:rpc_err))

    Req.Test.stub(:rpc_500, fn conn -> conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"result" => "ignored"}) end)
    assert {:error, {:unexpected_response, 500, _}} = JSONRPC.call("http://node", "m", [], opts(:rpc_500))

    Req.Test.stub(:rpc_boom, &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, {:transport, %Req.TransportError{reason: :econnrefused}}} =
             JSONRPC.call("http://node", "m", [], opts(:rpc_boom))
  end

  test "quantity/1 decodes hex and rejects protocol violations" do
    assert {:ok, 0} = JSONRPC.quantity("0x0")
    assert {:ok, 255} = JSONRPC.quantity("0xff")
    assert {:error, {:invalid_quantity, "1"}} = JSONRPC.quantity("1")
    assert {:error, {:invalid_quantity, "0x-1"}} = JSONRPC.quantity("0x-1")
    assert {:error, {:invalid_quantity, 123}} = JSONRPC.quantity(123)
  end
end
