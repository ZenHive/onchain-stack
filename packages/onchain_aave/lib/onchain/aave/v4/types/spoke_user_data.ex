defmodule Onchain.Aave.V4.Types.SpokeUserData do
  @moduledoc """
  Typed Aave V4 per-Spoke user account health data.

  Values remain in their contract units: risk premium is BPS, collateral
  factor and health factor are WAD, and total debt value is RAY-scaled.
  """

  use Descripex, namespace: "/aave/v4/types/spoke-user-data"

  @enforce_keys [
    :risk_premium,
    :avg_collateral_factor,
    :health_factor,
    :total_collateral_value,
    :total_debt_value_ray,
    :active_collateral_count,
    :borrow_count
  ]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          risk_premium: non_neg_integer(),
          avg_collateral_factor: non_neg_integer(),
          health_factor: non_neg_integer(),
          total_collateral_value: non_neg_integer(),
          total_debt_value_ray: non_neg_integer(),
          active_collateral_count: non_neg_integer(),
          borrow_count: non_neg_integer()
        }

  api(:from_raw, "Convert a decoded ISpoke.UserAccountData tuple into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "7-element tuple returned by getUserAccountData",
        source: "Onchain.Aave.V4.Spoke.get_user_account_data/3"
      ]
    ],
    returns: %{type: :struct, description: "%SpokeUserData{}"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw(
        {risk_premium, avg_collateral_factor, health_factor, total_collateral_value, total_debt_value_ray,
         active_collateral_count, borrow_count}
      ) do
    %__MODULE__{
      risk_premium: risk_premium,
      avg_collateral_factor: avg_collateral_factor,
      health_factor: health_factor,
      total_collateral_value: total_collateral_value,
      total_debt_value_ray: total_debt_value_ray,
      active_collateral_count: active_collateral_count,
      borrow_count: borrow_count
    }
  end
end

defmodule Onchain.Aave.V4.Types.SpokeUserPosition do
  @moduledoc """
  Typed Aave V4 `ISpoke.UserPosition` data for one user and reserve.
  """

  use Descripex, namespace: "/aave/v4/types/spoke-user-position"

  @enforce_keys [:drawn_shares, :premium_shares, :premium_offset_ray, :supplied_shares, :dynamic_config_key]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          drawn_shares: non_neg_integer(),
          premium_shares: non_neg_integer(),
          premium_offset_ray: integer(),
          supplied_shares: non_neg_integer(),
          dynamic_config_key: non_neg_integer()
        }

  api(:from_raw, "Convert a decoded ISpoke.UserPosition tuple into a typed struct.",
    params: [raw: [kind: :exchange_data, description: "5-element tuple returned by getUserPosition"]],
    returns: %{type: :struct, description: "%SpokeUserPosition{}"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw({drawn_shares, premium_shares, premium_offset_ray, supplied_shares, dynamic_config_key}) do
    %__MODULE__{
      drawn_shares: drawn_shares,
      premium_shares: premium_shares,
      premium_offset_ray: premium_offset_ray,
      supplied_shares: supplied_shares,
      dynamic_config_key: dynamic_config_key
    }
  end
end
