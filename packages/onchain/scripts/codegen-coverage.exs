# Run from packages/onchain_evm so the optional Solidity frontend is exercised:
# ONCHAIN_EVM_BUILD=1 MIX_ENV=test mix run --no-start ../onchain/scripts/codegen-coverage.exs
{:ok, _} = :cover.start()
module = Onchain.Contract.Generator
{:ok, ^module} = :cover.compile_beam(:code.which(module))

Mix.Task.run("test", [
  "../onchain/test/onchain/contract/generator_test.exs",
  "../onchain/test/onchain/contract/abi_test.exs",
  "test/onchain/contract/generator_test.exs"
])

{:ok, {^module, {covered, missed}}} = :cover.analyse(module, :coverage, :module)
percentage = covered * 100 / (covered + missed)
IO.puts("Generator coverage: #{Float.round(percentage, 2)}% (#{covered}/#{covered + missed} lines)")
if percentage < 80, do: Mix.raise("Generator coverage must be at least 80%")
