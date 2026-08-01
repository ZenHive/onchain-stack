defmodule Onchain.Aave.Types.AggregatedReserveDataTest do
  use ExUnit.Case, async: true

  alias Onchain.Aave.Types.AggregatedReserveData

  # WETH address as 20-byte binary
  @weth_bin <<192, 42, 170, 57, 178, 35, 254, 141, 10, 14, 92, 79, 39, 234, 217, 8, 60, 117, 108, 194>>
  @zero_addr <<0::160>>

  # Dynamic dispatch defeats the type checker for negative tests
  @doc false
  defp dynamic_from_raw(module, arg), do: module.from_raw(arg)

  @doc false
  # Build a 40-element tuple matching the ABI decode output for WETH-like data
  defp weth_raw do
    {
      @weth_bin,
      "Wrapped Ether",
      "WETH",
      18,
      # baseLTV=80.5%, liqThreshold=83%, liqBonus=105%, reserveFactor=15%
      8050,
      8300,
      10_500,
      1500,
      # collateral, borrowing, active, frozen
      true,
      true,
      true,
      false,
      # liquidityIndex (ray), variableBorrowIndex (ray)
      1_060_570_804_360_763_146_346_689_403,
      1_092_564_828_369_574_046_058_402_101,
      # liquidityRate (ray), variableBorrowRate (ray)
      19_388_999_231_221_783_539_154_459,
      24_383_045_487_462_157_012_468_460,
      # lastUpdateTimestamp
      1_772_522_639,
      # aTokenAddress, variableDebtTokenAddress, interestRateStrategyAddress
      @zero_addr,
      @zero_addr,
      @zero_addr,
      # availableLiquidity, totalScaledVariableDebt
      189_291_560_987_918_620_783_725,
      2_513_390_321_394_865_713_968_946,
      # priceInMarketReferenceCurrency
      200_229_832_133,
      # priceOracle
      @zero_addr,
      # variableRateSlope1/2, baseVariableBorrowRate, optimalUsageRatio (ray)
      27_000_000_000_000_000_000_000_000,
      800_000_000_000_000_000_000_000_000,
      0,
      900_000_000_000_000_000_000_000_000,
      # isPaused, isSiloedBorrowing
      false,
      false,
      # accruedToTreasury, isolationModeTotalDebt
      51_439_658_624_324_834_204,
      0,
      # flashLoanEnabled
      true,
      # debtCeiling, debtCeilingDecimals, borrowCap, supplyCap
      0,
      0,
      0,
      0,
      # borrowableInIsolation
      false,
      # virtualUnderlyingBalance, deficit
      189_291_554_494_014_123_254_134,
      8_105_466_388_536_457_758
    }
  end

  describe "struct" do
    test "enforces all 40 keys" do
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(AggregatedReserveData, %{})
      end
    end
  end

  describe "from_raw/1" do
    test "converts WETH-like data correctly" do
      result = AggregatedReserveData.from_raw(weth_raw())

      assert %AggregatedReserveData{} = result

      # Identity
      assert result.underlying_asset == "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
      assert result.name == "Wrapped Ether"
      assert result.symbol == "WETH"
      assert result.decimals == 18

      # Risk params (basis points → Decimal)
      assert Decimal.eq?(result.base_ltv_as_collateral, Decimal.new("0.805"))
      assert Decimal.eq?(result.reserve_liquidation_threshold, Decimal.new("0.83"))
      assert Decimal.eq?(result.reserve_liquidation_bonus, Decimal.new("1.05"))
      assert Decimal.eq?(result.reserve_factor, Decimal.new("0.15"))

      # Flags
      assert result.usage_as_collateral_enabled == true
      assert result.borrowing_enabled == true
      assert result.is_active == true
      assert result.is_frozen == false

      # Indices are Decimal (ray-converted)
      assert %Decimal{} = result.liquidity_index
      assert %Decimal{} = result.variable_borrow_index

      # Rates are Decimal (ray-converted)
      assert %Decimal{} = result.liquidity_rate
      assert %Decimal{} = result.variable_borrow_rate

      # Timestamp
      assert result.last_update_timestamp == 1_772_522_639

      # Amounts stay as raw integers
      assert result.available_liquidity == 189_291_560_987_918_620_783_725
      assert result.total_scaled_variable_debt == 2_513_390_321_394_865_713_968_946
      assert result.price_in_market_reference_currency == 200_229_832_133

      # Rate slopes (ray → Decimal)
      assert Decimal.eq?(result.variable_rate_slope1, Decimal.new("0.027"))
      assert Decimal.eq?(result.variable_rate_slope2, Decimal.new("0.8"))
      assert Decimal.eq?(result.base_variable_borrow_rate, Decimal.new("0"))
      assert Decimal.eq?(result.optimal_usage_ratio, Decimal.new("0.9"))

      # More flags
      assert result.is_paused == false
      assert result.is_siloed_borrowing == false
      assert result.flash_loan_enabled == true
      assert result.borrowable_in_isolation == false

      # Caps stay as raw
      assert result.debt_ceiling == 0
      assert result.borrow_cap == 0
      assert result.supply_cap == 0

      # Additional fields stay as raw
      assert result.virtual_underlying_balance == 189_291_554_494_014_123_254_134
      assert result.deficit == 8_105_466_388_536_457_758
    end

    test "raises FunctionClauseError for asset that is not 20 raw bytes" do
      # A 0x-prefixed hex string is a binary, but 42 bytes — the guard wants the decoded 20
      raw = put_elem(weth_raw(), 0, "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")

      assert_raise FunctionClauseError, fn ->
        AggregatedReserveData.from_raw(raw)
      end
    end

    test "raises FunctionClauseError for non-string name" do
      raw = put_elem(weth_raw(), 1, 42)

      assert_raise FunctionClauseError, fn ->
        dynamic_from_raw(AggregatedReserveData, raw)
      end
    end

    test "raises FunctionClauseError for wrong tuple size" do
      # 39 elements (one short)
      short = Tuple.delete_at(weth_raw(), 39)

      assert_raise FunctionClauseError, fn ->
        dynamic_from_raw(AggregatedReserveData, short)
      end
    end
  end
end
