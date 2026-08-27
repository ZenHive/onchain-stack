defmodule Mix.Tasks.Hieroglyph.Mutants do
  @shortdoc "Runs the planted-mutant corpus against the task-44 verification vectors"

  @moduledoc """
  Applies each planted mutant in `test/support/mutants/mutants.exs` to `lib/`,
  runs the suite, and reverts the file byte-exactly.

  A mutant is **killed** when the assertions added by roadmap task 44 — the
  independent ethers.js vector corpus and the spec-anchored assertions — fail
  on it. A mutant that only the pre-existing suite catches is a **survivor**,
  because the pre-existing suite is largely self-consistency (`decode(encode(x))`)
  and cannot detect a wire-format drift that both directions share.

  Two runs are recorded per mutant and kept apart:

    * `vectors` — `test/abi/ethers_corpus_test.exs` and
      `test/abi/abi_spec_test.exs` only. This is the number that matters.
    * `suite` — the whole `mix test` run, i.e. the "caught by something else"
      column. A `suite` failure alone never counts as a kill.

  Compilation is not an oracle: a mutant that fails to compile is reported as
  `invalid`, not as a kill.

  ## Usage

  The task lives under `test/support/` — it mutates `lib/` and is never
  shipped — so it is only on the code path in the test environment:

      MIX_ENV=test mix hieroglyph.mutants              # both runs, table + exit status
      MIX_ENV=test mix hieroglyph.mutants --vectors    # skip the whole-suite column
      MIX_ENV=test mix hieroglyph.mutants --only id    # one mutant by id (repeatable)

  The task exits non-zero when a mutant whose recorded expectation is
  `:killed` is not killed, when a mutant recorded as `:survivor` unexpectedly
  dies, when an anchor no longer matches its file exactly once, or when a
  mutated file is not restored byte-exactly.

  ## Control run

  Before the first mutation the task runs `@vector_files` against unmutated
  `lib/` and aborts unless they pass. Without that control a vector suite that
  is failing for an unrelated reason makes *every* mutant exit non-zero, which
  the classifier reads as `:killed` — a table showing a perfect kill rate while
  proving nothing. The control makes each later non-zero attributable to the
  mutation. It also covers `--only`, which otherwise selects away the one
  `:survivor` mutant whose expectation would have caught the same breakage.

  ## Recovering an interrupted run

  `lib/` is mutated on disk for the whole of each `mix test` invocation, which
  is where essentially all the wall-clock time goes. Exceptions are covered by
  `try/after`, but a signal is not: Ctrl-C reaches the BEAM break handler and
  `erlang:halt` unwinds nothing, so an interrupt during a run leaves a mutated
  file behind. To make that loud instead of silent, the original bytes are
  written to a `.hieroglyph-mutants.orig` sidecar before each mutation and removed
  only after the restore is verified byte-exact. A leftover sidecar therefore
  means a previous run was killed mid-mutation; the task refuses to start until
  it is resolved:

      git checkout -- lib/ && rm lib/**/*.hieroglyph-mutants.orig

  Nothing can protect against `SIGKILL` mid-write — the sidecar is what makes
  the damage recoverable and impossible to miss.
  """

  use Mix.Task

  @vector_files ["test/abi/ethers_corpus_test.exs", "test/abi/abi_spec_test.exs"]
  @corpus_path "test/support/mutants/mutants.exs"
  @sidecar_suffix ".hieroglyph-mutants.orig"

  # Substrings that mean "this mutant did not compile", i.e. a static-analysis
  # result rather than a wire-format oracle. `TokenMissingError` and
  # `MismatchedDelimiterError` are raised by Elixir's tokenizer for a mutation
  # that unbalances delimiters; without them such a mutant reads as a kill.
  @compile_failure_markers [
    "(CompileError)",
    "(SyntaxError)",
    "(TokenMissingError)",
    "(MismatchedDelimiterError)",
    "Compilation error"
  ]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(argv) do
    {opts, _rest} =
      OptionParser.parse!(argv, strict: [vectors: :boolean, only: :keep], aliases: [])

    mutants = select(load_corpus(), Keyword.get_values(opts, :only))
    run_suite? = not Keyword.get(opts, :vectors, false)

    assert_no_orphaned_sidecars!()
    assert_baseline_green!()

    results = Enum.map(mutants, &evaluate(&1, run_suite?))

    report(results, run_suite?)

    if Enum.all?(results, & &1.ok?) do
      :ok
    else
      Mix.raise("planted-mutant corpus failed — see the table above")
    end
  end

  @spec load_corpus() :: [map()]
  defp load_corpus do
    {mutants, _bindings} = Code.eval_file(@corpus_path)

    mutants
  end

  @spec select([map()], [String.t()]) :: [map()]
  defp select(mutants, []), do: mutants

  defp select(mutants, ids) do
    case Enum.filter(mutants, &(&1.id in ids)) do
      [] -> Mix.raise("no mutant matches --only #{Enum.join(ids, ",")}")
      selected -> selected
    end
  end

  # One mutant: snapshot, mutate, run, restore, verify the restore.
  #
  # The mutating write lives INSIDE the `try` on purpose: `File.write!` opens
  # with `:write`, which truncates before it writes, so a write that fails
  # partway (ENOSPC, EACCES, a read-only mount) leaves the file truncated
  # rather than merely mutated. Inside the `try` that damage is repaired by the
  # `after`; outside it, it would not be.
  @spec evaluate(map(), boolean()) :: map()
  defp evaluate(mutant, run_suite?) do
    original = File.read!(mutant.file)
    before_digest = :crypto.hash(:sha256, original)

    assert_single_anchor!(mutant, original)
    mutated = replace_once(original, mutant.find, mutant.replace)
    assert_mutation_bites!(mutant, original, mutated)

    sidecar = sidecar_path(mutant.file)
    File.write!(sidecar, original)

    outcome =
      try do
        File.write!(mutant.file, mutated)

        vectors = run_tests(@vector_files)
        suite = if run_suite?, do: run_tests([]), else: :skipped

        %{vectors: vectors, suite: suite}
      after
        File.write!(mutant.file, original)
      end

    restored? = :crypto.hash(:sha256, File.read!(mutant.file)) == before_digest

    # Drop the crash backup only once the restore is proven byte-exact, and
    # stop the whole run rather than mutating the next file on top of a tree
    # that is already wrong.
    if restored? do
      File.rm!(sidecar)
    else
      Mix.raise(
        "mutant #{mutant.id}: #{mutant.file} was not restored byte-exactly. " <>
          "The original bytes are in #{sidecar} — restore with " <>
          "`cp #{sidecar} #{mutant.file}` (or `git checkout -- #{mutant.file}`) before rerunning."
      )
    end

    verdict = verdict(outcome.vectors)

    Map.merge(mutant, %{
      vectors: outcome.vectors,
      suite: outcome.suite,
      verdict: verdict,
      restored?: restored?,
      ok?: restored? and verdict == mutant.expect
    })
  end

  # A previous run that was killed by a signal (Ctrl-C is the realistic case --
  # the BEAM break handler halts without unwinding, so the `after` above never
  # runs) leaves both a mutated file and its sidecar behind. Refuse to start:
  # mutating on top of an already-wrong tree produces a table nobody can trust,
  # and the sidecar is the only copy of the original bytes.
  @spec assert_no_orphaned_sidecars!() :: :ok
  defp assert_no_orphaned_sidecars! do
    case Path.wildcard("lib/**/*" <> @sidecar_suffix) do
      [] ->
        :ok

      orphans ->
        listed = Enum.join(orphans, ", ")
        recover = "git checkout -- lib/ && rm lib/**/*#{@sidecar_suffix}"

        Mix.raise(
          "a previous mutant run left #{length(orphans)} sidecar(s) behind, so `lib/` may still be mutated: #{listed}. Restore the tree and clear them first: #{recover}"
        )
    end
  end

  # The control run. Every mutant is graded by "did the vector files go
  # non-zero", so if they are already failing on unmutated `lib/` then every
  # mutant reads as killed and the corpus reports a perfect score against a
  # broken oracle.
  @spec assert_baseline_green!() :: :ok
  defp assert_baseline_green! do
    case run_tests(@vector_files) do
      :passed ->
        :ok

      outcome ->
        listed = Enum.join(@vector_files, " ")

        Mix.raise(
          "control run: #{listed} do not pass on unmutated lib/ (#{outcome}). Every mutant would read as killed. Fix the vector suite before running the corpus."
        )
    end
  end

  @spec sidecar_path(String.t()) :: String.t()
  defp sidecar_path(file), do: file <> @sidecar_suffix

  # A mutant whose `replace` does not actually change the file is not a mutant;
  # it would be recorded as a survivor and read as evidence about coverage.
  @spec assert_mutation_bites!(map(), String.t(), String.t()) :: :ok
  defp assert_mutation_bites!(mutant, original, mutated) do
    if original == mutated do
      Mix.raise(
        "mutant #{mutant.id}: `replace` leaves #{mutant.file} byte-identical — " <>
          "the mutation is a no-op and would be recorded as a survivor"
      )
    end

    :ok
  end

  @spec assert_single_anchor!(map(), String.t()) :: :ok
  defp assert_single_anchor!(mutant, source) do
    case source |> String.split(mutant.find) |> length() do
      2 ->
        :ok

      count ->
        Mix.raise(
          "mutant #{mutant.id}: anchor matched #{count - 1} times in #{mutant.file} (expected exactly 1) — " <>
            "the site moved; update test/support/mutants/mutants.exs instead of guessing"
        )
    end
  end

  @spec replace_once(String.t(), String.t(), String.t()) :: String.t()
  defp replace_once(source, find, replace) do
    String.replace(source, find, replace, global: false)
  end

  # `:failed` is the only kill signal. `:invalid` means the mutant did not
  # compile, which is a static-analysis result, not a wire-format oracle.
  @spec run_tests([String.t()]) :: :passed | :failed | :invalid
  defp run_tests(files) do
    {output, status} =
      System.cmd("mix", ["test" | files],
        env: [{"MIX_ENV", "test"}],
        stderr_to_stdout: true
      )

    cond do
      status == 0 -> :passed
      String.contains?(output, @compile_failure_markers) -> :invalid
      true -> :failed
    end
  end

  @spec verdict(:passed | :failed | :invalid) :: :killed | :survivor | :invalid
  defp verdict(:failed), do: :killed
  defp verdict(:passed), do: :survivor
  defp verdict(:invalid), do: :invalid

  @spec report([map()], boolean()) :: :ok
  defp report(results, run_suite?) do
    Mix.shell().info("\nplanted-mutant corpus (#{length(results)} mutants)\n")

    Enum.each(results, fn result ->
      suite = if run_suite?, do: " | suite: #{result.suite}", else: ""

      Mix.shell().info(
        "#{status_glyph(result)} #{String.pad_trailing(result.id, 34)} " <>
          "vectors: #{String.pad_trailing(to_string(result.vectors), 8)}" <>
          "-> #{String.pad_trailing(to_string(result.verdict), 10)}" <>
          "expected: #{String.pad_trailing(to_string(result.expect), 10)}#{suite}"
      )

      if !result.restored?, do: Mix.shell().error("   !! #{result.file} was not restored byte-exactly")
    end)

    Mix.shell().info("")

    :ok
  end

  @spec status_glyph(map()) :: String.t()
  defp status_glyph(%{ok?: true}), do: "ok  "
  defp status_glyph(_result), do: "FAIL"
end
