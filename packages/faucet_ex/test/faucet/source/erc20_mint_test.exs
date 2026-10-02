defmodule Faucet.Source.ERC20MintTest do
  use ExUnit.Case, async: true

  alias Faucet.Source.ERC20Mint

  @faucet "0xd9145b5f45ad4519c7accd6e0a4a82e83bb8a6dc"
  @token "0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f"
  @key <<1::256>>

  defp rpc_stub(name, handler) do
    Req.Test.stub(name, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"method" => method, "params" => params} = Jason.decode!(body)
      Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => handler.(method, params)})
    end)
  end

  defp base_opts(stub) do
    [
      faucet: @faucet,
      token: @token,
      private_key: @key,
      chain_id: 84_532,
      rpc_url: "http://node",
      req_options: [plug: {Req.Test, stub}, retry: false]
    ]
  end

  test "calldata/3 encodes mint(token, to, amount) with the right selector" do
    {:ok, signer} = Onchain.Signer.address_from_key(@key)
    assert {:ok, <<selector::binary-size(4), args::binary>>} = ERC20Mint.calldata(@token, signer, 25_000_000)

    assert selector == "mint(address,address,uint256)" |> Cartouche.Hash.keccak() |> binary_part(0, 4)

    assert {:ok, [token_bin, to_bin, 25_000_000]} =
             Onchain.ABI.decode_types("(address,address,uint256)", "0x" <> Base.encode16(args, case: :lower))

    assert Base.encode16(token_bin, case: :lower) == String.downcase(String.trim_leading(@token, "0x"))
    assert Base.encode16(to_bin, case: :lower) == String.downcase(String.trim_leading(signer, "0x"))
  end

  test "fund/2 mints the deficit through the injected sender with a fresh pending nonce" do
    {:ok, signer} = Onchain.Signer.address_from_key(@key)
    rpc_stub(:mint_nonce, fn "eth_getTransactionCount", [^signer, "pending"] -> "0x7" end)
    test_pid = self()

    send_transaction = fn to, calldata, signer_opts ->
      send(test_pid, {:sent, to, calldata, signer_opts})
      {:ok, "0xminted"}
    end

    opts = base_opts(:mint_nonce) ++ [deficit: 1_000_000, send_transaction: send_transaction, max_fee_per_gas: 100]
    assert {:ok, ["0xminted"]} = ERC20Mint.fund(signer, opts)

    assert_received {:sent, @faucet, calldata, signer_opts}
    assert {:ok, ^calldata} = ERC20Mint.calldata(@token, signer, 1_000_000)
    assert signer_opts[:nonce] == 7
    assert signer_opts[:gas_limit] == 200_000
    assert signer_opts[:chain_id] == 84_532
    assert signer_opts[:max_fee_per_gas] == 100
    assert signer_opts[:private_key] == @key
  end

  test "fund/2 prefers a fixed :amount over the deficit and rejects neither" do
    {:ok, signer} = Onchain.Signer.address_from_key(@key)
    rpc_stub(:mint_amount, fn "eth_getTransactionCount", _ -> "0x0" end)
    test_pid = self()

    sender = fn _to, calldata, _ ->
      send(test_pid, {:calldata, calldata})
      {:ok, "0x1"}
    end

    assert {:ok, _} =
             ERC20Mint.fund(signer, base_opts(:mint_amount) ++ [amount: 5, deficit: 9, send_transaction: sender])

    assert_received {:calldata, calldata}
    assert {:ok, ^calldata} = ERC20Mint.calldata(@token, signer, 5)

    assert {:error, {:invalid_option, :amount, nil}} =
             ERC20Mint.fund(signer, base_opts(:mint_amount) ++ [send_transaction: sender])
  end

  test "fund/2 and balance/2 name the missing option" do
    assert {:error, {:missing_option, :faucet}} = ERC20Mint.fund("0x1", token: @token)
    assert {:error, {:missing_option, :private_key}} = ERC20Mint.fund("0x1", faucet: @faucet, token: @token)
    assert {:error, {:missing_option, :token}} = ERC20Mint.balance("0x1", rpc_url: "http://node")
  end

  test "balance/2 reads the token and wait_confirmed/3 polls receipts" do
    {:ok, signer} = Onchain.Signer.address_from_key(@key)

    rpc_stub(:mint_read, fn
      "eth_call", [%{"to" => @token}, "latest"] -> "0x3"
      "eth_getTransactionReceipt", ["0xminted"] -> %{"status" => "0x1"}
    end)

    assert {:ok, 3} = ERC20Mint.balance(signer, base_opts(:mint_read))
    assert :ok = ERC20Mint.wait_confirmed(["0xminted"], signer, base_opts(:mint_read))
  end

  test "full loop mints exactly once when the deficit is covered" do
    {:ok, signer} = Onchain.Signer.address_from_key(@key)
    counter = :counters.new(1, [])

    rpc_stub(:mint_loop, fn
      "eth_call", _ ->
        :counters.add(counter, 1, 1)
        if :counters.get(counter, 1) == 1, do: "0x0", else: "0x" <> Integer.to_string(25_000_000, 16)

      "eth_getTransactionCount", _ ->
        "0x0"

      "eth_getTransactionReceipt", _ ->
        %{"status" => "0x1"}
    end)

    sender = fn _, _, _ -> {:ok, "0xminted"} end

    assert {:ok, 25_000_000} =
             Faucet.ensure_min_balance(
               ERC20Mint,
               signer,
               25_000_000,
               base_opts(:mint_loop) ++ [send_transaction: sender]
             )
  end
end
