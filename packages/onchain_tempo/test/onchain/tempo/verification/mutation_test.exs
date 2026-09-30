defmodule Onchain.Tempo.Verification.MutationTest do
  use ExUnit.Case, async: false

  alias Onchain.Tempo.Verification.Campaign

  @moduletag :verification
  @ledger_rel "priv/verification/0x76/ledger.json"

  # spec-tags: TEMPO-2, TEMPO-3
  setup_all do
    nif_before = nif_digest()
    results = Campaign.run()
    {:ok, results: results, nif_before: nif_before, nif_after: nif_digest()}
  end

  # A mutant NIF left in priv/native survives a hard kill and is loaded by
  # every later test run, so the campaign must never write it.
  test "campaign leaves the loaded priv/native NIF untouched", %{nif_before: before, nif_after: after_run} do
    assert before == after_run
  end

  test "campaign never writes tracked patch targets on disk", %{results: _results} do
    repo_root = Path.expand("../../../../..", __DIR__)

    for rel <- Campaign.tracked_patch_files() do
      path = Path.join("packages/onchain_tempo", rel)

      assert {_, 0} = System.cmd("git", ["diff", "--quiet", "--", path], cd: repo_root),
             "tracked file #{rel} differs from git after campaign"
    end
  end

  test "every mutant replace pattern is present in the live source" do
    root = Path.expand("../../../../", __DIR__)

    Enum.each(Campaign.mutants(), fn mutant ->
      path = Path.join(root, mutant.file)
      source = File.read!(path)

      assert String.contains?(source, mutant.replace),
             "mutant #{mutant.id} replace pattern missing from #{mutant.file}"
    end)
  end

  test "canaries for wrong field index, signing domain and key authorization are killed", %{results: results} do
    canaries = Enum.filter(results, & &1.canary?)
    assert match?([_, _, _ | _], canaries)

    Enum.each(canaries, fn canary ->
      assert canary.status == :killed,
             "canary #{canary.id} status=#{canary.status}; verification run is invalid (#{inspect(canary.evidence)})"

      assert oracle_kill?(canary.evidence),
             "canary #{canary.id} was not killed by the oracle (#{inspect(canary.evidence)})"
    end)

    ids = Enum.map(canaries, & &1.id)
    assert "canary_field_rlp_skip" in ids
    assert "canary_fee_payer_domain" in ids
    assert "canary_key_authorization_fee_hash" in ids
  end

  test "every mutant is classified and unclassified survivors fail the run", %{results: results} do
    ledger = ledger()
    classified = Map.new(ledger["survivors"] || [], &{&1["id"], &1})

    Enum.each(results, fn result ->
      case result.status do
        :killed ->
          :ok

        :invalid ->
          flunk("mutant #{result.id} did not apply: #{inspect(result.evidence)}")

        :survived ->
          entry = classified[result.id]

          assert is_map(entry),
                 "unclassified survivor #{result.id} (#{result.class}/#{result.surface})"

          assert entry["classification"] in ["equivalent", "unreachable", "redundant"],
                 "survivor #{result.id} has invalid classification #{inspect(entry["classification"])}"
      end
    end)

    assert length(results) == length(Campaign.mutants())

    recorded = Map.new(ledger["mutations"], &{&1["id"], &1["status"]})
    assert recorded == Map.new(results, &{&1.id, Atom.to_string(&1.status)})

    assert Enum.all?(
             results,
             &(&1.class in [
                 :field_index,
                 :signing_domain,
                 :type_byte,
                 :field_order,
                 :numeric_encoding,
                 :signature_recovery,
                 :fee_payer_data,
                 :key_authorization
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
          :fee_payer_data,
          :key_authorization
        ] do
      assert required in classes, "mutation campaign missing class #{required}"
    end

    assert File.exists?(ledger_path())
    ledger = ledger()
    assert ledger["artifact"] == "0x76"
    assert is_list(ledger["mutations"])
    assert ledger["commit"] =~ ~r/^[0-9a-f]{40}$/
    assert ledger["survivors"] == []
  end

  defp oracle_kill?(evidence) when is_list(evidence) and evidence != [], do: true
  defp oracle_kill?(_), do: false

  defp ledger do
    ledger_path()
    |> File.read!()
    |> Jason.decode!()
  end

  defp ledger_path, do: Application.app_dir(:onchain_tempo, @ledger_rel)

  defp nif_digest do
    path = Path.join(:code.priv_dir(:onchain_tempo), "native/onchain_tempo.so")
    :crypto.hash(:sha256, File.read!(path))
  end
end
