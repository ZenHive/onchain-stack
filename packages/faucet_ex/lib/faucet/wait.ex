defmodule Faucet.Wait do
  @moduledoc """
  Deadline-bounded polling shared by the loop and every adapter.

  Sleeps are capped at the remaining budget so a large interval can never
  overshoot the deadline by almost a full period, and floored at 1 ms so the
  scheduler still gets a yield when the budget is nearly spent.
  """

  use Descripex, namespace: "/faucet/wait"

  @default_timeout_ms 60_000
  @default_interval_ms 1_000

  @typedoc "Polling options: `:timeout_ms` (default 60_000) and `:poll_interval_ms` (default 1_000)."
  @type opts :: [timeout_ms: non_neg_integer(), poll_interval_ms: pos_integer()]

  api(:until, "Poll `probe` until it returns `{:done, value}`, giving up at the deadline.",
    params: [
      probe: [
        kind: :value,
        description:
          "Zero-arity function returning `{:done, value}`, `:retry`, or `{:error, reason}` (aborts immediately)"
      ],
      opts: [
        kind: :value,
        default: [],
        description: "`:timeout_ms` (default 60_000), `:poll_interval_ms` (default 1_000)"
      ]
    ],
    returns: %{
      type: "{:ok, value} | {:error, :timeout | term}",
      description: "The probe's value, `{:error, :timeout}` at the deadline, or the probe's own error"
    }
  )

  @spec until((-> {:done, term()} | :retry | {:error, term()}), opts()) :: {:ok, term()} | {:error, term()}
  def until(probe, opts \\ []) when is_function(probe, 0) do
    with {:ok, timeout_ms, interval_ms} <- validate(opts) do
      deadline = System.monotonic_time(:millisecond) + timeout_ms
      loop(probe, deadline, interval_ms)
    end
  end

  api(:validate, "Validate polling options before any network call.",
    params: [opts: [kind: :value, description: "Keyword list possibly carrying `:timeout_ms` / `:poll_interval_ms`"]],
    returns: %{
      type: "{:ok, timeout_ms, interval_ms} | {:error, {:invalid_option, key, value}}",
      description: "Resolved values with defaults applied, or the first offending option"
    }
  )

  @spec validate(keyword()) :: {:ok, non_neg_integer(), pos_integer()} | {:error, {:invalid_option, atom(), term()}}
  def validate(opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    interval_ms = Keyword.get(opts, :poll_interval_ms, @default_interval_ms)

    cond do
      not (is_integer(timeout_ms) and timeout_ms >= 0) -> {:error, {:invalid_option, :timeout_ms, timeout_ms}}
      not (is_integer(interval_ms) and interval_ms > 0) -> {:error, {:invalid_option, :poll_interval_ms, interval_ms}}
      true -> {:ok, timeout_ms, interval_ms}
    end
  end

  defp loop(probe, deadline, interval_ms) do
    case probe.() do
      {:done, value} ->
        {:ok, value}

      {:error, reason} ->
        {:error, reason}

      :retry ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining <= 0 do
          {:error, :timeout}
        else
          Process.sleep(max(min(interval_ms, remaining), 1))
          loop(probe, deadline, interval_ms)
        end
    end
  end
end
