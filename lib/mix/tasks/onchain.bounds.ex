defmodule Mix.Tasks.Onchain.Bounds do
  @shortdoc "Checks every declared sibling Hex requirement against the in-repo sibling version"

  @moduledoc """
  Verifies that every in-repo sibling requirement still admits the version that
  sibling actually carries in this checkout.

  This is the one failure class the monorepo introduces. Inside the repo a
  `sibling(:onchain, "~> 0.12")` call resolves to a path dep, so the `"~> 0.12"`
  half is never exercised — onchain can move to 1.0 and nothing local notices.
  It surfaces at `mix hex.publish` time, or worse, at a consumer's `mix deps.get`.

  ## Convention this task parses

  Sibling requirements are declared in `packages/<pkg>/mix.exs` as literal calls:

      sibling(:onchain, "~> 0.12")
      sibling(:onchain_evm, "~> 0.6", only: [:dev, :test])

  Both the name and the requirement must be literals — the task reads the source
  AST, it does not evaluate the file (evaluating a `mix.exs` would define eight
  `*.MixProject` modules inside the running Mix and drag the shared-helper load
  along with them).

  A package's own version is read from either `@version "x.y.z"` or a literal
  `version: "x.y.z"` in `project/0`.

  ## Usage

      mix onchain.bounds          # all packages
      mix onchain.bounds onchain  # only the named consumers
  """

  use Mix.Task

  @packages ~w(hieroglyph cartouche onchain onchain_aave onchain_aerodrome onchain_evm onchain_js onchain_tempo)

  @doc "The package roster, in cascade order (upstream first)."
  @spec packages() :: [String.t()]
  def packages, do: @packages

  @impl Mix.Task
  def run(args) do
    consumers = if args == [], do: @packages, else: args
    versions = Map.new(@packages, &{&1, version!(&1)})

    findings =
      consumers
      |> Enum.flat_map(fn consumer ->
        consumer |> siblings!() |> Enum.map(&check(consumer, &1, versions))
      end)

    Enum.each(findings, &Mix.shell().info(render(&1)))

    case Enum.reject(findings, &match?({:ok, _, _, _, _}, &1)) do
      [] ->
        Mix.shell().info("onchain.bounds: #{length(findings)} sibling requirement(s) OK")

      bad ->
        Mix.raise("onchain.bounds: #{length(bad)} sibling requirement(s) no longer admit the in-repo version")
    end
  end

  defp check(consumer, {name, req}, versions) do
    package = Atom.to_string(name)

    case Map.fetch(versions, package) do
      :error ->
        {:unknown, consumer, package, req, nil}

      {:ok, version} ->
        if Version.match?(version, req),
          do: {:ok, consumer, package, req, version},
          else: {:violation, consumer, package, req, version}
    end
  end

  defp render({:ok, consumer, package, req, version}),
    do: "  ok        #{consumer} -> #{package} #{req} admits #{version}"

  defp render({:violation, consumer, package, req, version}),
    do: "  VIOLATION #{consumer} -> #{package} #{req} does NOT admit the in-repo #{version}"

  defp render({:unknown, consumer, package, req, _}),
    do: "  UNKNOWN   #{consumer} -> #{package} #{req} names no package under packages/"

  # --- source parsing -------------------------------------------------------

  defp siblings!(package) do
    package
    |> ast!()
    |> collect(fn
      {:sibling, _meta, [name, req | _rest]} when is_atom(name) and is_binary(req) -> {name, req}
      _other -> nil
    end)
  end

  defp version!(package) do
    attribute =
      collect(ast!(package), fn
        {:@, _meta, [{:version, _, [value]}]} when is_binary(value) -> value
        _other -> nil
      end)

    literal =
      collect(ast!(package), fn
        {:version, value} when is_binary(value) -> value
        _other -> nil
      end)

    case attribute ++ literal do
      [version | _] -> version
      [] -> Mix.raise("onchain.bounds: no version literal found in #{mix_exs(package)}")
    end
  end

  defp ast!(package), do: package |> mix_exs() |> File.read!() |> Code.string_to_quoted!()

  defp mix_exs(package), do: Path.join([File.cwd!(), "packages", package, "mix.exs"])

  defp collect(ast, matcher) do
    {_ast, acc} =
      Macro.prewalk(ast, [], fn node, acc ->
        case matcher.(node) do
          nil -> {node, acc}
          hit -> {node, [hit | acc]}
        end
      end)

    Enum.reverse(acc)
  end
end
