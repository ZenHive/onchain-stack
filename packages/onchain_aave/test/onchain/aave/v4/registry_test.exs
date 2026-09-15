defmodule Onchain.Aave.V4.RegistryTest do
  use ExUnit.Case, async: true

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.V4.Hub
  alias Onchain.RPCStub

  @fixture Path.expand("../../../fixtures/v4_safe.csv", __DIR__)

  test "every pinned address-book row resolves with its canonical key" do
    rows = @fixture |> File.read!() |> String.split("\n", trim: true) |> tl()
    assert Enum.count_until(rows, 391) == 390

    for row <- rows do
      [expected, name, chain_id] = String.split(row, ",")
      [_namespace | labels] = String.split(name)
      network = if chain_id == "1", do: :ethereum, else: :avalanche
      key_name = registry_key(labels)
      {:ok, keys} = Contracts.v4_contracts(network: network)
      key = Enum.find(keys, &(Atom.to_string(&1) == key_name))
      assert key, "Missing #{name}"
      assert {:ok, actual} = Contracts.address(key, network: network)
      assert String.downcase(actual) == String.downcase(expected), name
    end
  end

  test "new tokenization spokes resolve by hub and asset" do
    assert {:ok, "0x7Df10B4A01350D2A1d95cFbE7c9207d7210A2663"} =
             Contracts.v4_tokenization_spoke(:global_dollar, :pt_usdg_24sep2026)

    assert {:ok, "0x1604D602f8A05CBA2d8Ff5d14DE4C3498f15B6B4"} =
             Contracts.v4_tokenization_spoke(:core, :wavax, network: :avalanche)

    assert {:error, {:unknown_tokenization_spoke, {:global_dollar, :weth}}} =
             Contracts.v4_tokenization_spoke(:global_dollar, :weth)

    assert {:error, {:unknown_hub, :global_dollar}} =
             Contracts.v4_tokenization_spoke(:global_dollar, :usdc, network: :avalanche)
  end

  test "legacy e-Spoke names remain aliases of the upstream spelling" do
    for family <- ~w(etherfi kelp lido), suffix <- ["", "_oracle"] do
      {:ok, keys} = Contracts.v4_contracts()
      names = Enum.map(["_spoke", "_e_spoke", "_espoke"], &("v4_" <> family <> &1 <> suffix))
      addresses = for key <- keys, Atom.to_string(key) in names, do: Contracts.address!(key)
      assert [_, _, _] = addresses
      assert [_] = Enum.uniq(addresses)
    end
  end

  test "Hub reads route a newly registered hub to its address" do
    expected = Contracts.address!(:v4_global_dollar_hub)
    selector = RPCStub.selector("getAssetCount()", [])

    url =
      RPCStub.start(fn request ->
        assert %{"method" => "eth_call", "params" => [call, "0x123"]} = request
        assert String.downcase(call["to"]) == String.downcase(expected)
        assert call["data"] == selector
        RPCStub.encode("(uint256)", [{6}])
      end)

    assert {:ok, 6} = Hub.get_asset_count(:global_dollar, [block: 0x123] ++ RPCStub.rpc_opts(url))
    assert {:error, {:unknown_hub, :unregistered}} = Hub.get_asset_count(:unregistered)
    assert {:ok, expected} = Hub.hub_address(:global_dollar)
    assert expected == Contracts.address!(:v4_global_dollar_hub)
    assert {:ok, _address} = Hub.hub_address(:core, network: :avalanche)
  end

  defp registry_key([category | labels])
       when category in ~w(HUBS SPOKES POSITION_MANAGERS EXTERNAL_LIBRARIES IR_STRATEGIES TOKENIZATION_SPOKES SPOKE_PRICE_FEEDS),
       do: registry_key(labels)

  defp registry_key(labels) do
    "v4_" <> (labels |> Enum.join("_") |> String.downcase() |> String.replace(~r/[^a-z0-9_]/, "_"))
  end
end
