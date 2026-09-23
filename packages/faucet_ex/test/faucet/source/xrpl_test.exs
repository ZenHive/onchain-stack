defmodule Faucet.Source.XRPLTest do
  use ExUnit.Case, async: true

  alias Faucet.Source.XRPL

  @address "rHb9CJAWyB4rj91VRWn96DkukG4bwdtyTh"

  defp opts(stub),
    do: [
      rpc_url: "http://xrpl",
      faucet_url: "http://faucet/accounts",
      req_options: [plug: {Req.Test, stub}, retry: false]
    ]

  test "balance/2 reads validated account_info drops and treats an unseen account as zero" do
    Req.Test.stub(:xrpl_bal, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert %{"method" => "account_info", "params" => [%{"account" => @address, "ledger_index" => "validated"}]} =
               Jason.decode!(body)

      Req.Test.json(conn, %{"result" => %{"account_data" => %{"Balance" => "10000000"}}})
    end)

    assert {:ok, 10_000_000} = XRPL.balance(@address, opts(:xrpl_bal))

    Req.Test.stub(:xrpl_new, &Req.Test.json(&1, %{"result" => %{"error" => "actNotFound"}}))
    assert {:ok, 0} = XRPL.balance(@address, opts(:xrpl_new))

    Req.Test.stub(:xrpl_odd, &Req.Test.json(&1, %{"result" => %{"account_data" => %{"Balance" => "abc"}}}))
    assert {:error, {:invalid_quantity, "abc"}} = XRPL.balance(@address, opts(:xrpl_odd))
  end

  test "fund/2 posts the destination and requires the faucet to echo it back" do
    Req.Test.stub(:xrpl_fund, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == %{"destination" => @address}
      Req.Test.json(conn, %{"account" => %{"address" => @address}, "amount" => 100})
    end)

    assert {:ok, [@address]} = XRPL.fund(@address, opts(:xrpl_fund))

    Req.Test.stub(:xrpl_other, &Req.Test.json(&1, %{"account" => %{"address" => "rOther"}}))
    assert {:error, {:provider_rejected, 200, _}} = XRPL.fund(@address, opts(:xrpl_other))

    Req.Test.stub(:xrpl_down, &Req.Test.transport_error(&1, :timeout))
    assert {:error, {:transport, _}} = XRPL.fund(@address, opts(:xrpl_down))
  end
end
