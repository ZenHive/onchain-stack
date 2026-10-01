# MIX_ENV=test mix run --no-start bench/capture_abi.exs
# Run only against the handwritten implementation, before replacing it.
defmodule Onchain.ABI.Bench.Capture do
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

modules = [Onchain.ABI, Onchain.ABI.TypeEncoder, Onchain.ABI.TypeDecoder, Onchain.ABI.FunctionSelector, Onchain.ABI.Event, Onchain.ABI.Parser]
Enum.each(modules, &Code.ensure_loaded!/1)
tracer = spawn(fn -> Onchain.ABI.Bench.Capture.loop(%{}, MapSet.new()) end)

Enum.each(modules, fn mod ->
  for {fun, arity} <- mod.__info__(:functions),
      fun not in [:describe, :__descripex__, :__api__, :module_info, :__info__] do
    :erlang.trace_pattern({mod, fun, arity}, [{:_, [], [{:exception_trace}]}], [])
  end
end)

:erlang.trace(:all, true, [:call, :set_on_spawn, {:tracer, tracer}])

tests =
  "test/abi/*_test.exs"
  |> Path.wildcard()
  |> Enum.reject(&String.ends_with?(&1, "/before_alloy_fixture_test.exs"))

Mix.Task.run("test", tests ++ ["test/abi_test.exs", "test/abi_regression_test.exs", "--seed", "9031"])
:erlang.trace(:all, false, [:call, :set_on_spawn])
ref = :erlang.trace_delivered(:all)

receive do
  {:trace_delivered, :all, ^ref} -> :ok
end

send(tracer, {:finish, self()})

receive do
  {:records, records} ->
    path = "test/support/fixtures/abi_before_alloy.etf"
    File.write!(path, :erlang.term_to_binary(records, [:compressed, :deterministic]))
    IO.puts("Captured #{length(records)} distinct ABI calls and outcomes in #{path}")
end
