defmodule Faucet.WaitTest do
  use ExUnit.Case, async: true

  alias Faucet.Wait

  test "returns the probe's value immediately when done" do
    assert {:ok, :now} = Wait.until(fn -> {:done, :now} end)
  end

  test "retries until done" do
    counter = :counters.new(1, [])

    probe = fn ->
      :counters.add(counter, 1, 1)
      if :counters.get(counter, 1) >= 3, do: {:done, :third}, else: :retry
    end

    assert {:ok, :third} = Wait.until(probe, poll_interval_ms: 1, timeout_ms: 1_000)
    assert :counters.get(counter, 1) == 3
  end

  test "gives up at the deadline" do
    assert {:error, :timeout} = Wait.until(fn -> :retry end, timeout_ms: 10, poll_interval_ms: 3)
  end

  test "aborts on a probe error without retrying" do
    counter = :counters.new(1, [])

    probe = fn ->
      :counters.add(counter, 1, 1)
      {:error, :node_down}
    end

    assert {:error, :node_down} = Wait.until(probe, timeout_ms: 1_000, poll_interval_ms: 1)
    assert :counters.get(counter, 1) == 1
  end

  test "timeout_ms: 0 still runs the probe once" do
    assert {:ok, 1} = Wait.until(fn -> {:done, 1} end, timeout_ms: 0)
    assert {:error, :timeout} = Wait.until(fn -> :retry end, timeout_ms: 0)
  end

  test "validates options" do
    assert {:ok, 60_000, 1_000} = Wait.validate([])
    assert {:error, {:invalid_option, :timeout_ms, "1"}} = Wait.validate(timeout_ms: "1")
    assert {:error, {:invalid_option, :poll_interval_ms, -5}} = Wait.validate(poll_interval_ms: -5)
    assert {:error, {:invalid_option, :poll_interval_ms, 0}} = Wait.until(fn -> :retry end, poll_interval_ms: 0)
  end
end
