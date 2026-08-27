defmodule Cartouche.Transaction.Call do
  @moduledoc """
  Represents Ethereum `eth_call` parameters, not a signable or broadcastable transaction.

  `destination` is required because generated contract calls always target a deployed contract.
  `data` is required because generated contract calls execute ABI-encoded calldata.
  `from` is optional because `eth_call` accepts a caller address but existing RPC callers pass it through options.
  `gas` is optional because `eth_call` can cap execution gas without creating a transaction gas limit.
  `value` is optional because `eth_call` can simulate payable execution without transferring funds.
  Fee, nonce, chain-id, access-list, and signature fields are excluded because calls are never signed or broadcast.
  """

  @type t :: %__MODULE__{
          destination: <<_::160>>,
          data: binary(),
          from: <<_::160>> | nil,
          gas: non_neg_integer() | nil,
          value: non_neg_integer() | nil
        }

  defstruct [:destination, :data, :from, :gas, :value]

  @doc """
  Builds an `eth_call` parameter struct.
  """
  @spec new(<<_::160>>, binary(), Keyword.t()) :: t()
  def new(destination, data, opts \\ []) when is_binary(data) do
    %__MODULE__{
      destination: destination,
      data: data,
      from: Keyword.get(opts, :from),
      gas: Keyword.get(opts, :gas),
      value: Keyword.get(opts, :value)
    }
  end
end
