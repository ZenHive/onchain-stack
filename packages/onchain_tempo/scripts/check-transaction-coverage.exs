alias Onchain.Tempo.Transaction

ExUnit.start(autorun: false, exclude: [:integration])
{:ok, _} = :cover.start()
{:ok, Transaction} = :cover.compile_beam(Transaction)

for path <- [
      "test/onchain/tempo/transaction_test.exs",
      "test/onchain/tempo/transaction/builder_test.exs",
      "test/onchain/tempo/transaction/builder_estimate_test.exs",
      "test/onchain/tempo/verification/native_test.exs",
      "test/onchain/tempo/verification/differential_test.exs",
      "test/onchain/tempo/verification/property_test.exs"
    ],
    do: Code.require_file(path)

result = ExUnit.run()
coverage = ExUnitJSON.Coverage.collect()
IO.puts(Jason.encode!(coverage, pretty: true))
if result.failures != 0 or coverage["total_percentage"] < 95, do: System.halt(1)
