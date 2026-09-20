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

      assert aliases["ci"] == [inspect("precommit.full")]
      refute inspect("check.dispatch") in aliases["precommit.full"]
      assert AliasGraph.expand(aliases, "ci") == expected
    end
  end

  test "root dispatch still fails and full QA still delegates to all packages serially" do
    source = File.read!(Path.join(@root, "mix.exs"))
    aliases = AliasGraph.read!(source)
    assert aliases == Map.fetch!(@before, "mix.exs")
    assert aliases["ci"] == [inspect("onchain.bounds"), "&packages_ci/1"]

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
