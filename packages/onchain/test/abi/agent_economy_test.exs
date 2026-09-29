defmodule ABI.AgentEconomyTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Hieroglyph.Manifest

  @annotated_modules [
    ABI,
    ABI.Event,
    ABI.FunctionSelector,
    ABI.TypeEncoder,
    ABI.TypeDecoder,
    ABI.Math
  ]

  # These are `@doc false` internal helpers, deliberately not in the API
  # surface. The cross-check below skips them so they don't trip the
  # "exported but not declared with api()" guard.
  @doc_false_exports MapSet.new([
                       {ABI.FunctionSelector, :dynamic?, 1},
                       {ABI.FunctionSelector, :get_function_type, 1},
                       {ABI.FunctionSelector, :get_state_mutability, 1}
                     ])

  describe "api() annotations" do
    for mod <- @annotated_modules do
      test "#{inspect(mod)} has __api__/0 with hints for all declared functions" do
        mod = unquote(mod)
        entries = mod.__api__()

        assert is_list(entries), "#{inspect(mod)}.__api__() should return a list"
        assert entries != [], "#{inspect(mod)}.__api__() should not be empty"

        for entry <- entries do
          assert is_map(entry.hints),
                 "#{inspect(mod)}.#{entry.name}/#{entry.arity} missing :hints"

          assert is_binary(entry.hints.description),
                 "#{inspect(mod)}.#{entry.name}/#{entry.arity} missing hints.description"
        end
      end
    end

    test "all public functions in annotated modules have hints metadata" do
      framework_skip = [
        :module_info,
        :__info__,
        :__api__,
        :__struct__,
        :describe,
        :__descripex_modules__,
        :behaviour_info,
        :"MACRO-__using__"
      ]

      for mod <- @annotated_modules do
        api_arities =
          for entry <- mod.__api__(),
              defaults = Map.get(entry, :defaults, 0),
              a <- (entry.arity - defaults)..entry.arity,
              into: MapSet.new(),
              do: {entry.name, a}

        for {func_name, arity} <- mod.module_info(:exports),
            func_name not in framework_skip,
            not MapSet.member?(@doc_false_exports, {mod, func_name, arity}) do
          assert MapSet.member?(api_arities, {func_name, arity}),
                 "#{inspect(mod)}.#{func_name}/#{arity} is exported but not declared with api()"
        end
      end
    end
  end

  describe "Discoverable (ABI.describe/0-2)" do
    test "describe/0 returns overview of all annotated modules" do
      overview = ABI.describe()

      assert is_list(overview)
      assert length(overview) == length(@annotated_modules)

      module_names = Enum.map(overview, & &1.module)

      for mod <- @annotated_modules do
        assert mod in module_names, "#{inspect(mod)} missing from ABI.describe()"
      end
    end

    test "describe/1 with short name returns function list" do
      functions = ABI.describe(:abi)

      assert is_list(functions)
      func_names = Enum.map(functions, & &1.name)
      assert :encode in func_names
      assert :decode in func_names
      assert :method_id in func_names
    end

    test "describe/1 with full module name works" do
      functions = ABI.describe(ABI.Math)

      assert is_list(functions)
      func_names = Enum.map(functions, & &1.name)
      assert :pad in func_names
      assert :unpad in func_names
    end

    test "describe/2 returns full function detail" do
      detail = ABI.describe(:abi, :encode)

      assert is_map(detail)
      assert detail.name == :encode
      assert is_binary(detail.description)
    end

    test "describe/2 returns nil for unknown function" do
      assert ABI.describe(:abi, :nonexistent) == nil
    end

    test "__descripex_modules__/0 returns the module list" do
      modules = ABI.__descripex_modules__()
      assert modules == @annotated_modules
    end
  end

  describe "namespace assignment" do
    test "ABI top-level has /abi namespace" do
      {:docs_v1, _, _, _, _moduledoc, meta, _} = Code.fetch_docs(ABI)
      assert meta[:namespace] == "/abi"
    end

    test "selector modules have /selector namespace" do
      for mod <- [ABI.Event, ABI.FunctionSelector] do
        {:docs_v1, _, _, _, _, meta, _} = Code.fetch_docs(mod)

        assert meta[:namespace] == "/selector",
               "#{inspect(mod)} should have namespace /selector, got #{inspect(meta[:namespace])}"
      end
    end

    test "codec modules have /codec namespace" do
      for mod <- [ABI.TypeEncoder, ABI.TypeDecoder] do
        {:docs_v1, _, _, _, _, meta, _} = Code.fetch_docs(mod)

        assert meta[:namespace] == "/codec",
               "#{inspect(mod)} should have namespace /codec, got #{inspect(meta[:namespace])}"
      end
    end

    test "Math has /math namespace" do
      {:docs_v1, _, _, _, _, meta, _} = Code.fetch_docs(ABI.Math)
      assert meta[:namespace] == "/math"
    end
  end

  describe "mix hieroglyph.manifest" do
    test "writes descripex JSON to a custom output path" do
      out = tmp_manifest()

      try do
        Manifest.run([out])

        assert %{"modules" => modules} = Jason.decode!(File.read!(out))
        assert Enum.any?(modules, &(&1["module"] == "ABI"))
      after
        File.rm(out)
      end
    end

    test "--check passes when the committed manifest matches, ignoring generated_at" do
      out = tmp_manifest()

      try do
        Manifest.run([out])
        original = File.read!(out)

        Manifest.run(["--check", out])

        assert File.read!(out) == original
      after
        File.rm(out)
      end
    end

    test "--check fails with a readable diff when the committed manifest has drifted" do
      out = tmp_manifest()

      try do
        Manifest.run([out])

        mutated =
          out
          |> File.read!()
          |> String.replace(~s("version": "1.0"), ~s("version": "0.0"))

        File.write!(out, mutated)

        error =
          assert_raise Mix.Error, fn ->
            Manifest.run(["--check", out])
          end

        assert error.message =~ "stale"
        assert error.message =~ ~s(-  "version": "0.0")
        assert error.message =~ ~s(+  "version": "1.0")
      after
        File.rm(out)
      end
    end
  end

  @spec tmp_manifest() :: Path.t()
  defp tmp_manifest do
    Path.join(System.tmp_dir!(), "manifest_#{System.unique_integer([:positive])}.json")
  end
end
