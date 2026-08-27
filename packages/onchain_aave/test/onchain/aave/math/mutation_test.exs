defmodule Onchain.Aave.Math.MutationTest do
  @moduledoc """
  Mutation adequacy for the V3/V4 math oracle: generated operator mutants,
  domain mutants (rounding / clamp / comparison), and a deliberate canary.
  """

  use ExUnit.Case, async: false

  alias Onchain.Aave.MathMutator
  alias Onchain.Aave.MathOracle

  @moduletag timeout: :infinity

  @goldens MathOracle.load_goldens!()

  describe "negative control" do
    test "floor-rounding ray_mul is killed by the Solidity goldens" do
      result = MathMutator.evaluate(MathMutator.canary(), @goldens)

      assert result.verdict == :killed,
             "canary survived — verification run is invalid: #{inspect(result)}"
    end
  end

  describe "mutation campaign" do
    test "generated and domain mutants are killed or classified with evidence" do
      results = MathMutator.campaign(@goldens)

      gaps =
        Enum.filter(results, fn
          %{verdict: :survived, classification: %{bucket: :gap}} -> true
          %{verdict: :survived, classification: nil} -> true
          _ -> false
        end)

      unclassified_killed = Enum.filter(results, &(&1.verdict == :killed and &1.evidence in [nil, ""]))

      assert gaps == [], "unclassified survivors (test/spec gaps): #{inspect(gaps)}"
      assert unclassified_killed == [], "killed mutants missing evidence"

      canary = Enum.find(results, &(&1.id == MathMutator.canary().id))
      assert canary.verdict == :killed

      on_disk = MathOracle.ledger_path() |> File.read!() |> Jason.decode!()
      v3 = MathOracle.load_wrapper!(:v3)
      v4 = MathOracle.load_wrapper!(:v4)

      assert on_disk["bytecode"]["v3"] == v3.meta["wrapper"]["bin_sha256"]
      assert on_disk["bytecode"]["v4"] == v4.meta["wrapper"]["bin_sha256"]
      assert on_disk["negative_control"]["id"] == canary.id
      assert on_disk["negative_control"]["verdict"] == "killed"
      assert on_disk["mutation"]["totals"]["killed"] == Enum.count(results, &(&1.verdict == :killed))
      assert on_disk["mutation"]["totals"]["survived"] == Enum.count(results, &(&1.verdict == :survived))
      assert on_disk["mutation"]["totals"]["generated"] == Enum.count(results, &(&1.source == :generated))
      assert on_disk["mutation"]["totals"]["domain"] == Enum.count(results, &(&1.source == :domain))

      survivor_ids = results |> Enum.filter(&(&1.verdict == :survived)) |> Enum.map(& &1.id) |> Enum.sort()
      ledger_ids = on_disk["mutation"]["survivors"] |> Enum.map(& &1["id"]) |> Enum.sort()
      assert ledger_ids == survivor_ids

      Enum.each(on_disk["mutation"]["survivors"], fn survivor ->
        assert survivor["bucket"] in ["equivalent", "unreachable", "redundant"]
        assert is_binary(survivor["evidence"]) and survivor["evidence"] != ""
      end)
    end
  end
end
