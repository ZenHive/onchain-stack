defmodule Faucet.Error do
  @moduledoc """
  Raised by the bang variants when funding cannot reach the requested minimum.

  Carries the source, address, minimum and the underlying reason so a test
  failure names the provider and what it said, never a bare `MatchError`.
  """

  @type t :: %__MODULE__{source: module(), address: String.t(), minimum: non_neg_integer(), reason: term()}

  defexception [:source, :address, :minimum, :reason]

  @impl true
  def message(%__MODULE__{source: source, address: address, minimum: minimum, reason: reason}) do
    unit = if function_exported?(source, :unit, 0), do: " #{source.unit()}", else: ""

    "#{inspect(source)} could not bring #{address} to #{minimum}#{unit}: #{format(reason)}"
  end

  defp format({:budget_exhausted, %{balance: balance, requests: requests}}),
    do: "request budget exhausted after #{requests} request(s); balance is #{balance}"

  defp format({:missing_credential, name, hint}), do: "missing #{name}. #{hint}"
  defp format(:timeout), do: "confirmation timed out"
  defp format(other), do: inspect(other)
end
