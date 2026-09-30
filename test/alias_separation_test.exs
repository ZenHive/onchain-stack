# Run without bootstrapping package dependencies:
# elixir test/alias_separation_test.exs
ExUnit.start()
Code.require_file("alias_graph.exs", __DIR__)

defmodule AliasSeparationTest do
  use ExUnit.Case, async: true

  @root Path.expand("..", __DIR__)
  @before elem(Code.eval_file("fixtures/aliases_before.exs", __DIR__), 0)
  @packages Path.wildcard(Path.join(@root, "packages/*/mix.exs"))

  for path <- @packages do
    @path path
    @relative Path.relative_to(path, @root)

    test "#{@relative} dispatch runs only formatting and compilation" do
      aliases = AliasGraph.read!(File.read!(@path))

      assert AliasGraph.expand(aliases, "check.dispatch") ==
               Enum.map(
                 ["format --check-formatted", "compile --warnings-as-errors"],
                 &inspect/1
               )
    end

    test "#{@relative} full QA retains its complete expanded graph" do
      aliases = AliasGraph.read!(File.read!(@path))
      baseline = Map.fetch!(@before, @relative)

      expected =
        baseline
        |> AliasGraph.expand("ci")
        |> Enum.map(fn step ->
          if @relative == "packages/onchain_aerodrome/mix.exs" and
               step == inspect("cmd env MIX_ENV=test mix test.json --cover --cover-threshold 65 --exclude integration") do
            # Preserve dispatch's Foundry bootstrap in the full coverage run.
            ~s|~s(cmd env MIX_ENV=test sh -c 'PATH="$HOME/.foundry/bin:$PATH" exec mix test.json --cover --cover-threshold 65 --exclude integration')|
          else
            step
          end
        end)

      expected =
        if @relative == "packages/onchain/mix.exs" do
          Enum.flat_map(expected, fn
            ~s("doctor --raise") = step ->
              [
                step,
                inspect("cmd env MIX_ENV=test mix doctor --raise --config-file .doctor-hieroglyph.exs"),
                inspect("cmd env MIX_ENV=test mix doctor --raise --config-file .doctor-cartouche.exs")
              ]

            ~s("cmd env MIX_ENV=test mix test.json --cover --cover-threshold 70 --exclude integration") ->
              [
                inspect("cmd env MIX_ENV=test mix onchain.coverage"),
                inspect("hieroglyph.manifest --check"),
                "&cargo_test/1",
                "&cargo_clippy/1"
              ]

            ~s("reach.check --dead-code --arch --smells") ->
              [inspect("reach.check --arch --smells")]

            step ->
              [step]
          end)
        else
          expected
        end

      # spec-tags: DIST-13
      expected =
        if @relative in ~w(packages/onchain/mix.exs packages/onchain_evm/mix.exs packages/onchain_tempo/mix.exs) do
          Enum.flat_map(expected, fn step ->
            if String.starts_with?(step, ~s("deps.audit)) do
              [step, "&cargo_audit/1"]
            else
              [step]
            end
          end)
        else
          expected
        end

      assert aliases["ci"] == [inspect("precommit.full")]
      refute inspect("check.dispatch") in aliases["precommit.full"]
      assert AliasGraph.expand(aliases, "ci") == expected
    end
  end

  test "root CI excludes the dev-only aggregate runtime dependencies" do
    source = File.read!(Path.join(@root, "mix.exs"))

    {_ast, cli} =
      source
      |> Code.string_to_quoted!()
      |> Macro.prewalk(nil, fn
        {:def, _, [{:cli, _, _}, [do: body]]} = node, _ -> {node, body}
        node, acc -> {node, acc}
      end)

    assert cli != nil
    {config, _} = Code.eval_quoted(cli)
    assert config[:preferred_envs][:ci] == :test
  end

  test "root dispatch still fails and full QA still delegates to all packages serially" do
    source = File.read!(Path.join(@root, "mix.exs"))
    aliases = AliasGraph.read!(source)
    assert aliases == Map.fetch!(@before, "mix.exs")

    assert aliases["ci"] == [
             inspect("onchain.bounds"),
             inspect("cmd elixir test/alias_separation_test.exs"),
             "&packages_ci/1"
           ]

    # Invoke the guard itself, without loading root dependencies.
    Mix.start()
    [guard] = aliases["check.dispatch"]
    {fun, []} = Code.eval_string(guard)
    assert_raise Mix.Error, ~r/for each package the task touches/, fn -> fun.([]) end

    assert source =~ "[] -> Mix.Tasks.Onchain.Bounds.packages()"
    assert source =~ "Enum.each(fn {package, index} ->"
    assert source =~ ~s(if status != 0 do)
    assert source =~ ~s(Mix.raise("mix ci failed)
  end
end
