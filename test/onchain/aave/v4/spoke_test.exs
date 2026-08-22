defmodule Onchain.Aave.V4.SpokeTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.V4.Spoke
  alias Onchain.Aave.V4.Types.SpokeDynamicReserveConfig
  alias Onchain.Aave.V4.Types.SpokeLiquidationConfig
  alias Onchain.Aave.V4.Types.SpokeReserveConfig
  alias Onchain.Aave.V4.Types.SpokeReserveData
  alias Onchain.Aave.V4.Types.SpokeUserData
  alias Onchain.Aave.V4.Types.SpokeUserPosition
  alias Onchain.RPCStub

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

    test "remaining type structs convert from_raw including a frozen-only flag mask" do
      frozen = SpokeReserveData.from_raw({@underlying_bin, @hub_bin, 1, 18, 0, 0x02, 0})
      assert frozen.frozen
      refute frozen.paused
      refute frozen.borrowable
      refute frozen.receive_shares_enabled

      assert %SpokeReserveConfig{collateral_risk: 1_200, paused: true, frozen: false, borrowable: true} =
               SpokeReserveConfig.from_raw(@reserve_config_tuple)

      assert %SpokeDynamicReserveConfig{
               collateral_factor: 8_300,
               max_liquidation_bonus: 10_555,
               liquidation_fee: 1_000
             } = SpokeDynamicReserveConfig.from_raw(@dynamic_config_tuple)

      assert %SpokeLiquidationConfig{
               target_health_factor: 1_240_000_000_000_000_000,
               health_factor_for_max_bonus: 900_000_000_000_000_000,
               liquidation_bonus_factor: 9_000
             } = SpokeLiquidationConfig.from_raw(@liquidation_config_tuple)

      assert %SpokeUserPosition{drawn_shares: 40, premium_offset_ray: -3, supplied_shares: 300} =
               SpokeUserPosition.from_raw(@user_position_tuple)
    end
  end

  describe "Spoke reads" do
    setup do
      seen = start_supervised!({Agent, fn -> [] end})
      payloads = selector_payloads()
      url = RPCStub.start(RPCStub.payload_handler(payloads, seen))

      %{rpc_opts: RPCStub.rpc_opts(url), seen: seen}
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
        RPCStub.start(fn _body ->
          {:error, %{"code" => 3, "message" => "execution reverted"}}
        end)

      assert {:error, {:rpc_error, %{code: 3, message: "execution reverted"}}} =
               Spoke.get_reserve_count(@spoke, RPCStub.rpc_opts(url))
    end

    test "passes through ABI decoding errors" do
      url = RPCStub.start(fn _body -> "0x1234" end)

      assert {:error, {:decode_error, _reason}} =
               Spoke.get_reserve(@spoke, @reserve_id, RPCStub.rpc_opts(url))
    end
  end

  describe "captured Main Spoke ABI payloads" do
    @weth "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    @empty_user "0x0000000000000000000000000000000000000001"
    @max_uint256 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF

    # Captured 2026-08-21 from Ethereum archive `eth_call` against Main Spoke
    # 0x94e7A5dCbE816e498b89aB752661904E2F56c485 — independent of the local encoder.
    @mainnet_get_reserve_0 "0x000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2000000000000000000000000cca852bc40e560adc3b1cc58ca5b55638ce826c9000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000000"
    @mainnet_get_liquidation_config "0x00000000000000000000000000000000000000000000000011355d6e217c00000000000000000000000000000000000000000000000000000c7d713b49da00000000000000000000000000000000000000000000000000000000000000002328"
    @mainnet_get_user_account_data "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
    @mainnet_get_user_position "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
    @mainnet_get_dynamic_reserve_config "0x000000000000000000000000000000000000000000000000000000000000206c000000000000000000000000000000000000000000000000000000000000293b00000000000000000000000000000000000000000000000000000000000003e8"

    setup do
      seen = start_supervised!({Agent, fn -> [] end})
      {:ok, user_bin} = Onchain.Address.validate(@empty_user)

      payloads = %{
        RPCStub.selector("getReserve(uint256)", [0]) => @mainnet_get_reserve_0,
        RPCStub.selector("getLiquidationConfig()", []) => @mainnet_get_liquidation_config,
        RPCStub.selector("getUserAccountData(address)", [user_bin]) => @mainnet_get_user_account_data,
        RPCStub.selector("getUserPosition(uint256,address)", [0, user_bin]) => @mainnet_get_user_position,
        RPCStub.selector("getDynamicReserveConfig(uint256,uint32)", [0, 0]) => @mainnet_get_dynamic_reserve_config
      }

      url = RPCStub.start(RPCStub.payload_handler(payloads, seen))

      %{rpc_opts: RPCStub.rpc_opts(url)}
    end

    test "decodes captured Main Spoke reserve, user, and config tuples", %{rpc_opts: rpc_opts} do
      assert {:ok,
              %SpokeReserveData{
                underlying: @weth,
                hub: @hub,
                asset_id: 0,
                decimals: 18,
                collateral_risk: 0,
                flags: 12,
                paused: false,
                frozen: false,
                borrowable: true,
                receive_shares_enabled: true,
                dynamic_config_key: 0
              }} = Spoke.get_reserve(@spoke, 0, rpc_opts)

      assert {:ok,
              %SpokeLiquidationConfig{
                target_health_factor: 1_240_000_000_000_000_000,
                health_factor_for_max_bonus: 900_000_000_000_000_000,
                liquidation_bonus_factor: 9_000
              }} = Spoke.get_liquidation_config(@spoke, rpc_opts)

      assert {:ok,
              %SpokeUserData{
                risk_premium: 0,
                avg_collateral_factor: 0,
                health_factor: @max_uint256,
                total_collateral_value: 0,
                total_debt_value_ray: 0,
                active_collateral_count: 0,
                borrow_count: 0
              }} = Spoke.get_user_account_data(@spoke, @empty_user, rpc_opts)

      assert {:ok,
              %SpokeUserPosition{
                drawn_shares: 0,
                premium_shares: 0,
                premium_offset_ray: 0,
                supplied_shares: 0,
                dynamic_config_key: 0
              }} = Spoke.get_user_position(@spoke, 0, @empty_user, rpc_opts)

      assert {:ok,
              %SpokeDynamicReserveConfig{
                collateral_factor: 8_300,
                max_liquidation_bonus: 10_555,
                liquidation_fee: 1_000
              }} = Spoke.get_dynamic_reserve_config(@spoke, 0, 0, rpc_opts)
    end
  end

  defp selector_payloads do
    {:ok, hub_bin} = Onchain.Address.validate(@hub)
    {:ok, user_bin} = Onchain.Address.validate(@user)
    {:ok, manager_bin} = Onchain.Address.validate(@position_manager)

    %{
      RPCStub.selector("getLiquidationConfig()", []) =>
        RPCStub.encode("((uint128,uint64,uint16))", [{@liquidation_config_tuple}]),
      RPCStub.selector("getReserveCount()", []) => RPCStub.encode("(uint256)", [{14}]),
      RPCStub.selector("getReserveSuppliedAssets(uint256)", [@reserve_id]) => RPCStub.encode("(uint256)", [{1_000}]),
      RPCStub.selector("getReserveSuppliedShares(uint256)", [@reserve_id]) => RPCStub.encode("(uint256)", [{900}]),
      RPCStub.selector("getReserveDebt(uint256)", [@reserve_id]) => RPCStub.encode("(uint256,uint256)", [{40, 5}]),
      RPCStub.selector("getReserveTotalDebt(uint256)", [@reserve_id]) => RPCStub.encode("(uint256)", [{45}]),
      RPCStub.selector("getReserveId(address,uint256)", [hub_bin, @asset_id]) =>
        RPCStub.encode("(uint256)", [{@reserve_id}]),
      RPCStub.selector("getReserve(uint256)", [@reserve_id]) =>
        RPCStub.encode("((address,address,uint16,uint8,uint24,uint8,uint32))", [{@reserve_tuple}]),
      RPCStub.selector("getReserveConfig(uint256)", [@reserve_id]) =>
        RPCStub.encode("((uint24,bool,bool,bool,bool))", [{@reserve_config_tuple}]),
      RPCStub.selector("getDynamicReserveConfig(uint256,uint32)", [@reserve_id, @dynamic_config_key]) =>
        RPCStub.encode("((uint16,uint32,uint16))", [{@dynamic_config_tuple}]),
      RPCStub.selector("getUserReserveStatus(uint256,address)", [@reserve_id, user_bin]) =>
        RPCStub.encode("(bool,bool)", [{true, false}]),
      RPCStub.selector("getUserSuppliedAssets(uint256,address)", [@reserve_id, user_bin]) =>
        RPCStub.encode("(uint256)", [{300}]),
      RPCStub.selector("getUserSuppliedShares(uint256,address)", [@reserve_id, user_bin]) =>
        RPCStub.encode("(uint256)", [{290}]),
      RPCStub.selector("getUserDebt(uint256,address)", [@reserve_id, user_bin]) =>
        RPCStub.encode("(uint256,uint256)", [{40, 5}]),
      RPCStub.selector("getUserTotalDebt(uint256,address)", [@reserve_id, user_bin]) =>
        RPCStub.encode("(uint256)", [{45}]),
      RPCStub.selector("getUserPremiumDebtRay(uint256,address)", [@reserve_id, user_bin]) =>
        RPCStub.encode("(uint256)", [{5_000_000_000_000_000_000_000_000_000}]),
      RPCStub.selector("getUserPosition(uint256,address)", [@reserve_id, user_bin]) =>
        RPCStub.encode("((uint120,uint120,int200,uint120,uint32))", [{@user_position_tuple}]),
      RPCStub.selector("getUserAccountData(address)", [user_bin]) =>
        RPCStub.encode("((uint256,uint256,uint256,uint256,uint256,uint256,uint256))", [{@user_data_tuple}]),
      RPCStub.selector("getUserLastRiskPremium(address)", [user_bin]) => RPCStub.encode("(uint256)", [{120}]),
      RPCStub.selector("getLiquidationBonus(uint256,address,uint256)", [@reserve_id, user_bin, @health_factor]) =>
        RPCStub.encode("(uint256)", [{10_250}]),
      RPCStub.selector("isPositionManagerActive(address)", [manager_bin]) => RPCStub.encode("(bool)", [{true}]),
      RPCStub.selector("isPositionManager(address,address)", [user_bin, manager_bin]) =>
        RPCStub.encode("(bool)", [{true}]),
      RPCStub.selector("getLiquidationLogic()", []) => RPCStub.encode("(address)", [{@liquidation_logic_bin}]),
      RPCStub.selector("ORACLE()", []) => RPCStub.encode("(address)", [{@oracle_bin}]),
      RPCStub.selector("MAX_USER_RESERVES_LIMIT()", []) => RPCStub.encode("(uint16)", [{@max_user_reserves_limit}])
    }
  end
end
