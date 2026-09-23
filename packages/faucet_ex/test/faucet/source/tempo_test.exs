defmodule Faucet.Source.TempoTest do
  use ExUnit.Case, async: false

  alias Faucet.Source.Tempo

  @address "0x" <> String.duplicate("ab", 20)
  @path_usd "0x20c0000000000000000000000000000000000000"

  defp opts(stub, extra \\ []),
    do: [rpc_url: "http://node", req_options: [plug: {Req.Test, stub}, retry: false]] ++ extra

  defp rpc_stub(name, handler) do
    Req.Test.stub(name, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"method" => method, "params" => params} = Jason.decode!(body)
      Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => handler.(method, params)})
    end)
  end

  describe "rpc_url/0" do
    test "defaults to Moderato and honours TEMPO_RPC_URL" do
      previous = System.get_env("TEMPO_RPC_URL")

      try do
        System.delete_env("TEMPO_RPC_URL")
        assert Tempo.rpc_url() == "https://rpc.moderato.tempo.xyz"
        System.put_env("TEMPO_RPC_URL", "https://mirror.example")
        assert Tempo.rpc_url() == "https://mirror.example"
      after
        if previous, do: System.put_env("TEMPO_RPC_URL", previous), else: System.delete_env("TEMPO_RPC_URL")
      end
    end
  end

  describe "fund/2" do
    test "calls tempo_fundAddress and returns the hashes" do
      rpc_stub(:tempo_fund, fn "tempo_fundAddress", [@address] -> ["0xfund1", "0xfund2"] end)
      assert {:ok, ["0xfund1", "0xfund2"]} = Tempo.fund(@address, opts(:tempo_fund))
    end

    test "rejects a non-list result and passes node errors through" do
      rpc_stub(:tempo_weird, fn _, _ -> "nope" end)
      assert {:error, {:unexpected_result, "nope"}} = Tempo.fund(@address, opts(:tempo_weird))

      Req.Test.stub(
        :tempo_err,
        &Req.Test.json(&1, %{"jsonrpc" => "2.0", "id" => 1, "error" => %{"message" => "rate limited"}})
      )

      assert {:error, {:rpc_error, %{"message" => "rate limited"}}} = Tempo.fund(@address, opts(:tempo_err))
    end
  end

  describe "balance/2" do
    test "reads the fee token by default and native gas on request" do
      rpc_stub(:tempo_bal, fn
        "eth_call", [%{"to" => @path_usd, "data" => "0x70a08231" <> _}, "latest"] -> "0x10"
        "eth_getBalance", [@address, "latest"] -> "0x20"
      end)

      assert {:ok, 16} = Tempo.balance(@address, opts(:tempo_bal))
      assert {:ok, 32} = Tempo.balance(@address, opts(:tempo_bal, asset: :native))
      assert {:error, {:invalid_option, :asset, :gold}} = Tempo.balance(@address, opts(:tempo_bal, asset: :gold))
    end

    test "honours a :fee_token override" do
      override = "0xabc0000000000000000000000000000000000000"
      rpc_stub(:tempo_fee, fn "eth_call", [%{"to" => ^override}, "latest"] -> "0x1" end)
      assert {:ok, 1} = Tempo.balance(@address, opts(:tempo_fee, fee_token: override))
    end
  end

  test "full loop: funds, polls the fee token until it lands" do
    counter = :counters.new(1, [])

    rpc_stub(:tempo_loop, fn
      "tempo_fundAddress", [@address] ->
        ["0xfund"]

      "eth_call", _ ->
        :counters.add(counter, 1, 1)
        if :counters.get(counter, 1) <= 2, do: "0x0", else: "0xde0b6b3a7640000"
    end)

    assert {:ok, 1_000_000_000_000_000_000} =
             Faucet.ensure_min_balance(Tempo, @address, 1, opts(:tempo_loop, poll_interval_ms: 1, timeout_ms: 500))
  end
end
