defmodule Faucet.TopUp do
  @moduledoc """
  The top-up loop: read → request → wait → re-read, bounded by a request
  budget and serialized per address.

  Serialization uses `:global.trans/2` keyed on `{Faucet, source, address}`, so
  two test modules funding the same address in parallel take turns instead of
  double-requesting. Disable with `lock: false`.
  """

  alias Faucet.Wait

  @default_max_requests 10

  @typedoc "Why the loop stopped short of the minimum."
  @type error ::
          {:budget_exhausted, %{balance: non_neg_integer(), required: non_neg_integer(), requests: pos_integer()}}
          | {:invalid_option, atom(), term()}
          | term()

  @doc false
  @spec run(module(), String.t(), non_neg_integer(), keyword()) :: {:ok, non_neg_integer()} | {:error, error()}
  def run(source, address, minimum, opts) do
    with {:ok, _timeout, _interval} <- Wait.validate(opts),
         {:ok, max_requests} <- max_requests(opts) do
      work = fn -> loop(source, address, minimum, opts, max_requests, 0) end

      if Keyword.get(opts, :lock, true) do
        :global.trans({{Faucet, source, String.downcase(address)}, self()}, work)
      else
        work.()
      end
    end
  end

  defp max_requests(opts) do
    case Keyword.get(opts, :max_requests, @default_max_requests) do
      n when is_integer(n) and n > 0 -> {:ok, n}
      other -> {:error, {:invalid_option, :max_requests, other}}
    end
  end

  defp loop(source, address, minimum, opts, budget, used) do
    case source.balance(address, opts) do
      {:ok, balance} when balance >= minimum ->
        {:ok, balance}

      {:ok, balance} when used >= budget ->
        {:error, {:budget_exhausted, %{balance: balance, required: minimum, requests: used}}}

      {:ok, balance} ->
        with :ok <- request_round(source, address, balance, minimum, opts) do
          loop(source, address, minimum, opts, budget, used + 1)
        end

      {:error, _} = error ->
        error
    end
  end

  defp request_round(source, address, balance, minimum, opts) do
    with {:ok, refs} <- source.fund(address, Keyword.put(opts, :deficit, minimum - balance)) do
      confirm(source, refs, address, balance, opts)
    end
  end

  # Sources that know how to confirm (receipt polling) do so; the rest are
  # polled on balance until it moves above the pre-request reading.
  defp confirm(source, refs, address, before, opts) do
    if function_exported?(source, :wait_confirmed, 3),
      do: source.wait_confirmed(refs, address, opts),
      else: poll_balance(source, address, before, opts)
  end

  defp poll_balance(source, address, before, opts) do
    case Wait.until(fn -> balance_probe(source, address, before, opts) end, opts) do
      {:ok, :ok} -> :ok
      {:error, _} = error -> error
    end
  end

  defp balance_probe(source, address, before, opts) do
    case source.balance(address, opts) do
      {:ok, now} when now > before -> {:done, :ok}
      {:ok, _} -> :retry
      {:error, reason} -> {:error, reason}
    end
  end
end
