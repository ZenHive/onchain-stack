defmodule OnchainAaveTest do
  use ExUnit.Case

  # Modules deliberately kept out of `OnchainAave.describe/0`: `Onchain.Aave.Opts`
  # is an internal option-splitting helper with no public surface, and
  # `OnchainAave` is the discovery entry point itself.
  @not_discoverable [OnchainAave, Onchain.Aave.Opts]

  test "discoverable modules are listed" do
    modules = OnchainAave.describe()

    assert is_list(modules)
    assert modules != []
  end

  # A hardcoded module count drifts silently under parallel development: two
  # branches each add one module and each bump the count by one, so the merged
  # list holds more modules than either branch asserted. Derive the expectation
  # from the compiled application instead — then a module that forgets to
  # register fails here instead of reaching consumers undiscoverable.
  test "every compiled module is either discoverable or explicitly internal" do
    {:ok, compiled} = :application.get_key(:onchain_aave, :modules)

    discoverable = MapSet.new(OnchainAave.describe(), & &1.module)

    unregistered =
      compiled
      |> Enum.reject(&test_support?/1)
      |> MapSet.new()
      |> MapSet.difference(discoverable)
      |> MapSet.difference(MapSet.new(@not_discoverable))
      |> MapSet.to_list()

    assert unregistered == [],
           "modules missing from OnchainAave.describe/0: #{inspect(unregistered)} — " <>
             "add them to `use Descripex.Discoverable` in lib/onchain_aave.ex, " <>
             "or to @not_discoverable here if they are internal"
  end

  # `elixirc_paths(:test)` compiles test/support into the application, so its
  # case templates show up in the module list. Detect them by source path rather
  # than by name, so a new support module needs no edit here.
  defp test_support?(module) do
    compile_info = module.module_info(:compile)
    source = compile_info |> Keyword.get(:source, ~c"") |> to_string()
    String.contains?(source, "/test/support/")
  end
end
