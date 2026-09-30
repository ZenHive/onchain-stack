defmodule ABI.AlloyCacheTest do
  # Resets the shared caches, so nothing else may run concurrently; the suite
  # otherwise fills the 1,024-entry schema cache before this module runs.
  use ExUnit.Case, async: false

  alias ABI.Alloy
  alias ABI.FunctionSelector

  setup do
    :persistent_term.erase({Alloy, :schema})
    :persistent_term.erase({Alloy, :signature})
    :ok
  end

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

  # spec-tags: NIF-7
  test "concurrent misses in the same cache keep every entry" do
    selectors = for n <- 1..200, do: %FunctionSelector{function: "same_cache_probe_#{n}", types: []}

    signatures =
      selectors
      |> Enum.map(&Task.async(fn -> Alloy.signature(&1, :event) end))
      |> Task.await_many()

    cache = :persistent_term.get({Alloy, :signature})

    for {selector, signature} <- Enum.zip(selectors, signatures) do
      assert Map.fetch!(cache, {:event, selector}) == signature
    end
  end
end
