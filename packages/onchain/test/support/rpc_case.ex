defmodule Onchain.RPCCase do
  @moduledoc false

  # Resolves RPC URL from env vars. Used by all integration tests needing RPC.

  @doc false
  @spec rpc_url() :: String.t() | nil
  def rpc_url do
    System.get_env("ETHEREUM_API_URL") || System.get_env("ETH_RPC_URL")
  end

  @doc false
  @spec rpc_url!() :: String.t()
  def rpc_url! do
    rpc_url() || flunk_missing_rpc()
  end

  @spec flunk_missing_rpc() :: no_return()
  defp flunk_missing_rpc do
    ExUnit.Assertions.flunk("""
    Missing Ethereum RPC URL!

    Set one of these environment variables:
      export ETHEREUM_API_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
      export ETH_RPC_URL="https://mainnet.infura.io/v3/YOUR_KEY"
    """)
  end

  @doc false
  # Hosted / plan-limited endpoint used to pin node-capability refusals. The
  # default ETHEREUM_API_URL in this repo is the archive node, which implements
  # methods a consumer's Alchemy/Infura URL refuses.
  @spec limited_rpc_url() :: String.t() | nil
  def limited_rpc_url do
    System.get_env("ETHEREUM_LIMITED_RPC_URL") || System.get_env("ETHEREUM_ALCHEMY_URL")
  end

  @doc false
  @spec limited_rpc_url!() :: String.t()
  def limited_rpc_url! do
    limited_rpc_url() || flunk_missing_limited_rpc()
  end

  @spec flunk_missing_limited_rpc() :: no_return()
  defp flunk_missing_limited_rpc do
    ExUnit.Assertions.flunk("""
    Missing limited Ethereum RPC URL!

    These tests need a hosted / plan-limited endpoint (Alchemy, Infura, or similar),
    not the archive node at localhost:8545. Set one of:

      export ETHEREUM_LIMITED_RPC_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
      export ETHEREUM_ALCHEMY_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
    """)
  end
end
