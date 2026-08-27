defmodule Onchain.Aave.Types.BaseCurrencyInfo do
  @moduledoc """
  Typed struct for Aave V3 `BaseCurrencyInfo` from `getReservesData`.

  Wraps the 4 values returned alongside reserve data into named fields.
  `market_reference_currency_price_in_usd` is converted with `Onchain.Aave.Math.to_usd/1`
  (Aave fixed 10^8 scale).
  `network_base_token_price_in_usd` is scaled using the returned
  `network_base_token_price_decimals`.

  ## Fields

  | Field | Raw Type | Elixir Type | Conversion |
  |-------|----------|-------------|------------|
  | `market_reference_currency_unit` | uint256 | integer | raw |
  | `market_reference_currency_price_in_usd` | int256 | Decimal.t() | `to_usd/1` (10^8) |
  | `network_base_token_price_in_usd` | int256 | Decimal.t() | `div_pow10/2` with `network_base_token_price_decimals` |
  | `network_base_token_price_decimals` | uint8 | integer | raw |
  """

  use Descripex, namespace: "/aave/types/base-currency-info"

  alias Onchain.Aave.Math

  @enforce_keys [
    :market_reference_currency_unit,
    :market_reference_currency_price_in_usd,
    :network_base_token_price_in_usd,
    :network_base_token_price_decimals
  ]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          market_reference_currency_unit: non_neg_integer(),
          market_reference_currency_price_in_usd: Decimal.t(),
          network_base_token_price_in_usd: Decimal.t(),
          network_base_token_price_decimals: non_neg_integer()
        }

  api(:from_raw, "Convert raw BaseCurrencyInfo tuple from getReservesData into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "4-element tuple: {unit, market_ref_price, network_token_price, price_decimals}",
        source: "Onchain.Aave.UiPoolDataProvider.get_reserves_data/1"
      ]
    ],
    returns: %{type: :struct, description: "%BaseCurrencyInfo{} with converted fields"}
  )

  @spec from_raw({integer(), integer(), integer(), non_neg_integer()}) :: t()
  def from_raw({unit, market_ref_price, network_token_price, price_decimals})
      when is_integer(unit) and is_integer(market_ref_price) and is_integer(network_token_price) and
             is_integer(price_decimals) do
    %__MODULE__{
      market_reference_currency_unit: unit,
      market_reference_currency_price_in_usd: Math.to_usd(market_ref_price),
      network_base_token_price_in_usd: Onchain.Decimal.div_pow10(network_token_price, price_decimals),
      network_base_token_price_decimals: price_decimals
    }
  end
end
