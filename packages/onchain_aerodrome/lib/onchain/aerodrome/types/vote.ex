defmodule Onchain.Aerodrome.Types.Vote do
  @moduledoc """
  Nested `{lp, weight}` vote row shared by `Types.VeNFT` and `Types.Relay`.

  The deployed ABIs (`priv/abis/ve_sugar.json` `byId` `votes` components and
  `priv/abis/relay_sugar.json` `all(address)` `votes` components) are
  byte-identical. This module is the single definition; both parents alias it.
  Do not restate the field list on VeNFT or Relay.

  `weight` is an integer. `lp` is EIP-55 checksummed.
  """

  use Descripex, namespace: "/aerodrome/types/vote"

  alias Onchain.Aerodrome.Types.Row

  # ABI order. Do not reorder for readability.
  @fields [:lp, :weight]
  @address_fields [:lp]

  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          lp: String.t(),
          weight: non_neg_integer()
        }

  api(:from_raw, "Convert a positional {lp, weight} vote tuple into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "Tuple matching the votes nested components of ve_sugar.json byId and relay_sugar.json all(address)"
      ]
    ],
    returns: %{type: :struct, description: "%Onchain.Aerodrome.Types.Vote{} with checksummed lp"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw(raw) do
    %__MODULE__{} = Row.from_raw(__MODULE__, @fields, @address_fields, raw)
  end
end
