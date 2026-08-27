defmodule Mix.Tasks.Hieroglyph.Manifest do
  @shortdoc "Generate api_manifest.json from descripex metadata"

  @moduledoc """
  Generates a static `api_manifest.json` from the library's descripex annotations.

  The manifest is a JSON-serializable representation of every public function
  in the library — params, return types, errors, specs, and descriptions.
  Suitable for downstream codegen (cartouche-generated contract bindings),
  agent discovery, validators, and CI contract-stability diffs across
  hieroglyph version bumps.

      mix hieroglyph.manifest
      mix hieroglyph.manifest path/to/output.json
      mix hieroglyph.manifest --check
      mix hieroglyph.manifest --check path/to/output.json

  `--check` regenerates the manifest in memory and compares it against the
  committed file, ignoring only `generated_at`. Exits non-zero with a
  readable diff when they differ. Wired into `mix ci` so a descripex
  upgrade or an `api()` edit cannot silently drift the artifact.

  Uses `ABI.__descripex_modules__/0` as the single source of truth for which
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
    manifest = Manifest.build(ABI.__descripex_modules__())

    if opts[:check] do
      check!(output_file, manifest)
    else
      write!(output_file, manifest)
    end
  end

  @spec write!(Path.t(), map()) :: :ok
  defp write!(output_file, manifest) do
    File.write!(output_file, Jason.encode!(manifest, pretty: true))
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
      #{path} is stale (ignoring generated_at). Re-run `mix hieroglyph.manifest` and commit the result.

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
  defp diff_hunk({:eq, lines}) when length(lines) > 6 do
    prefix = Enum.map(Enum.take(lines, 3), &(" " <> &1))
    suffix = Enum.map(Enum.take(lines, -3), &(" " <> &1))
    prefix ++ [" ..."] ++ suffix
  end

  defp diff_hunk({:eq, lines}), do: Enum.map(lines, &(" " <> &1))
  defp diff_hunk({:del, lines}), do: Enum.map(lines, &("-" <> &1))
  defp diff_hunk({:ins, lines}), do: Enum.map(lines, &("+" <> &1))
end
