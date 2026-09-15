defmodule Onchain.Aerodrome.EpochTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Onchain.Aerodrome.Contracts
  alias Onchain.Aerodrome.Epoch

  doctest Epoch

  @unix_2020 DateTime.to_unix(~U[2020-01-01 00:00:00Z])
  @unix_2030 DateTime.to_unix(~U[2030-12-31 23:59:59Z])
  # Thursday 2024-01-04 00:00:00 UTC, an exact epoch boundary.
  @thursday_2024 1_704_326_400

  describe "start/1" do
    test "Unix epoch 0 is an epoch start — no offset is required" do
      assert Epoch.start(0) == 0
    end

    test "uses Contracts.constants().epoch_seconds rather than a second literal" do
      week = Contracts.constants().epoch_seconds

      for t <- [0, 1, week - 1, week, @thursday_2024, @thursday_2024 + 86_399, @unix_2020] do
        assert Epoch.start(t) == week * div(t, week)
      end
    end

    test "rejects negative and pre-1970 timestamps" do
      assert Epoch.start(-1) == {:error, {:timestamp_out_of_range, -1}}
      assert Epoch.start(-604_800) == {:error, {:timestamp_out_of_range, -604_800}}
    end
  end

  property "start/1 is Thursday 00:00:00 UTC for timestamps from 2020 through 2030" do
    check all(ts <- integer(@unix_2020..@unix_2030), max_runs: 500) do
      start = Epoch.start(ts)
      dt = DateTime.from_unix!(start)

      assert Date.day_of_week(dt) == 4
      assert dt.hour == 0
      assert dt.minute == 0
      assert dt.second == 0
    end
  end

  describe "end/1" do
    test "is exclusive: the exclusive end is not in the same epoch as ts" do
      ts = @thursday_2024 + 12_345
      # An off-by-one here silently double-counts an epoch of emissions.
      assert Epoch.contains?(Epoch.end(ts), ts) == false
      assert Epoch.contains?(Epoch.end(ts) - 1, ts) == true
    end
  end

  describe "next/1 and previous/1" do
    test "next/1 is the start of the following epoch" do
      assert Epoch.next(@thursday_2024) == Epoch.end(@thursday_2024)
      assert Epoch.next(@thursday_2024 + 1) == Epoch.end(@thursday_2024)
    end

    test "previous/1 walks back one week and errors before 1970" do
      week = Contracts.constants().epoch_seconds
      assert Epoch.previous(@thursday_2024) == @thursday_2024 - week
      assert Epoch.previous(0) == {:error, {:timestamp_out_of_range, 0}}
      assert Epoch.previous(week - 1) == {:error, {:timestamp_out_of_range, week - 1}}
    end
  end

  describe "index/1" do
    test "is the absolute week number since the Unix epoch" do
      week = Contracts.constants().epoch_seconds
      assert Epoch.index(0) == 0
      assert Epoch.index(@thursday_2024) == div(@thursday_2024, week)
      assert Epoch.index(@thursday_2024) == Epoch.index(@thursday_2024 + 1)
    end
  end

  describe "bounds/1" do
    test "returns a half-open interval" do
      {start, finish} = Epoch.bounds(@thursday_2024 + 99)
      assert start == Epoch.start(@thursday_2024)
      assert finish == Epoch.end(@thursday_2024)
      assert Epoch.contains?(start, @thursday_2024 + 99)
      refute Epoch.contains?(finish, @thursday_2024 + 99)
    end
  end

  describe "contains?/2" do
    test "is true for any instant in the same epoch, including the start" do
      assert Epoch.contains?(@thursday_2024, @thursday_2024)
      assert Epoch.contains?(@thursday_2024, @thursday_2024 + 1)
      refute Epoch.contains?(@thursday_2024, Epoch.end(@thursday_2024))
    end
  end

  describe "range/2" do
    test "includes the epoch containing from_ts and returns starts ascending" do
      week = Contracts.constants().epoch_seconds
      from = @thursday_2024 + 10
      to = @thursday_2024 + week + 10

      assert Epoch.range(from, to) == [@thursday_2024, @thursday_2024 + week]
    end

    test "includes a single start when both timestamps fall in the same epoch" do
      assert Epoch.range(@thursday_2024, @thursday_2024) == [@thursday_2024]
      assert Epoch.range(@thursday_2024 + 1, @thursday_2024 + 2) == [@thursday_2024]
    end

    test "returns [] when to_ts precedes from_ts rather than raising" do
      assert Epoch.range(@thursday_2024, @thursday_2024 - 1) == []
      assert Epoch.range(10, 0) == []
    end
  end

  describe "seconds_remaining/1" do
    test "is a full week at an epoch start and 1 at the last included second" do
      week = Contracts.constants().epoch_seconds
      assert Epoch.seconds_remaining(@thursday_2024) == week
      assert Epoch.seconds_remaining(Epoch.end(@thursday_2024) - 1) == 1
    end
  end

  describe "epochs_per_year/0" do
    test "returns the integer 52" do
      assert Epoch.epochs_per_year() == 52
    end
  end

  describe "out-of-range timestamps" do
    test "every timestamp-taking function rejects negatives rather than a negative index" do
      ts = -1
      error = {:error, {:timestamp_out_of_range, ts}}

      assert Epoch.start(ts) == error
      assert Epoch.end(ts) == error
      assert Epoch.next(ts) == error
      assert Epoch.previous(ts) == error
      assert Epoch.index(ts) == error
      assert Epoch.bounds(ts) == error
      assert Epoch.contains?(ts, 0) == error
      assert Epoch.contains?(0, ts) == error
      assert Epoch.range(ts, 0) == error
      assert Epoch.range(0, ts) == error
      assert Epoch.seconds_remaining(ts) == error
    end
  end
end
