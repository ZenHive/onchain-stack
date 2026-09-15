defmodule Onchain.Aerodrome.Types.Token do
  @moduledoc """
  Typed struct for one Sugar `tokens` row.

  Shared by `LpSugar.tokens` and `TokenSugar.tokens`. The two ABI captures
  carry byte-identical `tokens` output components; the drift test asserts that
  rather than assuming it. Field order is that shared ABI shape.

  `account_balance` is an integer. Addresses are EIP-55 checksummed.
  """

  use Descripex, namespace: "/aerodrome/types/token"

  alias Onchain.Aerodrome.Types.Row

  # ABI order. Do not reorder for readability.
  @fields [:token_address, :symbol, :decimals, :account_balance, :listed, :emerging]
  @address_fields [:token_address]

  @enforce_keys @fields
  defstruct @fields

  @type t :: %__MODULE__{
          token_address: String.t(),
          symbol: String.t(),
          decimals: non_neg_integer(),
          account_balance: non_neg_integer(),
          listed: boolean(),
          emerging: boolean()
        }

  api(:from_raw, "Convert a positional Sugar tokens row into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "Tuple matching the tokens output components of lp_sugar.json and token_sugar.json"
      ]
    ],
    returns: %{type: :struct, description: "%Onchain.Aerodrome.Types.Token{} with checksummed address"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw(raw) do
    %__MODULE__{} = Row.from_raw(__MODULE__, @fields, @address_fields, raw)
  end
end
