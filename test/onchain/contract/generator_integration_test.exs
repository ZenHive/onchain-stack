defmodule Onchain.Contract.GeneratorIntegrationTest do
  use ExUnit.Case, async: true

  alias Onchain.Contract.Generator

  @moduletag :integration

  # Generated module from Chainlink ABI JSON
  defmodule ChainlinkModule do
    @moduledoc false
    use Generator,
      abi_json: File.read!(Path.join(:code.priv_dir(:onchain_evm), "abis/chainlink_aggregator.json"))
  end

  # Generated module from ERC-20 ABI JSON
  defmodule ERC20Module do
    @moduledoc false
    use Generator,
      abi_json: ~s([
        {"inputs":[{"name":"account","type":"address"}],"name":"balanceOf","outputs":[{"name":"","type":"uint256"}],"stateMutability":"view","type":"function"},
        {"inputs":[],"name":"decimals","outputs":[{"name":"","type":"uint8"}],"stateMutability":"view","type":"function"},
        {"inputs":[],"name":"symbol","outputs":[{"name":"","type":"string"}],"stateMutability":"view","type":"function"}
      ])
  end

  # Chainlink ETH/USD price feed on mainnet
  @chainlink_eth_usd "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419"
  # USDC on mainnet
  @usdc "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  # Vitalik's address
  @vitalik "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"

  describe "Chainlink generated module" do
    test "decimals returns 8 for ETH/USD feed" do
      rpc_url = Onchain.RPCCase.rpc_url!()

      assert {:ok, [8]} = ChainlinkModule.decimals(@chainlink_eth_usd, rpc_url: rpc_url)
    end

    test "version returns a positive integer" do
      rpc_url = Onchain.RPCCase.rpc_url!()

      assert {:ok, [version]} = ChainlinkModule.version(@chainlink_eth_usd, rpc_url: rpc_url)
      assert is_integer(version)
      assert version > 0
    end

    test "latest_round_data returns 5 values" do
      rpc_url = Onchain.RPCCase.rpc_url!()

      assert {:ok, values} = ChainlinkModule.latest_round_data(@chainlink_eth_usd, rpc_url: rpc_url)
      assert length(values) == 5
      # answer (ETH price in USD with 8 decimals) should be positive
      assert Enum.at(values, 1) > 0
    end

    test "bang variant works" do
      rpc_url = Onchain.RPCCase.rpc_url!()

      assert [8] = ChainlinkModule.decimals!(@chainlink_eth_usd, rpc_url: rpc_url)
    end
  end

  describe "ERC-20 generated module" do
    test "decimals returns 6 for USDC" do
      rpc_url = Onchain.RPCCase.rpc_url!()

      assert {:ok, [6]} = ERC20Module.decimals(@usdc, rpc_url: rpc_url)
    end

    test "symbol returns USDC" do
      rpc_url = Onchain.RPCCase.rpc_url!()

      assert {:ok, ["USDC"]} = ERC20Module.symbol(@usdc, rpc_url: rpc_url)
    end

    test "balance_of returns a non-negative integer" do
      rpc_url = Onchain.RPCCase.rpc_url!()

      assert {:ok, [balance]} = ERC20Module.balance_of(@usdc, @vitalik, rpc_url: rpc_url)
      assert is_integer(balance)
      assert balance >= 0
    end
  end
end
