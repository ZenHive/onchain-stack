defmodule Onchain.Aave.V4.HubTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.V4.Hub
  alias Onchain.Aave.V4.Hub.Asset
  alias Onchain.Aave.V4.Hub.SpokeConfig
  alias Onchain.Aave.V4.Hub.SpokeData

  @hubs [:core, :prime, :plus]
  @asset_id 0
  @spoke "0x94e7A5dCbE816e498b89aB752661904E2F56c485"
  @usdc "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

  @asset_tuple {1_000, 10, 6, 800, 50, -3, 200, 15, 5, 1_000_000, 50_000, 1_700_000_000, <<1::160>>, <<2::160>>,
                <<3::160>>, <<4::160>>, 7}

  @spoke_data_tuple {200, 15, -3, 800, 1_000_000, 500_000, 2_000, true, false, 7}
  @spoke_config_tuple {1_000_000, 500_000, 2_000, true, false}

  describe "hub_address/2" do
    test "resolves all three configured Hubs to distinct checksummed addresses" do
      addresses =
        Enum.map(@hubs, fn hub ->
          assert {:ok, addr} = Hub.hub_address(hub)
          addr
        end)

      assert addresses == [
               Contracts.address!(:v4_core_hub),
               Contracts.address!(:v4_prime_hub),
               Contracts.address!(:v4_plus_hub)
             ]

      assert length(Enum.uniq(addresses)) == 3
    end

    test "returns unknown_hub for an unconfigured atom" do
      assert {:error, {:unknown_hub, :bogus}} = Hub.hub_address(:bogus)
    end

    test "returns unsupported_network for a network with no Aave deployment" do
      assert {:error, {:unsupported_network, :solana}} = Hub.hub_address(:core, network: :solana)
    end

    test "returns unknown_contract on a V3-only network" do
      assert {:error, {:unknown_contract, :v4_core_hub}} = Hub.hub_address(:core, network: :arbitrum)
    end
  end

  describe "input validation" do
    test "spoke-taking reads reject an invalid Spoke address before RPC" do
      Enum.each(
        [
          &Hub.is_spoke_listed(:core, @asset_id, &1),
          &Hub.get_spoke(:core, @asset_id, &1),
          &Hub.get_spoke_config(:core, @asset_id, &1),
          &Hub.get_spoke_added_assets(:core, @asset_id, &1),
          &Hub.get_spoke_drawn_shares(:core, @asset_id, &1),
          &Hub.get_spoke_owed(:core, @asset_id, &1),
          &Hub.get_spoke_total_owed(:core, @asset_id, &1),
          &Hub.get_spoke_deficit_ray(:core, @asset_id, &1)
        ],
        fn fun ->
          assert {:error, {:invalid_address, "bad"}} = fun.("bad")
        end
      )
    end

    test "get_asset_id/3 rejects an invalid underlying address" do
      assert {:error, {:invalid_address, "bad"}} = Hub.get_asset_id(:core, "bad")
    end

    test "reads fail unknown_hub before RPC" do
      assert {:error, {:unknown_hub, :bogus}} = Hub.get_asset_count(:bogus)
      assert {:error, {:unknown_hub, :bogus}} = Hub.get_spoke_count(:bogus, @asset_id)
    end

    test "reads fail on a V3-only network" do
      assert {:error, {:unknown_contract, :v4_core_hub}} =
               Hub.get_asset_count(:core, network: :arbitrum)
    end
  end

  describe "from_raw" do
    test "Asset.from_raw/1 checksums addresses and keeps signed premium offset" do
      asset = Asset.from_raw(@asset_tuple)

      assert asset.liquidity == 1_000
      assert asset.decimals == 6
      assert asset.premium_offset_ray == -3
      assert asset.drawn_rate == 50_000
      assert asset.deficit_ray == 7
      assert asset.underlying == Onchain.Address.checksum!(<<1::160>>)
      assert asset.fee_receiver == Onchain.Address.checksum!(<<4::160>>)
    end

    test "SpokeData.from_raw/1 keeps caps, flags, and signed offset" do
      data = SpokeData.from_raw(@spoke_data_tuple)

      assert data.drawn_shares == 200
      assert data.add_cap == 1_000_000
      assert data.draw_cap == 500_000
      assert data.risk_premium_threshold == 2_000
      assert data.active
      refute data.halted
      assert data.premium_offset_ray == -3
    end

    test "SpokeConfig.from_raw/1 keeps caps and flags" do
      config = SpokeConfig.from_raw(@spoke_config_tuple)

      assert config.add_cap == 1_000_000
      assert config.draw_cap == 500_000
      assert config.active
      refute config.halted
    end
  end

  describe "Hub reads across Core, Prime, and Plus" do
    setup do
      payloads = selector_payloads()
      {:ok, seen} = Agent.start_link(fn -> [] end)
      url = start_rpc_stub(fn body -> handle_eth_call(body, payloads, seen) end)

      on_exit(fn ->
        if Process.alive?(seen), do: Agent.stop(seen)
      end)

      %{rpc_opts: [rpc_url: url, timeout: 2_000, req_options: [connect_options: [protocols: [:http1]]]], seen: seen}
    end

    test "every selected read succeeds on all three Hubs", %{rpc_opts: rpc_opts} do
      spoke = @spoke

      Enum.each(@hubs, fn hub ->
        assert {:ok, 3} = Hub.get_spoke_count(hub, @asset_id, rpc_opts)
        assert {:ok, true} = Hub.is_spoke_listed(hub, @asset_id, spoke, rpc_opts)
        assert {:ok, checksummed} = Hub.get_spoke_address(hub, @asset_id, 0, rpc_opts)
        assert checksummed == Onchain.Address.checksum!(spoke)

        assert {:ok, %SpokeData{drawn_shares: 200, add_cap: 1_000_000, active: true, halted: false}} =
                 Hub.get_spoke(hub, @asset_id, spoke, rpc_opts)

        assert {:ok, %SpokeConfig{add_cap: 1_000_000, draw_cap: 500_000, active: true}} =
                 Hub.get_spoke_config(hub, @asset_id, spoke, rpc_opts)

        assert {:ok, 800} = Hub.get_spoke_added_assets(hub, @asset_id, spoke, rpc_opts)
        assert {:ok, 200} = Hub.get_spoke_drawn_shares(hub, @asset_id, spoke, rpc_opts)
        assert {:ok, {100, 7}} = Hub.get_spoke_owed(hub, @asset_id, spoke, rpc_opts)
        assert {:ok, 107} = Hub.get_spoke_total_owed(hub, @asset_id, spoke, rpc_opts)
        assert {:ok, 7} = Hub.get_spoke_deficit_ray(hub, @asset_id, spoke, rpc_opts)

        assert {:ok, 5} = Hub.get_asset_count(hub, rpc_opts)

        assert {:ok, %Asset{liquidity: 1_000, drawn_rate: 50_000, premium_offset_ray: -3}} =
                 Hub.get_asset(hub, @asset_id, rpc_opts)

        assert {:ok, 1_000} = Hub.get_asset_liquidity(hub, @asset_id, rpc_opts)
        assert {:ok, {100, 7}} = Hub.get_asset_owed(hub, @asset_id, rpc_opts)
        assert {:ok, 107} = Hub.get_asset_total_owed(hub, @asset_id, rpc_opts)
        assert {:ok, 7} = Hub.get_asset_deficit_ray(hub, @asset_id, rpc_opts)
        assert {:ok, 50_000} = Hub.get_asset_drawn_rate(hub, @asset_id, rpc_opts)
        assert {:ok, 1_000_000} = Hub.get_asset_drawn_index(hub, @asset_id, rpc_opts)
        assert {:ok, 0} = Hub.get_asset_id(hub, @usdc, rpc_opts)

        assert {:ok, {underlying, 6}} = Hub.get_asset_underlying_and_decimals(hub, @asset_id, rpc_opts)
        assert underlying == Onchain.Address.checksum!(@usdc)
      end)
    end

    test "routes each hub atom to its configured contract", %{rpc_opts: rpc_opts, seen: seen} do
      Enum.each(@hubs, fn hub ->
        assert {:ok, _} = Hub.get_asset_count(hub, rpc_opts)
      end)

      seen_tos =
        seen
        |> Agent.get(& &1)
        |> Enum.map(&String.downcase/1)
        |> Enum.uniq()
        |> Enum.sort()

      expected =
        @hubs
        |> Enum.map(fn hub ->
          {:ok, addr} = Hub.hub_address(hub)
          String.downcase(addr)
        end)
        |> Enum.sort()

      assert seen_tos == expected
    end
  end

  defp selector_payloads do
    {:ok, spoke_bin} = Onchain.Address.validate(@spoke)
    {:ok, usdc_bin} = Onchain.Address.validate(@usdc)

    %{
      selector("getSpokeCount(uint256)", [0]) => encode("(uint256)", [{3}]),
      selector("isSpokeListed(uint256,address)", [0, spoke_bin]) => encode("(bool)", [{true}]),
      selector("getSpokeAddress(uint256,uint256)", [0, 0]) => encode("(address)", [{spoke_bin}]),
      selector("getSpoke(uint256,address)", [0, spoke_bin]) =>
        encode("((uint256,uint256,int256,uint256,uint256,uint256,uint256,bool,bool,uint256))", [{@spoke_data_tuple}]),
      selector("getSpokeConfig(uint256,address)", [0, spoke_bin]) =>
        encode("((uint256,uint256,uint256,bool,bool))", [{@spoke_config_tuple}]),
      selector("getSpokeAddedAssets(uint256,address)", [0, spoke_bin]) => encode("(uint256)", [{800}]),
      selector("getSpokeDrawnShares(uint256,address)", [0, spoke_bin]) => encode("(uint256)", [{200}]),
      selector("getSpokeOwed(uint256,address)", [0, spoke_bin]) => encode("(uint256,uint256)", [{100, 7}]),
      selector("getSpokeTotalOwed(uint256,address)", [0, spoke_bin]) => encode("(uint256)", [{107}]),
      selector("getSpokeDeficitRay(uint256,address)", [0, spoke_bin]) => encode("(uint256)", [{7}]),
      selector("getAssetCount()", []) => encode("(uint256)", [{5}]),
      selector("getAsset(uint256)", [0]) =>
        encode(
          "((uint256,uint256,uint256,uint256,uint256,int256,uint256,uint256,uint256,uint256,uint256,uint256,address,address,address,address,uint256))",
          [{@asset_tuple}]
        ),
      selector("getAssetLiquidity(uint256)", [0]) => encode("(uint256)", [{1_000}]),
      selector("getAssetOwed(uint256)", [0]) => encode("(uint256,uint256)", [{100, 7}]),
      selector("getAssetTotalOwed(uint256)", [0]) => encode("(uint256)", [{107}]),
      selector("getAssetDeficitRay(uint256)", [0]) => encode("(uint256)", [{7}]),
      selector("getAssetDrawnRate(uint256)", [0]) => encode("(uint256)", [{50_000}]),
      selector("getAssetDrawnIndex(uint256)", [0]) => encode("(uint256)", [{1_000_000}]),
      selector("getAssetId(address)", [usdc_bin]) => encode("(uint256)", [{0}]),
      selector("getAssetUnderlyingAndDecimals(uint256)", [0]) => encode("(address,uint8)", [{usdc_bin, 6}])
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
