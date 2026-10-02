defmodule Faucet.Source.SolanaTest do
  use ExUnit.Case, async: true

  alias Faucet.Source.Solana

  @pubkey "9xQeWvG816bUx9EPjHmaT23yvVM2ZWbrrpZb9PusVFin"

  defp opts(stub, extra \\ []),
    do: [rpc_url: "http://devnet", req_options: [plug: {Req.Test, stub}, retry: false]] ++ extra

  defp rpc_stub(name, handler) do
    Req.Test.stub(name, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"method" => method, "params" => params} = Jason.decode!(body)
      Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => handler.(method, params)})
    end)
  end

  test "balance/2 unwraps getBalance's value at the configured commitment" do
    rpc_stub(:sol_bal, fn "getBalance", [@pubkey, %{"commitment" => "finalized"}] ->
      %{"context" => %{}, "value" => 42}
    end)

    assert {:ok, 42} = Solana.balance(@pubkey, opts(:sol_bal, commitment: "finalized"))

    rpc_stub(:sol_weird, fn _, _ -> %{"value" => "42"} end)
    assert {:error, {:unexpected_result, _}} = Solana.balance(@pubkey, opts(:sol_weird))
  end

  test "fund/2 airdrops the configured lamports, capped to the loop's deficit" do
    rpc_stub(:sol_air, fn "requestAirdrop", [@pubkey, lamports, %{"commitment" => "confirmed"}] -> "sig-#{lamports}" end)

    assert {:ok, ["sig-1000000000"]} = Solana.fund(@pubkey, opts(:sol_air))
    assert {:ok, ["sig-250"]} = Solana.fund(@pubkey, opts(:sol_air, deficit: 250))
    assert {:ok, ["sig-100"]} = Solana.fund(@pubkey, opts(:sol_air, lamports: 100, deficit: 250))
  end

  test "fund/2 rejects a non-string signature" do
    rpc_stub(:sol_bad, fn _, _ -> 1 end)
    assert {:error, {:unexpected_result, 1}} = Solana.fund(@pubkey, opts(:sol_bad))
  end

  test "unit/0" do
    assert Solana.unit() == "lamports"
  end
end
