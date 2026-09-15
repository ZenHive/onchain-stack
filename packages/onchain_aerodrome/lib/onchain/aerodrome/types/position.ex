defmodule Onchain.Aerodrome.Types.Position do
  @moduledoc """
  Typed struct for one `LpSugar.positions` row.

  Field order is the deployed ABI (`priv/abis/lp_sugar.json` `positions`
  output components). The same shape is what `positionsByFactory` and
  `positionsUnstakedConcentrated` return. Positional decode cannot see a Sugar
  redeploy that reorders those components; the ABI drift test is what fails
  when that happens.

  ## `locker`, `unlocks_at`, and `alm` on a vanilla position

  Sugar always emits these three fields. They are zero when the position is
  not locked and not ALM-managed:

  - `locker` is the lock contract. The checksummed zero address means the
    position is not in a locker.
  - `unlocks_at` is the Unix timestamp the lock expires. `0` means there is
    no lock, so there is no unlock time.
  - `alm` is the automated-liquidity-manager wrapper. The checksummed zero
    address means the position is not ALM-managed.

  They are not omitted and they are not rewritten to `nil`: a missing lock
  or ALM is the zero value the contract actually returns. Amount fields stay
  integers.
  """

  use Descripex, namespace: "/aerodrome/types/position"

  alias Onchain.Aerodrome.Types.Row

  # ABI order. Do not reorder for readability.
  @fields [
    :id,
    :lp,
    :liquidity,
    :staked,
    :amount0,
    :amount1,
    :staked0,
    :staked1,
    :unstaked_earned0,
    :unstaked_earned1,
    :emissions_earned,
    :tick_lower,
    :tick_upper,
    :sqrt_ratio_lower,
    :sqrt_ratio_upper,
    :locker,
    :unlocks_at,
    :alm
  ]

  @address_fields [:lp, :locker, :alm]

  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          lp: String.t(),
          liquidity: non_neg_integer(),
          staked: non_neg_integer(),
          amount0: non_neg_integer(),
          amount1: non_neg_integer(),
          staked0: non_neg_integer(),
          staked1: non_neg_integer(),
          unstaked_earned0: non_neg_integer(),
          unstaked_earned1: non_neg_integer(),
          emissions_earned: non_neg_integer(),
          tick_lower: integer(),
          tick_upper: integer(),
          sqrt_ratio_lower: non_neg_integer(),
          sqrt_ratio_upper: non_neg_integer(),
          locker: String.t(),
          unlocks_at: non_neg_integer(),
          alm: String.t()
        }

  api(:from_raw, "Convert a positional LpSugar.positions row into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "Tuple matching lp_sugar.json positions output components in ABI order"
      ]
    ],
    returns: %{type: :struct, description: "%Onchain.Aerodrome.Types.Position{} with checksummed addresses"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw(raw) do
    %__MODULE__{} = Row.from_raw(__MODULE__, @fields, @address_fields, raw)
  end
end
