defmodule Onchain.Aerodrome.Types.Lp do
  @moduledoc """
  Typed struct for one `LpSugar.all` row.

  Field order is the deployed ABI (`priv/abis/lp_sugar.json` `all` output
  components). Positional decode cannot see a Sugar redeploy that reorders
  those components; the ABI drift test is what fails when that happens.

  ## `type` is the pool-type discriminator

  `type` is the load-bearing field that splits quoting and analytics:

  - `-1` — v2 stable pool
  - `0` — v2 volatile pool
  - any positive value — Slipstream concentrated-liquidity tick spacing

  Money fields (`liquidity`, `reserve0`/`reserve1`, `staked0`/`staked1`,
  `emissions`, `token0_fees`/`token1_fees`, `locked`, and
  the rest of the uint amounts) stay integers. `emissions` is a **per-second**
  rate. Addresses are EIP-55 checksummed; the zero address is stored as the
  checksummed zero address, not rewritten to `nil`.

  `emissions_cap` is an integer relative share in basis points, not a token
  amount. `emissions` already reflects the notified rate; do not apply the
  cap again to that rate or its weekly amount.
  """

  use Descripex, namespace: "/aerodrome/types/lp"

  alias Onchain.Aerodrome.Types.Row

  # ABI order. Do not reorder for readability.
  @fields [
    :lp,
    :symbol,
    :decimals,
    :liquidity,
    :type,
    :tick,
    :sqrt_ratio,
    :token0,
    :reserve0,
    :staked0,
    :token1,
    :reserve1,
    :staked1,
    :gauge,
    :gauge_liquidity,
    :gauge_alive,
    :fee,
    :bribe,
    :factory,
    :emissions,
    :emissions_token,
    :emissions_cap,
    :pool_fee,
    :unstaked_fee,
    :token0_fees,
    :token1_fees,
    :locked,
    :emerging,
    :created_at,
    :nfpm,
    :alm,
    :root
  ]

  @address_fields [
    :lp,
    :token0,
    :token1,
    :gauge,
    :fee,
    :bribe,
    :factory,
    :emissions_token,
    :nfpm,
    :alm,
    :root
  ]

  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          lp: String.t(),
          symbol: String.t(),
          decimals: non_neg_integer(),
          liquidity: non_neg_integer(),
          type: integer(),
          tick: integer(),
          sqrt_ratio: non_neg_integer(),
          token0: String.t(),
          reserve0: non_neg_integer(),
          staked0: non_neg_integer(),
          token1: String.t(),
          reserve1: non_neg_integer(),
          staked1: non_neg_integer(),
          gauge: String.t(),
          gauge_liquidity: non_neg_integer(),
          gauge_alive: boolean(),
          fee: String.t(),
          bribe: String.t(),
          factory: String.t(),
          emissions: non_neg_integer(),
          emissions_token: String.t(),
          emissions_cap: non_neg_integer(),
          pool_fee: non_neg_integer(),
          unstaked_fee: non_neg_integer(),
          token0_fees: non_neg_integer(),
          token1_fees: non_neg_integer(),
          locked: non_neg_integer(),
          emerging: non_neg_integer(),
          created_at: non_neg_integer(),
          nfpm: String.t(),
          alm: String.t(),
          root: String.t()
        }

  api(:from_raw, "Convert a positional LpSugar.all row into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "Tuple matching lp_sugar.json all output components in ABI order"
      ]
    ],
    returns: %{type: :struct, description: "%Onchain.Aerodrome.Types.Lp{} with checksummed addresses"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw(raw) do
    %__MODULE__{} = Row.from_raw(__MODULE__, @fields, @address_fields, raw)
  end
end
