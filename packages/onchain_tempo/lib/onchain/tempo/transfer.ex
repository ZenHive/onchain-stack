defmodule Onchain.Tempo.Transfer do
  @moduledoc """
  Tempo-specific `TransferWithMemo` event log parsing.

  TIP-20 extends ERC-20 with `transferWithMemo(address,uint256,bytes32)`. This
  module parses the corresponding event logs. Standard `Transfer` event parsing
  is handled by `Onchain.Transfer` in the core onchain package.

  ## Usage

      receipt = Onchain.Tempo.RPC.parse_receipt(raw_receipt)
      memo_transfers = Onchain.Tempo.Transfer.parse_transfer_with_memo_logs(receipt.logs)
  """
  # TransferWithMemo event signature — Tempo-specific.
  # Moderato emits `memo` as an indexed topic and `amount` in the data payload.
  @transfer_with_memo_sig "TransferWithMemo(address indexed from, address indexed to, uint256 amount, bytes32 indexed memo)"

  @doc """
  Returns the `TransferWithMemo` event signature string.
  """
  @spec transfer_with_memo_sig() :: String.t()
  def transfer_with_memo_sig, do: @transfer_with_memo_sig

  @doc """
  Parse `TransferWithMemo` events from a list of atom-keyed log entries.

  Returns a flat list of maps with `:token`, `:from`, `:to`, `:amount`, `:memo`
  keys. Non-matching logs are silently skipped.

  The output shape matches `Onchain.Transfer` structs with an additional `:memo`
  field, enabling uniform matching in callers.
  """
  @spec parse_transfer_with_memo_logs([map()]) :: [map()]
  def parse_transfer_with_memo_logs(logs) when is_list(logs) do
    Enum.flat_map(logs, fn log ->
      case Onchain.Log.decode_event(log, @transfer_with_memo_sig) do
        {:ok, %{from: from, to: to, amount: amount, memo: memo_bytes}} ->
          [
            %{
              token: log.address,
              from: from,
              to: to,
              amount: amount,
              memo: encode_memo(memo_bytes)
            }
          ]

        _ ->
          []
      end
    end)
  end

  # Encodes a raw bytes32 memo value to hex string for comparison.
  # Onchain.Log.decode_event returns bytes32 as a 32-byte binary.
  defp encode_memo(memo) when is_binary(memo) and byte_size(memo) == 32 do
    "0x" <> Base.encode16(memo, case: :lower)
  end

  defp encode_memo(<<"0x", _::binary>> = hex), do: String.downcase(hex)
  defp encode_memo(memo) when is_binary(memo), do: "0x" <> String.downcase(memo)
end
