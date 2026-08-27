# Re-grades reported SURVIVORS against the FULL test suite.
#
# Why this exists (roadmap task 46, 2026-08-27): muex picks the test files for
# a mutation with Muex.DependencyAnalyzer, and that analyzer builds malformed
# module atoms -- `Enum.join(["Elixir" | parts])` with no dot separator yields
# :ElixirABITypeEncoder, never :"Elixir.ABI.TypeEncoder". Every lookup misses,
# `fallback_to_all/2` fires, and the full suite runs. That accidental miss is
# what makes most modules sound.
#
# `ABI` is the exception: two test files also name it in a `describe` string,
# which goes through a different branch and produces the WELL-FORMED atom, so
# the lookup hits, the fallback never fires, and every mutation in lib/abi.ex
# was graded against 2 of 15 test files. Verified by hand: replacing the body
# of ABI.encode/2 with nil -- reported `survived` -- fails 60 of 460 tests.
#
# A `killed` verdict from a subset is sound (some test really did fail). Only
# `survived` is suspect, so only survivors are re-graded here.
#
# The mutation is regenerated and applied with muex's OWN Loader / Mutator /
# Compiler / Sandbox, so this never hand-reproduces a patch; the single
# deliberate difference is the test file list.
#
#   MIX_ENV=test mix run .mutation/verify-survivors.exs <campaign.json> [file-prefix]
#     [--limit N] [--status killed]
#
# Writes .mutation/results/verified.json and exits non-zero if any reported
# survivor is actually killed.

[campaign | rest] = System.argv()
{opts, rest} = OptionParser.parse!(rest, strict: [limit: :integer, status: :string])
only = List.first(rest)
limit = Keyword.get(opts, :limit)

# Which campaign verdict to re-grade. Defaults to the survivors, which is the
# whole point of the script; `--status killed` is used once, to sample the
# kills and bound the false-kill rate the restore defect can produce (§7.7).
want_status = Keyword.get(opts, :status, "survived")

language = Muex.Language.Elixir
mutators = Muex.Config.all_mutators([], language)
{:ok, files} = Muex.Loader.load_all(["lib/abi.ex", "lib/abi/*.ex"], language)

# run.sh already trimmed the banner: campaign.json starts at the document.
doc = campaign |> File.read!() |> Jason.decode!()

key = fn m -> {m["location"]["file"], m["location"]["line"], m["mutator"], m["description"]} end

reported =
  doc["mutations"]
  |> Enum.filter(&(&1["status"] == want_status))
  |> then(fn ms -> if only, do: Enum.filter(ms, &String.starts_with?(&1["location"]["file"], only)), else: ms end)
  |> then(fn ms -> if limit, do: Enum.take(ms, limit), else: ms end)

