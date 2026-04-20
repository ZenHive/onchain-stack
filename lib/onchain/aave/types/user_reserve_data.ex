defmodule Onchain.Aave.Types.UserReserveData do
  @moduledoc """
  Typed struct for Aave V3 per-user reserve data from `getUserReservesData`.

  Contains scaled token balances (raw integers) for a single reserve.
  Scaled values must be divided by the reserve's `liquidityIndex` or
  `variableBorrowIndex` (from `AggregatedReserveData`) to get actual amounts.

  ## Fields

  | Field | Raw Type | Elixir Type | Conversion |
  |-------|----------|-------------|------------|
  | `underlying_asset` | address | String.t() | `Address.checksum!/1` |
  | `scaled_a_token_balance` | uint256 | non_neg_integer() | raw |
  | `usage_as_collateral_enabled_on_user` | bool | boolean() | raw |
  | `scaled_variable_debt` | uint256 | non_neg_integer() | raw |
  """

  use Descripex, namespace: "/aave/types/user-reserve-data"

  alias Onchain.Address

  @enforce_keys [
    :underlying_asset,
    :scaled_a_token_balance,
    :usage_as_collateral_enabled_on_user,
    :scaled_variable_debt
  ]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          underlying_asset: String.t(),
          scaled_a_token_balance: non_neg_integer(),
          usage_as_collateral_enabled_on_user: boolean(),
          scaled_variable_debt: non_neg_integer()
        }

  api(:from_raw, "Convert raw UserReserveData tuple from getUserReservesData into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "4-element tuple: {address, scaled_balance, collateral_enabled, scaled_debt}",
        source: "Onchain.Aave.UiPoolDataProvider.get_user_reserves_data/2"
      ]
    ],
    returns: %{type: :struct, description: "%UserReserveData{} with checksummed address"}
  )

  @spec from_raw({binary(), non_neg_integer(), boolean(), non_neg_integer()}) :: t()
  def from_raw({asset, balance, collateral, debt})
      when is_binary(asset) and byte_size(asset) == 20 and is_integer(balance) and is_boolean(collateral) and
             is_integer(debt) do
    %__MODULE__{
      underlying_asset: Address.checksum!(asset),
      scaled_a_token_balance: balance,
      usage_as_collateral_enabled_on_user: collateral,
      scaled_variable_debt: debt
    }
  end
end
