defmodule Onchain.Aerodrome.Types.Reward do
  @moduledoc """
  Typed struct for one `RewardsSugar.rewards` row.

  Field order is the deployed ABI (`priv/abis/rewards_sugar.json` `rewards`
  output components). `rewardsByAddress` returns the same shape. This is a
  flat six-field record (`venft_id`, `lp`, `amount`, `token`, `fee`,
  `bribe`) and is not structurally related to `Types.LpEpoch.TokenAmount`.
  Do not merge the field lists.

  Positional decode cannot see a Sugar redeploy that reorders those
  components; the ABI drift test is what fails when that happens.

  `amount` is an integer. Addresses are EIP-55 checksummed.
  """

  use Descripex, namespace: "/aerodrome/types/reward"

  alias Onchain.Aerodrome.Types.Row

  # ABI order. Do not reorder for readability.
  @fields [:venft_id, :lp, :amount, :token, :fee, :bribe]
  @address_fields [:lp, :token, :fee, :bribe]

  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          venft_id: non_neg_integer(),
          lp: String.t(),
          amount: non_neg_integer(),
          token: String.t(),
          fee: String.t(),
          bribe: String.t()
        }

  api(:from_raw, "Convert a positional RewardsSugar.rewards row into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "Tuple matching rewards_sugar.json rewards output components in ABI order"
      ]
    ],
    returns: %{type: :struct, description: "%Onchain.Aerodrome.Types.Reward{} with checksummed addresses"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw(raw) do
    %__MODULE__{} = Row.from_raw(__MODULE__, @fields, @address_fields, raw)
  end
end
