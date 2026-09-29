defmodule Cartouche.Filter.Log do
  @moduledoc """
  A decoded Ethereum log entry.

  Produced by `Cartouche.Filter` for `kind: :log` filters and returned by
  `Cartouche.RPC.get_filter_logs/2`. Addresses, hashes, and topics are decoded
  to raw binaries; `:block_number`, `:log_index`, and `:transaction_index` to
  integers. `:extra_data` is the opaque term a `Cartouche.Filter` was started
  with, stamped onto every log it dispatches, and is `nil` elsewhere.
  """
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
          block_hash: binary(),
          block_number: non_neg_integer(),
          data: binary(),
          log_index: non_neg_integer(),
          removed: boolean(),
          topics: [binary()],
          transaction_hash: binary(),
          transaction_index: non_neg_integer(),
          extra_data: term()
        }

  @doc false
  @spec deserialize(map()) :: t()
  def deserialize(%{
        "address" => address,
        "blockHash" => block_hash,
        "blockNumber" => block_number,
        "data" => data,
        "logIndex" => log_index,
        "removed" => removed,
        "topics" => topics,
        "transactionHash" => transaction_hash,
        "transactionIndex" => transaction_index
      }) do
    %__MODULE__{
      address: Hex.decode_address!(address),
      block_hash: Hex.decode_word!(block_hash),
      block_number: Hex.decode_hex_number!(block_number),
      data: from_hex!(data),
      log_index: Hex.decode_hex_number!(log_index),
      removed: removed,
      topics: Enum.map(topics, &Hex.decode_word!/1),
      transaction_hash: from_hex!(transaction_hash),
      transaction_index: Hex.decode_hex_number!(transaction_index)
    }
  end
end
