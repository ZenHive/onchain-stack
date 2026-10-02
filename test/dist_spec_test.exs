# Run without bootstrapping package dependencies:
# elixir test/dist_spec_test.exs
ExUnit.start()
Mix.start()
Code.require_file("../lib/mix/tasks/onchain.bounds.ex", __DIR__)

defmodule DistSpecTest do
  # Guards the DIST rules that hold over the repo layout rather than one
  # package: sibling/3 resolution, bounds checking, and the crate split.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Onchain.Bounds

  @root Path.expand("..", __DIR__)

  setup do
    tmp = Path.join(System.tmp_dir!(), "dist_spec_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    publish = System.get_env("ONCHAIN_PUBLISH")

    on_exit(fn ->
      File.rm_rf!(tmp)
      if publish, do: System.put_env("ONCHAIN_PUBLISH", publish), else: System.delete_env("ONCHAIN_PUBLISH")
    end)

    {:ok, tmp: tmp}
  end

  # spec-tags: DIST-9
  describe "sibling/3 resolution" do
    for path <- Path.wildcard(Path.join(@root, "packages/*/mix.exs")),
        File.read!(path) =~ "defp sibling(" do
      @package path |> Path.dirname() |> Path.basename()

      test "#{@package} picks the path branch by marker and ONCHAIN_PUBLISH only", %{tmp: tmp} do
        sibling = load_sibling(@package, tmp)
        File.mkdir_p!(Path.join(tmp, "packages/onchain"))
        System.delete_env("ONCHAIN_PUBLISH")

        # The sibling directory exists, but without the marker this is a stranger's deps/.
        assert sibling.(:onchain, "~> 0.16", []) == {:onchain, "~> 0.16", []}

        File.write!(Path.join(tmp, ".onchain-monorepo-root"), "")

        assert {:onchain, opts} = sibling.(:onchain, "~> 0.16", only: :test)
        assert opts[:path] == Path.join(tmp, "packages/onchain")
        assert opts[:override] == true
        assert opts[:only] == :test

        System.put_env("ONCHAIN_PUBLISH", "1")
        assert sibling.(:onchain, "~> 0.16", []) == {:onchain, "~> 0.16", []}
      end
    end
  end

  # spec-tags: DIST-11
  describe "mix onchain.bounds" do
    test "passes on this checkout" do
      in_dir(@root, fn -> Bounds.run([]) end)
      assert_received {:mix_shell, :info, ["onchain.bounds: " <> _]}
    end

    test "fails when a requirement no longer admits the in-repo version", %{tmp: tmp} do
      for package <- Bounds.packages() do
        write_mix_exs(tmp, package, ~s|@version "1.0.0"|)
      end

      write_mix_exs(tmp, "onchain_aave", ~s|@version "0.5.0"\ndefp deps, do: [sibling(:onchain, "~> 0.16")]|)

      assert_raise Mix.Error, ~r/1 sibling requirement/, fn -> in_dir(tmp, fn -> Bounds.run([]) end) end

      write_mix_exs(tmp, "onchain_aave", ~s|@version "0.5.0"\ndefp deps, do: [sibling(:onchain, "~> 1.0")]|)
      in_dir(tmp, fn -> Bounds.run([]) end)
      assert_received {:mix_shell, :info, ["onchain.bounds: 1 sibling requirement(s) OK"]}
    end
  end

  # spec-tags: DIST-12
  describe "native crate split" do
    test "the core ABI crate resolves no Tempo, commonware or solar package" do
      crate = Path.join(@root, "packages/onchain/native/onchain_abi")

      for file <- ["Cargo.toml", "Cargo.lock"] do
        assert File.read!(Path.join(crate, file)) |> forbidden_crates() == [], "#{file} pulls a forbidden crate"
      end
    end

    test "Tempo and Solidity parsing live in their own packages' crates" do
      tempo = File.read!(Path.join(@root, "packages/onchain_tempo/native/onchain_tempo/Cargo.toml"))
      solidity = File.read!(Path.join(@root, "packages/onchain_evm/native/onchain_solidity/Cargo.toml"))

      assert tempo =~ ~r/^tempo-primitives\s*=/m
      assert solidity =~ ~r/^solar-parse\s*=/m
    end

    test "the scan trips on each forbidden crate (negative control)" do
      lock = """
      [[package]]
      name = "tempo-primitives"
      [[package]]
      name = "commonware-cryptography"
      [[package]]
      name = "solar-parse"
      """

      assert forbidden_crates(lock) == ["tempo-primitives", "commonware-cryptography", "solar-parse"]
      assert forbidden_crates(~s|tempo-primitives = "=1.11.0"|) == ["tempo-primitives"]
      assert forbidden_crates(~s|alloy-rlp = "0.3"\n# no tempo here|) == []
    end
  end

  # Compiles the package's own `sibling` clause as if its mix.exs sat at
  # tmp/packages/<package>/mix.exs, so `__DIR__` points into the scratch tree.
  defp load_sibling(package, tmp) do
    source = File.read!(Path.join(@root, "packages/#{package}/mix.exs"))
    {_ast, [clause]} = Macro.prewalk(Code.string_to_quoted!(source), [], &take_sibling/2)
    module = Module.concat(__MODULE__, "Sibling#{System.unique_integer([:positive])}")

    Code.compile_quoted(
      quote(do: defmodule(unquote(module), do: unquote(clause))),
      Path.join(tmp, "packages/#{package}/mix.exs")
    )

    &module.sibling/3
  end

  defp take_sibling({:defp, meta, [{:sibling, _, _} | _] = body}, acc), do: {nil, [{:def, meta, body} | acc]}
  defp take_sibling(node, acc), do: {node, acc}

  defp forbidden_crates(text) do
    ~r/(?:^name = "|^)((?:tempo|commonware|solar)[\w-]*)/m
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
  end

  defp write_mix_exs(tmp, package, body) do
    dir = Path.join(tmp, "packages/#{package}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "mix.exs"), "defmodule Fixture do\n#{body}\nend\n")
  end

  defp in_dir(dir, fun) do
    Mix.shell(Mix.Shell.Process)
    File.cd!(dir, fun)
  end
end
