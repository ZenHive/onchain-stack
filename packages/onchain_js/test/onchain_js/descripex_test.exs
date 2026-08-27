defmodule OnchainJs.DescripexTest do
  @moduledoc """
  Guards the agent-facing contract: every documented public function in the
  annotated modules carries `api()` metadata, in `__api__/0` *and* in the BEAM
  doc chunk for every arity.

  Without this, hints rot silently — a function added later still compiles,
  still documents, and simply disappears from `OnchainJs.describe/2`.
  """

  use ExUnit.Case, async: true

  @annotated [OnchainJs.Runtime]

  # Public functions that carry `@doc false` and are therefore outside the
  # agent-facing surface: OTP callbacks and descripex's own introspection.
  @excluded [{:child_spec, 1}, {:__api__, 0}, {:__api__, 1}]

  defp documented_functions(module) do
    Enum.reject(module.__info__(:functions), fn {name, _arity} = fun ->
      fun in @excluded or String.starts_with?(Atom.to_string(name), "_")
    end)
  end

  defp doc_chunk_entries(module) do
    {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)

    for {{:function, name, arity}, _line, _sig, _doc, meta} <- docs,
        {name, arity} not in @excluded,
        do: {{name, arity}, meta}
  end

  describe "api() coverage" do
    test "every annotated module exposes __api__/0" do
      for module <- @annotated do
        assert function_exported?(module, :__api__, 0),
               "#{inspect(module)} is listed as annotated but has no __api__/0"
      end
    end

    test "every documented public function has an __api__ entry" do
      for module <- @annotated do
        declared = MapSet.new(module.__api__(), & &1.name)

        for {name, arity} <- documented_functions(module) do
          assert MapSet.member?(declared, name),
                 "#{inspect(module)}.#{name}/#{arity} has no api() declaration"
        end
      end
    end

    test "every arity carries :hints in the BEAM doc chunk" do
      for module <- @annotated,
          {{name, arity}, meta} <- doc_chunk_entries(module) do
        assert is_map(meta[:hints]),
               "#{inspect(module)}.#{name}/#{arity} is missing :hints in the doc chunk"
      end
    end
  end

  describe "declaration quality" do
    test "every declared param states a kind and a description" do
      for module <- @annotated,
          entry <- module.__api__(),
          {param, hints} <- entry.hints.params do
        assert hints[:kind] in [:value, :exchange_data],
               "#{inspect(module)}.#{entry.name} param #{param} has kind #{inspect(hints[:kind])}"

        assert is_binary(hints[:description]) and hints[:description] != "",
               "#{inspect(module)}.#{entry.name} param #{param} has no description"
      end
    end

    test "every :exchange_data param names where the value comes from" do
      for module <- @annotated,
          entry <- module.__api__(),
          {param, hints} <- entry.hints.params,
          hints[:kind] == :exchange_data do
        assert is_binary(hints[:source]) and hints[:source] != "",
               "#{inspect(module)}.#{entry.name} param #{param} is :exchange_data without a :source"
      end
    end

    test "every declaration states what it returns" do
      for module <- @annotated, entry <- module.__api__() do
        returns = entry.hints.returns

        assert is_map(returns) and is_binary(returns[:type]) and is_binary(returns[:description]),
               "#{inspect(module)}.#{entry.name} has no usable :returns declaration"
      end
    end

    test "param order matches the function's positional arguments" do
      # api() validates this at compile time; pinning it here means a future
      # reordering of a def's arguments fails loudly rather than silently
      # shifting what an agent passes where.
      eval = OnchainJs.Runtime.__api__(:eval)
      assert eval.param_order == [:runtime, :code, :opts]

      call = OnchainJs.Runtime.__api__(:call)
      assert call.param_order == [:runtime, :fn_name, :args, :opts]
    end
  end

  describe "progressive disclosure" do
    test "describe/0 lists the annotated modules" do
      overview = OnchainJs.describe()
      assert is_map(overview) or is_list(overview)
      assert inspect(overview) =~ "Runtime"
    end

    test "describe/1 lists the runtime's functions" do
      listing = OnchainJs.describe(:runtime)
      rendered = inspect(listing, limit: :infinity)

      for name <- ~w(start_link eval call stop apply_browser_stubs) do
        assert rendered =~ name, "describe(:runtime) does not mention #{name}"
      end
    end

    test "describe/2 returns callable detail for one function" do
      detail = OnchainJs.describe(:runtime, :eval)

      assert detail.name == :eval
      assert detail.arity == 3
      assert detail.defaults == 1
      assert detail.params.code.kind == :value
      assert detail.params.runtime.kind == :exchange_data
      assert detail.returns.type =~ "QuickBEAM.JSError"
    end

    test "describe/2 on an unknown function does not pretend it exists" do
      refute match?(%{name: :nope}, OnchainJs.describe(:runtime, :nope))
    end
  end

  describe "manifest" do
    test "the module set builds a JSON-serialisable manifest" do
      manifest = Descripex.Manifest.build(@annotated)

      assert {:ok, json} = Jason.encode(manifest)
      assert json =~ "apply_browser_stubs"
    end

    test "MCP tool generation names every declared function" do
      tools = Descripex.MCP.tools(@annotated)
      names = Enum.map(tools, & &1.name)

      assert length(names) == length(OnchainJs.Runtime.__api__())
      assert Enum.any?(names, &(&1 =~ "eval"))
    end
  end
end
