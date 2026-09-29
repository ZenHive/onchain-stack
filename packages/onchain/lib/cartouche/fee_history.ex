defmodule Cartouche.FeeHistory do
  @moduledoc ~S"""
  Represents fee history data as defined in EIP-1559.

  See `Cartouche.RPC.fee_history` for getting traces from
  an Ethereum JSON-RPC host.

  See also:
    * Alchemy docs: https://docs.alchemy.com/reference/eth-feehistory
    * Infura docs: https://docs.infura.io/api/networks/ethereum/json-rpc-methods/eth_feehistory
  """
  use Descripex, namespace: "/ethereum/fee_history"

  @type t() :: %__MODULE__{
          oldest_block: integer(),
          base_fee_per_gas: [integer()],
          gas_used_ratio: [integer()],
          reward: [[float()]] | nil
        }

  defstruct [
    :oldest_block,
    :base_fee_per_gas,
    :gas_used_ratio,
    :reward
  ]

  api(:deserialize, "Decode an `eth_feeHistory` JSON-RPC result into a `Cartouche.FeeHistory` struct.",
    params: [
      params: [
        kind: :exchange_data,
        source: "Cartouche.RPC.fee_history/1",
        description:
          "Map returned by `eth_feeHistory`, including `oldestBlock`, `baseFeePerGas`, `gasUsedRatio`, and optional `reward` fields."
      ]
    ],
    returns: %{
      type: :fee_history,
      description:
        "`%Cartouche.FeeHistory{}` with decoded integer fee arrays, gas-used ratios, and optional priority fee rewards."
    }
  )

  @doc ~S"""
  Deserializes fee history data from `eth_feeHistory` RPC response.

  ## Examples

      iex> %{
      ...>   "oldestBlock" => "0xfd6a75",
      ...>   "reward" => [
      ...>     [
      ...>       "0x3b9aca00",
      ...>       "0x3b9aca00",
      ...>       "0x59682f00"
      ...>     ],
      ...>     [
      ...>       "0x3b9aca00",
      ...>       "0x3b9aca00",
      ...>       "0x77359400"
      ...>     ],
      ...>     [
      ...>       "0x3b9aca00",
      ...>       "0x3b9aca00",
      ...>       "0x3b9aca00"
      ...>     ],
      ...>     [
      ...>       "0x2e7ddb00",
      ...>       "0x3b9aca00",
      ...>       "0x77359400"
      ...>     ],
      ...>     [
      ...>       "0x3b9aca00",
      ...>       "0x3b9aca00",
      ...>       "0x59682f00"
      ...>     ]
      ...>   ],
      ...>   "baseFeePerGas" => [
      ...>     "0x4c9d974c3",
      ...>     "0x4c38a847a",
      ...>     "0x49206d475",
      ...>     "0x47ac58b63",
      ...>     "0x471e805d8",
      ...>     "0x46f5f64a6"
      ...>   ],
      ...>   "gasUsedRatio" => [
      ...>     0.4794155666666667,
      ...>     0.3375966,
      ...>     0.42049746666666665,
      ...>     0.4690773,
      ...>     0.49109343333333333
      ...>   ]
      ...> }
      ...> |> Cartouche.FeeHistory.deserialize()
      %Cartouche.FeeHistory{
        base_fee_per_gas: [20566340803, 20460504186, 19629790325, 19239635811, 19090900440, 19048391846],
        gas_used_ratio: [0.4794155666666667, 0.3375966, 0.42049746666666665, 0.4690773, 0.49109343333333333],
        oldest_block: 16607861,
        reward: [[1000000000, 1000000000, 1500000000], [1000000000, 1000000000, 2000000000], [1000000000, 1000000000, 1000000000], [780000000, 1000000000, 2000000000], [1000000000, 1000000000, 1500000000]]
      }

      iex> %{"baseFeePerGas" => ["0xa", "0xa"], "gasUsedRatio" => [0.1878495], "oldestBlock" => "0xa01de6"}
      ...> |> Cartouche.FeeHistory.deserialize()
      %Cartouche.FeeHistory{base_fee_per_gas: [10, 10], gas_used_ratio: [0.1878495], oldest_block: 10493414, reward: nil}
  """
  @spec deserialize(map()) :: t() | no_return()
  def deserialize(
        %{"oldestBlock" => oldest_block, "baseFeePerGas" => base_fee_per_gas, "gasUsedRatio" => gas_used_ratio} = params
      ) do
    %__MODULE__{
      oldest_block: Cartouche.Hex.decode_hex_number!(oldest_block),
      base_fee_per_gas: Enum.map(base_fee_per_gas, &Cartouche.Hex.decode_hex_number!/1),
      gas_used_ratio: gas_used_ratio,
      reward:
        case params["reward"] do
          nil ->
            nil

          reward ->
            Enum.map(reward, fn r -> Enum.map(r, &Cartouche.Hex.decode_hex_number!/1) end)
        end
    }
  end
end
