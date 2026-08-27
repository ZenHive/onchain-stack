defmodule Onchain.Solidity.Resolver do
  @moduledoc false
  # Pure-Elixir Solidity file-graph resolution: import discovery, Foundry-style
  # remappings, DFS dependency ordering, and merged-source assembly.
  #
  # Lives in its own module (no `use Rustler`) so test coverage can instrument
  # it. The sibling `Onchain.Solidity` carries the revm/Alloy NIF, whose
  # `on_load` is incompatible with cover's beam recompilation; keeping the
  # resolution logic out of that module lets the coverage gate measure it.
  #
  # The three NIF-backed steps — extracting imports, parsing the root contract,
  # and whole-source parsing — are delegated back to `Onchain.Solidity`.

  alias Onchain.Solidity

  @remappings_filename "remappings.txt"
  @source_file_marker_prefix "// onchain:resolved-source "

  @doc false
  @spec resolve_sol_file(String.t(), Solidity.parse_sol_file_opts()) ::
          {:ok, Solidity.resolved_sol_file()}
          | {:error, {:file_error, String.t()} | {:parse_error, String.t()}}
  def resolve_sol_file(path, opts \\ []) do
    with {:ok, absolute_path} <- expand_sol_path(path),
         {:ok, root_contract} <- resolve_root_contract_name(absolute_path, opts),
         {:ok, remappings} <- resolve_remappings(absolute_path, opts),
         {:ok, files} <- resolve_file_graph(absolute_path, remappings, MapSet.new()),
         {:ok, source} <- build_merged_source(files) do
      {:ok, %{source: source, files: files, root_contract: root_contract}}
    end
  end

  @doc false
  @spec parse_sol_file(String.t(), Solidity.parse_sol_file_opts()) ::
          {:ok, Solidity.parsed_sol()}
          | {:error, {:parse_error, String.t()} | {:file_error, String.t()}}
  def parse_sol_file(path, opts \\ []) do
    with {:ok, resolution} <- resolve_sol_file(path, opts) do
      parse_resolved_sol_file(resolution, opts)
    end
  end

  @doc false
  # Parses a resolved source graph, preserving single-file compatibility for mismatched filenames.
  @spec parse_resolved_sol_file(Solidity.resolved_sol_file(), Solidity.parse_sol_file_opts()) ::
          {:ok, Solidity.parsed_sol()} | {:error, {:parse_error, String.t()}}
  defp parse_resolved_sol_file(resolution, opts) do
    case Solidity.__parse_sol_root__(resolution.source, resolution.root_contract) do
      {:error, {:parse_error, reason}} = error ->
        if allow_single_file_fallback?(resolution, opts) and
             String.contains?(reason, "root contract") do
          Solidity.parse_sol(resolution.source)
        else
          error
        end

      result ->
        result
    end
  end

  @doc false
  # Falls back to full-source parsing only for legacy single-file callers without an explicit root override.
  @spec allow_single_file_fallback?(Solidity.resolved_sol_file(), Solidity.parse_sol_file_opts()) ::
          boolean()
  defp allow_single_file_fallback?(resolution, opts) do
    match?([_], resolution.files) and not Keyword.has_key?(opts, :root_contract)
  end

  @doc false
  # Expands a root Solidity file to an absolute path and verifies it exists.
  @spec expand_sol_path(String.t()) :: {:ok, String.t()} | {:error, {:file_error, String.t()}}
  defp expand_sol_path(path) do
    expanded = Path.expand(path)

    case File.stat(expanded) do
      {:ok, %File.Stat{type: :regular}} -> {:ok, expanded}
      {:ok, _other} -> {:error, {:file_error, "#{expanded}: not a regular file"}}
      {:error, reason} -> {:error, {:file_error, "#{expanded}: #{reason}"}}
    end
  end

  @doc false
  # Picks the root contract name from opts or the root file basename.
  @spec resolve_root_contract_name(String.t(), Solidity.parse_sol_file_opts()) ::
          {:ok, String.t()} | {:error, {:file_error, String.t()}}
  defp resolve_root_contract_name(path, opts) do
    root_contract =
      opts
      |> Keyword.get(:root_contract)
      |> case do
        nil -> Path.basename(path, ".sol")
        value when is_binary(value) -> String.trim(value)
      end

    if root_contract == "" do
      {:error, {:file_error, "root contract could not be inferred from #{path}"}}
    else
      {:ok, root_contract}
    end
  end

  @doc false
  # Merges auto-discovered remappings.txt entries with explicit overrides.
  @spec resolve_remappings(String.t(), Solidity.parse_sol_file_opts()) ::
          {:ok, [{String.t(), String.t()}]} | {:error, {:file_error, String.t()}}
  defp resolve_remappings(path, opts) do
    remappings_file = find_remappings_file(Path.dirname(path))
    base_dir = remappings_base_dir(remappings_file, path)

    with {:ok, auto_remappings} <- read_remappings_file(remappings_file),
         {:ok, explicit_remappings} <-
           parse_remapping_strings(Keyword.get(opts, :remappings, []), base_dir, :explicit) do
      {:ok, explicit_remappings ++ auto_remappings}
    end
  end

  @doc false
  # Finds the nearest remappings.txt by walking ancestor directories upward.
  @spec find_remappings_file(String.t()) :: String.t() | nil
  defp find_remappings_file(directory) do
    candidate = Path.join(directory, @remappings_filename)

    if File.regular?(candidate) do
      candidate
    else
      parent = Path.dirname(directory)

      if parent == directory do
        nil
      else
        find_remappings_file(parent)
      end
    end
  end

  @doc false
  # Resolves the base directory used for remapping target expansion.
  @spec remappings_base_dir(String.t() | nil, String.t()) :: String.t()
  defp remappings_base_dir(nil, path), do: Path.dirname(path)
  defp remappings_base_dir(remappings_file, _path), do: Path.dirname(remappings_file)

  @doc false
  # Parses remappings.txt when present; absent files contribute no remappings.
  @spec read_remappings_file(String.t() | nil) ::
          {:ok, [{String.t(), String.t()}]} | {:error, {:file_error, String.t()}}
  defp read_remappings_file(nil), do: {:ok, []}

  defp read_remappings_file(path) do
    case File.read(path) do
      {:ok, contents} -> parse_remapping_strings(String.split(contents, "\n"), Path.dirname(path), path)
      {:error, reason} -> {:error, {:file_error, "#{path}: #{reason}"}}
    end
  end

  @doc false
  # Parses Foundry-style remapping lines into normalized prefix/target tuples.
  @spec parse_remapping_strings([String.t()], String.t(), String.t() | :explicit) ::
          {:ok, [{String.t(), String.t()}]} | {:error, {:file_error, String.t()}}
  defp parse_remapping_strings(lines, base_dir, source_label) when is_list(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {line, line_number}, {:ok, remappings} ->
      case parse_remapping_line(line, line_number, base_dir, source_label) do
        {:ok, nil} -> {:cont, {:ok, remappings}}
        {:ok, remapping} -> {:cont, {:ok, [remapping | remappings]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, remappings} -> {:ok, Enum.reverse(remappings)}
      error -> error
    end
  end

  @doc false
  # Normalizes a single remapping line, skipping blanks and comments.
  @spec parse_remapping_line(String.t(), pos_integer(), String.t(), String.t() | :explicit) ::
          {:ok, {String.t(), String.t()} | nil} | {:error, {:file_error, String.t()}}
  defp parse_remapping_line("", _line_number, _base_dir, _source_label) do
    {:ok, nil}
  end

  defp parse_remapping_line(line, line_number, base_dir, source_label) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        {:ok, nil}

      String.starts_with?(trimmed, "#") ->
        {:ok, nil}

      true ->
        parse_remapping_value(trimmed, line_number, base_dir, source_label)
    end
  end

  @doc false
  # Parses and validates a remapping key=value pair, normalizing segments and expanding the target path.
  @spec parse_remapping_value(String.t(), pos_integer(), String.t(), String.t() | :explicit) ::
          {:ok, {String.t(), String.t()}} | {:error, {:file_error, String.t()}}
  defp parse_remapping_value(trimmed, line_number, base_dir, source_label) do
    case String.split(trimmed, "=", parts: 2) do
      [prefix, target] ->
        normalized_prefix = normalize_remapping_segment(prefix)
        normalized_target = normalize_remapping_segment(target)

        if normalized_prefix == "" or normalized_target == "" do
          {:error, {:file_error, invalid_remapping_message(source_label, line_number, trimmed)}}
        else
          {:ok, {normalized_prefix, Path.expand(normalized_target, base_dir)}}
        end

      _other ->
        {:error, {:file_error, invalid_remapping_message(source_label, line_number, trimmed)}}
    end
  end

  @doc false
  # Ensures remapping prefixes and targets use consistent trailing slash semantics.
  @spec normalize_remapping_segment(String.t()) :: String.t()
  defp normalize_remapping_segment(segment) do
    segment
    |> String.trim()
    |> case do
      "" -> ""
      value -> if String.ends_with?(value, "/"), do: value, else: value <> "/"
    end
  end

  @doc false
  # Formats invalid remapping errors consistently across explicit and file-sourced entries.
  @spec invalid_remapping_message(:explicit | String.t(), pos_integer(), String.t()) :: String.t()
  defp invalid_remapping_message(:explicit, line_number, line) do
    "explicit remapping ##{line_number} is invalid: #{line}"
  end

  defp invalid_remapping_message(source_label, line_number, line) do
    "#{source_label}: invalid remapping on line #{line_number}: #{line}"
  end

  @doc false
  # Resolves a root file and all reachable imports using DFS post-order.
  @spec resolve_file_graph(String.t(), [{String.t(), String.t()}], MapSet.t(String.t())) ::
          {:ok, [String.t()]} | {:error, {:parse_error, String.t()} | {:file_error, String.t()}}
  defp resolve_file_graph(path, remappings, seen) do
    if MapSet.member?(seen, path) do
      {:ok, []}
    else
      with {:ok, source} <- File.read(path),
           {:ok, imports} <- Solidity.__extract_sol_imports__(source),
           {:ok, dependency_files} <- resolve_imports(imports, path, remappings, MapSet.put(seen, path)) do
        {:ok, dependency_files ++ [path]}
      else
        {:error, {:parse_error, _reason}} = error -> error
        {:error, {:file_error, _reason}} = error -> error
        {:error, reason} -> {:error, {:file_error, "#{path}: #{inspect(reason)}"}}
      end
    end
  end

  @doc false
  # Resolves each import in order while preserving DFS dependency order.
  @spec resolve_imports([String.t()], String.t(), [{String.t(), String.t()}], MapSet.t(String.t())) ::
          {:ok, [String.t()]} | {:error, {:parse_error, String.t()} | {:file_error, String.t()}}
  defp resolve_imports(imports, importer_path, remappings, seen) do
    imports
    |> Enum.reduce_while({:ok, {seen, []}}, fn import_path, {:ok, {current_seen, files}} ->
      resolve_single_import(import_path, importer_path, remappings, {current_seen, files})
    end)
    |> case do
      {:ok, {_seen, files}} -> {:ok, files}
      error -> error
    end
  end

  @doc false
  # Resolves one import within the reduce_while accumulator, returning {:cont, ...} or {:halt, ...}.
  @spec resolve_single_import(
          String.t(),
          String.t(),
          [{String.t(), String.t()}],
          {MapSet.t(String.t()), [String.t()]}
        ) ::
          {:cont, {:ok, {MapSet.t(String.t()), [String.t()]}}}
          | {:halt, {:error, {:file_error, String.t()} | {:parse_error, String.t()}}}
  defp resolve_single_import(import_path, importer_path, remappings, {current_seen, files}) do
    case resolve_import_path(import_path, importer_path, remappings) do
      {:ok, resolved_path} ->
        resolve_if_unseen(resolved_path, remappings, {current_seen, files})

      {:error, _reason} = error ->
        {:halt, error}
    end
  end

  @doc false
  # Skips already-seen paths; otherwise recurses into the file graph and merges results.
  @spec resolve_if_unseen(
          String.t(),
          [{String.t(), String.t()}],
          {MapSet.t(String.t()), [String.t()]}
        ) ::
          {:cont, {:ok, {MapSet.t(String.t()), [String.t()]}}}
          | {:halt, {:error, {:file_error, String.t()} | {:parse_error, String.t()}}}
  defp resolve_if_unseen(resolved_path, remappings, {current_seen, files}) do
    if MapSet.member?(current_seen, resolved_path) do
      {:cont, {:ok, {current_seen, files}}}
    else
      case resolve_file_graph(resolved_path, remappings, current_seen) do
        {:ok, child_files} ->
          {:cont, {:ok, {MapSet.union(current_seen, MapSet.new(child_files)), files ++ child_files}}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end
  end

  @doc false
  # Resolves a single import path relative to the importer or through remappings.
  @spec resolve_import_path(String.t(), String.t(), [{String.t(), String.t()}]) ::
          {:ok, String.t()} | {:error, {:file_error, String.t()}}
  defp resolve_import_path(import_path, importer_path, remappings) do
    cond do
      Path.type(import_path) == :absolute ->
        validate_resolved_import(import_path, importer_path, import_path)

      String.starts_with?(import_path, "./") or String.starts_with?(import_path, "../") ->
        import_path
        |> Path.expand(Path.dirname(importer_path))
        |> validate_resolved_import(importer_path, import_path)

      true ->
        resolve_remapped_import(import_path, importer_path, remappings)
    end
  end

  @doc false
  # Resolves remapped imports using longest-prefix match, with earlier entries winning ties.
  @spec resolve_remapped_import(String.t(), String.t(), [{String.t(), String.t()}]) ::
          {:ok, String.t()} | {:error, {:file_error, String.t()}}
  defp resolve_remapped_import(import_path, importer_path, remappings) do
    case matching_remapping(import_path, remappings) do
      nil ->
        {:error, {:file_error, "could not resolve import #{inspect(import_path)} from #{importer_path}"}}

      {prefix, target} ->
        suffix = String.replace_prefix(import_path, prefix, "")

        target
        |> Path.join(suffix)
        |> Path.expand()
        |> validate_resolved_import(importer_path, import_path)
    end
  end

  @doc false
  # Picks the best remapping by longest prefix, preserving caller order for ties.
  @spec matching_remapping(String.t(), [{String.t(), String.t()}]) ::
          {String.t(), String.t()} | nil
  defp matching_remapping(import_path, remappings) do
    remappings
    |> Enum.with_index()
    |> Enum.filter(fn {{prefix, _target}, _index} -> String.starts_with?(import_path, prefix) end)
    |> Enum.max_by(
      fn {{prefix, _target}, index} -> {String.length(prefix), -index} end,
      fn -> nil end
    )
    |> case do
      nil -> nil
      {{prefix, target}, _index} -> {prefix, target}
    end
  end

  @doc false
  # Verifies an import resolves to a real file before it enters the graph.
  @spec validate_resolved_import(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, {:file_error, String.t()}}
  defp validate_resolved_import(resolved_path, importer_path, original_import) do
    case File.stat(resolved_path) do
      {:ok, %File.Stat{type: :regular}} ->
        {:ok, resolved_path}

      {:ok, _other} ->
        {:error,
         {:file_error, "import #{inspect(original_import)} from #{importer_path} did not resolve to a regular file"}}

      {:error, reason} ->
        {:error,
         {:file_error, "import #{inspect(original_import)} from #{importer_path} resolved to #{resolved_path}: #{reason}"}}
    end
  end

  @doc false
  # Re-reads the resolved files and concatenates them into a single parseable source string.
  @spec build_merged_source([String.t()]) ::
          {:ok, String.t()} | {:error, {:file_error, String.t()}}
  defp build_merged_source(files) do
    files
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, sections} ->
      case File.read(path) do
        {:ok, source} -> {:cont, {:ok, [source_section(path, source) | sections]}}
        {:error, reason} -> {:halt, {:error, {:file_error, "#{path}: #{reason}"}}}
      end
    end)
    |> case do
      {:ok, sections} -> {:ok, sections |> Enum.reverse() |> Enum.join("\n\n")}
      error -> error
    end
  end

  @doc false
  # Adds a lightweight file marker so merged-source parse errors still point back to source files.
  @spec source_section(String.t(), String.t()) :: String.t()
  defp source_section(path, source) do
    IO.iodata_to_binary([@source_file_marker_prefix, path, "\n", source])
  end
end
