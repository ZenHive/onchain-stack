defmodule Onchain.Aerodrome.Types.Swap do
  @moduledoc """
  Typed struct for one `LpSugar.forSwaps` row.

  Field order is the deployed ABI (`priv/abis/lp_sugar.json` `forSwaps`
  output components). Positional decode cannot see a Sugar redeploy that
  reorders those components; the ABI drift test is what fails when that
  happens.

  `type` is the same discriminator as `Types.Lp`: `-1` is v2 stable, `0`
  is v2 volatile, any positive value is a Slipstream tick spacing. `pool_fee`
  is an integer. Addresses are EIP-55 checksummed.
  """

  use Descripex, namespace: "/aerodrome/types/swap"

  alias Onchain.Aerodrome.Types.Row

  # ABI order. Do not reorder for readability.
  @fields [:lp, :type, :token0, :token1, :factory, :pool_fee]
  @address_fields [:lp, :token0, :token1, :factory]

  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          lp: String.t(),
          type: integer(),
          token0: String.t(),
          token1: String.t(),
          factory: String.t(),
          pool_fee: non_neg_integer()
        }

  api(:from_raw, "Convert a positional LpSugar.forSwaps row into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "Tuple matching lp_sugar.json forSwaps output components in ABI order"
      ]
    ],
    returns: %{type: :struct, description: "%Onchain.Aerodrome.Types.Swap{} with checksummed addresses"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw(raw) do
    %__MODULE__{} = Row.from_raw(__MODULE__, @fields, @address_fields, raw)
  end
end
