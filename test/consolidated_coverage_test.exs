# elixir test/consolidated_coverage_test.exs
ExUnit.start()
Mix.start()
Code.require_file("../packages/onchain/dev/mix/tasks/onchain.coverage.ex", __DIR__)

defmodule ConsolidatedCoverageTest do
  use ExUnit.Case, async: false
  alias Mix.Tasks.Onchain.Coverage

  defp row(name, covered, missed) do
    %{"module" => name, "covered_lines" => covered, "uncovered_lines" => List.duplicate(1, missed)}
  end

  defp baseline do
    [row("Onchain.ABI", 95, 5), row("Onchain.RPC", 85, 15), row("Onchain.Signer", 95, 5), row("Onchain.ENS", 70, 30)]
  end

  test "preserves each library floor at its boundary" do
    assert :ok = Coverage.check!(baseline())
  end

  test "high Onchain coverage cannot conceal deficient ABI coverage" do
    rows = [row("Onchain.ABI", 94, 6), row("Onchain.Extra", 10_000, 0) | tl(baseline())]
    assert_raise Mix.Error, ~r/ABI coverage below 95%/, fn -> Coverage.check!(rows) end
  end

  test "signer coverage retains its critical floor" do
    rows = baseline() ++ [row("Onchain.Signer.CloudKMS", 90, 10)]
    assert_raise Mix.Error, ~r/Cartouche signers coverage below 95%/, fn -> Coverage.check!(rows) end
  end

  test "former cartouche modules keep the cartouche floor under their new names" do
    rows = baseline() ++ [row("Onchain.Block", 0, 100)]
    assert_raise Mix.Error, ~r/Cartouche coverage below 85%/, fn -> Coverage.check!(rows) end
  end

  test "a missing library report fails closed" do
    assert_raise Mix.Error, ~r/No coverage recorded for ABI/, fn -> Coverage.check!(tl(baseline())) end
  end

  test "an empty report fails closed" do
    assert_raise Mix.Error, ~r/No coverage recorded/, fn -> Coverage.check!([]) end
  end
end
