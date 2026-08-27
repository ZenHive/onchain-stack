defmodule Onchain.Subscription.Parser do
  @moduledoc false

  # Pure parsing functions for eth_subscribe notification payloads.
  # Converts raw JSON-RPC subscription results into normalized Elixir maps.
  # No WebSocket dependency — all functions are pure and testable in isolation.

  import Onchain.RPC.Helpers, only: [parse_log: 1, parse_hex_integer: 1, parse_address: 1]

  alias Onchain.Subscription

  @tx_hash_hex_length 66

  @doc false
  @spec parse_event(:new_heads, map()) :: {:ok, Subscription.head()} | {:error, term()}
  @spec parse_event(:pending_transactions, String.t()) :: {:ok, String.t()} | {:error, term()}
  @spec parse_event(:logs, map()) :: {:ok, Subscription.log()} | {:error, term()}
  def parse_event(:new_heads, raw) when is_map(raw) do
    {:ok,
     %{
       number: parse_hex_integer(raw["number"]),
       hash: raw["hash"],
       parent_hash: raw["parentHash"],
       timestamp: parse_hex_integer(raw["timestamp"]),
       miner: parse_address(raw["miner"]),
       gas_limit: parse_hex_integer(raw["gasLimit"]),
       gas_used: parse_hex_integer(raw["gasUsed"]),
       base_fee_per_gas: parse_hex_integer(raw["baseFeePerGas"]),
       logs_bloom: raw["logsBloom"],
       transactions_root: raw["transactionsRoot"],
       state_root: raw["stateRoot"],
       receipts_root: raw["receiptsRoot"]
     }}
  end

  def parse_event(:new_heads, other), do: {:error, {:invalid_head, other}}

  def parse_event(:pending_transactions, hash) when is_binary(hash) do
    cond do
      not String.starts_with?(hash, "0x") -> {:error, {:invalid_tx_hash, hash}}
      byte_size(hash) != @tx_hash_hex_length -> {:error, {:invalid_tx_hash, hash}}
      not Onchain.Hex.valid?(hash) -> {:error, {:invalid_tx_hash, hash}}
      true -> {:ok, hash}
    end
  end

  def parse_event(:pending_transactions, other), do: {:error, {:invalid_tx_hash, other}}

  def parse_event(:logs, raw) when is_map(raw) do
    {:ok, parse_log(raw)}
  end

  def parse_event(:logs, other), do: {:error, {:invalid_log, other}}
end
