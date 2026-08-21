defmodule Onchain.Aave.V4.Types.SpokeReserveData do
  @moduledoc """
  Typed Aave V4 `ISpoke.Reserve` data.

  Amounts and risk parameters remain raw integers. The packed reserve flags are
  retained and also exposed as named booleans.
  """

  use Descripex, namespace: "/aave/v4/types/spoke-reserve-data"

  alias Onchain.Address

  @paused_mask 0x01
  @frozen_mask 0x02
  @borrowable_mask 0x04
  @receive_shares_enabled_mask 0x08

  @enforce_keys [
    :underlying,
    :hub,
    :asset_id,
    :decimals,
    :collateral_risk,
    :flags,
    :paused,
    :frozen,
    :borrowable,
    :receive_shares_enabled,
    :dynamic_config_key
  ]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          underlying: String.t(),
          hub: String.t(),
          asset_id: non_neg_integer(),
          decimals: non_neg_integer(),
          collateral_risk: non_neg_integer(),
          flags: non_neg_integer(),
          paused: boolean(),
          frozen: boolean(),
          borrowable: boolean(),
          receive_shares_enabled: boolean(),
          dynamic_config_key: non_neg_integer()
        }

  api(:from_raw, "Convert a decoded ISpoke.Reserve tuple into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "7-element tuple returned by getReserve",
        source: "Onchain.Aave.V4.Spoke.get_reserve/3"
      ]
    ],
    returns: %{type: :struct, description: "%SpokeReserveData{} with checksummed addresses and decoded flags"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw({underlying, hub, asset_id, decimals, collateral_risk, flags, dynamic_config_key}) do
    %__MODULE__{
      underlying: Address.checksum!(underlying),
      hub: Address.checksum!(hub),
      asset_id: asset_id,
      decimals: decimals,
      collateral_risk: collateral_risk,
      flags: flags,
      paused: flag_set?(flags, @paused_mask),
      frozen: flag_set?(flags, @frozen_mask),
      borrowable: flag_set?(flags, @borrowable_mask),
      receive_shares_enabled: flag_set?(flags, @receive_shares_enabled_mask),
      dynamic_config_key: dynamic_config_key
    }
  end

  @spec flag_set?(non_neg_integer(), non_neg_integer()) :: boolean()
  defp flag_set?(flags, mask), do: Bitwise.band(flags, mask) != 0
end

defmodule Onchain.Aave.V4.Types.SpokeReserveConfig do
  @moduledoc """
  Typed Aave V4 `ISpoke.ReserveConfig` data.
  """

  use Descripex, namespace: "/aave/v4/types/spoke-reserve-config"

  @enforce_keys [:collateral_risk, :paused, :frozen, :borrowable, :receive_shares_enabled]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          collateral_risk: non_neg_integer(),
          paused: boolean(),
          frozen: boolean(),
          borrowable: boolean(),
          receive_shares_enabled: boolean()
        }

  api(:from_raw, "Convert a decoded ISpoke.ReserveConfig tuple into a typed struct.",
    params: [raw: [kind: :exchange_data, description: "5-element tuple returned by getReserveConfig"]],
    returns: %{type: :struct, description: "%SpokeReserveConfig{}"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw({collateral_risk, paused, frozen, borrowable, receive_shares_enabled}) do
    %__MODULE__{
      collateral_risk: collateral_risk,
      paused: paused,
      frozen: frozen,
      borrowable: borrowable,
      receive_shares_enabled: receive_shares_enabled
    }
  end
end

defmodule Onchain.Aave.V4.Types.SpokeDynamicReserveConfig do
  @moduledoc """
  Typed Aave V4 `ISpoke.DynamicReserveConfig` data.
  """

  use Descripex, namespace: "/aave/v4/types/spoke-dynamic-reserve-config"

  @enforce_keys [:collateral_factor, :max_liquidation_bonus, :liquidation_fee]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          collateral_factor: non_neg_integer(),
          max_liquidation_bonus: non_neg_integer(),
          liquidation_fee: non_neg_integer()
        }

  api(:from_raw, "Convert a decoded ISpoke.DynamicReserveConfig tuple into a typed struct.",
    params: [raw: [kind: :exchange_data, description: "3-element tuple returned by getDynamicReserveConfig"]],
    returns: %{type: :struct, description: "%SpokeDynamicReserveConfig{}"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw({collateral_factor, max_liquidation_bonus, liquidation_fee}) do
    %__MODULE__{
      collateral_factor: collateral_factor,
      max_liquidation_bonus: max_liquidation_bonus,
      liquidation_fee: liquidation_fee
    }
  end
end

defmodule Onchain.Aave.V4.Types.SpokeLiquidationConfig do
  @moduledoc """
  Typed Aave V4 `ISpoke.LiquidationConfig` data.
  """

  use Descripex, namespace: "/aave/v4/types/spoke-liquidation-config"

  @enforce_keys [:target_health_factor, :health_factor_for_max_bonus, :liquidation_bonus_factor]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          target_health_factor: non_neg_integer(),
          health_factor_for_max_bonus: non_neg_integer(),
          liquidation_bonus_factor: non_neg_integer()
        }

  api(:from_raw, "Convert a decoded ISpoke.LiquidationConfig tuple into a typed struct.",
    params: [raw: [kind: :exchange_data, description: "3-element tuple returned by getLiquidationConfig"]],
    returns: %{type: :struct, description: "%SpokeLiquidationConfig{}"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw({target_health_factor, health_factor_for_max_bonus, liquidation_bonus_factor}) do
    %__MODULE__{
      target_health_factor: target_health_factor,
      health_factor_for_max_bonus: health_factor_for_max_bonus,
      liquidation_bonus_factor: liquidation_bonus_factor
    }
  end
end
