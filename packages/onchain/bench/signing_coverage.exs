# ONCHAIN_BUILD=1 MIX_ENV=test mix run --no-start bench/signing_coverage.exs
# Instrument only the critical signer modules; this is not full-package QA.
Application.load(:onchain)
{:ok, modules} = :application.get_key(:onchain, :modules)

modules =
  Enum.filter(modules, fn module ->
    String.starts_with?(Atom.to_string(module), "Elixir.Cartouche.Signer") and
      String.contains?(to_string(module.module_info(:compile)[:source]), "/lib/cartouche/")
  end)

{:ok, _} = :cover.start()

for module <- modules do
  Code.ensure_loaded!(module)
  {:ok, ^module} = :cover.compile_beam(:code.which(module))
end

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
  "test/abi/native_boundary_test.exs",
  "bench/teardown_test.exs"
])

results =
  Enum.map(modules, fn module ->
    {:ok, lines} = :cover.analyse(module, :coverage, :line)

    # Use the same line accounting as ExUnitJSON.Coverage: exclude generated
    # line zero, deduplicate source lines, and classify executed lines as covered.
    lines = lines |> Enum.reject(fn {{_, line}, _} -> line == 0 end) |> Enum.uniq_by(fn {{_, line}, _} -> line end)
    uncovered = for {{_, line}, {0, missed}} <- lines, missed > 0, do: line

    %{
      module: Atom.to_string(module),
      covered: length(lines) - length(uncovered),
      missed: length(uncovered),
      uncovered_lines: uncovered
    }
  end)

covered = Enum.sum(Enum.map(results, & &1.covered))
total = covered + Enum.sum(Enum.map(results, & &1.missed))
percentage = covered / total * 100

File.write!(
  "bench/transaction-signer-coverage.json",
  Jason.encode!(%{percentage: percentage, modules: results}, pretty: true)
)

IO.puts("Signer coverage: #{Float.round(percentage, 2)}% (#{covered}/#{total}); required 95%")
if percentage < 95, do: raise("Signer coverage below 95%")
