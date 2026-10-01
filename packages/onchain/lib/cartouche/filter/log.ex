defmodule Cartouche.Filter.Log do
  @moduledoc """
  A decoded Ethereum log entry.

  Produced by `Cartouche.Filter` for `kind: :log` filters and returned by
  `Cartouche.RPC.eth_get_logs/2`, `Cartouche.RPC.get_filter_logs/2`, and
  `Cartouche.Receipt` logs, and subscription notifications. `:removed` is nil
  when omitted by the node. Pending logs may omit or null their block and
  transaction location fields; these decode to nil.
  Addresses, hashes, and topics are decoded
  to raw binaries; `:block_number`, `:log_index`, and `:transaction_index` to
  integers. `:extra_data` is the opaque term a `Cartouche.Filter` was started
  with, stamped onto every log it dispatches, and is `nil` elsewhere.
  """
  use Descripex, namespace: "/ethereum/log"
  use Cartouche.Hex

  defstruct [
    :address,
    :block_hash,
    :block_number,
    :data,
    :log_index,
    :removed,
    :topics,
    :transaction_hash,
    :transaction_index,
    :extra_data
  ]

  @type t :: %__MODULE__{
          address: binary(),
          block_hash: binary() | nil,
          block_number: non_neg_integer() | nil,
          data: binary(),
          log_index: non_neg_integer() | nil,
          removed: boolean() | nil,
          topics: [binary()],
          transaction_hash: binary() | nil,
          transaction_index: non_neg_integer() | nil,
          extra_data: term()
        }

  api(:deserialize, "Deserialize an Ethereum transaction receipt log from a JSON-RPC object.",
    params: [
      params: [
        kind: :exchange_data,
        source: "Cartouche.RPC.get_trx_receipt/2",
        description:
          "Receipt log object with hex quantity fields, block and transaction hashes, emitting address, data, and topics."
      ]
    ],
    returns: %{
      type: :receipt_log,
      description:
        "%Cartouche.Filter.Log{} with decoded log index, block/transaction location, emitting address, data bytes, and topic words."
    }
  )

  @doc ~S"""
  Deserializes a transaction receipt as serialized by an Ethereum JSON-RPC response.

  See also https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt

  ## Examples

      iex> use Cartouche.Hex
      iex> %{
      ...>   "logIndex" => "0x1",
      ...>   "blockNumber" => "0x1b4",
      ...>   "blockHash" => "0xa957d47df264a31badc3ae823e10ac1d444b098d9b73d204c40426e57f47e8c3",
      ...>   "transactionHash" =>  "0xaadf829c5a142f1fccd7d8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcf",
      ...>   "transactionIndex" => "0x0",
      ...>   "address" => "0x16c5785ac562ff41e2dcfdf829c5a142f1fccd7d",
      ...>   "data" => "0x0000000000000000000000000000000000000000000000000000000000000000",
      ...>   "topics" => [
      ...>     "0x59ebeb90bc63057b6515673c3ecf9438e5058bca0f92585014eced636878c9a5"
      ...>   ]
      ...> }
      ...> |> Cartouche.Filter.Log.deserialize()
      %Cartouche.Filter.Log{
        log_index: 1,
        block_number: 0x01b4,
        block_hash: ~h[0xa957d47df264a31badc3ae823e10ac1d444b098d9b73d204c40426e57f47e8c3],
        transaction_hash: ~h[0xaadf829c5a142f1fccd7d8216c5785ac562ff41e2dcfdf5785ac562ff41e2dcf],
        transaction_index: 0,
        address: ~h[0x16c5785ac562ff41e2dcfdf829c5a142f1fccd7d],
        data: ~h[0x0000000000000000000000000000000000000000000000000000000000000000],
        topics: [
          ~h[0x59ebeb90bc63057b6515673c3ecf9438e5058bca0f92585014eced636878c9a5]
        ]
      }
  """
  @spec deserialize(map()) :: t()
  def deserialize(%{"address" => address, "data" => data, "topics" => topics} = params) do
    %__MODULE__{
      address: Hex.decode_address!(address),
      block_hash: decode_optional_word(params["blockHash"]),
      block_number: Hex.decode_maybe_hex_number!(params["blockNumber"]),
      data: from_hex!(data),
      log_index: Hex.decode_maybe_hex_number!(params["logIndex"]),
      removed: Map.get(params, "removed"),
      topics: Enum.map(topics, &Hex.decode_word!/1),
      transaction_hash: decode_optional_word(params["transactionHash"]),
      transaction_index: Hex.decode_maybe_hex_number!(params["transactionIndex"])
    }
  end

  @spec decode_optional_word(String.t() | nil) :: binary() | nil
  defp decode_optional_word(nil), do: nil
  defp decode_optional_word(word), do: Hex.decode_word!(word)

  @doc false
  @spec decode_logs(list()) :: [t()]
  def decode_logs(logs) when is_list(logs), do: Enum.map(logs, &deserialize/1)
end
