defmodule Onchain.Aave.V4.RegistryIntegrationTest do
  use ExUnit.Case, async: true

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.V4.Hub
  alias Onchain.Aave.V4.Spoke

  @moduletag :integration
  @ethereum_block 25_985_721
  @avalanche_block 95_376_891

  test "Global Dollar Hub has assets at the pinned Ethereum block" do
    rpc_url =
      System.get_env("ETHEREUM_API_URL") || System.get_env("ETH_RPC_URL") ||
        flunk("Missing Ethereum RPC: export ETHEREUM_API_URL=\"https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY\"")

    assert {:ok, count} = Hub.get_asset_count(:global_dollar, rpc_url: rpc_url, block: @ethereum_block)
    assert count == 6
  end

  test "Avalanche Main Spoke has reserves at the pinned Avalanche block" do
    rpc_url =
      System.get_env("AVALANCHE_RPC_URL") ||
        flunk("Missing Avalanche RPC: export AVALANCHE_RPC_URL=\"https://api.avax.network/ext/bc/C/rpc\"")

    assert {:ok, spoke} = Contracts.address(:v4_main_spoke, network: :avalanche)

    assert {:ok, count} =
             Spoke.get_reserve_count(spoke, network: :avalanche, rpc_url: rpc_url, block: @avalanche_block)

    assert count == 6
  end
end