IO.puts("#{want_status} to re-grade: #{length(reported)}#{if only, do: " (filtered to #{only})", else: ""}")

# Regenerate every mutation exactly as the campaign did, so a reported survivor
# can be located without reconstructing its patch.
generated =
  Enum.flat_map(files, fn file ->
    file.ast
    |> Muex.Mutator.walk(mutators, %{file: file.path, skip_calls: []})
    |> Enum.map(&{&1, file})
  end)

by_key =
  Enum.group_by(generated, fn {m, _f} ->
    {m.location.file, m.location.line, inspect(m.mutator), m.description}
  end)

test_files =
  ["test"] |> Muex.Config.expand_test_paths() |> Enum.map(&Path.relative_to(&1, File.cwd!()))

IO.puts("full suite: #{length(test_files)} test files")

[sandbox] = Muex.Sandbox.create_pool(1, project_root: File.cwd!(), build_env: "test", test_paths: ["test"])

# Muex.Sandbox.apply_mutation/4 deletes the stale .beam so the child `mix test`
# is forced to recompile the mutated module. Muex.Sandbox.restore/2 does NOT --
# it copies the original source back and leaves the MUTATED .beam sitting in
# the sandbox's _build. Mix then decides whether to recompile by comparing the
# source's mtime against its manifest, at one-second granularity, and a restore
# lands in the same second as the compile that preceded it. So the restored
# file can look unchanged, the mutated .beam survives into the NEXT mutant's
# test run, and that mutant is graded against a previous mutant's code.
#
# The failure is not symmetric with the sandbox transient in the ledger's §7.6:
# it corrupts toward a false KILL, because what leaks in is a mutation that
# already killed something. Measured: lib/abi/type_decoder.ex:349
# `1..element_count` -> `element_count..1` was reported killed, and the same
# edit applied by hand to the real tree passes all 531 tests -- it is
# length-preserving and cannot fail anything.
#
# The FIRST fix here was wrong, and wrong in the opposite direction: touching
# each write to `os_time + 5` is not monotonic across iterations. A full-suite
# run takes ~2 s, so the restore's future stamp outlived the next
# apply_mutation's ordinary write; the mutated source looked OLDER than the
# manifest, Mix skipped it, and the mutant was graded against the UNMUTATED
# tree -- a false SURVIVAL. Measured: re-running the same 11 inputs flipped 5
# of them from survived to killed, alternating strictly by queue position, and
# `lib/abi.ex:674` `0x08 -> 0x07` fails 3 tests when applied by hand.
#
# So the stamp must be strictly increasing over the whole run, not relative to
# the current clock. Every write -- mutation and restore alike -- gets the next
# stamp, which is always greater than any mtime Mix has recorded, so Mix
# recompiles unconditionally and no verdict can depend on queue position.
stamp = :counters.new(1, [])
:counters.put(stamp, 1, System.os_time(:second) + 10)

force_recompile = fn path ->
  :counters.add(stamp, 1, 10)
  File.touch!(Path.join(sandbox.root, path), :counters.get(stamp, 1))
end

# CONTROL: the unmutated tree must be green in this sandbox. Without it, a
# sandbox that cannot run the suite at all reports every mutant as killed and
# the whole re-grade reads as a clean bill of health.
control = Muex.TestRunner.Port.run_tests(test_files, timeout_ms: 120_000, cd: sandbox.root)

case control do
  {:ok, %{failures: 0}} ->
    IO.puts("control: unmutated suite green in sandbox\n")

  other ->
    Muex.Sandbox.cleanup([sandbox])
    IO.puts("CONTROL FAILED: #{inspect(other)}")
    System.halt(1)
end

{results, mismatches} =
  reported
  |> Enum.with_index(1)
  |> Enum.map_reduce(0, fn {m, i}, bad ->
    k = key.(m)
    group = Map.get(by_key, k, [])

    {verdict, detail} =
      case group do
        [] ->
          {"not_found", "could not regenerate this mutation"}

        [{mutation, file} | _] ->
          case Muex.Compiler.compile_to_source(mutation, file, language) do
            {:ok, src} ->
              case Muex.Sandbox.apply_mutation(sandbox, file.path, src, file.module_name) do
                {:ok, _} ->
                  force_recompile.(file.path)

                  try do
                    case Muex.TestRunner.Port.run_tests(test_files,
                           timeout_ms: 120_000,
                           cd: sandbox.root
                         ) do
                      {:ok, %{failures: 0}} -> {"survived", nil}
                      {:ok, %{failures: n}} -> {"killed", "#{n} test failure(s)"}
                      {:error, :timeout} -> {"timeout", nil}
                      {:error, r} -> {"invalid", inspect(r)}
                    end
                  after
                    Muex.Sandbox.restore(sandbox, file.path)
                    force_recompile.(file.path)
                  end

                {:error, r} ->
                  {"invalid", inspect(r)}
              end

            {:error, r} ->
              {"invalid", inspect(r)}
          end
      end

    bad = if verdict != want_status, do: bad + 1, else: bad

    if verdict != want_status or rem(i, 25) == 0 do
      IO.puts(
        "[#{i}/#{length(reported)}] #{elem(k, 0)}:#{elem(k, 1)} #{m["description"]} -> #{verdict}#{if detail, do: " (#{detail})", else: ""}"
      )
    end

    {%{
       "file" => elem(k, 0),
       "line" => elem(k, 1),
       "mutator" => elem(k, 2),
       "description" => elem(k, 3),
       "reported" => want_status,
       "verified" => verdict,
       "detail" => detail
     }, bad}
  end)

Muex.Sandbox.cleanup([sandbox])

# Output path is derived from the input so a second pass cannot clobber the
# first: pass 1 reads campaign.json -> verified.json, pass 2 reads
# pass2-input.json -> verified-pass2.json.
out =
  case Path.basename(campaign, ".json") do
    "campaign" -> ".mutation/results/verified.json"
    other -> ".mutation/results/verified-#{String.replace(other, "-input", "")}.json"
  end
File.write!(out, Jason.encode!(%{"campaign" => campaign, "results" => results}, pretty: true))

IO.puts("\nwrote #{out}")
IO.puts("reported #{want_status}, verified otherwise: #{mismatches} of #{length(reported)}")
if mismatches > 0, do: System.halt(1)
