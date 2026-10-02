defmodule Faucet.Test.FakeSource do
  @moduledoc false
  # Scriptable `Faucet.Source` without `wait_confirmed/3`: the loop must fall
  # back to balance polling. State lives in an Agent passed as `:agent`.
  @behaviour Faucet.Source

  @impl true
  def unit, do: "units"

  @impl true
  def balance(address, opts) do
    Agent.get_and_update(Keyword.fetch!(opts, :agent), fn state ->
      {reading, rest} = pop(state.balances)
      {reading, %{state | balances: rest, calls: [{:balance, address} | state.calls]}}
    end)
  end

  @impl true
  def fund(address, opts) do
    Agent.get_and_update(Keyword.fetch!(opts, :agent), fn state ->
      {result, rest} = pop(state.funds)
      {result, %{state | funds: rest, calls: [{:fund, address, Keyword.get(opts, :deficit)} | state.calls]}}
    end)
  end

  # The last element repeats forever so a script can end in a steady state.
  defp pop([only]), do: {only, [only]}
  defp pop([head | rest]), do: {head, rest}

  @doc false
  def start(balances, funds \\ [{:ok, ["ref"]}]) do
    {:ok, agent} = Agent.start_link(fn -> %{balances: balances, funds: funds, calls: []} end)
    agent
  end

  @doc false
  def calls(agent), do: agent |> Agent.get(& &1.calls) |> Enum.reverse()
end

defmodule Faucet.Test.ConfirmingSource do
  @moduledoc false
  # Same script, but confirms through `wait_confirmed/3` (records the refs).
  @behaviour Faucet.Source

  alias Faucet.Test.FakeSource

  @impl true
  def unit, do: "units"

  @impl true
  defdelegate balance(address, opts), to: FakeSource

  @impl true
  defdelegate fund(address, opts), to: FakeSource

  @impl true
  def wait_confirmed(refs, address, opts) do
    Agent.get_and_update(Keyword.fetch!(opts, :agent), fn state ->
      result = Map.get(state, :confirm, :ok)
      {result, Map.update!(state, :calls, &[{:wait_confirmed, refs, address} | &1])}
    end)
  end
end
