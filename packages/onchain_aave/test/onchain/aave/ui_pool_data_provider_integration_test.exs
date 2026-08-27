defmodule Onchain.Aave.UiPoolDataProvider.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.Types.AggregatedReserveData
  alias Onchain.Aave.Types.BaseCurrencyInfo
  alias Onchain.Aave.Types.UserReserveData
  alias Onchain.Aave.UiPoolDataProvider

  @moduletag :integration

  # Active Aave V3 borrower — same address used in pool integration tests
  @known_borrower "0xF380B8F1e63e2BEd7CA329CA1FdDbC39B52cC0d3"

  # --- get_reserves_list ---

  describe "get_reserves_list/1" do
    test "returns non-empty list of checksummed addresses" do
      {:ok, addresses} = UiPoolDataProvider.get_reserves_list(Onchain.RPCCase.rpc_opts!())

      assert is_list(addresses)
      assert addresses != []

      # All addresses should be checksummed 0x strings
      Enum.each(addresses, fn addr ->
        assert String.starts_with?(addr, "0x")
        assert String.length(addr) == 42
      end)
    end

    test "includes known tokens (WETH, USDC)" do
      {:ok, addresses} = UiPoolDataProvider.get_reserves_list(Onchain.RPCCase.rpc_opts!())

      weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
      usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

      assert weth in addresses, "Expected WETH in reserves list"
      assert usdc in addresses, "Expected USDC in reserves list"
    end
  end

  describe "get_reserves_list!/1" do
    test "returns list directly" do
      addresses = UiPoolDataProvider.get_reserves_list!(Onchain.RPCCase.rpc_opts!())

      assert is_list(addresses)
      assert addresses != []
    end
  end

  # --- get_reserves_data ---

  describe "get_reserves_data/1" do
    test "returns {reserves, base_currency_info} tuple" do
      {:ok, {reserves, base}} = UiPoolDataProvider.get_reserves_data(Onchain.RPCCase.rpc_opts!())

      assert is_list(reserves)
      assert reserves != []
      assert %BaseCurrencyInfo{} = base
    end

    test "reserves are AggregatedReserveData structs with correct types" do
      {:ok, {reserves, _base}} = UiPoolDataProvider.get_reserves_data(Onchain.RPCCase.rpc_opts!())

      first = hd(reserves)
      assert %AggregatedReserveData{} = first

      # Identity
      assert is_binary(first.underlying_asset)
      assert String.starts_with?(first.underlying_asset, "0x")
      assert is_binary(first.name)
      assert is_binary(first.symbol)
      assert is_integer(first.decimals)

      # Risk params are Decimal
      assert %Decimal{} = first.base_ltv_as_collateral
      assert %Decimal{} = first.reserve_liquidation_threshold
      assert %Decimal{} = first.reserve_liquidation_bonus
      assert %Decimal{} = first.reserve_factor

      # Flags
      assert is_boolean(first.usage_as_collateral_enabled)
      assert is_boolean(first.borrowing_enabled)
      assert is_boolean(first.is_active)
      assert is_boolean(first.is_frozen)

      # Rates are Decimal
      assert %Decimal{} = first.liquidity_rate
      assert %Decimal{} = first.variable_borrow_rate

      # Addresses are checksummed strings
      assert String.starts_with?(first.a_token_address, "0x")
      assert String.starts_with?(first.variable_debt_token_address, "0x")
      assert String.starts_with?(first.price_oracle, "0x")

      # Amounts are raw integers
      assert is_integer(first.available_liquidity)
      assert is_integer(first.total_scaled_variable_debt)
      assert is_integer(first.price_in_market_reference_currency)
    end

    test "first collateral-enabled reserve has sane risk parameters" do
      # Originally pinned to WETH, but Aave governance set WETH's LTV to 0 on
      # 2026-04-19 following an RPC incident. Filtering by capability keeps the
      # test stable across future governance actions.
      {:ok, {reserves, _base}} = UiPoolDataProvider.get_reserves_data(Onchain.RPCCase.rpc_opts!())

      reserve =
        Enum.find(reserves, fn r ->
          r.usage_as_collateral_enabled and
            r.is_active and
            not r.is_frozen and
            Decimal.gt?(r.base_ltv_as_collateral, Decimal.new("0"))
        end)

      assert reserve != nil, "no collateral-enabled reserve found"

      # LTV between 0 and 1
      assert Decimal.gt?(reserve.base_ltv_as_collateral, Decimal.new("0"))
      assert Decimal.lt?(reserve.base_ltv_as_collateral, Decimal.new("1"))

      # Liquidation threshold > LTV
      assert Decimal.gte?(reserve.reserve_liquidation_threshold, reserve.base_ltv_as_collateral)

      # Liquidation bonus > 1 (e.g. 1.05 = 5% bonus)
      assert Decimal.gt?(reserve.reserve_liquidation_bonus, Decimal.new("1"))

      # Active and not frozen
      assert reserve.is_active == true
      assert reserve.is_frozen == false
    end

    test "base currency info has sane values" do
      {:ok, {_reserves, base}} = UiPoolDataProvider.get_reserves_data(Onchain.RPCCase.rpc_opts!())

      assert %BaseCurrencyInfo{} = base
      # Aave uses 10^8 as base currency unit
      assert base.market_reference_currency_unit == 100_000_000
      # USD price should be 1.0 (market ref = USD)
      assert Decimal.eq?(base.market_reference_currency_price_in_usd, Decimal.new("1"))
      # ETH price should be > $100 and < $100,000
      assert Decimal.gt?(base.network_base_token_price_in_usd, Decimal.new("100"))
      assert Decimal.lt?(base.network_base_token_price_in_usd, Decimal.new("100000"))
      assert base.network_base_token_price_decimals == 8
    end
  end

  describe "get_reserves_data!/1" do
    test "returns tuple directly" do
      {reserves, base} = UiPoolDataProvider.get_reserves_data!(Onchain.RPCCase.rpc_opts!())

      assert is_list(reserves)
      assert %BaseCurrencyInfo{} = base
    end
  end

  # --- get_user_reserves_data ---

  describe "get_user_reserves_data/2 with known borrower" do
    test "returns {user_reserves, e_mode_id} tuple" do
      {:ok, {user_reserves, e_mode_id}} =
        UiPoolDataProvider.get_user_reserves_data(@known_borrower, Onchain.RPCCase.rpc_opts!())

      assert is_list(user_reserves)
      assert user_reserves != []
      assert is_integer(e_mode_id)
    end

    test "user reserves are UserReserveData structs" do
      {:ok, {user_reserves, _e_mode}} =
        UiPoolDataProvider.get_user_reserves_data(@known_borrower, Onchain.RPCCase.rpc_opts!())

      first = hd(user_reserves)
      assert %UserReserveData{} = first
      assert is_binary(first.underlying_asset)
      assert String.starts_with?(first.underlying_asset, "0x")
      assert is_integer(first.scaled_a_token_balance)
      assert is_boolean(first.usage_as_collateral_enabled_on_user)
      assert is_integer(first.scaled_variable_debt)
    end

    test "known borrower has at least one non-zero position" do
      {:ok, {user_reserves, _e_mode}} =
        UiPoolDataProvider.get_user_reserves_data(@known_borrower, Onchain.RPCCase.rpc_opts!())

      active =
        Enum.filter(user_reserves, fn r ->
          r.scaled_a_token_balance > 0 or r.scaled_variable_debt > 0
        end)

      assert active != [], "Expected at least one active position for known borrower"
    end
  end

  describe "get_user_reserves_data/2 with binary address" do
    test "accepts 20-byte binary address" do
      {:ok, user_bin} = Onchain.Address.validate(@known_borrower)

      {:ok, {user_reserves, _e_mode}} =
        UiPoolDataProvider.get_user_reserves_data(user_bin, Onchain.RPCCase.rpc_opts!())

      assert is_list(user_reserves)
      assert user_reserves != []
    end
  end

  describe "get_user_reserves_data!/2" do
    test "returns tuple directly" do
      {user_reserves, e_mode_id} =
        UiPoolDataProvider.get_user_reserves_data!(@known_borrower, Onchain.RPCCase.rpc_opts!())

      assert is_list(user_reserves)
      assert is_integer(e_mode_id)
    end
  end
end
