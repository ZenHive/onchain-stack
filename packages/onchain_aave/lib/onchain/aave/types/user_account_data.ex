defmodule Onchain.Aave.Types.UserAccountData do
  @moduledoc """
  Typed struct for Aave V3 `getUserAccountData` response.

  Wraps the 6 raw `uint256` values returned by the Pool contract into
  named fields with `Decimal.t()` values, converted via `Onchain.Aave.Math`.

  ## Fields

  | Field | Math | Aave Meaning |
  |-------|------|--------------|
  | `total_collateral_base` | `to_usd/1` (10^8) | Total collateral in base currency (USD) |
  | `total_debt_base` | `to_usd/1` (10^8) | Total debt in base currency (USD) |
  | `available_borrows_base` | `to_usd/1` (10^8) | Remaining borrowing power in base currency |
  | `current_liquidation_threshold` | `to_ltv/1` (10^4) | Weighted avg liquidation threshold (0..1) |
  | `ltv` | `to_ltv/1` (10^4) | Weighted avg loan-to-value ratio (0..1) |
  | `health_factor` | `to_health_factor/1` (10^18) | Position health (> 1 = safe) |
  """

  use Descripex, namespace: "/aave/types/user-account-data"

  alias Onchain.Aave.Math

  @enforce_keys [
    :total_collateral_base,
    :total_debt_base,
    :available_borrows_base,
    :current_liquidation_threshold,
    :ltv,
    :health_factor
  ]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          total_collateral_base: Decimal.t(),
          total_debt_base: Decimal.t(),
          available_borrows_base: Decimal.t(),
          current_liquidation_threshold: Decimal.t(),
          ltv: Decimal.t(),
          health_factor: Decimal.t()
        }

  api(:from_raw, "Convert raw uint256 list from getUserAccountData into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description:
          "6-element list of integers: [collateral, debt, available_borrows, liq_threshold, ltv, health_factor]",
        source: "Onchain.Aave.Pool.get_user_account_data/2"
      ]
    ],
    returns: %{type: :struct, description: "%UserAccountData{} with Decimal fields"}
  )

  @spec from_raw([integer()]) :: t()
  def from_raw([collateral, debt, available, liq_threshold, ltv, health_factor])
      when is_integer(collateral) and is_integer(debt) and is_integer(available) and is_integer(liq_threshold) and
             is_integer(ltv) and is_integer(health_factor) do
    %__MODULE__{
      total_collateral_base: Math.to_usd(collateral),
      total_debt_base: Math.to_usd(debt),
      available_borrows_base: Math.to_usd(available),
      current_liquidation_threshold: Math.to_ltv(liq_threshold),
      ltv: Math.to_ltv(ltv),
      health_factor: Math.to_health_factor(health_factor)
    }
  end
end
