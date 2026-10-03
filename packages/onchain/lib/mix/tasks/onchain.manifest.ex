defmodule Mix.Tasks.Onchain.Manifest do
  @shortdoc "Generate api_manifest.json from descripex metadata"

  @moduledoc """
  Generates a static `api_manifest.json` from the library's descripex annotations.

  The manifest is a JSON-serializable representation of every public function
  in the library — params, return types, errors, specs, and descriptions.
  Suitable for downstream codegen (generated contract bindings), agent
  discovery, validators, and contract-stability diffs across onchain version
  bumps.

      mix onchain.manifest
      mix onchain.manifest path/to/output.json
      mix onchain.manifest --check
      mix onchain.manifest --check path/to/output.json

  `--check` regenerates the manifest in memory and compares it against the
  committed file, ignoring only `generated_at`. Exits non-zero with a
  readable diff when they differ. Wired into `mix ci` so a descripex
  upgrade or an `api()` edit cannot silently drift the artifact.

  Static output uses the Unix epoch for `generated_at` and sorts map keys,
  including the generated descripex contract blocks, for reproducible bytes.

  Uses `Onchain.ABI.__descripex_modules__/0` as the single source of truth for which
  modules to include. Output defaults to `api_manifest.json` in the project root.
  """

  use Mix.Task

  alias Descripex.Manifest

  @default_output "api_manifest.json"

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {opts, positional} = OptionParser.parse!(args, strict: [check: :boolean])
    output_file = List.first(positional) || @default_output
    modules = Onchain.ABI.__descripex_modules__()

    manifest =
      modules
      |> Manifest.build()
      |> Map.put(:generated_at, "1970-01-01T00:00:00Z")
      |> Map.update!(:modules, &Enum.zip_with(modules, &1, fn module, entry -> canonical_module(module, entry) end))

    if opts[:check] do
      check!(output_file, manifest)
    else
      write!(output_file, manifest)
    end
  end

  @spec canonical_module(module(), map()) :: map()
  defp canonical_module(module, entry) do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)

    contracts =
      for {{:function, name, arity}, _, _, _, %{hints: hints}} <- docs,
          into: %{},
          do: {{Atom.to_string(name), arity}, Map.delete(hints, :description)}

    Map.update!(entry, :functions, &Enum.map(&1, fn function -> canonical_function(function, contracts) end))
  end

  @spec canonical_function(map(), map()) :: map()
  defp canonical_function(function, contracts) do
    case {function.description, Map.fetch(contracts, {function.name, function.arity})} do
      {description, {:ok, contract}} when is_binary(description) ->
        literal = inspect(contract, pretty: true, limit: :infinity, custom_options: [sort_maps: true])

        # Descripex embeds unsorted inspect output at compile time. Use the
        # doc hints (before runtime enrichment) to retain its shape.
        description =
          Regex.replace(~r/```elixir\n# descripex:contract\n.*?\n```/s, description, fn _ ->
            "```elixir\n# descripex:contract\n#{literal}\n```"
          end)

        %{function | description: description}

      _ ->
        function
    end
  end

  @spec ordered_json(term()) :: term()
  defp ordered_json(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), ordered_json(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Jason.OrderedObject.new()
  end

  defp ordered_json(list) when is_list(list), do: Enum.map(list, &ordered_json/1)
  defp ordered_json(value), do: value

  @spec write!(Path.t(), map()) :: :ok
  defp write!(output_file, manifest) do
    File.write!(output_file, Jason.encode!(ordered_json(manifest), pretty: true))
    count = Enum.sum_by(manifest.modules, &length(&1.functions))

    Mix.shell().info("Generated #{output_file} (#{length(manifest.modules)} modules, #{count} entries)")
  end

  @spec check!(Path.t(), map()) :: :ok
  defp check!(path, manifest) do
    generated = comparable(Jason.decode!(Jason.encode!(manifest)))
    committed = comparable(Jason.decode!(File.read!(path)))

    if generated == committed do
      Mix.shell().info("#{path} is up to date")
    else
      Mix.raise("""
      #{path} is stale (ignoring generated_at). Re-run `mix onchain.manifest` and commit the result.

      #{readable_diff(committed, generated)}
      """)
    end
  end

  @spec comparable(map()) :: map()
  defp comparable(map) when is_map(map), do: Map.delete(map, "generated_at")

  @spec readable_diff(map(), map()) :: String.t()
  defp readable_diff(committed, generated) do
    left = committed |> Jason.encode!(pretty: true) |> String.split("\n")
    right = generated |> Jason.encode!(pretty: true) |> String.split("\n")

    left
    |> List.myers_difference(right)
    |> Enum.flat_map(&diff_hunk/1)
    |> Enum.join("\n")
  end

  @spec diff_hunk({:eq | :del | :ins, [String.t()]}) :: [String.t()]
  defp diff_hunk({:eq, [_, _, _, _, _, _, _ | _] = lines}) do
    prefix = Enum.map(Enum.take(lines, 3), &(" " <> &1))
    suffix = Enum.map(Enum.take(lines, -3), &(" " <> &1))
    prefix ++ [" ..."] ++ suffix
  end

  defp diff_hunk({:eq, lines}), do: Enum.map(lines, &(" " <> &1))
  defp diff_hunk({:del, lines}), do: Enum.map(lines, &("-" <> &1))
  defp diff_hunk({:ins, lines}), do: Enum.map(lines, &("+" <> &1))
end
