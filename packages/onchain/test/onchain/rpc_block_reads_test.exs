defmodule Onchain.RPC.BlockReadsTest do
  use ExUnit.Case, async: true

  alias Onchain.RPC

  @block_number 16
  @block_hash "0x" <> String.duplicate("cd", 32)

  test "get_block_access_list/2 preserves the node's raw camelCase shape" do
    access_list = [
      %{
        "address" => "0x" <> String.duplicate("00", 19) <> "01",
        "balanceChanges" => [],
        "codeChanges" => [],
        "nonceChanges" => [],
        "storageChanges" => [],
        "storageReads" => []
      }
    ]

    assert {:ok, ^access_list} = RPC.get_block_access_list(@block_hash, rpc_opts(access_list))
    assert_request("eth_getBlockAccessList", [@block_hash])

    assert {:ok, nil} = RPC.get_block_access_list(@block_number, rpc_opts(nil))
    assert_request("eth_getBlockAccessList", ["0x10"])
  end

  test "get_block_access_list/2 rejects a malformed block selector" do
    assert {:error, {:invalid_block, :unknown}} = RPC.get_block_access_list(:unknown)
  end

  test "get_block_access_list/2 rejects a malformed successful RPC payload" do
    assert {:error, {:rpc_error, %{message: access_list_message}}} =
             RPC.get_block_access_list(@block_number, rpc_opts("not-a-list"))

    assert access_list_message =~ "unexpected block access list response"

    assert {:error, {:rpc_error, %{message: access_list_entry_message}}} =
             RPC.get_block_access_list(@block_number, rpc_opts([nil]))

    assert access_list_entry_message =~ "unexpected block access list response"
  end

  test "get_block_access_list!/2 unwraps a successful read" do
    assert [] == RPC.get_block_access_list!(@block_number, rpc_opts([]))
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

  defp assert_request(method, params) do
    assert_receive {:rpc_request, %{"method" => ^method, "params" => ^params}}
  end
end
