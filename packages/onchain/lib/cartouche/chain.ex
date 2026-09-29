defmodule Cartouche.Chain do
  @moduledoc """
  Chain registry and chain-id parsing helpers.

  This registry is static and never performs network I/O. Callers may use
  `Cartouche.RPC.eth_config/1` as an independent read to cross-check a node's
  reported chain configuration, but its result does not mutate or control this
  table.
  """

  use Descripex, namespace: "/ethereum/chain"

  @chains %{
    mainnet: 1,
    ropsten: 2,
    rinkeby: 4,
    goerli: 5,
    kovan: 42,
    base: 8453,
    base_sepolia: 84_532,
    arbitrum: 42_161,
    arbitrum_sepolia: 421_614,
    mumbai: 80_001,
    sepolia: 11_155_111,
    optimism: 10,
    optimism_sepolia: 11_155_420,
    world_chain: 480,
    world_chain_sepolia: 4801,
    unichain: 130,
    avalanche: 43_114,
    bnb_smart_chain: 56,
    hyper_evm: 999,
    lens: 232,
    polygon: 137,
    sonic: 146,
    ink: 57_073,
    plume: 98_866
  }

  api(:parse_id, "Parse an Ethereum chain id from either a numeric id or a known chain name.",
    params: [
      chain_id: [
        kind: :value,
        description: "Ethereum chain id integer or known chain atom such as `:mainnet`, `:sepolia`, or `:base`."
      ]
    ],
    returns: %{
      type: :integer,
      description: "Ethereum chain id integer suitable for signing, RPC requests, and EIP-155 recovery-bit math."
    }
  )

  @doc ~S"""
  Parses a chain id, which can be given as an integer or an atom of a known network.

  ## Examples

      iex> Cartouche.Chain.parse_id(5)
      5

      iex> Cartouche.Chain.parse_id(:unichain)
      130
  """
  @spec parse_id(atom() | integer()) :: integer() | no_return()
  def parse_id(chain_id) when is_atom(chain_id), do: Map.fetch!(@chains, chain_id)
  def parse_id(chain_id) when is_integer(chain_id), do: chain_id

  api(:chain_id_value, "Resolve a chain id for transaction construction, defaulting to the application chain.",
    params: [
      chain_id: [
        kind: :value,
        description:
          "Ethereum chain id integer, known chain atom such as `:mainnet`, or `nil` for the application default."
      ]
    ],
    returns: %{
      type: :integer,
      description: "Ethereum chain id integer suitable for typed transaction construction."
    }
  )

  @doc ~S"""
  Resolves a chain id for transaction construction, defaulting to the application chain.

  ## Examples

      iex> Cartouche.Chain.chain_id_value(:goerli)
      5

      iex> Cartouche.Chain.chain_id_value(42)
      42
  """
  @spec chain_id_value(atom() | integer() | nil) :: integer()
  def chain_id_value(nil), do: Cartouche.Application.chain_id()
  def chain_id_value(chain_id), do: parse_id(chain_id)
end
