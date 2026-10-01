defmodule Cartouche.RPCNodeIntrospectionTest do
  use ExUnit.Case, async: true

  alias Cartouche.RPC.SyncStatus

  # execution-apis v1.0.0-beta.7 eth_syncing example
  # (src/eth/client.yaml): startingBlock 0x0, currentBlock 0x1518, highestBlock 0x9567a3.
  @spec_sync_object %{
    "startingBlock" => "0x0",
    "currentBlock" => "0x1518",
    "highestBlock" => "0x9567a3"
  }

  # Observed on Alchemy mainnet, 2026-10-01, HTTP 400. Keep the refusal verbatim.
  @alchemy_peer_count_refusal "net_peerCount is not available on the ETH_MAINNET. For more information see our docs: https://docs.alchemy.com/alchemy/documentation/apis/ethereum"

  @block_hash "0x" <> String.duplicate("cd", 32)

  test "eth_syncing decodes the spec progress object and bare false as one union" do
    assert %SyncStatus{starting_block: 0, current_block: 0x1518, highest_block: 0x9567A3} =
             SyncStatus.deserialize(@spec_sync_object)

    assert {:ok, %SyncStatus{starting_block: 0, current_block: 0x1518, highest_block: 0x9567A3}} =
             Cartouche.RPC.eth_syncing(rpc_opts(@spec_sync_object))

    assert {:ok, false} = Cartouche.RPC.eth_syncing(rpc_opts(false))
    assert_request("eth_syncing", [])
  end

  test "eth_syncing keeps the three spec quantities when a client adds fields" do
    object = Map.put(@spec_sync_object, "syncedAccounts", "0x10")

    assert {:ok, %SyncStatus{starting_block: 0, current_block: 0x1518, highest_block: 0x9567A3}} =
             Cartouche.RPC.eth_syncing(rpc_opts(object))
  end

  test "eth_syncing rejects a result outside the false-or-object union" do
    assert {:error, message} = Cartouche.RPC.eth_syncing(rpc_opts(true))
    assert message =~ "eth_syncing"
    assert message =~ "false or a sync-status object"
  end

  test "block transaction counts decode a quantity or null and reject a bad block" do
    assert {:ok, 2} = Cartouche.RPC.eth_get_block_transaction_count_by_hash(@block_hash, rpc_opts("0x2"))
    assert_request("eth_getBlockTransactionCountByHash", [@block_hash])

    assert {:ok, 2} = Cartouche.RPC.eth_get_block_transaction_count_by_number(16, rpc_opts("0x2"))
    assert_request("eth_getBlockTransactionCountByNumber", ["0x10"])

    assert {:ok, nil} = Cartouche.RPC.eth_get_block_transaction_count_by_number("latest", rpc_opts(nil))
    assert_request("eth_getBlockTransactionCountByNumber", ["latest"])

    assert {:error, {:invalid_block_hash, "0xshort"}} =
             Cartouche.RPC.eth_get_block_transaction_count_by_hash("0xshort")

    assert {:error, {:invalid_block, :unknown}} =
             Cartouche.RPC.eth_get_block_transaction_count_by_number(:unknown)

    assert {:error, message} =
             Cartouche.RPC.eth_get_block_transaction_count_by_number(16, rpc_opts("not-a-quantity"))

    assert message =~ "eth_getBlockTransactionCountByNumber"
  end

  test "untagged methods surface Alchemy's HTTP 400 refusal as method_not_found" do
    for {function, method} <- [
          {&Cartouche.RPC.net_peer_count/1, "net_peerCount"},
          {&Cartouche.RPC.net_listening/1, "net_listening"},
          {&Cartouche.RPC.web3_client_version/1, "web3_clientVersion"}
        ] do
      assert {:error, {:method_not_found, %{code: -32_600, message: @alchemy_peer_count_refusal}}} =
               function.(http_error_opts(400, -32_600, @alchemy_peer_count_refusal))

      assert_request(method, [])
    end
  end

  test "net_listening and web3_clientVersion decode the values the hosted lanes returned" do
    assert {:ok, true} = Cartouche.RPC.net_listening(rpc_opts(true))

    assert {:ok, "reth/v2.5.2-5a6940e/x86_64-unknown-linux-gnu"} =
             Cartouche.RPC.web3_client_version(rpc_opts("reth/v2.5.2-5a6940e/x86_64-unknown-linux-gnu"))
  end

  defp rpc_opts(result) do
    test_pid = self()

    plug = fn conn ->
      request = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
      send(test_pid, {:rpc_request, request})
      Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => request["id"], "result" => result})
    end

    [rpc_url: "http://stub.invalid", req_options: [plug: plug]]
  end

  defp http_error_opts(status, code, message) do
    test_pid = self()

    plug = fn conn ->
      request = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
      send(test_pid, {:rpc_request, request})

      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(%{
        "jsonrpc" => "2.0",
        "id" => request["id"],
        "error" => %{"code" => code, "message" => message}
      })
    end

    [rpc_url: "http://stub.invalid", req_options: [plug: plug]]
  end

  defp assert_request(method, params) do
    assert_receive {:rpc_request, %{"method" => ^method, "params" => ^params}}
  end
end
