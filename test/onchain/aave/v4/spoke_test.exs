defmodule Onchain.Aave.V4.SpokeTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.V4.Spoke
  alias Onchain.Aave.V4.Types.SpokeDynamicReserveConfig
  alias Onchain.Aave.V4.Types.SpokeLiquidationConfig
  alias Onchain.Aave.V4.Types.SpokeReserveConfig
  alias Onchain.Aave.V4.Types.SpokeReserveData
  alias Onchain.Aave.V4.Types.SpokeUserData
  alias Onchain.Aave.V4.Types.SpokeUserPosition

  @spoke "0x94e7A5dCbE816e498b89aB752661904E2F56c485"
  @user "0x1111111111111111111111111111111111111111"
  @hub "0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9"
  @position_manager "0x51305839CE822a7b4b12AA7D86eA7005052d575c"
  @reserve_id 4
  @asset_id 9
  @dynamic_config_key 7
  @health_factor 1_200_000_000_000_000_000
  @max_user_reserves_limit 65_535
  @reserve_flags 0x0D
  @selector_start 0
  @selector_length 10
  @automatic_port 0
  @receive_all_bytes 0
  @rpc_timeout_ms 2_000
  @stub_ready_timeout_ms 1_000
  @stub_accept_timeout_ms 5_000

  @underlying_bin <<1::160>>
  @hub_bin <<2::160>>
  @liquidation_logic_bin <<3::160>>
  @oracle_bin <<4::160>>
  @reserve_tuple {@underlying_bin, @hub_bin, @asset_id, 6, 1_200, @reserve_flags, @dynamic_config_key}
  @reserve_config_tuple {1_200, true, false, true, true}
  @dynamic_config_tuple {8_300, 10_555, 1_000}
  @liquidation_config_tuple {1_240_000_000_000_000_000, 900_000_000_000_000_000, 9_000}
  @user_position_tuple {40, 5, -3, 300, @dynamic_config_key}
  @user_data_tuple {125, 800_000_000_000_000_000, @health_factor, 10_000, 2_000_000_000_000_000_000_000_000_000, 2, 1}

  describe "typed data" do
    test "SpokeReserveData.from_raw/1 retains and decodes every reserve flag" do
      reserve = SpokeReserveData.from_raw(@reserve_tuple)

      assert reserve.underlying == Onchain.Address.checksum!(@underlying_bin)
      assert reserve.hub == Onchain.Address.checksum!(@hub_bin)
      assert reserve.flags == @reserve_flags
      assert reserve.paused
      refute reserve.frozen
      assert reserve.borrowable
      assert reserve.receive_shares_enabled
    end

    test "SpokeUserData.from_raw/1 keeps contract units and counts" do
      user_data = SpokeUserData.from_raw(@user_data_tuple)

      assert user_data.risk_premium == 125
      assert user_data.health_factor == @health_factor
      assert user_data.total_debt_value_ray == 2_000_000_000_000_000_000_000_000_000
      assert user_data.active_collateral_count == 2
      assert user_data.borrow_count == 1
    end
  end

  describe "Spoke reads" do
    setup do
      {:ok, seen} = Agent.start_link(fn -> [] end)
      payloads = selector_payloads()
      url = start_rpc_stub(fn body -> handle_eth_call(body, payloads, seen) end)

      on_exit(fn ->
        if Process.alive?(seen), do: Agent.stop(seen)
      end)

      %{rpc_opts: rpc_opts(url), seen: seen}
    end

    test "decodes the selected reserve, cap, liquidation, and user reads", %{rpc_opts: rpc_opts, seen: seen} do
      assert {:ok, %SpokeLiquidationConfig{target_health_factor: 1_240_000_000_000_000_000}} =
               Spoke.get_liquidation_config(@spoke, rpc_opts)

      assert {:ok, 14} = Spoke.get_reserve_count(@spoke, rpc_opts)
      assert {:ok, 1_000} = Spoke.get_reserve_supplied_assets(@spoke, @reserve_id, rpc_opts)
      assert {:ok, 900} = Spoke.get_reserve_supplied_shares(@spoke, @reserve_id, rpc_opts)
      assert {:ok, {40, 5}} = Spoke.get_reserve_debt(@spoke, @reserve_id, rpc_opts)
      assert {:ok, 45} = Spoke.get_reserve_total_debt(@spoke, @reserve_id, rpc_opts)
      assert {:ok, @reserve_id} = Spoke.get_reserve_id(@spoke, @hub, @asset_id, rpc_opts)

      assert {:ok, %SpokeReserveData{asset_id: @asset_id, borrowable: true, paused: true}} =
               Spoke.get_reserve(@spoke, @reserve_id, rpc_opts)

      assert {:ok, %SpokeReserveConfig{collateral_risk: 1_200, borrowable: true}} =
               Spoke.get_reserve_config(@spoke, @reserve_id, rpc_opts)

      assert {:ok, %SpokeDynamicReserveConfig{collateral_factor: 8_300, liquidation_fee: 1_000}} =
               Spoke.get_dynamic_reserve_config(@spoke, @reserve_id, @dynamic_config_key, rpc_opts)

      assert {:ok, {true, false}} = Spoke.get_user_reserve_status(@spoke, @reserve_id, @user, rpc_opts)
      assert {:ok, 300} = Spoke.get_user_supplied_assets(@spoke, @reserve_id, @user, rpc_opts)
      assert {:ok, 290} = Spoke.get_user_supplied_shares(@spoke, @reserve_id, @user, rpc_opts)
      assert {:ok, {40, 5}} = Spoke.get_user_debt(@spoke, @reserve_id, @user, rpc_opts)
      assert {:ok, 45} = Spoke.get_user_total_debt(@spoke, @reserve_id, @user, rpc_opts)

      assert {:ok, 5_000_000_000_000_000_000_000_000_000} =
               Spoke.get_user_premium_debt_ray(@spoke, @reserve_id, @user, rpc_opts)

      assert {:ok, %SpokeUserPosition{drawn_shares: 40, premium_offset_ray: -3, supplied_shares: 300}} =
               Spoke.get_user_position(@spoke, @reserve_id, @user, rpc_opts)

      assert {:ok, %SpokeUserData{risk_premium: 125, health_factor: @health_factor, borrow_count: 1}} =
               Spoke.get_user_account_data(@spoke, @user, rpc_opts)

      assert {:ok, 120} = Spoke.get_user_last_risk_premium(@spoke, @user, rpc_opts)
      assert {:ok, 10_250} = Spoke.get_liquidation_bonus(@spoke, @reserve_id, @user, @health_factor, rpc_opts)
      assert {:ok, true} = Spoke.position_manager_active?(@spoke, @position_manager, rpc_opts)
      assert {:ok, true} = Spoke.position_manager?(@spoke, @user, @position_manager, rpc_opts)

      assert {:ok, liquidation_logic} = Spoke.get_liquidation_logic(@spoke, rpc_opts)
      assert liquidation_logic == Onchain.Address.checksum!(@liquidation_logic_bin)

      assert {:ok, oracle} = Spoke.oracle(@spoke, rpc_opts)
      assert oracle == Onchain.Address.checksum!(@oracle_bin)

      assert {:ok, @max_user_reserves_limit} = Spoke.max_user_reserves_limit(@spoke, rpc_opts)

      assert seen
             |> Agent.get(& &1)
             |> Enum.all?(&Onchain.Address.equal?(&1, @spoke))
    end
  end

  describe "errors" do
    test "default arities reject an invalid Spoke address across the read surface" do
      reads = [
        fn -> Spoke.get_liquidation_config("bad") end,
        fn -> Spoke.get_reserve_count("bad") end,
        fn -> Spoke.get_reserve_supplied_assets("bad", @reserve_id) end,
        fn -> Spoke.get_reserve_supplied_shares("bad", @reserve_id) end,
        fn -> Spoke.get_reserve_debt("bad", @reserve_id) end,
        fn -> Spoke.get_reserve_total_debt("bad", @reserve_id) end,
        fn -> Spoke.get_reserve_id("bad", @hub, @asset_id) end,
        fn -> Spoke.get_reserve("bad", @reserve_id) end,
        fn -> Spoke.get_reserve_config("bad", @reserve_id) end,
        fn -> Spoke.get_dynamic_reserve_config("bad", @reserve_id, @dynamic_config_key) end,
        fn -> Spoke.get_user_reserve_status("bad", @reserve_id, @user) end,
        fn -> Spoke.get_user_supplied_assets("bad", @reserve_id, @user) end,
        fn -> Spoke.get_user_supplied_shares("bad", @reserve_id, @user) end,
        fn -> Spoke.get_user_debt("bad", @reserve_id, @user) end,
        fn -> Spoke.get_user_total_debt("bad", @reserve_id, @user) end,
        fn -> Spoke.get_user_premium_debt_ray("bad", @reserve_id, @user) end,
        fn -> Spoke.get_user_position("bad", @reserve_id, @user) end,
        fn -> Spoke.get_user_account_data("bad", @user) end,
        fn -> Spoke.get_user_last_risk_premium("bad", @user) end,
        fn -> Spoke.get_liquidation_bonus("bad", @reserve_id, @user, @health_factor) end,
        fn -> Spoke.position_manager_active?("bad", @position_manager) end,
        fn -> Spoke.position_manager?("bad", @user, @position_manager) end,
        fn -> Spoke.get_liquidation_logic("bad") end,
        fn -> Spoke.oracle("bad") end,
        fn -> Spoke.max_user_reserves_limit("bad") end
      ]

      Enum.each(reads, fn read ->
        assert {:error, {:invalid_address, "bad"}} = read.()
      end)
    end

    test "rejects invalid Spoke and parameter addresses before RPC" do
      assert {:error, {:invalid_address, "bad"}} = Spoke.get_reserve_count("bad")
      assert {:error, {:invalid_address, "bad"}} = Spoke.get_reserve_id(@spoke, "bad", @asset_id)
      assert {:error, {:invalid_address, "bad"}} = Spoke.get_user_account_data(@spoke, "bad")
      assert {:error, {:invalid_address, "bad"}} = Spoke.position_manager_active?(@spoke, "bad")
      assert {:error, {:invalid_address, "bad"}} = Spoke.position_manager?(@spoke, @user, "bad")
    end

    test "passes through JSON-RPC errors" do
      url =
        start_rpc_stub(fn _body ->
          {:error, %{"code" => 3, "message" => "execution reverted"}}
        end)

      assert {:error, {:rpc_error, %{code: 3, message: "execution reverted"}}} =
               Spoke.get_reserve_count(@spoke, rpc_opts(url))
    end

    test "passes through ABI decoding errors" do
      url = start_rpc_stub(fn _body -> "0x1234" end)

      assert {:error, {:decode_error, _reason}} =
               Spoke.get_reserve(@spoke, @reserve_id, rpc_opts(url))
    end
  end

  defp selector_payloads do
    {:ok, hub_bin} = Onchain.Address.validate(@hub)
    {:ok, user_bin} = Onchain.Address.validate(@user)
    {:ok, manager_bin} = Onchain.Address.validate(@position_manager)

    %{
      selector("getLiquidationConfig()", []) => encode("((uint128,uint64,uint16))", [{@liquidation_config_tuple}]),
      selector("getReserveCount()", []) => encode("(uint256)", [{14}]),
      selector("getReserveSuppliedAssets(uint256)", [@reserve_id]) => encode("(uint256)", [{1_000}]),
      selector("getReserveSuppliedShares(uint256)", [@reserve_id]) => encode("(uint256)", [{900}]),
      selector("getReserveDebt(uint256)", [@reserve_id]) => encode("(uint256,uint256)", [{40, 5}]),
      selector("getReserveTotalDebt(uint256)", [@reserve_id]) => encode("(uint256)", [{45}]),
      selector("getReserveId(address,uint256)", [hub_bin, @asset_id]) => encode("(uint256)", [{@reserve_id}]),
      selector("getReserve(uint256)", [@reserve_id]) =>
        encode("((address,address,uint16,uint8,uint24,uint8,uint32))", [{@reserve_tuple}]),
      selector("getReserveConfig(uint256)", [@reserve_id]) =>
        encode("((uint24,bool,bool,bool,bool))", [{@reserve_config_tuple}]),
      selector("getDynamicReserveConfig(uint256,uint32)", [@reserve_id, @dynamic_config_key]) =>
        encode("((uint16,uint32,uint16))", [{@dynamic_config_tuple}]),
      selector("getUserReserveStatus(uint256,address)", [@reserve_id, user_bin]) =>
        encode("(bool,bool)", [{true, false}]),
      selector("getUserSuppliedAssets(uint256,address)", [@reserve_id, user_bin]) => encode("(uint256)", [{300}]),
      selector("getUserSuppliedShares(uint256,address)", [@reserve_id, user_bin]) => encode("(uint256)", [{290}]),
      selector("getUserDebt(uint256,address)", [@reserve_id, user_bin]) => encode("(uint256,uint256)", [{40, 5}]),
      selector("getUserTotalDebt(uint256,address)", [@reserve_id, user_bin]) => encode("(uint256)", [{45}]),
      selector("getUserPremiumDebtRay(uint256,address)", [@reserve_id, user_bin]) =>
        encode("(uint256)", [{5_000_000_000_000_000_000_000_000_000}]),
      selector("getUserPosition(uint256,address)", [@reserve_id, user_bin]) =>
        encode("((uint120,uint120,int200,uint120,uint32))", [{@user_position_tuple}]),
      selector("getUserAccountData(address)", [user_bin]) =>
        encode("((uint256,uint256,uint256,uint256,uint256,uint256,uint256))", [{@user_data_tuple}]),
      selector("getUserLastRiskPremium(address)", [user_bin]) => encode("(uint256)", [{120}]),
      selector("getLiquidationBonus(uint256,address,uint256)", [@reserve_id, user_bin, @health_factor]) =>
        encode("(uint256)", [{10_250}]),
      selector("isPositionManagerActive(address)", [manager_bin]) => encode("(bool)", [{true}]),
      selector("isPositionManager(address,address)", [user_bin, manager_bin]) => encode("(bool)", [{true}]),
      selector("getLiquidationLogic()", []) => encode("(address)", [{@liquidation_logic_bin}]),
      selector("ORACLE()", []) => encode("(address)", [{@oracle_bin}]),
      selector("MAX_USER_RESERVES_LIMIT()", []) => encode("(uint16)", [{@max_user_reserves_limit}])
    }
  end

  defp selector(signature, params) do
    {:ok, hex} = Onchain.ABI.encode_call(signature, params)
    String.slice(hex, @selector_start, @selector_length)
  end

  defp encode(types, data) do
    "0x" <> Base.encode16(ABI.encode(types, data), case: :lower)
  end

  defp handle_eth_call(%{"method" => "eth_call", "params" => [%{"data" => data, "to" => to} | _]}, payloads, seen) do
    Agent.update(seen, &[to | &1])
    selector = String.slice(String.downcase(data), @selector_start, @selector_length)

    Map.get_lazy(payloads, selector, fn ->
      flunk("stub has no payload for selector #{selector} (data=#{data})")
    end)
  end

  defp rpc_opts(url) do
    [rpc_url: url, timeout: @rpc_timeout_ms, req_options: [connect_options: [protocols: [:http1]]]]
  end

  defp start_rpc_stub(handler) do
    {:ok, listen} =
      :gen_tcp.listen(@automatic_port, [:binary, packet: :http_bin, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

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
      @stub_ready_timeout_ms -> flunk("JSON-RPC stub failed to start")
    end

    on_exit(fn ->
      Process.exit(pid, :kill)
      :gen_tcp.close(listen)
    end)

    "http://127.0.0.1:#{port}"
  end

  defp stub_loop(listen, handler) do
    case :gen_tcp.accept(listen, @stub_accept_timeout_ms) do
      {:ok, socket} ->
        serve_one(socket, handler)
        stub_loop(listen, handler)

      {:error, :timeout} ->
        stub_loop(listen, handler)

      {:error, :closed} ->
        :ok
    end
  end

  defp serve_one(socket, handler) do
    {:ok, {:http_request, :POST, _, _}} = :gen_tcp.recv(socket, @receive_all_bytes)
    length = recv_content_length(socket, @receive_all_bytes)
    :ok = :inet.setopts(socket, packet: :raw)
    {:ok, body} = :gen_tcp.recv(socket, length)
    decoded = Jason.decode!(body)
    response = rpc_response(decoded, handler.(decoded))
    payload = Jason.encode!(response)

    :ok =
      :gen_tcp.send(socket, [
        "HTTP/1.1 200 OK\r\n",
        "content-type: application/json\r\n",
        "content-length: #{byte_size(payload)}\r\n",
        "connection: close\r\n\r\n",
        payload
      ])

    :gen_tcp.close(socket)
  end

  defp rpc_response(decoded, {:error, error}) do
    %{"jsonrpc" => "2.0", "id" => decoded["id"], "error" => error}
  end

  defp rpc_response(decoded, result) do
    %{"jsonrpc" => "2.0", "id" => decoded["id"], "result" => result}
  end

  defp recv_content_length(socket, acc) do
    case :gen_tcp.recv(socket, @receive_all_bytes) do
      {:ok, :http_eoh} ->
        acc

      {:ok, {:http_header, _, name, _, value}} ->
        if header_name(name) == "content-length" do
          recv_content_length(socket, String.to_integer(header_value(value)))
        else
          recv_content_length(socket, acc)
        end
    end
  end

  defp header_name(name) when is_atom(name), do: name |> Atom.to_string() |> String.downcase()
  defp header_name(name) when is_binary(name), do: String.downcase(name)
  defp header_name(name) when is_list(name), do: name |> List.to_string() |> String.downcase()

  defp header_value(value) when is_binary(value), do: value
  defp header_value(value) when is_list(value), do: List.to_string(value)
end
