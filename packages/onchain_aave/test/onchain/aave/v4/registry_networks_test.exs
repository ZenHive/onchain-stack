defmodule Onchain.Aave.V4.RegistryNetworksTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.V4OnlyRegistry

  test "networks includes deployments present only in V4" do
    source = File.read!(Path.expand("../../../../lib/onchain/aave/contracts.ex", __DIR__))

    ast =
      source
      |> String.replace("Onchain.Aave.Contracts", "Onchain.Aave.V4OnlyRegistry")
      |> String.replace("/aave/contracts", "/aave/test/v4_only_registry")
      |> Code.string_to_quoted!()
      |> Macro.prewalk(fn
        {:@, meta, [{:v4_addresses, attr_meta, [{:%{}, map_meta, networks}]}]} ->
          networks = Keyword.put(networks, :v4_only, Keyword.fetch!(networks, :ethereum))
          {:@, meta, [{:v4_addresses, attr_meta, [{:%{}, map_meta, networks}]}]}

        node ->
          node
      end)

    on_exit(fn ->
      :code.purge(V4OnlyRegistry)
      :code.delete(V4OnlyRegistry)
    end)

    [{registry, _bytecode}] = Code.compile_quoted(ast)
    assert :v4_only in registry.networks()

    assert {:error, {:unsupported_network, :v4_only}} =
             registry.contracts(network: :v4_only)
  end
end
