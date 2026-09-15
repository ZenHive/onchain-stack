defmodule Onchain.Aerodrome.Types.LpEpoch.TokenAmount do
  @moduledoc """
  Nested `{token, amount}` pair used by `Types.LpEpoch` bribes and fees.

  Field order is the deployed ABI (`priv/abis/rewards_sugar.json`
  `epochsLatest` `bribes` / `fees` components — the two arrays share this
  shape). This is not `Types.Reward`. `amount` is an integer. `token` is
  EIP-55 checksummed.
  """

  use Descripex, namespace: "/aerodrome/types/lp-epoch/token-amount"

  alias Onchain.Aerodrome.Types.Row

  # ABI order. Do not reorder for readability.
  @fields [:token, :amount]
  @address_fields [:token]

  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          token: String.t(),
          amount: non_neg_integer()
        }

  api(:from_raw, "Convert a positional {token, amount} bribe/fee tuple into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "Tuple matching rewards_sugar.json epochsLatest bribes/fees nested components"
      ]
    ],
    returns: %{type: :struct, description: "%Onchain.Aerodrome.Types.LpEpoch.TokenAmount{}"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw(raw) do
    %__MODULE__{} = Row.from_raw(__MODULE__, @fields, @address_fields, raw)
  end
end

defmodule Onchain.Aerodrome.Types.LpEpoch do
  @moduledoc """
  Typed struct for one `RewardsSugar.epochsLatest` row.

  Field order is the deployed ABI (`priv/abis/rewards_sugar.json`
  `epochsLatest` output components). `epochsByAddress` returns the same shape.
  Positional decode cannot see a Sugar redeploy that reorders those
  components; the ABI drift test is what fails when that happens.

  `votes` here is a uint256 total, not a list of `Types.Vote`. `bribes` and
  `fees` are lists of `TokenAmount` (`{token, amount}`). That nested type is
  not `Types.Reward` — Reward is a flat six-field record with a different
  field list.

  Amount fields stay integers. Addresses are EIP-55 checksummed.
  """

  use Descripex, namespace: "/aerodrome/types/lp-epoch"

  alias Onchain.Aerodrome.Types.LpEpoch.TokenAmount
  alias Onchain.Aerodrome.Types.Row

  # ABI order. Do not reorder for readability.
  @fields [:ts, :lp, :votes, :emissions, :bribes, :fees]
  @address_fields [:lp]

  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          ts: non_neg_integer(),
          lp: String.t(),
          votes: non_neg_integer(),
          emissions: non_neg_integer(),
          bribes: [TokenAmount.t()],
          fees: [TokenAmount.t()]
        }

  api(:from_raw, "Convert a positional RewardsSugar.epochsLatest row into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "Tuple matching rewards_sugar.json epochsLatest output components in ABI order"
      ]
    ],
    returns: %{type: :struct, description: "%Onchain.Aerodrome.Types.LpEpoch{} with checksummed lp"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw(raw) do
    %__MODULE__{} = epoch = Row.from_raw(__MODULE__, @fields, @address_fields, raw)

    %{
      epoch
      | bribes: Enum.map(epoch.bribes, &TokenAmount.from_raw/1),
        fees: Enum.map(epoch.fees, &TokenAmount.from_raw/1)
    }
  end
end
