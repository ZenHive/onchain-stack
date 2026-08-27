defmodule Onchain.Aave.Types.AggregatedReserveData do
  @moduledoc """
  Typed struct for Aave V3 `AggregatedReserveData` from `getReservesData`.

  Wraps the 40 values per reserve into named fields with appropriate conversions.

  ## Conversion Philosophy

  Fields with **fixed, universal scales** are converted to `Decimal.t()`:
  - Basis points (10^4) → `Math.to_ltv/1` (risk params, liquidation bonus)
  - Ray (10^27) → `Math.to_ray/1` (indices, interest rates)

  Fields with **context-dependent scales** stay as raw integers:
  - Token amounts (depend on per-token `decimals`)
  - Prices (depend on `BaseCurrencyInfo`)
  - Caps, ceilings, timestamps

  Addresses are checksummed via `Address.checksum!/1`.

  ## Field Groups

  **Identity** (4): underlying_asset, name, symbol, decimals
  **Risk params** (4, basis points): base_ltv_as_collateral, reserve_liquidation_threshold,
    reserve_liquidation_bonus, reserve_factor
  **Flags** (8, booleans): usage_as_collateral_enabled, borrowing_enabled, is_active,
    is_frozen, is_paused, is_siloed_borrowing, flash_loan_enabled, borrowable_in_isolation
  **Indices** (2, ray): liquidity_index, variable_borrow_index
  **Rates** (6, ray): liquidity_rate, variable_borrow_rate, variable_rate_slope1,
    variable_rate_slope2, base_variable_borrow_rate, optimal_usage_ratio
  **Timestamp** (1, raw): last_update_timestamp
  **Addresses** (4): a_token_address, variable_debt_token_address,
    interest_rate_strategy_address, price_oracle
  **Amounts** (4, raw integers): available_liquidity, total_scaled_variable_debt,
    accrued_to_treasury, isolation_mode_total_debt
  **Price** (1, raw): price_in_market_reference_currency
  **Caps** (4, raw): debt_ceiling, debt_ceiling_decimals, borrow_cap, supply_cap
  **Additional** (2, raw): virtual_underlying_balance, deficit
  """

  use Descripex, namespace: "/aave/types/aggregated-reserve-data"

  alias Onchain.Aave.Math
  alias Onchain.Address

  @enforce_keys [
    # Identity
    :underlying_asset,
    :name,
    :symbol,
    :decimals,
    # Risk params (basis points → Decimal)
    :base_ltv_as_collateral,
    :reserve_liquidation_threshold,
    :reserve_liquidation_bonus,
    :reserve_factor,
    # Flags
    :usage_as_collateral_enabled,
    :borrowing_enabled,
    :is_active,
    :is_frozen,
    # Indices (ray → Decimal)
    :liquidity_index,
    :variable_borrow_index,
    # Rates (ray → Decimal)
    :liquidity_rate,
    :variable_borrow_rate,
    # Timestamp
    :last_update_timestamp,
    # Addresses
    :a_token_address,
    :variable_debt_token_address,
    :interest_rate_strategy_address,
    # Amounts (raw)
    :available_liquidity,
    :total_scaled_variable_debt,
    # Price (raw)
    :price_in_market_reference_currency,
    # Address
    :price_oracle,
    # Rates (ray → Decimal)
    :variable_rate_slope1,
    :variable_rate_slope2,
    :base_variable_borrow_rate,
    :optimal_usage_ratio,
    # Flags
    :is_paused,
    :is_siloed_borrowing,
    # Amounts (raw)
    :accrued_to_treasury,
    :isolation_mode_total_debt,
    # Flag
    :flash_loan_enabled,
    # Caps (raw)
    :debt_ceiling,
    :debt_ceiling_decimals,
    :borrow_cap,
    :supply_cap,
    # Flag
    :borrowable_in_isolation,
    # Additional (raw)
    :virtual_underlying_balance,
    :deficit
  ]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          # Identity
          underlying_asset: String.t(),
          name: String.t(),
          symbol: String.t(),
          decimals: non_neg_integer(),
          # Risk params (Decimal ratios)
          base_ltv_as_collateral: Decimal.t(),
          reserve_liquidation_threshold: Decimal.t(),
          reserve_liquidation_bonus: Decimal.t(),
          reserve_factor: Decimal.t(),
          # Flags
          usage_as_collateral_enabled: boolean(),
          borrowing_enabled: boolean(),
          is_active: boolean(),
          is_frozen: boolean(),
          # Indices (Decimal rays)
          liquidity_index: Decimal.t(),
          variable_borrow_index: Decimal.t(),
          # Rates (Decimal rays)
          liquidity_rate: Decimal.t(),
          variable_borrow_rate: Decimal.t(),
          # Timestamp
          last_update_timestamp: non_neg_integer(),
          # Addresses
          a_token_address: String.t(),
          variable_debt_token_address: String.t(),
          interest_rate_strategy_address: String.t(),
          # Amounts (raw)
          available_liquidity: non_neg_integer(),
          total_scaled_variable_debt: non_neg_integer(),
          # Price (raw)
          price_in_market_reference_currency: non_neg_integer(),
          # Address
          price_oracle: String.t(),
          # Rates (Decimal rays)
          variable_rate_slope1: Decimal.t(),
          variable_rate_slope2: Decimal.t(),
          base_variable_borrow_rate: Decimal.t(),
          optimal_usage_ratio: Decimal.t(),
          # Flags
          is_paused: boolean(),
          is_siloed_borrowing: boolean(),
          # Amounts (raw)
          accrued_to_treasury: non_neg_integer(),
          isolation_mode_total_debt: non_neg_integer(),
          # Flag
          flash_loan_enabled: boolean(),
          # Caps (raw)
          debt_ceiling: non_neg_integer(),
          debt_ceiling_decimals: non_neg_integer(),
          borrow_cap: non_neg_integer(),
          supply_cap: non_neg_integer(),
          # Flag
          borrowable_in_isolation: boolean(),
          # Additional (raw)
          virtual_underlying_balance: non_neg_integer(),
          deficit: non_neg_integer()
        }

  api(:from_raw, "Convert raw AggregatedReserveData tuple from getReservesData into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "40-element tuple matching the Aave V3 AggregatedReserveData Solidity struct",
        source: "Onchain.Aave.UiPoolDataProvider.get_reserves_data/1"
      ]
    ],
    returns: %{type: :struct, description: "%AggregatedReserveData{} with converted fields"}
  )

  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  @spec from_raw(tuple()) :: t()
  def from_raw(
        {asset, name, symbol, decimals, base_ltv, liq_threshold, liq_bonus, reserve_factor, collateral_enabled,
         borrowing_enabled, is_active, is_frozen, liquidity_index, var_borrow_index, liquidity_rate, var_borrow_rate,
         last_update_ts, a_token, var_debt_token, interest_rate_strategy, available_liq, total_scaled_var_debt,
         price_in_market_ref, price_oracle, var_slope1, var_slope2, base_var_borrow_rate, optimal_ratio, is_paused,
         is_siloed, accrued_treasury, isolation_debt, flash_loan, debt_ceiling, debt_ceiling_decimals, borrow_cap,
         supply_cap, borrowable_isolation, virtual_balance, deficit}
      )
      when is_binary(asset) and byte_size(asset) == 20 and is_binary(name) and is_binary(symbol) do
    %__MODULE__{
      # Identity
      underlying_asset: Address.checksum!(asset),
      name: name,
      symbol: symbol,
      decimals: decimals,
      # Risk params (basis points → Decimal)
      base_ltv_as_collateral: Math.to_ltv(base_ltv),
      reserve_liquidation_threshold: Math.to_ltv(liq_threshold),
      reserve_liquidation_bonus: Math.to_ltv(liq_bonus),
      reserve_factor: Math.to_ltv(reserve_factor),
      # Flags
      usage_as_collateral_enabled: collateral_enabled,
      borrowing_enabled: borrowing_enabled,
      is_active: is_active,
      is_frozen: is_frozen,
      # Indices (ray → Decimal)
      liquidity_index: Math.to_ray(liquidity_index),
      variable_borrow_index: Math.to_ray(var_borrow_index),
      # Rates (ray → Decimal)
      liquidity_rate: Math.to_ray(liquidity_rate),
      variable_borrow_rate: Math.to_ray(var_borrow_rate),
      # Timestamp
      last_update_timestamp: last_update_ts,
      # Addresses
      a_token_address: Address.checksum!(a_token),
      variable_debt_token_address: Address.checksum!(var_debt_token),
      interest_rate_strategy_address: Address.checksum!(interest_rate_strategy),
      # Amounts (raw)
      available_liquidity: available_liq,
      total_scaled_variable_debt: total_scaled_var_debt,
      # Price (raw)
      price_in_market_reference_currency: price_in_market_ref,
      # Address
      price_oracle: Address.checksum!(price_oracle),
      # Rates (ray → Decimal)
      variable_rate_slope1: Math.to_ray(var_slope1),
      variable_rate_slope2: Math.to_ray(var_slope2),
      base_variable_borrow_rate: Math.to_ray(base_var_borrow_rate),
      optimal_usage_ratio: Math.to_ray(optimal_ratio),
      # Flags
      is_paused: is_paused,
      is_siloed_borrowing: is_siloed,
      # Amounts (raw)
      accrued_to_treasury: accrued_treasury,
      isolation_mode_total_debt: isolation_debt,
      # Flag
      flash_loan_enabled: flash_loan,
      # Caps (raw)
      debt_ceiling: debt_ceiling,
      debt_ceiling_decimals: debt_ceiling_decimals,
      borrow_cap: borrow_cap,
      supply_cap: supply_cap,
      # Flag
      borrowable_in_isolation: borrowable_isolation,
      # Additional (raw)
      virtual_underlying_balance: virtual_balance,
      deficit: deficit
    }
  end
end
