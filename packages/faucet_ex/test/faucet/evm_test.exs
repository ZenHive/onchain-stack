defmodule Faucet.EVMTest do
  use ExUnit.Case, async: true

  alias Faucet.EVM
  alias Faucet.Test.FakeSource

  @address "0x898018e18e1aa5819282ec4d9b784e1ae7eecac4"
  @token "0x20c0000000000000000000000000000000000000"

  defp opts(stub), do: [rpc_url: "http://node", req_options: [plug: {Req.Test, stub}, retry: false]]

  defp rpc_stub(name, handler) do
    Req.Test.stub(name, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"method" => method, "params" => params} = Jason.decode!(body)
      Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => handler.(method, params)})
    end)
  end

  test "native_balance/2 reads eth_getBalance at latest" do
    rpc_stub(:native, fn "eth_getBalance", [@address, "latest"] -> "0x2a" end)
    assert {:ok, 42} = EVM.native_balance(@address, opts(:native))
  end

  test "erc20_balance/3 issues balanceOf(address) against the token" do
    rpc_stub(:erc20, fn "eth_call", [%{"to" => @token, "data" => data}, "latest"] ->
      assert data == "0x70a08231" <> String.duplicate("0", 24) <> String.trim_leading(@address, "0x")
      "0xde0b6b3a7640000"
    end)

    assert {:ok, 1_000_000_000_000_000_000} = EVM.erc20_balance(@token, @address, opts(:erc20))
  end

  test "balance_of_calldata/1 rejects malformed addresses" do
    assert {:error, {:invalid_address, "0x12"}} = EVM.balance_of_calldata("0x12")
    assert {:error, {:invalid_address, "0x" <> _}} = EVM.balance_of_calldata("0x" <> String.duplicate("zz", 20))
    assert {:error, {:invalid_address, nil}} = EVM.balance_of_calldata(nil)
  end

  describe "wait_receipt/2" do
    test "polls through nil until the receipt succeeds" do
      counter = :counters.new(1, [])

      rpc_stub(:receipt_ok, fn "eth_getTransactionReceipt", ["0xhash"] ->
        :counters.add(counter, 1, 1)
        if :counters.get(counter, 1) < 3, do: nil, else: %{"status" => "0x1"}
      end)

      assert :ok = EVM.wait_receipt("0xhash", opts(:receipt_ok) ++ [poll_interval_ms: 1, timeout_ms: 1_000])
      assert :counters.get(counter, 1) == 3
    end

    test "reports a reverted transaction with its receipt" do
      rpc_stub(:receipt_revert, fn _, _ -> %{"status" => "0x0", "transactionHash" => "0xhash"} end)
      assert {:error, {:reverted, %{"status" => "0x0"}}} = EVM.wait_receipt("0xhash", opts(:receipt_revert))
    end

    test "times out while the receipt stays pending" do
      rpc_stub(:receipt_pending, fn _, _ -> nil end)

      assert {:error, :timeout} =
               EVM.wait_receipt("0xhash", opts(:receipt_pending) ++ [poll_interval_ms: 1, timeout_ms: 10])
    end
  end

  describe "fresh wallets (onchain present)" do
    test "fresh_wallet/0 derives a matching address" do
      assert {:ok, %{private_key: key, address_hex: hex, address_bin: bin}} = EVM.fresh_wallet()
      assert byte_size(key) == 32 and byte_size(bin) == 20
      assert {:ok, ^hex} = Onchain.Signer.address_from_key(key)
      assert "0x" <> Base.encode16(bin, case: :lower) == String.downcase(hex)
    end

    test "fresh_funded_wallet/3 funds the generated address through the source" do
      agent = FakeSource.start([{:ok, 0}, {:ok, 5}])

      assert {:ok, %{address_hex: hex}} = EVM.fresh_funded_wallet(FakeSource, 5, agent: agent, poll_interval_ms: 1)
      assert [{:balance, ^hex}, {:fund, ^hex, 5}, {:balance, ^hex}, {:balance, ^hex}] = FakeSource.calls(agent)
    end
  end
end
