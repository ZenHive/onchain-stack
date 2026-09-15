defmodule Onchain.Aerodrome.Types.VeNFT do
  @moduledoc """
  Typed struct for one `VeSugar.byId` row.

  Field order is the deployed ABI (`priv/abis/ve_sugar.json` `byId` output
  components). `VeSugar.all` and `VeSugar.byAccount` return the same shape as
  a list. Positional decode cannot see a Sugar redeploy that reorders those
  components; the ABI drift test is what fails when that happens.

  `votes` is a list of `Types.Vote` (`{lp, weight}`), the same nested type
  `Types.Relay` uses. Amount fields stay integers. Addresses are EIP-55
  checksummed; the zero address is stored as the checksummed zero address,
  not rewritten to `nil`.
  """

  use Descripex, namespace: "/aerodrome/types/ve-nft"

  alias Onchain.Aerodrome.Types.Row
  alias Onchain.Aerodrome.Types.Vote

  # ABI order. Do not reorder for readability.
  @fields [
    :id,
    :account,
    :decimals,
    :amount,
    :voting_amount,
    :governance_amount,
    :rebase_amount,
    :expires_at,
    :voted_at,
    :votes,
    :token,
    :permanent,
    :delegate_id,
    :managed_id
  ]

  @address_fields [:account, :token]

  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          account: String.t(),
          decimals: non_neg_integer(),
          amount: non_neg_integer(),
          voting_amount: non_neg_integer(),
          governance_amount: non_neg_integer(),
          rebase_amount: non_neg_integer(),
          expires_at: non_neg_integer(),
          voted_at: non_neg_integer(),
          votes: [Vote.t()],
          token: String.t(),
          permanent: boolean(),
          delegate_id: non_neg_integer(),
          managed_id: non_neg_integer()
        }

  api(:from_raw, "Convert a positional VeSugar.byId row into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "Tuple matching ve_sugar.json byId output components in ABI order"
      ]
    ],
    returns: %{type: :struct, description: "%Onchain.Aerodrome.Types.VeNFT{} with checksummed addresses"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw(raw) do
    %__MODULE__{} = venft = Row.from_raw(__MODULE__, @fields, @address_fields, raw)
    %{venft | votes: Enum.map(venft.votes, &Vote.from_raw/1)}
  end
end
