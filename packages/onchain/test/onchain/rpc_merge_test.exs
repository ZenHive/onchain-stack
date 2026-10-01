defmodule Onchain.RPCMergeTest do
  use ExUnit.Case, async: true

  alias Cartouche.RPC
  alias Onchain.RPC.Helpers

  test "block reads retain the requests hash and nullable pending fields" do
    raw = %{"number" => nil, "hash" => nil, "requestsHash" => "0x" <> String.duplicate("ab", 32)}
    opts = result_opts(raw)
    assert {:ok, %Cartouche.Block{} = block} = RPC.get_block_by_number("pending", opts)
    assert is_nil(block.number)
    assert is_nil(block.hash)
    assert block.requests_hash == :binary.copy(<<0xAB>>, 32)
    assert_receive {:wire, %{"method" => "eth_getBlockByNumber", "params" => ["pending", false]}}

    assert {:ok, nil} = RPC.get_block_by_number(42, result_opts(nil))
    assert_receive {:wire, %{"params" => ["0x2a", false]}}
  end

  test "nonce aliases accept both address forms and both block option names" do
    for {address, block_opts} <- [
          {<<1::160>>, [block_number: :pending]},
          {"0x" <> String.duplicate("00", 19) <> "01", [block: "pending"]}
        ],
        function <- [:get_nonce, :get_transaction_count] do
      assert {:ok, 42} = apply(RPC, function, [address, block_opts ++ result_opts("0x2a")])

      assert_receive {:wire,
                      %{
                        "method" => "eth_getTransactionCount",
                        "params" => ["0x0000000000000000000000000000000000000001", "pending"]
                      }}
    end
  end

  test "fee history options and count adapters send the same canonical quantity" do
    raw = %{"oldestBlock" => "0x10", "baseFeePerGas" => ["0x1", "0x2"], "gasUsedRatio" => [0.5], "reward" => [["0x3"]]}
    opts = result_opts(raw)
    assert {:ok, expected} = RPC.fee_history(1, opts)
    assert_receive {:wire, %{"params" => ["0x1", "latest", [50]]}}
    assert {:ok, ^expected} = RPC.fee_history([block_count: "0x1", reward_percentiles: [50]] ++ opts)
    assert_receive {:wire, %{"params" => ["0x1", "latest", [50]]}}
  end

  test "Onchain.RPC is aliases only and forwards block_number" do
    assert Code.ensure_loaded?(Onchain.RPC)
    assert Code.ensure_loaded?(RPC)
    assert Code.ensure_loaded?(Helpers)

    for {name, arity} <- [
          {:eth_call, 3},
          {:eth_estimate_gas, 2},
          {:eth_send_raw_transaction, 2},
          {:get_balance, 2},
          {:block_number, 0},
          {:chain_id, 0},
          {:get_block_by_number, 2},
          {:get_transaction_receipt, 2},
          {:get_transaction_count, 2},
          {:eth_get_code, 2},
          {:fee_history, 2},
          {:blob_base_fee, 0},
          {:get_block_access_list, 2},
          {:call, 3},
          {:batch, 2}
        ] do
      assert function_exported?(Onchain.RPC, name, arity)
      assert function_exported?(RPC, name, arity)
    end

    refute Code.ensure_loaded?(Cartouche.RPC.DSL)
    refute function_exported?(Helpers, :parse_log, 1)
    refute function_exported?(Onchain.RPC, :send_rpc, 3)

    assert {:ok, 42} = Onchain.RPC.block_number(result_opts("0x2a"))
    assert_receive {:wire, %{"method" => "eth_blockNumber", "params" => []}}
  end

  defp result_opts(result) do
    pid = self()

    [
      rpc_url: "http://rpc.invalid",
      req_options: [
        plug: fn conn ->
          request = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
          send(pid, {:wire, request})
          Req.Test.json(conn, %{id: request["id"], jsonrpc: "2.0", result: result})
        end
      ]
    ]
  end
end
