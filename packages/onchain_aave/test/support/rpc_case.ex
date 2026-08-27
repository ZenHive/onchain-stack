defmodule Onchain.RPCCase do
  @moduledoc false

  # Resolves RPC URL from env vars. Used by all integration tests needing RPC.

  @doc false
  def rpc_url do
    System.get_env("ETHEREUM_API_URL") || System.get_env("ETH_RPC_URL")
  end

  @doc false
  def rpc_url! do
    rpc_url() || flunk_missing_rpc()
  end

  @doc false
  def rpc_opts!, do: [rpc_url: rpc_url!()]

  # Declared `no_return()` because it only ever raises. Its sibling
  # `Onchain.SignerCase` inlines the same `flunk/1` call into the `||` branch, so
  # dialyzer infers a return type there; extracting it into a named function
  # here makes the raise-only path visible and warn-worthy without the spec.
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
