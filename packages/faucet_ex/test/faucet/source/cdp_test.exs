defmodule Faucet.Source.CDPTest do
  use ExUnit.Case, async: true

  alias Faucet.Source.CDP

  @address "0x898018e18e1aa5819282ec4d9b784e1ae7eecac4"
  @usdc "0x036CbD53842c5426634e7929541eC2318f3dCF7e"

  setup do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    secret = Base.encode64(priv <> pub)
    %{pub: pub, creds: [api_key_id: "organizations/x/apiKeys/y", api_key_secret: secret]}
  end

  defp opts(stub, extra), do: [network: "base-sepolia", req_options: [plug: {Req.Test, stub}, retry: false]] ++ extra

  defp rpc_stub(name, handler) do
    Req.Test.stub(name, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"method" => method, "params" => params} = Jason.decode!(body)
      Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => handler.(method, params)})
    end)
  end

  test "networks/0 lists the two supported testnets" do
    assert Enum.sort(CDP.networks()) == ["base-sepolia", "ethereum-sepolia"]
  end

  test "refuses unsupported networks before any call" do
    assert {:error, {:unsupported_network, "base", _}} = CDP.balance(@address, network: "base")
    assert {:error, {:unsupported_network, nil, _}} = CDP.fund(@address, [])
  end

  test "balance/2 reads native ETH by default and an ERC-20 when a token address is given" do
    rpc_stub(:cdp_bal, fn
      "eth_getBalance", [@address, "latest"] -> "0x5"
      "eth_call", [%{"to" => @usdc}, "latest"] -> "0x6"
    end)

    assert {:ok, 5} = CDP.balance(@address, opts(:cdp_bal, rpc_url: "http://node"))
    assert {:ok, 6} = CDP.balance(@address, opts(:cdp_bal, rpc_url: "http://node", token: "usdc", token_address: @usdc))

    assert {:error, {:missing_option, :token_address}} =
             CDP.balance(@address, opts(:cdp_bal, rpc_url: "http://node", token: "usdc"))
  end

  test "fund/2 posts a signed EdDSA JWT, idempotency key and the request body", %{pub: pub, creds: creds} do
    Req.Test.stub(:cdp_fund, fn conn ->
      ["Bearer " <> jwt] = Plug.Conn.get_req_header(conn, "authorization")
      [header, claims, signature] = String.split(jwt, ".")

      assert %{"alg" => "EdDSA", "typ" => "JWT", "kid" => "organizations/x/apiKeys/y", "nonce" => _} =
               header |> Base.url_decode64!(padding: false) |> Jason.decode!()

      decoded_claims = claims |> Base.url_decode64!(padding: false) |> Jason.decode!()
      assert decoded_claims["iss"] == "cdp"
      assert decoded_claims["uris"] == ["POST api.cdp.coinbase.com/platform/v2/evm/faucet"]
      assert decoded_claims["exp"] - decoded_claims["nbf"] == 120

      assert :crypto.verify(:eddsa, :none, header <> "." <> claims, Base.url_decode64!(signature, padding: false), [
               pub,
               :ed25519
             ])

      [key] = Plug.Conn.get_req_header(conn, "x-idempotency-key")
      assert String.match?(key, ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == %{"network" => "base-sepolia", "address" => @address, "token" => "eth"}

      Req.Test.json(conn, %{"transactionHash" => "0xcdp"})
    end)

    assert {:ok, ["0xcdp"]} = CDP.fund(@address, opts(:cdp_fund, creds))
  end

  test "fund/2 reports provider rejections with status and body", %{creds: creds} do
    Req.Test.stub(:cdp_400, fn conn ->
      conn
      |> Plug.Conn.put_status(400)
      |> Req.Test.json(%{"errorType" => "invalid_request", "errorMessage" => "valid EVM hex address"})
    end)

    assert {:error, {:provider_rejected, 400, %{"errorType" => "invalid_request"}}} =
             CDP.fund("bad", opts(:cdp_400, creds))
  end

  test "fund/2 fails fast on missing or malformed credentials without calling the provider" do
    Req.Test.stub(:cdp_never, fn _ -> flunk("provider must not be called") end)

    assert {:error, {:missing_credential, "CDP_API_KEY_ID", hint}} =
             CDP.fund(@address, opts(:cdp_never, api_key_id: nil, api_key_secret: "x"))

    assert hint =~ "portal.cdp.coinbase.com"

    assert {:error, {:invalid_credential, :api_key_secret, _}} =
             CDP.fund(@address, opts(:cdp_never, api_key_id: "id", api_key_secret: Base.encode64("short")))
  end

  test "wait_confirmed/3 polls every receipt through the network's node" do
    rpc_stub(:cdp_receipts, fn "eth_getTransactionReceipt", [hash] ->
      %{"status" => "0x1", "transactionHash" => hash}
    end)

    assert :ok = CDP.wait_confirmed(["0xa", "0xb"], @address, opts(:cdp_receipts, rpc_url: "http://node"))

    rpc_stub(:cdp_revert, fn "eth_getTransactionReceipt", _ -> %{"status" => "0x0"} end)
    assert {:error, {:reverted, _}} = CDP.wait_confirmed(["0xa"], @address, opts(:cdp_revert, rpc_url: "http://node"))
  end
end
