defmodule ABI.AlloyCacheTest do
  use ExUnit.Case, async: false

  alias ABI.Alloy
  alias ABI.FunctionSelector

  # spec-tags: NIF-7
  test "concurrent schema and signature misses keep both cache entries" do
    for n <- 1..32 do
      types = [%{type: {:uint, 256}}, %{type: {:bytes, n}}]
      selector = %FunctionSelector{function: "cache_probe_#{n}", types: [%{type: {:bytes, n}}]}

      [schema, signature] =
        Task.await_many([
          Task.async(fn -> Alloy.schema(types) end),
          Task.async(fn -> Alloy.signature(selector, :function) end)
        ])

      assert Map.fetch!(:persistent_term.get({Alloy, :schema}), {types, <<>>}) == schema
      assert Map.fetch!(:persistent_term.get({Alloy, :signature}), {:function, selector}) == signature
    end
  end
end
