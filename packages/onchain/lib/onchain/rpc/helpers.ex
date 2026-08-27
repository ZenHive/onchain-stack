defmodule Onchain.RPC.Helpers do
  @moduledoc false

  # Shared helpers for RPC-adjacent modules (Onchain.RPC, Onchain.Block, etc.).
  # Provides input validation, block normalization, option mapping, and RPC dispatch.

  require Logger

  @default_timeout_ms 30_000
  @block_tags ~w(latest finalized pending earliest safe)
  @tx_hash_hex_length 66

  @doc false
  @spec block_tags() :: [String.t()]
  def block_tags, do: @block_tags

  @doc false
  # Sends an RPC request and normalizes the error format.
  # Cartouche.RPC.send_rpc/3 errors are a union of rpc_error map, invalid-params,
  # Req.Response.t(), and a transport-error String.t() — but a returned revert map
  # can still surface non-map values at runtime. Tracked upstream as cartouche
  # ROADMAP Phase 2, Tasks 2014+2015+2035 — error-shape widening + JSON-encode
  # rescue (see the root ROADMAP.md). Re-probed 2026-06-24 against cartouche 0.5.0
  # (Req transport); keep the suppression until the upstream union fully narrows
  # the non-map case away.
  @dialyzer {:no_match, do_rpc: 3}
  @spec do_rpc(String.t(), list(), keyword()) :: {:ok, term()} | {:error, term()}
  def do_rpc(method, params, opts) do
    case Cartouche.RPC.send_rpc(method, params, opts) do
      {:ok, result} -> {:ok, result}
      {:error, %{} = map} -> {:error, {:rpc_error, maybe_put_revert_data_hex(map)}}
      {:error, other} -> {:error, {:rpc_error, %{message: inspect(other)}}}
    end
  end

  # When Cartouche attaches execution-revert bytes as `:revert`, mirror them as
  # `:data` (0x hex) so callers can pass the map straight to `Onchain.ABI.decode_error/2`.
  @doc false
  @spec maybe_put_revert_data_hex(map()) :: map()
  def maybe_put_revert_data_hex(%{revert: revert} = map) when is_binary(revert) do
    Map.put_new(map, :data, Onchain.Hex.encode(revert))
  end

  def maybe_put_revert_data_hex(map), do: map

  @doc false
  # Validates an address at the RPC-helper boundary and normalizes to lowercase hex.
  # Accepts either:
  #   * "0x" + exactly 40 hex chars (canonical hex form)
  #   * 20-byte raw binary (internal flow from Onchain.Address.validate/1)
  # Rejects malformed hex strings (wrong length, bad chars, missing 0x) — including
  # the Task 55 ambiguity: a 20-byte binary whose leading two bytes are the ASCII
  # "0x" literal. Those are almost always a hex string of wrong length rather than
  # an intentional raw binary address, and silently re-encoding them produced a
  # wildly different on-chain address.
  @spec ensure_hex_address(term()) :: {:ok, String.t()} | {:error, term()}
  def ensure_hex_address("0x" <> rest = input) when byte_size(rest) == 40 do
    if Onchain.Hex.valid?(input),
      do: {:ok, "0x" <> String.downcase(rest)},
      else: {:error, {:invalid_address, input}}
  end

  def ensure_hex_address(<<"0x", _::binary>> = input), do: {:error, {:invalid_address, input}}

  def ensure_hex_address(bin) when is_binary(bin) and byte_size(bin) == 20, do: {:ok, Onchain.Hex.encode(bin)}

  def ensure_hex_address(input), do: {:error, {:invalid_address, input}}

  @doc false
  # Validates that data is a 0x-prefixed even-length hex string.
  # "0x" alone (empty calldata) is accepted.
  @spec ensure_hex_data(term()) :: {:ok, String.t()} | {:error, term()}
  def ensure_hex_data("0x" <> rest = data) do
    cond do
      not Onchain.Hex.valid?(data) -> {:error, {:invalid_data, data}}
      rem(byte_size(rest), 2) != 0 -> {:error, {:invalid_data, data}}
      true -> {:ok, data}
    end
  end

  def ensure_hex_data(input), do: {:error, {:invalid_data, input}}

  @doc false
  # Normalizes a block identifier for RPC params.
  # Accepts tag strings, non-negative integers (converted to hex), and "0x..." hex strings.
  @spec normalize_block(term()) :: {:ok, String.t()} | {:error, term()}
  def normalize_block(tag) when tag in @block_tags, do: {:ok, tag}
  def normalize_block(n) when is_integer(n) and n >= 0, do: {:ok, Onchain.Hex.from_integer(n)}

  def normalize_block("0x" <> _ = hex) do
    if Onchain.Hex.valid?(hex), do: {:ok, hex}, else: {:error, {:invalid_block, hex}}
  end

  def normalize_block(other), do: {:error, {:invalid_block, other}}

  @doc false
  # Normalizes a concrete block number for RPC params that require a quantity (not a tag).
  # Accepts non-negative integers (converted to hex) and "0x..." hex strings; rejects block tags.
  @spec normalize_block_number(term()) :: {:ok, String.t()} | {:error, term()}
  def normalize_block_number(n) when is_integer(n) and n >= 0, do: {:ok, Onchain.Hex.from_integer(n)}

  def normalize_block_number("0x" <> _ = hex) do
    if Onchain.Hex.valid?(hex), do: {:ok, hex}, else: {:error, {:invalid_block, hex}}
  end

  def normalize_block_number(other), do: {:error, {:invalid_block, other}}

  @doc false
  # Validates that a value is a 0x-prefixed hex string of exactly 32 bytes (66 chars).
  @spec ensure_tx_hash(term()) :: {:ok, String.t()} | {:error, term()}
  def ensure_tx_hash("0x" <> _ = hash) do
    cond do
      not Onchain.Hex.valid?(hash) -> {:error, {:invalid_tx_hash, hash}}
      byte_size(hash) != @tx_hash_hex_length -> {:error, {:invalid_tx_hash, hash}}
      true -> {:ok, hash}
    end
  end

  def ensure_tx_hash(other), do: {:error, {:invalid_tx_hash, other}}

  @doc false
  # Validates a storage slot key: 0x-prefixed hex string of exactly 32 bytes.
  # Same shape as a tx hash but tagged distinctly so callers see the right boundary.
  @spec ensure_storage_key(term()) :: {:ok, String.t()} | {:error, {:invalid_storage_key, term()}}
  def ensure_storage_key(key) do
    case ensure_tx_hash(key) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, {:invalid_tx_hash, input}} -> {:error, {:invalid_storage_key, input}}
    end
  end

  @doc false
  # Validates `eth_feeHistory` block_count: integer in 1..1024 (EIP-1474 cap).
  # Encodes the integer to lowercase 0x hex on success.
  @spec ensure_block_count(term()) :: {:ok, String.t()} | {:error, term()}
  def ensure_block_count(n) when is_integer(n) and n >= 1 and n <= 1024, do: {:ok, Onchain.Hex.from_integer(n)}

  def ensure_block_count(other), do: {:error, {:invalid_block_count, other}}

  @doc false
  # Validates `eth_feeHistory` reward_percentiles: non-empty list of integers in 0..100,
  # monotonically non-decreasing per EIP-1474.
  @spec ensure_reward_percentiles(term()) :: :ok | {:error, term()}
  def ensure_reward_percentiles([]), do: {:error, {:invalid_reward_percentiles, :empty}}

  def ensure_reward_percentiles(list) when is_list(list) do
    with :ok <- check_percentile_range(list) do
      check_percentile_monotonic(list)
    end
  end

  def ensure_reward_percentiles(_other), do: {:error, {:invalid_reward_percentiles, :not_a_list}}

  defp check_percentile_range(list) do
    Enum.reduce_while(list, :ok, fn
      n, :ok when is_integer(n) and n >= 0 and n <= 100 -> {:cont, :ok}
      n, _ -> {:halt, {:error, {:invalid_reward_percentiles, {:out_of_range, n}}}}
    end)
  end

  defp check_percentile_monotonic(list) do
    if list == Enum.sort(list),
      do: :ok,
      else: {:error, {:invalid_reward_percentiles, :not_monotonic}}
  end

  @doc false
  # Maps our option names to the underlying RPC client's expected keys.
  #
  # `:errors` is forwarded verbatim to cartouche. When the node returns a
  # JSON-RPC `code: 3` revert and the revert payload's selector matches one of
  # the supplied custom-error signatures (e.g. `"InsufficientBalance(uint256)"`),
  # cartouche populates `:error_abi` and `:error_params` on the inner error map
  # in addition to the always-present `:revert` binary. See `Onchain.RPC`
  # `@moduledoc`'s "Error Format" for the full shape.
  @spec to_rpc_opts(keyword()) :: keyword()
  def to_rpc_opts(opts) do
    opts
    |> Keyword.take([:rpc_url, :timeout, :errors, :retry, :req_options])
    |> Keyword.put_new(:timeout, @default_timeout_ms)
    |> rename_key(:rpc_url, :ethereum_node)
  end

  @doc false
  # Renames a keyword list key if present.
  @spec rename_key(keyword(), atom(), atom()) :: keyword()
  def rename_key(opts, old_key, new_key) do
    case Keyword.pop(opts, old_key) do
      {nil, opts} -> opts
      {value, opts} -> Keyword.put(opts, new_key, value)
    end
  end

  # --- RPC response parsing helpers ---
  # Used by Onchain.RPC and Onchain.Subscription.Parser to convert
  # raw JSON-RPC response fields into normalized Elixir values.

  @doc false
  # Parses hex fields in a raw log map from the RPC response.
  @spec parse_log(map()) :: map()
  def parse_log(log) when is_map(log) do
    %{
      address: parse_address(log["address"]),
      topics: log["topics"] || [],
      data: log["data"],
      block_number: parse_hex_integer(log["blockNumber"]),
      transaction_hash: log["transactionHash"],
      log_index: parse_hex_integer(log["logIndex"]),
      transaction_index: parse_hex_integer(log["transactionIndex"]),
      removed: log["removed"] || false
    }
  end

  @doc false
  # Parses a hex address string to checksummed format.
  @spec parse_address(String.t() | nil) :: String.t() | nil
  def parse_address(nil), do: nil

  def parse_address(hex) do
    case Onchain.Address.checksum(hex) do
      {:ok, checksummed} -> checksummed
      {:error, _} -> hex
    end
  end

  @doc false
  # Parses a hex integer string, returning nil for nil input.
  @spec parse_hex_integer(String.t() | nil) :: non_neg_integer() | nil
  def parse_hex_integer(nil), do: nil

  def parse_hex_integer(hex) do
    case Onchain.Hex.to_integer(hex) do
      {:ok, n} ->
        n

      {:error, _} ->
        Logger.debug("Failed to parse hex integer from RPC response: #{inspect(hex)}")
        nil
    end
  end

  @doc false
  # Decodes eth_getTransactionByHash JSON object (camelCase keys) to atom-keyed map.
  @spec parse_transaction_map(map()) :: map()
  def parse_transaction_map(tx) when is_map(tx) do
    %{
      hash: tx["hash"],
      nonce: parse_hex_integer(tx["nonce"]),
      block_hash: tx["blockHash"],
      block_number: parse_hex_integer(tx["blockNumber"]),
      transaction_index: parse_hex_integer(tx["transactionIndex"]),
      from: parse_address(tx["from"]),
      to: parse_address(tx["to"]),
      value: parse_hex_integer(tx["value"]),
      gas: parse_hex_integer(tx["gas"]),
      gas_price: parse_hex_integer(tx["gasPrice"]),
      max_fee_per_gas: parse_hex_integer(tx["maxFeePerGas"]),
      max_priority_fee_per_gas: parse_hex_integer(tx["maxPriorityFeePerGas"]),
      input: tx["input"],
      type: parse_hex_integer(tx["type"]),
      chain_id: parse_hex_integer(tx["chainId"])
    }
  end

  @doc false
  # Decodes eth_getBlockByNumber JSON object when full_transactions is false (hashes only)
  # or true (full tx maps). Aligns with parse_transaction_map/1 field conventions.
  @spec parse_block_response(map()) :: {:ok, map()} | {:error, term()}
  def parse_block_response(raw) when is_map(raw) do
    with {:ok, number} <- parse_block_number(raw["number"]),
         {:ok, transactions} <- parse_block_transactions(raw["transactions"]),
         {:ok, withdrawals} <- parse_withdrawals(raw["withdrawals"]) do
      {:ok,
       %{
         number: number,
         hash: raw["hash"],
         parent_hash: raw["parentHash"],
         sha3_uncles: raw["sha3Uncles"],
         logs_bloom: raw["logsBloom"],
         transactions_root: raw["transactionsRoot"],
         state_root: raw["stateRoot"],
         receipts_root: raw["receiptsRoot"],
         miner: parse_address(raw["miner"]),
         difficulty: parse_hex_integer(raw["difficulty"]),
         total_difficulty: parse_hex_integer(raw["totalDifficulty"]),
         extra_data: raw["extraData"],
         size: parse_hex_integer(raw["size"]),
         gas_limit: parse_hex_integer(raw["gasLimit"]),
         gas_used: parse_hex_integer(raw["gasUsed"]),
         timestamp: parse_hex_integer(raw["timestamp"]),
         transactions: transactions,
         uncles: raw["uncles"] || [],
         mix_hash: raw["mixHash"],
         nonce: raw["nonce"],
         base_fee_per_gas: parse_hex_integer(raw["baseFeePerGas"]),
         withdrawals_root: raw["withdrawalsRoot"],
         withdrawals: withdrawals,
         blob_gas_used: parse_hex_integer(raw["blobGasUsed"]),
         excess_blob_gas: parse_hex_integer(raw["excessBlobGas"]),
         parent_beacon_block_root: raw["parentBeaconBlockRoot"],
         requests_hash: raw["requestsHash"]
       }}
    end
  end

  @spec parse_block_number(String.t() | nil) :: {:ok, non_neg_integer() | nil} | {:error, term()}
  defp parse_block_number(nil), do: {:ok, nil}

  defp parse_block_number(hex) do
    case Onchain.Hex.to_integer(hex) do
      {:ok, n} -> {:ok, n}
      {:error, _} -> {:error, {:invalid_block_response, :number, hex}}
    end
  end

  @spec parse_block_transactions(term()) :: {:ok, [map() | String.t()]} | {:error, term()}
  defp parse_block_transactions(nil), do: {:ok, []}

  defp parse_block_transactions(list) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case parse_block_transaction_item(item) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp parse_block_transactions(_), do: {:ok, []}

  @spec parse_block_transaction_item(term()) :: {:ok, map() | String.t()} | {:error, term()}
  defp parse_block_transaction_item(%{} = tx), do: {:ok, parse_transaction_map(tx)}
  defp parse_block_transaction_item(other) when is_binary(other), do: {:ok, other}

  defp parse_block_transaction_item(other), do: {:error, {:invalid_block_response, :transactions, other}}

  @spec parse_withdrawals(term()) :: {:ok, [map()] | nil} | {:error, term()}
  defp parse_withdrawals(nil), do: {:ok, nil}

  defp parse_withdrawals(list) when is_list(list) do
    list
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case parse_withdrawal_item(item) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  defp parse_withdrawals(_), do: {:ok, nil}

  @spec parse_withdrawal_item(term()) :: {:ok, map()} | {:error, term()}
  defp parse_withdrawal_item(w) when is_map(w) do
    {:ok,
     %{
       index: parse_hex_integer(w["index"]),
       validator_index: parse_hex_integer(w["validatorIndex"]),
       address: parse_address(w["address"]),
       amount: parse_hex_integer(w["amount"])
     }}
  end

  defp parse_withdrawal_item(other), do: {:error, {:invalid_block_response, :withdrawals, other}}
end
