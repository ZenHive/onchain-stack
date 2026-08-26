defmodule Onchain.Tempo.Verification.MutationTest do
  use ExUnit.Case, async: false

  alias Onchain.Tempo.Verification.Campaign

  @moduletag :verification
  @ledger_rel "priv/verification/0x76/ledger.json"

  setup_all do
    {:ok, results: Campaign.run()}
  end

  test "canaries for a wrong field index and signing domain are killed", %{results: results} do
    canaries = Enum.filter(results, & &1.canary?)
    assert match?([_, _ | _], canaries)

    Enum.each(canaries, fn canary ->
      assert canary.status == :killed,
             "canary #{canary.id} survived; verification run is invalid (#{inspect(canary.evidence)})"
    end)

    assert "canary_calls_index" in Enum.map(canaries, & &1.id)
    assert "canary_fee_payer_domain" in Enum.map(canaries, & &1.id)
  end

  test "every mutant is classified and unclassified survivors fail the run", %{results: results} do
    ledger = ledger()
    classified = Map.new(ledger["survivors"] || [], &{&1["id"], &1})

    Enum.each(results, fn result ->
      case result.status do
        :killed ->
          :ok

        :survived ->
          entry = classified[result.id]

          assert is_map(entry),
                 "unclassified survivor #{result.id} (#{result.class}/#{result.surface})"

          assert entry["classification"] in ["equivalent", "unreachable", "redundant"],
                 "survivor #{result.id} has invalid classification #{inspect(entry["classification"])}"
      end
    end)

    assert length(results) == length(Campaign.mutants())

    assert Enum.all?(
             results,
             &(&1.class in [
                 :field_index,
                 :signing_domain,
                 :type_byte,
                 :field_order,
                 :numeric_encoding,
                 :signature_recovery,
                 :fee_payer_data
               ])
           )
  end

  test "campaign targets field order, type/domain bytes, fee-payer data, numeric encoding and recovery" do
    classes = MapSet.new(Enum.map(Campaign.mutants(), & &1.class))

    for required <- [
          :field_index,
          :signing_domain,
          :type_byte,
          :field_order,
          :numeric_encoding,
          :signature_recovery,
          :fee_payer_data
        ] do
      assert required in classes, "mutation campaign missing class #{required}"
    end

    assert File.exists?(ledger_path())
    ledger = ledger()
    assert ledger["artifact"] == "0x76"
    assert is_list(ledger["mutations"])
  end

  defp ledger do
    ledger_path()
    |> File.read!()
    |> Jason.decode!()
  end

  defp ledger_path, do: Application.app_dir(:onchain_tempo, @ledger_rel)
end
