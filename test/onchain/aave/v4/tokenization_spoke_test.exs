defmodule Onchain.Aave.V4.TokenizationSpokeTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.V4.TokenizationSpoke

  @owner "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @assets 1_100
  @shares 1_000
  @total_assets 50_000
  @total_supply 45_000
  @balance 250
  @max_amount 1_000_000
  @asset_id 3
  @spoke_cap 1_099_511_627_775
  @permit_ns 42
  @deposit_hash <<1::256>>
  @mint_hash <<2::256>>
  @withdraw_hash <<3::256>>
  @redeem_hash <<4::256>>
  @permit_hash <<5::256>>
  @domain_hash <<6::256>>

  describe "lookup/3" do
    test "resolves configured Tokenization Spokes across Core, Prime, and Plus" do
      assert TokenizationSpoke.lookup(:core, :weth) == Contracts.v4_tokenization_spoke(:core, :weth)
      assert TokenizationSpoke.lookup(:prime, :gho) == Contracts.v4_tokenization_spoke(:prime, :gho)
      assert TokenizationSpoke.lookup(:plus, :pt_susde) == Contracts.v4_tokenization_spoke(:plus, :pt_susde)
    end

    test "same asset on different Hubs resolves to distinct addresses" do
      {:ok, core_usdc} = TokenizationSpoke.lookup(:core, :usdc)
      {:ok, prime_usdc} = TokenizationSpoke.lookup(:prime, :usdc)
      {:ok, plus_usdc} = TokenizationSpoke.lookup(:plus, :usdc)

      assert length(Enum.uniq([core_usdc, prime_usdc, plus_usdc])) == 3
    end

    test "every registered Tokenization Spoke is a valid checksummed address" do
      Enum.each([:core, :prime, :plus], fn hub ->
        Enum.each(tokenization_assets(hub), fn asset ->
          assert {:ok, addr} = TokenizationSpoke.lookup(hub, asset),
                 "expected lookup(#{inspect(hub)}, #{inspect(asset)}) to succeed"

          assert {:ok, _} = Onchain.Address.validate(addr)
          assert addr == Onchain.Address.checksum!(addr)
        end)
      end)
    end

    test "returns unknown_hub for an unconfigured hub atom" do
      assert {:error, {:unknown_hub, :bogus}} = TokenizationSpoke.lookup(:bogus, :weth)
    end

    test "returns unknown_tokenization_spoke for an unconfigured asset" do
      assert {:error, {:unknown_tokenization_spoke, {:core, :bogus}}} =
               TokenizationSpoke.lookup(:core, :bogus)
    end

    test "asset present in one hub but absent in another returns unknown_tokenization_spoke" do
      assert {:ok, _} = TokenizationSpoke.lookup(:core, :aave)

      assert {:error, {:unknown_tokenization_spoke, {:prime, :aave}}} =
               TokenizationSpoke.lookup(:prime, :aave)
    end

    test "returns unsupported_network on a V3-only network" do
      assert {:error, {:unsupported_network, :arbitrum}} =
               TokenizationSpoke.lookup(:core, :weth, network: :arbitrum)
    end
  end

  describe "input validation" do
    test "reads reject an invalid spoke address before RPC" do
      Enum.each(
        [
          &TokenizationSpoke.asset/1,
          &TokenizationSpoke.total_assets/1,
          &TokenizationSpoke.total_supply/1,
          &TokenizationSpoke.hub/1,
          &TokenizationSpoke.asset_id/1,
          &TokenizationSpoke.max_allowed_spoke_cap/1,
          &TokenizationSpoke.permit_nonce_namespace/1,
          &TokenizationSpoke.deposit_typehash/1,
          &TokenizationSpoke.mint_typehash/1,
          &TokenizationSpoke.withdraw_typehash/1,
          &TokenizationSpoke.redeem_typehash/1,
          &TokenizationSpoke.permit_typehash/1,
          &TokenizationSpoke.domain_separator/1
        ],
        fn fun ->
          assert {:error, {:invalid_address, "bad"}} = fun.("bad")
        end
      )
    end

    test "amount-taking reads reject an invalid spoke address before RPC" do
      Enum.each(
        [
          &TokenizationSpoke.convert_to_shares(&1, @assets),
          &TokenizationSpoke.convert_to_assets(&1, @shares),
          &TokenizationSpoke.preview_deposit(&1, @assets),
          &TokenizationSpoke.preview_mint(&1, @shares),
          &TokenizationSpoke.preview_withdraw(&1, @assets),
          &TokenizationSpoke.preview_redeem(&1, @shares)
        ],
        fn fun ->
          assert {:error, {:invalid_address, "bad"}} = fun.("bad")
        end
      )
    end

    test "account-taking reads reject an invalid owner/receiver before RPC" do
      {:ok, spoke} = TokenizationSpoke.lookup(:core, :weth)

      Enum.each(
        [
          &TokenizationSpoke.balance_of(spoke, &1),
          &TokenizationSpoke.max_deposit(spoke, &1),
          &TokenizationSpoke.max_mint(spoke, &1),
          &TokenizationSpoke.max_withdraw(spoke, &1),
          &TokenizationSpoke.max_redeem(spoke, &1)
        ],
        fn fun ->
          assert {:error, {:invalid_address, "bad"}} = fun.("bad")
        end
      )
    end

    test "account-taking reads reject an invalid spoke when the account is valid" do
      assert {:error, {:invalid_address, "bad"}} = TokenizationSpoke.balance_of("bad", @owner)
    end
  end

  describe "ERC-4626 accounting and V4 metadata reads" do
    setup do
      {:ok, spoke} = TokenizationSpoke.lookup(:core, :weth)
      {:ok, usdc} = TokenizationSpoke.lookup(:core, :usdc)
      {:ok, prime} = TokenizationSpoke.lookup(:prime, :weth)
      payloads = selector_payloads()
      {:ok, seen} = Agent.start_link(fn -> [] end)
      url = start_rpc_stub(fn body -> handle_eth_call(body, payloads, seen) end)

      on_exit(fn ->
        if Process.alive?(seen), do: Agent.stop(seen)
      end)

      %{
        spoke: spoke,
        usdc: usdc,
        prime: prime,
        rpc_opts: [rpc_url: url, timeout: 2_000, req_options: [connect_options: [protocols: [:http1]]]],
        seen: seen
      }
    end

    test "ERC-4626 accounting reads decode from a configured Tokenization Spoke", %{
      spoke: spoke,
      rpc_opts: rpc_opts
    } do
      {:ok, weth_underlying} = Onchain.Address.validate("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")
      expected_asset = Onchain.Address.checksum!(weth_underlying)

      assert {:ok, ^expected_asset} = TokenizationSpoke.asset(spoke, rpc_opts)
      assert {:ok, @total_assets} = TokenizationSpoke.total_assets(spoke, rpc_opts)
      assert {:ok, @total_supply} = TokenizationSpoke.total_supply(spoke, rpc_opts)
      assert {:ok, @balance} = TokenizationSpoke.balance_of(spoke, @owner, rpc_opts)
      assert {:ok, @shares} = TokenizationSpoke.convert_to_shares(spoke, @assets, rpc_opts)
      assert {:ok, @assets} = TokenizationSpoke.convert_to_assets(spoke, @shares, rpc_opts)
      assert {:ok, @shares} = TokenizationSpoke.preview_deposit(spoke, @assets, rpc_opts)
      assert {:ok, @assets} = TokenizationSpoke.preview_mint(spoke, @shares, rpc_opts)
      assert {:ok, @shares} = TokenizationSpoke.preview_withdraw(spoke, @assets, rpc_opts)
      assert {:ok, @assets} = TokenizationSpoke.preview_redeem(spoke, @shares, rpc_opts)
      assert {:ok, @max_amount} = TokenizationSpoke.max_deposit(spoke, @owner, rpc_opts)
      assert {:ok, @max_amount} = TokenizationSpoke.max_mint(spoke, @owner, rpc_opts)
      assert {:ok, @max_amount} = TokenizationSpoke.max_withdraw(spoke, @owner, rpc_opts)
      assert {:ok, @max_amount} = TokenizationSpoke.max_redeem(spoke, @owner, rpc_opts)
    end

    test "V4-specific metadata reads decode from a configured Tokenization Spoke", %{
      spoke: spoke,
      rpc_opts: rpc_opts
    } do
      {:ok, hub_addr} = Contracts.address(:v4_core_hub)

      assert {:ok, ^hub_addr} = TokenizationSpoke.hub(spoke, rpc_opts)
      assert {:ok, @asset_id} = TokenizationSpoke.asset_id(spoke, rpc_opts)
      assert {:ok, @spoke_cap} = TokenizationSpoke.max_allowed_spoke_cap(spoke, rpc_opts)
      assert {:ok, @permit_ns} = TokenizationSpoke.permit_nonce_namespace(spoke, rpc_opts)

      assert {:ok, deposit} = TokenizationSpoke.deposit_typehash(spoke, rpc_opts)
      assert {:ok, mint} = TokenizationSpoke.mint_typehash(spoke, rpc_opts)
      assert {:ok, withdraw} = TokenizationSpoke.withdraw_typehash(spoke, rpc_opts)
      assert {:ok, redeem} = TokenizationSpoke.redeem_typehash(spoke, rpc_opts)
      assert {:ok, permit} = TokenizationSpoke.permit_typehash(spoke, rpc_opts)
      assert {:ok, domain} = TokenizationSpoke.domain_separator(spoke, rpc_opts)

      assert deposit == Onchain.Hex.encode(@deposit_hash)
      assert mint == Onchain.Hex.encode(@mint_hash)
      assert withdraw == Onchain.Hex.encode(@withdraw_hash)
      assert redeem == Onchain.Hex.encode(@redeem_hash)
      assert permit == Onchain.Hex.encode(@permit_hash)
      assert domain == Onchain.Hex.encode(@domain_hash)
    end

    test "lookup address is the eth_call target for configured spokes", %{
      spoke: core_weth,
      usdc: core_usdc,
      prime: prime_weth,
      rpc_opts: rpc_opts,
      seen: seen
    } do
      assert {:ok, _} = TokenizationSpoke.total_assets(core_weth, rpc_opts)
      assert {:ok, _} = TokenizationSpoke.total_assets(core_usdc, rpc_opts)
      assert {:ok, _} = TokenizationSpoke.total_assets(prime_weth, rpc_opts)

      seen_tos =
        seen
        |> Agent.get(& &1)
        |> Enum.map(&String.downcase/1)
        |> Enum.uniq()
        |> Enum.sort()

      expected =
        [core_weth, core_usdc, prime_weth]
        |> Enum.map(&String.downcase/1)
        |> Enum.sort()

      assert seen_tos == expected
    end
  end

  defp tokenization_assets(:core),
    do: ~w(aave cbbtc eurc frxusd gho lbtc link rlusd rseth usdc usdg usdt wbtc weeth weth wsteth xaut)a

  defp tokenization_assets(:prime), do: ~w(cbbtc gho usdc usdt wbtc weth wsteth)a
  defp tokenization_assets(:plus), do: ~w(gho pt_susde pt_usde susde usdc usde usdt)a

  defp selector_payloads do
    {:ok, owner_bin} = Onchain.Address.validate(@owner)
    {:ok, weth_bin} = Onchain.Address.validate("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")
    {:ok, hub_bin} = Onchain.Address.validate(Contracts.address!(:v4_core_hub))

    %{
      selector("asset()", []) => encode("(address)", [{weth_bin}]),
      selector("totalAssets()", []) => encode("(uint256)", [{@total_assets}]),
      selector("totalSupply()", []) => encode("(uint256)", [{@total_supply}]),
      selector("balanceOf(address)", [owner_bin]) => encode("(uint256)", [{@balance}]),
      selector("convertToShares(uint256)", [@assets]) => encode("(uint256)", [{@shares}]),
      selector("convertToAssets(uint256)", [@shares]) => encode("(uint256)", [{@assets}]),
      selector("previewDeposit(uint256)", [@assets]) => encode("(uint256)", [{@shares}]),
      selector("previewMint(uint256)", [@shares]) => encode("(uint256)", [{@assets}]),
      selector("previewWithdraw(uint256)", [@assets]) => encode("(uint256)", [{@shares}]),
      selector("previewRedeem(uint256)", [@shares]) => encode("(uint256)", [{@assets}]),
      selector("maxDeposit(address)", [owner_bin]) => encode("(uint256)", [{@max_amount}]),
      selector("maxMint(address)", [owner_bin]) => encode("(uint256)", [{@max_amount}]),
      selector("maxWithdraw(address)", [owner_bin]) => encode("(uint256)", [{@max_amount}]),
      selector("maxRedeem(address)", [owner_bin]) => encode("(uint256)", [{@max_amount}]),
      selector("hub()", []) => encode("(address)", [{hub_bin}]),
      selector("assetId()", []) => encode("(uint256)", [{@asset_id}]),
      selector("MAX_ALLOWED_SPOKE_CAP()", []) => encode("(uint256)", [{@spoke_cap}]),
      selector("PERMIT_NONCE_NAMESPACE()", []) => encode("(uint256)", [{@permit_ns}]),
      selector("DEPOSIT_TYPEHASH()", []) => encode("(bytes32)", [{@deposit_hash}]),
      selector("MINT_TYPEHASH()", []) => encode("(bytes32)", [{@mint_hash}]),
      selector("WITHDRAW_TYPEHASH()", []) => encode("(bytes32)", [{@withdraw_hash}]),
      selector("REDEEM_TYPEHASH()", []) => encode("(bytes32)", [{@redeem_hash}]),
      selector("PERMIT_TYPEHASH()", []) => encode("(bytes32)", [{@permit_hash}]),
      selector("DOMAIN_SEPARATOR()", []) => encode("(bytes32)", [{@domain_hash}])
    }
  end

  defp selector(signature, params) do
    {:ok, hex} = Onchain.ABI.encode_call(signature, params)
    String.slice(hex, 0, 10)
  end

  defp encode(types, data) do
    "0x" <> Base.encode16(ABI.encode(types, data), case: :lower)
  end

  defp handle_eth_call(%{"method" => "eth_call", "params" => [%{"data" => data, "to" => to} | _]}, payloads, seen) do
    Agent.update(seen, &[to | &1])
    sel = String.slice(String.downcase(data), 0, 10)

    Map.get_lazy(payloads, sel, fn ->
      flunk("stub has no payload for selector #{sel} (data=#{data})")
    end)
  end

  defp start_rpc_stub(handler) do
    {:ok, listen} =
      :gen_tcp.listen(0, [:binary, packet: :http_bin, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(listen)
    parent = self()

    pid =
      spawn_link(fn ->
        send(parent, {:stub_ready, self()})
        stub_loop(listen, handler)
      end)

    receive do
      {:stub_ready, ^pid} -> :ok
    after
      1_000 -> flunk("JSON-RPC stub failed to start")
    end

    on_exit(fn ->
      Process.exit(pid, :kill)
      :gen_tcp.close(listen)
    end)

    "http://127.0.0.1:#{port}"
  end

  defp stub_loop(listen, handler) do
    case :gen_tcp.accept(listen, 5_000) do
      {:ok, sock} ->
        serve_one(sock, handler)
        stub_loop(listen, handler)

      {:error, :timeout} ->
        stub_loop(listen, handler)

      {:error, :closed} ->
        :ok
    end
  end

  defp serve_one(sock, handler) do
    {:ok, {:http_request, :POST, _, _}} = :gen_tcp.recv(sock, 0)
    length = recv_content_length(sock, 0)
    :ok = :inet.setopts(sock, packet: :raw)
    {:ok, body} = :gen_tcp.recv(sock, length)
    decoded = Jason.decode!(body)
    result = handler.(decoded)
    payload = Jason.encode!(%{"jsonrpc" => "2.0", "id" => decoded["id"], "result" => result})

    :ok =
      :gen_tcp.send(sock, [
        "HTTP/1.1 200 OK\r\n",
        "content-type: application/json\r\n",
        "content-length: #{byte_size(payload)}\r\n",
        "connection: close\r\n\r\n",
        payload
      ])

    :gen_tcp.close(sock)
  end

  defp recv_content_length(sock, acc) do
    case :gen_tcp.recv(sock, 0) do
      {:ok, :http_eoh} ->
        acc

      {:ok, {:http_header, _, name, _, value}} ->
        if header_name(name) == "content-length" do
          recv_content_length(sock, String.to_integer(header_value(value)))
        else
          recv_content_length(sock, acc)
        end
    end
  end

  defp header_name(name) when is_atom(name), do: name |> Atom.to_string() |> String.downcase()
  defp header_name(name) when is_binary(name), do: String.downcase(name)
  defp header_name(name) when is_list(name), do: name |> List.to_string() |> String.downcase()

  defp header_value(value) when is_binary(value), do: value
  defp header_value(value) when is_list(value), do: List.to_string(value)
end
