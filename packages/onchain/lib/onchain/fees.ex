defmodule Onchain.Fees do
  @moduledoc """
  EIP-1559 fee suggestion math over `Cartouche.FeeHistory.t()`.

  Pure functions — no RPC, no I/O. Pair with `Onchain.RPC.fee_history/2` to
  fetch the input struct.

  ## Algorithm

  Given a fee history with `base_fee_per_gas` (block_count + 1 entries — the
  array is oldest-to-newest with the projected next-block fee at the LAST index
  per the `eth_feeHistory` spec) and `reward` (block_count rows × N percentile
  columns), `suggest_fees/2`:

  1. Reads `base_fee = List.last(history.base_fee_per_gas)` — the next-block fee.
  2. For each block, picks the priority fee at `:percentile_index` (default 0).
  3. Takes the median of those per-block priority fees as `max_priority`.
  4. Computes `max_fee = ceil(base_fee × buffer) + max_priority`.

  ## Buffer default

  The default `:buffer` is `1.2` for parity with cartouche's `v2_gas_parameters`.
  EIP-1559's reference recommendation is `2.0` for ~12-block headroom; pass
  `buffer: 2.0` for the conservative default. Lower values risk transactions
  getting stuck in a rising-fee market.

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `suggest_fees/2` | Compute `{base_fee, max_priority, max_fee}` recommendation |
  | `suggest_fees!/2` | Same, raises on error |

  ## Error Format

  - `{:error, :no_base_fee_data}` — `history.base_fee_per_gas` is `nil` or empty,
    so there is no next-block fee to project from.
  - `{:error, {:invalid_base_fee, value}}` — the last `base_fee_per_gas` entry is
    not a number.
  - `{:error, :no_reward_data}` — `history.reward` is `nil` or empty (caller
    passed empty `reward_percentiles` to `eth_feeHistory`), or a row is not a list.
  - `{:error, {:percentile_index_out_of_range, idx, width}}` — requested column
    doesn't exist in the reward rows. `width` is the narrowest row's length.
  - `{:error, {:invalid_buffer, value}}` — buffer is not a positive number.
  """

  use Descripex, namespace: "/fees"

  api(:suggest_fees, "Compute EIP-1559 fee recommendation from a Cartouche.FeeHistory struct.",
    params: [
      history: [
        kind: :value,
        description: "Cartouche.FeeHistory.t() — typically from Onchain.RPC.fee_history/2"
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          "Options: :percentile_index (default 0 — column in history.reward), :buffer (default 1.2 — base-fee multiplier for max_fee headroom)"
      ]
    ],
    returns: %{
      type: "{:ok, {non_neg_integer, non_neg_integer, non_neg_integer}} | {:error, term}",
      description: "Tuple of {base_fee, max_priority, max_fee} in wei"
    }
  )

  @spec suggest_fees(Cartouche.FeeHistory.t(), keyword()) ::
          {:ok, {non_neg_integer(), non_neg_integer(), non_neg_integer()}} | {:error, term()}
  def suggest_fees(%Cartouche.FeeHistory{} = history, opts \\ []) do
    percentile_index = Keyword.get(opts, :percentile_index, 0)
    buffer = Keyword.get(opts, :buffer, 1.2)

    with :ok <- validate_buffer(buffer),
         {:ok, base_fee} <- fetch_base_fee(history),
         {:ok, reward} <- fetch_reward(history),
         {:ok, width} <- reward_width(reward),
         :ok <- validate_percentile_index(percentile_index, width) do
      # `row` is the per-block percentile list (1-4 elements) and percentile_index a
      # small constant, so Enum.at here is O(small), not O(block_count).
      # The directive must be the last comment above the flagged line: reach scopes
      # `disable-next-line` to `comment_line + 1`.
      # reach:disable-next-line suboptimal -- Enum.at over a 1-4 element row, not a hot path
      priority_estimates = Enum.map(reward, fn row -> round(Enum.at(row, percentile_index)) end)

      max_priority = median(priority_estimates)
      max_fee = ceil(base_fee * buffer) + max_priority

      {:ok, {base_fee, max_priority, max_fee}}
    end
  end

  api(:suggest_fees!, "Compute EIP-1559 fee recommendation. Raises on error.",
    params: [
      history: [kind: :value, description: "Cartouche.FeeHistory.t()"],
      opts: [kind: :value, default: [], description: "Options: :percentile_index, :buffer"]
    ],
    returns: %{
      type: "{non_neg_integer, non_neg_integer, non_neg_integer}",
      description: "Tuple of {base_fee, max_priority, max_fee} in wei"
    }
  )

  @spec suggest_fees!(Cartouche.FeeHistory.t(), keyword()) ::
          {non_neg_integer(), non_neg_integer(), non_neg_integer()}
  def suggest_fees!(history, opts \\ []) do
    case suggest_fees(history, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "suggest_fees failed: #{inspect(reason)}"
    end
  end

  defp validate_buffer(n) when is_number(n) and n > 0, do: :ok
  defp validate_buffer(other), do: {:error, {:invalid_buffer, other}}

  defp fetch_base_fee(%Cartouche.FeeHistory{base_fee_per_gas: list}) when is_list(list) do
    case List.last(list) do
      nil -> {:error, :no_base_fee_data}
      base_fee when is_number(base_fee) -> {:ok, base_fee}
      other -> {:error, {:invalid_base_fee, other}}
    end
  end

  defp fetch_base_fee(%Cartouche.FeeHistory{}), do: {:error, :no_base_fee_data}

  defp fetch_reward(%Cartouche.FeeHistory{reward: nil}), do: {:error, :no_reward_data}
  defp fetch_reward(%Cartouche.FeeHistory{reward: []}), do: {:error, :no_reward_data}
  defp fetch_reward(%Cartouche.FeeHistory{reward: reward}), do: {:ok, reward}

  # The narrowest row bounds the valid index: `eth_feeHistory` is specified to return one
  # column per requested percentile, but a ragged row from a non-conforming node would
  # otherwise make `Enum.at/2` yield nil and crash `round/1` mid-map.
  defp reward_width(rows) when is_list(rows) do
    if rows != [] and Enum.all?(rows, &is_list/1) do
      {:ok, rows |> Enum.map(&length/1) |> Enum.min()}
    else
      {:error, :no_reward_data}
    end
  end

  defp reward_width(_), do: {:error, :no_reward_data}

  defp validate_percentile_index(idx, width) when is_integer(idx) and idx >= 0 and idx < width, do: :ok

  defp validate_percentile_index(idx, width), do: {:error, {:percentile_index_out_of_range, idx, width}}

  defp median(list) do
    sorted = Enum.sort(list)
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 1 do
      Enum.at(sorted, mid)
    else
      a = Enum.at(sorted, mid - 1)
      b = Enum.at(sorted, mid)
      div(a + b, 2)
    end
  end
end
