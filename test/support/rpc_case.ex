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

  @doc false
  @spec flunk_missing_rpc() :: no_return()
  defp flunk_missing_rpc do
    ExUnit.Assertions.flunk("""
    Missing Ethereum RPC URL!

    Set one of these environment variables:
      export ETHEREUM_API_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
      export ETH_RPC_URL="https://mainnet.infura.io/v3/YOUR_KEY"
    """)
  end
end
