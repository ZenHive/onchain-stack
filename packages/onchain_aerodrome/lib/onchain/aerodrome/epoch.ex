defmodule Onchain.Aerodrome.Epoch do
  @moduledoc """
  Weekly ve(3,3) epoch arithmetic for Aerodrome.

  Epoch length is `Contracts.constants().epoch_seconds` (604_800). That value
  is RewardsSugar `WEEK()` at `0x1b121EfDaF4ABb8785a315C51D29BCE0552A7678`,
  probed 2026-08-26 as check 6 in `priv/abis/README.md`. The deployed contract
  is the authority: if `WEEK()` and `Contracts.constants().epoch_seconds` ever
  disagree, the contract wins. This module does not talk to RPC.

  Epochs flip Thursday 00:00 UTC because Unix epoch 0 was a Thursday, so
  `floor(ts / week) * week` lands on Thursday midnight with no correction
  term. There is no offset constant.

  `index/1` is the absolute week number since the Unix epoch. It is large,
  stable, and joins on-chain data; it is not counted from an Aerodrome
  genesis timestamp (settled 2026-08-26).

  This is the only epoch helper in the package. Analytics owns the module;
  callers that need boundaries come here rather than re-deriving them.

  ## Stable contract with the rest of the package

  Keep these two entry points stable:

  - `range/2` — epoch-start series for RewardsSugar `epochsByAddress`
    pagination in the read layer
  - `epochs_per_year/0` — the integer 52 that `Analytics.APR` uses as its
    annualiser

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `start/1` | Inclusive Thursday 00:00:00 UTC opening the epoch containing `ts` |
  | `end/1` | Exclusive end: the start of the next epoch |
  | `next/1` | Start of the epoch after the one containing `ts` |
  | `previous/1` | Start of the epoch before the one containing `ts` |
  | `index/1` | Absolute week number since the Unix epoch |
  | `bounds/1` | `{start, end}` with `end` exclusive |
  | `contains?/2` | Whether `ts` sits in the epoch identified by `epoch_ts` |
  | `range/2` | Ascending epoch starts covering `[from_ts, to_ts]` |
  | `seconds_remaining/1` | Seconds until the exclusive end of the current epoch |
  | `epochs_per_year/0` | `52`, the APR annualiser |
  """

  use Descripex, namespace: "/aerodrome/epoch"

  alias Onchain.Aerodrome.Contracts

  @type unix_seconds :: non_neg_integer()
  @type timestamp_error :: {:error, {:timestamp_out_of_range, integer()}}

  # --- start ---

  api(:start, "Inclusive Unix timestamp of the Thursday 00:00:00 UTC that opens the epoch containing ts.",
    params: [
      ts: [kind: :value, description: "Unix timestamp in seconds"]
    ],
    returns: %{
      type: "non_neg_integer() | {:error, {:timestamp_out_of_range, integer()}}",
      description: "Epoch start, or a tagged error for ts < 0"
    }
  )

  @doc """
  Inclusive Unix timestamp of the Thursday 00:00:00 UTC that opens the epoch containing `ts`.

  Equal to `floor(ts / week) * week` with `week` from `Contracts.constants().epoch_seconds`.
  No offset is applied: Unix epoch 0 was a Thursday.

      iex> Onchain.Aerodrome.Epoch.start(1_704_326_400)
      1_704_326_400

      iex> Onchain.Aerodrome.Epoch.start(1_704_326_401)
      1_704_326_400

      iex> Onchain.Aerodrome.Epoch.start(-1)
      {:error, {:timestamp_out_of_range, -1}}
  """
  @spec start(integer()) :: unix_seconds() | timestamp_error()
  def start(ts) when is_integer(ts) and ts >= 0 do
    week = epoch_seconds()
    week * div(ts, week)
  end

  def start(ts) when is_integer(ts), do: {:error, {:timestamp_out_of_range, ts}}

  # --- end ---

  api(:end, "Exclusive end of the epoch containing ts: the start of the next epoch.",
    params: [
      ts: [kind: :value, description: "Unix timestamp in seconds"]
    ],
    returns: %{
      type: "non_neg_integer() | {:error, {:timestamp_out_of_range, integer()}}",
      description: "Next epoch start (exclusive end of the current epoch)"
    }
  )

  @doc """
  Exclusive end of the epoch containing `ts` — the start of the next epoch.

  Exclusive on purpose: treating this instant as still inside the current epoch
  silently double-counts an epoch of emissions. `contains?(end(ts), ts)` is false.

      iex> Onchain.Aerodrome.Epoch.end(1_704_326_400)
      1_704_931_200
  """
  # `end` is reserved; unquote is how the exported Epoch.end/1 is named.
  @spec unquote(:end)(integer()) :: unix_seconds() | timestamp_error()
  def unquote(:end)(ts), do: shift(ts, 1)

  # --- next ---

  api(:next, "Start of the epoch after the one containing ts.",
    params: [
      ts: [kind: :value, description: "Unix timestamp in seconds"]
    ],
    returns: %{
      type: "non_neg_integer() | {:error, {:timestamp_out_of_range, integer()}}",
      description: "Next epoch start"
    }
  )

  @doc """
  Start of the epoch after the one containing `ts`.

  Same instant as `end/1`: the exclusive end of the current epoch is the next
  epoch's start.

      iex> Onchain.Aerodrome.Epoch.next(1_704_326_400)
      1_704_931_200
  """
  @spec next(integer()) :: unix_seconds() | timestamp_error()
  def next(ts), do: shift(ts, 1)

  # --- previous ---

  api(:previous, "Start of the epoch before the one containing ts.",
    params: [
      ts: [kind: :value, description: "Unix timestamp in seconds"]
    ],
    returns: %{
      type: "non_neg_integer() | {:error, {:timestamp_out_of_range, integer()}}",
      description: "Previous epoch start, or a tagged error when that start would be before 1970"
    }
  )

  @doc """
  Start of the epoch before the one containing `ts`.

  Returns `{:error, {:timestamp_out_of_range, ts}}` when that start would be
  negative (the Unix epoch's own week has no predecessor).

      iex> Onchain.Aerodrome.Epoch.previous(1_704_326_400)
      1_703_721_600

      iex> Onchain.Aerodrome.Epoch.previous(0)
      {:error, {:timestamp_out_of_range, 0}}
  """
  @spec previous(integer()) :: unix_seconds() | timestamp_error()
  def previous(ts), do: shift(ts, -1)

  # --- index ---

  api(:index, "Absolute week number of the epoch containing ts, counted from the Unix epoch.",
    params: [
      ts: [kind: :value, description: "Unix timestamp in seconds"]
    ],
    returns: %{
      type: "non_neg_integer() | {:error, {:timestamp_out_of_range, integer()}}",
      description: "Absolute epoch index since Unix epoch 0"
    }
  )

  @doc """
  Absolute week number of the epoch containing `ts`, counted from the Unix epoch.

  Large, stable, and comparable to on-chain epoch fields. Not relative to an
  Aerodrome genesis timestamp.

      iex> Onchain.Aerodrome.Epoch.index(0)
      0

      iex> Onchain.Aerodrome.Epoch.index(1_704_326_400)
      2818
  """
  @spec index(integer()) :: non_neg_integer() | timestamp_error()
  def index(ts), do: map_start(ts, fn start -> div(start, epoch_seconds()) end)

  # --- bounds ---

  api(:bounds, "Half-open {start, end} bounds of the epoch containing ts.",
    params: [
      ts: [kind: :value, description: "Unix timestamp in seconds"]
    ],
    returns: %{
      type: "{non_neg_integer(), non_neg_integer()} | {:error, {:timestamp_out_of_range, integer()}}",
      description: "Inclusive start and exclusive end"
    }
  )

  @doc """
  Half-open `{start, end}` bounds of the epoch containing `ts`.

  `end` is exclusive: it is the start of the next epoch.

      iex> Onchain.Aerodrome.Epoch.bounds(1_704_326_400)
      {1_704_326_400, 1_704_931_200}
  """
  @spec bounds(integer()) :: {unix_seconds(), unix_seconds()} | timestamp_error()
  def bounds(ts), do: map_start(ts, fn start -> {start, start + epoch_seconds()} end)

  # --- contains? ---

  api(:contains?, "Whether ts sits in the epoch identified by epoch_ts.",
    params: [
      epoch_ts: [kind: :value, description: "Any Unix timestamp in the candidate epoch"],
      ts: [kind: :value, description: "Unix timestamp to test"]
    ],
    returns: %{
      type: "boolean() | {:error, {:timestamp_out_of_range, integer()}}",
      description: "true when both timestamps fall in the same epoch"
    }
  )

  @doc """
  Returns whether `ts` sits in the epoch identified by `epoch_ts`.

  `epoch_ts` may be any instant in that epoch, including its start. The
  exclusive end returned by `end/1` belongs to the *next* epoch, so
  `contains?(end(ts), ts)` is false.

      iex> Onchain.Aerodrome.Epoch.contains?(1_704_326_400, 1_704_326_401)
      true

      iex> Onchain.Aerodrome.Epoch.contains?(1_704_931_200, 1_704_326_400)
      false
  """
  @spec contains?(integer(), integer()) :: boolean() | timestamp_error()
  def contains?(epoch_ts, ts) when is_integer(epoch_ts) and is_integer(ts) do
    case {start(epoch_ts), start(ts)} do
      {{:error, _} = error, _} -> error
      {_, {:error, _} = error} -> error
      {left, right} -> left == right
    end
  end

  # --- range ---

  api(:range, "Ascending epoch starts covering the closed timestamp window [from_ts, to_ts].",
    params: [
      from_ts: [kind: :value, description: "Window start (Unix seconds)"],
      to_ts: [kind: :value, description: "Window end (Unix seconds)"]
    ],
    returns: %{
      type: "[non_neg_integer()] | {:error, {:timestamp_out_of_range, integer()}}",
      description: "Epoch starts, inclusive of the epoch containing from_ts; [] when to_ts precedes from_ts"
    }
  )

  @doc """
  Ascending epoch starts covering the closed timestamp window `[from_ts, to_ts]`.

  Inclusive of the epoch containing `from_ts` and of the epoch containing
  `to_ts`. Returns `[]` when `to_ts` precedes `from_ts` rather than raising.
  The read layer uses this to build the epoch series for RewardsSugar
  `epochsByAddress` pagination.

      iex> Onchain.Aerodrome.Epoch.range(1_704_326_400, 1_704_326_400)
      [1_704_326_400]

      iex> Onchain.Aerodrome.Epoch.range(1_704_326_400, 1_704_931_200)
      [1_704_326_400, 1_704_931_200]

      iex> Onchain.Aerodrome.Epoch.range(1_704_326_400, 1_704_326_399)
      []
  """
  @spec range(integer(), integer()) :: [unix_seconds()] | timestamp_error()
  def range(from_ts, to_ts) when is_integer(from_ts) and is_integer(to_ts) do
    with {:ok, from_ts} <- require_ts(from_ts),
         {:ok, to_ts} <- require_ts(to_ts) do
      collect_starts(from_ts, to_ts)
    end
  end

  # --- seconds_remaining ---

  api(:seconds_remaining, "Seconds remaining until the exclusive end of the epoch containing ts.",
    params: [
      ts: [kind: :value, description: "Unix timestamp in seconds"]
    ],
    returns: %{
      type: "pos_integer() | {:error, {:timestamp_out_of_range, integer()}}",
      description: "Seconds until exclusive end; a full week when ts is itself an epoch start"
    }
  )

  @doc """
  Seconds remaining until the exclusive end of the epoch containing `ts`.

      iex> Onchain.Aerodrome.Epoch.seconds_remaining(1_704_326_400)
      604_800

      iex> Onchain.Aerodrome.Epoch.seconds_remaining(1_704_931_199)
      1
  """
  @spec seconds_remaining(integer()) :: pos_integer() | timestamp_error()
  def seconds_remaining(ts) do
    map_start(ts, fn start -> start + epoch_seconds() - ts end)
  end

  # --- epochs_per_year ---

  api(:epochs_per_year, "APR annualiser: 52 weekly epochs per year.",
    params: [],
    returns: %{
      type: "52",
      description: "Integer week count Analytics.APR multiplies a weekly rate by"
    }
  )

  @doc """
  Integer `52` — the annualiser `Analytics.APR` uses.

  `52 * 604_800` is about 364 days. Annualising from a daily rate overstates
  by roughly 7x; weekly epochs are the unit of Aerodrome emissions.

      iex> Onchain.Aerodrome.Epoch.epochs_per_year()
      52
  """
  @spec epochs_per_year() :: 52
  def epochs_per_year, do: 52

  @spec epoch_seconds() :: pos_integer()
  defp epoch_seconds do
    %{epoch_seconds: seconds} = Contracts.constants()
    seconds
  end

  @spec require_ts(integer()) :: {:ok, unix_seconds()} | timestamp_error()
  defp require_ts(ts) when ts >= 0, do: {:ok, ts}
  defp require_ts(ts), do: {:error, {:timestamp_out_of_range, ts}}

  @spec collect_starts(unix_seconds(), unix_seconds()) :: [unix_seconds()]
  defp collect_starts(from_ts, to_ts) when to_ts < from_ts, do: []

  defp collect_starts(from_ts, to_ts) do
    week = epoch_seconds()
    first = week * div(from_ts, week)
    last = week * div(to_ts, week)
    Enum.to_list(first..last//week)
  end

  @spec map_start(integer(), (unix_seconds() -> result)) :: result | timestamp_error()
        when result: var
  defp map_start(ts, fun) do
    case start(ts) do
      {:error, _} = error -> error
      start -> fun.(start)
    end
  end

  @spec shift(integer(), -1 | 1) :: unix_seconds() | timestamp_error()
  defp shift(ts, direction) do
    map_start(ts, fn start ->
      shifted = start + direction * epoch_seconds()

      if shifted < 0 do
        {:error, {:timestamp_out_of_range, ts}}
      else
        shifted
      end
    end)
  end
end
