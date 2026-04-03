defmodule Onchain.Solidity do
  @moduledoc """
  Solidity ABI parser powered by Alloy and solang-parser via Rustler NIF.

  Supports three input modes:

  - **ABI JSON** — standard `solc` output. Parses function signatures, selectors,
    parameter types, events, and errors. Use `parse_abi_json/1`.
  - **Solidity source** — raw source strings. Recovers structs, enums, NatSpec,
    and constants that ABI JSON discards. Use `parse_sol/1`.
  - **Resolved Solidity files** — root `.sol` files with relative imports and
    Foundry-style remappings. Use `resolve_sol_file/2` or `parse_sol_file/2`.

  ## Output Structure

  Both parsers return maps with `:functions`, `:events`, `:errors`, `:constructor`.
  The Solidity parser additionally returns `:structs`, `:enums`, and `:constants`,
  and attaches `:natspec` to each function entry.

  ### Parameter Maps

  All parameter maps use `:ty` (not `:type`) for the Solidity type string. Nested
  struct/tuple parameters include `:components` with recursive `param()` maps.

  ### Selectors & Topics

  Selectors and topic hashes are `0x`-prefixed hex strings (e.g. `"0x70a08231"`),
  consistent with the `Onchain.Hex` convention used throughout the codebase.

  The `:return_type` field on each function produces tuple-type strings compatible
  with `Onchain.ABI.decode_response/2` (e.g. `"(uint256,uint256,bool)"`).

  ## Error Format

  | Source | Error Shape |
  |--------|-------------|
  | Invalid JSON / malformed ABI | `{:error, {:parse_error, reason}}` |
  | Invalid Solidity source | `{:error, {:parse_error, reason}}` |
  | File not found / unreadable | `{:error, {:file_error, reason}}` |

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `parse_abi_json/1` | Parse ABI JSON string → structured map |
  | `parse_abi_json!/1` | Same, raises on error |
  | `parse_abi_file/1` | Read file + parse ABI JSON |
  | `parse_abi_file!/1` | Same, raises on error |
  | `parse_sol/1` | Parse Solidity source string → enriched map |
  | `parse_sol!/1` | Same, raises on error |
  | `resolve_sol_file/2` | Resolve a root `.sol` file, its imports, and remappings |
  | `resolve_sol_file!/2` | Same, raises on error |
  | `parse_sol_file/2` | Resolve imports/remappings, then parse the root contract |
  | `parse_sol_file!/2` | Same, raises on error |
  """

  use Descripex, namespace: "/solidity"
  use Rustler, otp_app: :onchain_evm, crate: "onchain_solidity"

  @remappings_filename "remappings.txt"
  @source_file_marker_prefix "// onchain:resolved-source "

  # --- Types ---

  @typedoc "ABI parameter with Solidity type and optional nested components."
  @type param :: %{name: String.t(), ty: String.t(), components: [param()]}

  @typedoc "Event parameter — like `param()` but includes `:indexed` flag."
  @type event_param :: %{
          name: String.t(),
          ty: String.t(),
          indexed: boolean(),
          components: [param()]
        }

  @typedoc "Parsed ABI function entry."
  @type function_info :: %{
          name: String.t(),
          signature: String.t(),
          selector: String.t(),
          return_type: String.t(),
          state_mutability: String.t(),
          inputs: [param()],
          outputs: [param()]
        }

  @typedoc "Parsed function entry with NatSpec (from .sol source)."
  @type function_info_with_natspec :: %{
          name: String.t(),
          signature: String.t(),
          selector: String.t(),
          return_type: String.t(),
          state_mutability: String.t(),
          inputs: [param()],
          outputs: [param()],
          natspec: natspec() | nil
        }

  @typedoc "Parsed ABI event entry."
  @type event_info :: %{
          name: String.t(),
          signature: String.t(),
          topic: String.t(),
          anonymous: boolean(),
          inputs: [event_param()]
        }

  @typedoc "Parsed ABI error entry."
  @type error_info :: %{
          name: String.t(),
          signature: String.t(),
          selector: String.t(),
          inputs: [param()]
        }

  @typedoc "Parsed ABI constructor entry, or `nil` if not present."
  @type constructor_info :: %{inputs: [param()], state_mutability: String.t()} | nil

  @typedoc "Complete parsed ABI with functions, events, errors, and constructor."
  @type parsed_abi :: %{
          functions: [function_info()],
          events: [event_info()],
          errors: [error_info()],
          constructor: constructor_info()
        }

  @typedoc "Struct definition from Solidity source."
  @type struct_info :: %{name: String.t(), fields: [%{name: String.t(), ty: String.t()}]}

  @typedoc "Enum definition from Solidity source."
  @type enum_info :: %{name: String.t(), variants: [String.t()]}

  @typedoc "Constant definition from Solidity source."
  @type constant_info :: %{name: String.t(), ty: String.t(), value: String.t()}

  @typedoc "NatSpec documentation for a function."
  @type natspec :: %{
          notice: String.t(),
          params: %{String.t() => String.t()},
          returns: %{String.t() => String.t()}
        }

  @typedoc "Complete parsed Solidity source with structs, enums, constants, and NatSpec."
  @type parsed_sol :: %{
          functions: [function_info_with_natspec()],
          events: [event_info()],
          errors: [error_info()],
          constructor: constructor_info(),
          structs: [struct_info()],
          enums: [enum_info()],
          constants: [constant_info()]
        }

  @typedoc "Foundry-style remapping string such as `\"@aave/core-v3/=lib/aave-v3-core/\"`."
  @type remapping_string :: String.t()

  @typedoc "Options for resolved Solidity file parsing."
  @type parse_sol_file_opts :: [remappings: [remapping_string()], root_contract: String.t()]

  @typedoc "Resolved Solidity file graph and merged source."
  @type resolved_sol_file :: %{
          source: String.t(),
          files: [String.t()],
          root_contract: String.t()
        }

  # --- parse_abi_json ---

  api(:parse_abi_json, "Parse a Solidity ABI JSON string into structured Elixir data.",
    params: [
      json: [
        kind: :value,
        description: "ABI JSON string (standard solc output format — array of ABI items)"
      ]
    ],
    returns: %{
      type: "{:ok, parsed_abi()} | {:error, {:parse_error, String.t()}}",
      description: "Parsed ABI with :functions, :events, :errors, :constructor keys"
    }
  )

  @spec parse_abi_json(String.t()) :: {:ok, parsed_abi()} | {:error, {:parse_error, String.t()}}
  def parse_abi_json(_json), do: :erlang.nif_error(:nif_not_loaded)

  # --- parse_abi_json! ---

  api(:parse_abi_json!, "Parse a Solidity ABI JSON string. Raises on error.",
    params: [
      json: [
        kind: :value,
        description: "ABI JSON string (standard solc output format — array of ABI items)"
      ]
    ],
    returns: %{
      type: "parsed_abi()",
      description: "Parsed ABI with :functions, :events, :errors, :constructor keys"
    }
  )

  @spec parse_abi_json!(String.t()) :: parsed_abi()
  def parse_abi_json!(json) do
    case parse_abi_json(json) do
      {:ok, result} -> result
      {:error, {:parse_error, reason}} -> raise "ABI parse failed: #{reason}"
      {:error, reason} -> raise "ABI parse failed: #{inspect(reason)}"
    end
  end

  # --- parse_abi_file ---

  api(:parse_abi_file, "Read a file and parse its contents as Solidity ABI JSON.",
    params: [
      path: [
        kind: :value,
        description: "Path to an ABI JSON file (e.g. \"priv/abis/erc20.json\")"
      ]
    ],
    returns: %{
      type: "{:ok, parsed_abi()} | {:error, {:parse_error, String.t()} | {:file_error, String.t()}}",
      description: "Parsed ABI with :functions, :events, :errors, :constructor keys"
    }
  )

  @spec parse_abi_file(String.t()) ::
          {:ok, parsed_abi()} | {:error, {:parse_error, String.t()} | {:file_error, String.t()}}
  def parse_abi_file(path) do
    case File.read(path) do
      {:ok, contents} -> parse_abi_json(contents)
      {:error, reason} -> {:error, {:file_error, "#{path}: #{reason}"}}
    end
  end

  # --- parse_abi_file! ---

  api(:parse_abi_file!, "Read a file and parse its contents as Solidity ABI JSON. Raises on error.",
    params: [
      path: [
        kind: :value,
        description: "Path to an ABI JSON file (e.g. \"priv/abis/erc20.json\")"
      ]
    ],
    returns: %{
      type: "parsed_abi()",
      description: "Parsed ABI with :functions, :events, :errors, :constructor keys"
    }
  )

  @spec parse_abi_file!(String.t()) :: parsed_abi()
  def parse_abi_file!(path) do
    case parse_abi_file(path) do
      {:ok, result} -> result
      {:error, {:parse_error, reason}} -> raise "ABI parse failed: #{reason}"
      {:error, {:file_error, reason}} -> raise "ABI file error: #{reason}"
      {:error, reason} -> raise "ABI error: #{inspect(reason)}"
    end
  end

  # --- parse_sol ---

  api(
    :parse_sol,
    "Parse a Solidity source string into structured Elixir data with structs, enums, and NatSpec.",
    params: [
      source: [
        kind: :value,
        description: "Solidity source code string (e.g. an interface definition)"
      ]
    ],
    returns: %{
      type: "{:ok, parsed_sol()} | {:error, {:parse_error, String.t()}}",
      description:
        "Enriched parsed data with :functions, :events, :errors, :constructor, :structs, :enums, :constants keys"
    }
  )

  @spec parse_sol(String.t()) :: {:ok, parsed_sol()} | {:error, {:parse_error, String.t()}}
  def parse_sol(_source), do: :erlang.nif_error(:nif_not_loaded)

  # --- parse_sol! ---

  api(:parse_sol!, "Parse a Solidity source string. Raises on error.",
    params: [
      source: [
        kind: :value,
        description: "Solidity source code string (e.g. an interface definition)"
      ]
    ],
    returns: %{
      type: "parsed_sol()",
      description:
        "Enriched parsed data with :functions, :events, :errors, :constructor, :structs, :enums, :constants keys"
    }
  )

  @spec parse_sol!(String.t()) :: parsed_sol()
  def parse_sol!(source) do
    case parse_sol(source) do
      {:ok, result} -> result
      {:error, {:parse_error, reason}} -> raise "Solidity parse failed: #{reason}"
      {:error, reason} -> raise "Solidity parse failed: #{inspect(reason)}"
    end
  end

  # --- resolve_sol_file ---

  api(:resolve_sol_file, "Resolve a root Solidity file, its imports, and remappings.",
    params: [
      path: [
        kind: :value,
        description: "Path to the root .sol file"
      ],
      opts: [
        kind: :value,
        description:
          "Keyword opts. Supports :root_contract override and :remappings with Foundry-style `prefix=target` entries"
      ]
    ],
    returns: %{
      type: "{:ok, resolved_sol_file()} | {:error, {:file_error, String.t()} | {:parse_error, String.t()}}",
      description: "Merged source, resolved file list, and selected root contract"
    }
  )

  @spec resolve_sol_file(String.t(), parse_sol_file_opts()) ::
          {:ok, resolved_sol_file()} | {:error, {:file_error, String.t()} | {:parse_error, String.t()}}
  def resolve_sol_file(path, opts \\ []) do
    with {:ok, absolute_path} <- expand_sol_path(path),
         {:ok, root_contract} <- resolve_root_contract_name(absolute_path, opts),
         {:ok, remappings} <- resolve_remappings(absolute_path, opts),
         {:ok, files} <- resolve_file_graph(absolute_path, remappings, MapSet.new()),
         {:ok, source} <- build_merged_source(files) do
      {:ok, %{source: source, files: files, root_contract: root_contract}}
    end
  end

  # --- resolve_sol_file! ---

  api(:resolve_sol_file!, "Resolve a root Solidity file. Raises on error.",
    params: [
      path: [
        kind: :value,
        description: "Path to the root .sol file"
      ],
      opts: [
        kind: :value,
        description:
          "Keyword opts. Supports :root_contract override and :remappings with Foundry-style `prefix=target` entries"
      ]
    ],
    returns: %{
      type: "resolved_sol_file()",
      description: "Merged source, resolved file list, and selected root contract"
    }
  )

  @spec resolve_sol_file!(String.t(), parse_sol_file_opts()) :: resolved_sol_file()
  def resolve_sol_file!(path, opts \\ []) do
    case resolve_sol_file(path, opts) do
      {:ok, result} -> result
      {:error, {:parse_error, reason}} -> raise "Solidity parse failed: #{reason}"
      {:error, {:file_error, reason}} -> raise "Solidity file error: #{reason}"
      {:error, reason} -> raise "Solidity error: #{inspect(reason)}"
    end
  end

  # --- parse_sol_file ---

  api(:parse_sol_file, "Resolve a Solidity file graph and parse the selected root contract.",
    params: [
      path: [
        kind: :value,
        description: "Path to a root .sol file (e.g. \"priv/contracts/IPool.sol\")"
      ],
      opts: [
        kind: :value,
        description:
          "Keyword opts. Supports :root_contract override and :remappings with Foundry-style `prefix=target` entries"
      ]
    ],
    returns: %{
      type: "{:ok, parsed_sol()} | {:error, {:parse_error, String.t()} | {:file_error, String.t()}}",
      description:
        "Enriched parsed data with :functions, :events, :errors, :constructor, :structs, :enums, :constants keys"
    }
  )

  @spec parse_sol_file(String.t(), parse_sol_file_opts()) ::
          {:ok, parsed_sol()} | {:error, {:parse_error, String.t()} | {:file_error, String.t()}}
  def parse_sol_file(path, opts \\ []) do
    with {:ok, resolution} <- resolve_sol_file(path, opts) do
      parse_resolved_sol_file(resolution, opts)
    end
  end

  # --- parse_sol_file! ---

  api(:parse_sol_file!, "Resolve a Solidity file graph and parse it. Raises on error.",
    params: [
      path: [
        kind: :value,
        description: "Path to a root .sol file (e.g. \"priv/contracts/IPool.sol\")"
      ],
      opts: [
        kind: :value,
        description:
          "Keyword opts. Supports :root_contract override and :remappings with Foundry-style `prefix=target` entries"
      ]
    ],
    returns: %{
      type: "parsed_sol()",
      description:
        "Enriched parsed data with :functions, :events, :errors, :constructor, :structs, :enums, :constants keys"
    }
  )

  @spec parse_sol_file!(String.t(), parse_sol_file_opts()) :: parsed_sol()
  def parse_sol_file!(path, opts \\ []) do
    case parse_sol_file(path, opts) do
      {:ok, result} -> result
      {:error, {:parse_error, reason}} -> raise "Solidity parse failed: #{reason}"
      {:error, {:file_error, reason}} -> raise "Solidity file error: #{reason}"
      {:error, reason} -> raise "Solidity error: #{inspect(reason)}"
    end
  end

  @doc false
  def __parse_sol_root__(_source, _root_contract), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  def __extract_sol_imports__(_source), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  # Parses a resolved source graph, preserving single-file compatibility for mismatched filenames.
  defp parse_resolved_sol_file(resolution, opts) do
    case __parse_sol_root__(resolution.source, resolution.root_contract) do
      {:error, {:parse_error, reason}} = error ->
        if allow_single_file_fallback?(resolution, opts) and
             String.contains?(reason, "root contract") do
          parse_sol(resolution.source)
        else
          error
        end

      result ->
        result
    end
  end

  @doc false
  # Falls back to full-source parsing only for legacy single-file callers without an explicit root override.
  defp allow_single_file_fallback?(resolution, opts) do
    length(resolution.files) == 1 and not Keyword.has_key?(opts, :root_contract)
  end

  @doc false
  # Expands a root Solidity file to an absolute path and verifies it exists.
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
  defp remappings_base_dir(nil, path), do: Path.dirname(path)
  defp remappings_base_dir(remappings_file, _path), do: Path.dirname(remappings_file)

  @doc false
  # Parses remappings.txt when present; absent files contribute no remappings.
  defp read_remappings_file(nil), do: {:ok, []}

  @doc false
  defp read_remappings_file(path) do
    case File.read(path) do
      {:ok, contents} -> parse_remapping_strings(String.split(contents, "\n"), Path.dirname(path), path)
      {:error, reason} -> {:error, {:file_error, "#{path}: #{reason}"}}
    end
  end

  @doc false
  # Parses Foundry-style remapping lines into normalized prefix/target tuples.
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
  defp parse_remapping_line("", _line_number, _base_dir, _source_label) do
    {:ok, nil}
  end

  @doc false
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
  defp invalid_remapping_message(:explicit, line_number, line) do
    "explicit remapping ##{line_number} is invalid: #{line}"
  end

  @doc false
  defp invalid_remapping_message(source_label, line_number, line) do
    "#{source_label}: invalid remapping on line #{line_number}: #{line}"
  end

  @doc false
  # Resolves a root file and all reachable imports using DFS post-order.
  defp resolve_file_graph(path, remappings, seen) do
    if MapSet.member?(seen, path) do
      {:ok, []}
    else
      with {:ok, source} <- File.read(path),
           {:ok, imports} <- __extract_sol_imports__(source),
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
  defp source_section(path, source) do
    IO.iodata_to_binary([@source_file_marker_prefix, path, "\n", source])
  end
end
