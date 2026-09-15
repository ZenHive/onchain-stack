defmodule Onchain.Aerodrome.Types.Relay.AccountVeNFT do
  @moduledoc """
  Nested `{id, amount, earned}` row unique to `Types.Relay.account_venfts`.

  Field order is the deployed ABI (`priv/abis/relay_sugar.json` `all(address)`
  `account_venfts` components). This is not a `Types.VeNFT` and not a
  `Types.Vote`. Amount fields stay integers.
  """

  use Descripex, namespace: "/aerodrome/types/relay/account-venft"

  alias Onchain.Aerodrome.Types.Row

  # ABI order. Do not reorder for readability.
  @fields [:id, :amount, :earned]
  @address_fields []

  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          amount: non_neg_integer(),
          earned: non_neg_integer()
        }

  api(:from_raw, "Convert a positional {id, amount, earned} account_venfts tuple into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "Tuple matching relay_sugar.json all(address) account_venfts nested components"
      ]
    ],
    returns: %{type: :struct, description: "%Onchain.Aerodrome.Types.Relay.AccountVeNFT{}"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw(raw) do
    %__MODULE__{} = Row.from_raw(__MODULE__, @fields, @address_fields, raw)
  end
end

defmodule Onchain.Aerodrome.Types.Relay do
  @moduledoc """
  Typed struct for one `RelaySugar.all(address)` row.

  The field list is read from the deployed ABI
  (`priv/abis/relay_sugar.json` `all(address)` output components). Do not
  re-derive it from memory, from a hand count, or from RelaySugar's function
  count — those numbers are a different quantity and have already been wrong
  more than once. Positional decode cannot see a Sugar redeploy that reorders
  those components; the ABI drift test is what fails when that happens.

  Two nested arrays:

  - `votes` is `[Types.Vote]` — the same `{lp, weight}` shape `Types.VeNFT`
    uses, defined once and aliased here
  - `account_venfts` is `[AccountVeNFT]` — `{id, amount, earned}`, unique to
    this struct

  `managers` is a list of EIP-55 checksummed addresses. Amount fields stay
  integers.
  """

  use Descripex, namespace: "/aerodrome/types/relay"

  alias Onchain.Address
  alias Onchain.Aerodrome.Types.Relay.AccountVeNFT
  alias Onchain.Aerodrome.Types.Row
  alias Onchain.Aerodrome.Types.Vote

  # ABI order from relay_sugar.json all(address). Do not reorder for readability.
  @fields [
    :venft_id,
    :decimals,
    :amount,
    :voting_amount,
    :used_voting_amount,
    :voted_at,
    :votes,
    :token,
    :compounded,
    :withdrawable,
    :run_at,
    :managers,
    :relay,
    :compounder,
    :inactive,
    :name,
    :account_venfts
  ]

  @address_fields [:token, :relay]

  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          venft_id: non_neg_integer(),
          decimals: non_neg_integer(),
          amount: non_neg_integer(),
          voting_amount: non_neg_integer(),
          used_voting_amount: non_neg_integer(),
          voted_at: non_neg_integer(),
          votes: [Vote.t()],
          token: String.t(),
          compounded: non_neg_integer(),
          withdrawable: non_neg_integer(),
          run_at: non_neg_integer(),
          managers: [String.t()],
          relay: String.t(),
          compounder: boolean(),
          inactive: boolean(),
          name: String.t(),
          account_venfts: [AccountVeNFT.t()]
        }

  api(:from_raw, "Convert a positional RelaySugar.all(address) row into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "Tuple matching relay_sugar.json all(address) output components in ABI order"
      ]
    ],
    returns: %{type: :struct, description: "%Onchain.Aerodrome.Types.Relay{} with nested votes and account_venfts"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw(raw) do
    relay = Row.from_raw(__MODULE__, @fields, @address_fields, raw)

    %{
      relay
      | votes: Enum.map(relay.votes, &Vote.from_raw/1),
        managers: Enum.map(relay.managers, &Address.checksum!/1),
        account_venfts: Enum.map(relay.account_venfts, &AccountVeNFT.from_raw/1)
    }
  end
end
