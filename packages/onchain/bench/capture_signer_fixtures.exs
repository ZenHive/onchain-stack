# Run against 186b9137b128598e2576c667de1d9ba7aaabfa40 before consolidation:
# MIX_ENV=test mix run --no-start bench/capture_signer_fixtures.exs
# Captures successful calls from existing tests, including private backend dispatch.
tracer =
  spawn(fn ->
    loop = fn loop, stacks, records ->
      receive do
        {:trace, pid, :call, {mod, fun, args}} ->
          key = {pid, mod, fun, length(args)}
          loop.(loop, Map.update(stacks, key, [args], &[args | &1]), records)

        {:trace, pid, :return_from, {mod, fun, arity}, result} ->
          key = {pid, mod, fun, arity}
          [args | rest] = Map.fetch!(stacks, key)

          records =
            case result do
              {:ok, value} ->
                expected = if mod == Onchain.Signer, do: Cartouche.Transaction.V2.encode(value), else: value
                [{mod, fun, args, expected} | records]

              _ ->
                records
            end

          loop.(loop, Map.put(stacks, key, rest), records)

        {:collect, caller} ->
          send(caller, {:fixtures, records})

        _ ->
          loop.(loop, stacks, records)
      end
    end

    loop.(loop, %{}, [])
  end)

for {mod, fun, arity} <- [
      {Onchain.Signer, :sign_transaction, 3},
      {Cartouche.Signer, :sign_direct, 4},
      {Cartouche.Signer, :backend_sign, 4}
    ] do
  Code.ensure_loaded!(mod)
  :erlang.trace_pattern({mod, fun, arity}, [{:_, [], [{:return_trace}]}], [:local])
end

:erlang.trace(:all, true, [:call, {:tracer, tracer}])

Mix.Task.run("test", [
  "test/transaction_test.exs",
  "test/typed_test.exs",
  "test/cartouche/transaction",
  "test/signer_test.exs",
  "test/signer",
  "test/signature_test.exs",
  "test/recover_test.exs",
  "test/recovery_bit_test.exs",
  "test/keys_test.exs",
  "test/onchain/signer_test.exs",
  "test/onchain/signer_gas_estimate_test.exs",
  "bench/teardown_test.exs",
  "--seed",
  "9040"
])

:erlang.trace(:all, false, [:call])
ref = :erlang.trace_delivered(:all)

receive do
  {:trace_delivered, :all, ^ref} -> :ok
end

send(tracer, {:collect, self()})

fixtures =
  receive do
    {:fixtures, records} -> records |> Enum.uniq() |> Enum.sort()
  end

File.write!("test/support/fixtures/signers_before_consolidation.etf", :erlang.term_to_binary(fixtures, [:compressed]))
IO.inspect(Enum.frequencies_by(fixtures, fn {mod, fun, _, _} -> {mod, fun} end), label: "Captured fixtures")
