# MIX_ENV=test mix run --no-start bench/capture_transactions.exs
# Run only against the handwritten implementation, before replacing it.
if Code.ensure_loaded?(Onchain.Transaction.Native), do: raise("capture requires the pre-alloy revision")

defmodule Onchain.Bench.Capture do
  @moduledoc false

  @spec loop(map(), MapSet.t()) :: term()
  def loop(stacks, records) do
    receive do
      {:trace, pid, :call, {mod, fun, args}} ->
        frame = {mod, fun, args}
        loop(Map.update(stacks, pid, [frame], &[frame | &1]), records)

      {:trace, pid, kind, {mod, fun, arity}, result}
      when kind in [:return_from, :exception_from] ->
        case Map.get(stacks, pid, []) do
          [{^mod, ^fun, args} | rest] when length(args) == arity ->
            record = {mod, fun, args, kind, result}
            loop(Map.put(stacks, pid, rest), MapSet.put(records, record))

          _ ->
            loop(stacks, records)
        end

      {:finish, caller} ->
        send(caller, {:records, records |> MapSet.to_list() |> Enum.sort()})
    end
  end
end

modules = [
  Onchain.Transaction.V1,
  Onchain.Transaction.V2,
  Onchain.Transaction.V_2930,
  Onchain.Transaction.V3,
  Onchain.Transaction.V4,
  Onchain.Typed,
  Onchain.Typed.Type
]

Enum.each(modules, &Code.ensure_loaded!/1)
tracer = spawn(fn -> Onchain.Bench.Capture.loop(%{}, MapSet.new()) end)

Enum.each(modules, fn mod ->
  for {fun, arity} <- mod.__info__(:functions),
      fun not in [:describe, :__descripex__, :__api__, :module_info, :__info__] do
    :erlang.trace_pattern({mod, fun, arity}, [{:_, [], [{:exception_trace}]}], [])
  end
end)

:erlang.trace(:all, true, [:call, :set_on_spawn, {:tracer, tracer}])

tests = [
  "test/transaction_test.exs",
  "test/typed_test.exs",
  "test/cartouche/transaction",
  "test/signer_test.exs",
  "test/signature_test.exs"
]

Mix.Task.run("test", tests ++ ["--seed", "9032"])
:erlang.trace(:all, false, [:call, :set_on_spawn])
ref = :erlang.trace_delivered(:all)

receive do
  {:trace_delivered, :all, ^ref} -> :ok
end

send(tracer, {:finish, self()})

receive do
  {:records, records} ->
    path = "test/support/fixtures/transactions_before_alloy.etf"
    File.write!(path, :erlang.term_to_binary(records, [:compressed, :deterministic]))
    IO.puts("Captured #{length(records)} distinct Cartouche calls and outcomes in #{path}")
end
