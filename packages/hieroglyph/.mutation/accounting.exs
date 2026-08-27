# Re-derives the mutation counts muex drops BEFORE the worker pool, which its
# JSON report cannot show.
#
# Two subtractive steps run between mutation generation and execution:
#
#   * `maybe_drop_unlocatable/2` removes mutations reported at `line: 0` unless
#     --keep-metadata-mutations is passed. muex documents those as
#     compile-time/invalid mutants; they cannot be dispositioned by site.
#   * `drop_equivalent/2` removes AST-pattern-equivalent mutants. This one is
#     always on and is NOT the same layer as --tce: TCE runs per mutant inside
#     the worker and surfaces as `status: "equivalent"` in the JSON, while this
#     layer deletes the mutation before the pool ever sees it.
#
# Both counts are logged only under --verbose, and --verbose costs a full
# re-run of the campaign to recover a number that needs no test execution at
# all. This script regenerates the mutations exactly as `Muex.do_run/2` does
# and counts each stage, running no tests.
#
#   MIX_ENV=test mix run .mutation/accounting.exs

files_patterns = ["lib/abi.ex", "lib/abi/*.ex"]
language = Muex.Language.Elixir

# The same 18 the campaign runs: every builtin mutator supporting Elixir.
mutators = Muex.Config.all_mutators([], language)

{:ok, files} = Muex.Loader.load_all(files_patterns, language)

generated =
  Enum.flat_map(files, fn file ->
    Muex.Mutator.walk(file.ast, mutators, %{file: file.path, skip_calls: []})
  end)

locatable? = fn mutation ->
  case get_in(mutation, [:location, :line]) do
    line when is_integer(line) and line > 0 -> true
    _ -> false
  end
end

{located, unlocated} = Enum.split_with(generated, locatable?)
kept = Muex.Equivalence.filter_equivalent(located)

per_file =
  generated
  |> Enum.group_by(&get_in(&1, [:location, :file]))
  |> Enum.map(fn {f, ms} -> {f, length(ms)} end)
  |> Enum.sort()

IO.puts("files loaded:              #{length(files)}")
IO.puts("mutations generated:       #{length(generated)}")
IO.puts("dropped, line: 0:          #{length(unlocated)}")
IO.puts("dropped, AST-equivalent:   #{length(located) - length(kept)}")
IO.puts("reaching the worker pool:  #{length(kept)}   (== campaign JSON `total`)")
IO.puts("")
IO.puts("generated per file:")
Enum.each(per_file, fn {f, n} -> IO.puts("  #{String.pad_trailing(f, 32)} #{n}") end)
