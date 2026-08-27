# Decides, by compiling, which surviving mutants are PROVABLY EQUIVALENT --
# they produce byte-identical BEAM code, so no test can ever kill them.
#
# Why this is not just `mix muex --tce` (roadmap task 46, 2026-08-27):
# Muex.Tce.compile_binary/2 keeps only the FIRST module the compiler returns
# (`[{module, binary} | _]` in deps/muex/lib/muex/tce.ex). Nested modules
# compile first, so for a file whose top-level module contains a nested
# `defmodule` -- lib/abi/type_decoder.ex nests StrictViolation at line 17 --
# BOTH sides fingerprint the INNER module and every mutation outside it
# compares equal. That silently dropped 672 of type_decoder.ex's 867 mutations
# from the 2026-08-26 campaign, including `@word_size_bytes 32 -> 33`.
# Reproduced minimally in .mutation/tce-nested-module.exs.
#
# The fix here is one line of the idea: fingerprint EVERY module the compile
# returns, keyed by name, and compare the whole map. Everything else -- the
# probe rename, the line-annotation stripping, the refusal to call a failed
# compile equivalent -- follows muex's design, which is sound.
#
# Direction of error matters: a mutant wrongly called equivalent is INVISIBLE
# to criterion 4, while a genuinely equivalent mutant wrongly left in the
# survivor set merely costs an argument. So anything that fails to compile,
# fails to parse, or cannot be regenerated is reported NOT equivalent.
#
#   MIX_ENV=test mix run .mutation/equivalence.exs <survivors.json>
#
# Writes .mutation/results/equivalent.json.
[input] = System.argv()

language = Muex.Language.Elixir
mutators = Muex.Config.all_mutators([], language)
{:ok, files} = Muex.Loader.load_all(["lib/abi.ex", "lib/abi/*.ex"], language)

raw = File.read!(input)
{start, _} = :binary.match(raw, "{")
doc = raw |> binary_part(start, byte_size(raw) - start) |> Jason.decode!()
survivors = doc["mutations"] || doc["results"]
IO.puts("candidates: #{length(survivors)}")

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

probe = fn ->
  {:__aliases__, [], [String.to_atom("EquivProbe#{System.unique_integer([:positive])}")]}
end

# Compile under a throwaway top-level name and fingerprint EVERY module the
# compiler emits, not just the first. Line annotations are stripped so only the
# behavioural instruction stream remains.
strip_lines = fn strip_lines, term ->
  cond do
    is_list(term) -> term |> Enum.reject(&match?({:line, _}, &1)) |> Enum.map(&strip_lines.(strip_lines, &1))
    is_tuple(term) -> term |> Tuple.to_list() |> then(&strip_lines.(strip_lines, &1)) |> List.to_tuple()
    true -> term
  end
end

fingerprint = fn ast, alias_ast ->
  case ast do
    {:defmodule, meta, [_old, body]} ->
      renamed = {:defmodule, meta, [alias_ast, body]}

      {result, _diag} =
        Code.with_diagnostics(fn ->
          try do
            mods = Code.compile_quoted(renamed)

            prints =
              Enum.map(mods, fn {mod, bin} ->
                {:beam_file, _m, _e, _a, _c, code} = :beam_disasm.file(bin)
                # The probe name is shared by both sides, so only the SUFFIX
                # after it identifies a nested module.
                {mod |> Atom.to_string() |> String.split(".") |> Enum.drop(2),
                 strip_lines.(strip_lines, code)}
              end)

            Enum.each(mods, fn {mod, _} -> :code.purge(mod); :code.delete(mod) end)
            {:ok, Enum.sort(prints)}
          rescue
            _ -> :error
          catch
            _, _ -> :error
          end
        end)

      result

    _ ->
      :error
  end
end

originals =
  Map.new(files, fn f ->
    {f.path, f.path |> File.read!() |> Code.string_to_quoted!()}
  end)

{results, equiv} =
  survivors
  |> Enum.with_index(1)
  |> Enum.map_reduce(0, fn {m, i}, n ->
    {f, line, mutator, desc} =
      case m do
        %{"location" => %{"file" => f, "line" => l}} -> {f, l, m["mutator"], m["description"]}
        %{"file" => f, "line" => l} -> {f, l, m["mutator"], m["description"]}
      end

    verdict =
      case Map.get(by_key, {f, line, mutator, desc}, []) do
        [] ->
          "not_found"

        [{mutation, file} | _] ->
          with {:ok, src} <- Muex.Compiler.compile_to_source(mutation, file, language),
               {:ok, mutant_ast} <- Code.string_to_quoted(src) do
            a = probe.()

            case {fingerprint.(originals[f], a), fingerprint.(mutant_ast, a)} do
              {{:ok, x}, {:ok, y}} when x == y -> "equivalent"
              {{:ok, _}, {:ok, _}} -> "distinguishable"
              _ -> "compile_error"
            end
          else
            _ -> "compile_error"
          end
      end

    if rem(i, 100) == 0, do: IO.puts("[#{i}/#{length(survivors)}] #{n} equivalent so far")

    {%{"file" => f, "line" => line, "mutator" => mutator, "description" => desc, "equivalence" => verdict},
     if(verdict == "equivalent", do: n + 1, else: n)}
  end)

File.write!(".mutation/results/equivalent.json", Jason.encode!(%{"results" => results}))

results
|> Enum.frequencies_by(& &1["equivalence"])
|> Enum.sort_by(&(-elem(&1, 1)))
|> Enum.each(fn {k, v} -> IO.puts("  #{v}\t#{k}") end)

IO.puts("\nprovably equivalent: #{equiv} of #{length(survivors)}")
