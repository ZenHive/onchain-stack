defmodule Onchain.Aave.Contracts do
  @moduledoc """
  Aave V3 contract address registry.

  Pure-function lookup for known Aave protocol contract addresses. All other
  Aave modules (Pool, Oracle, UiPoolDataProvider) depend on this for addresses.

  ## Supported Networks

  Ethereum, Arbitrum, Optimism, Base, Polygon, Avalanche (all Aave V3 mainnet),
  and Sepolia (V3 testnet).

  ## Error Format

  - Unknown contract: `{:error, {:unknown_contract, key}}`
  - Unsupported network: `{:error, {:unsupported_network, network}}`

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `address/2` | Look up a contract's checksummed address |
  | `address!/2` | Same, raises on error |
  | `networks/0` | List supported networks |
  | `contracts/1` | List contract keys for a network |
  """

  use Descripex, namespace: "/aave/contracts"

  # Aave V3 canonical addresses — deployed via CREATE2, so arbitrum,
  # optimism, polygon, and avalanche share the same addresses.
  @aave_v3_canonical_pool "0x794a61358D6845594F94dc1DB02A252b5b4814aD"
  @aave_v3_canonical_provider "0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb"

  @addresses %{
    ethereum: %{
      pool_addresses_provider: "0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e",
      pool: "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2",
      oracle: "0x54586bE62E3c3580375aE3723C145253060Ca0C2",
      ui_pool_data_provider: "0x56b7A1012765C285afAC8b8F25C69Bf10ccfE978"
    },
    arbitrum: %{
      pool_addresses_provider: @aave_v3_canonical_provider,
      pool: @aave_v3_canonical_pool,
      oracle: "0xb56c2F0B653B2e0b10C9b928C8580Ac5Df02C7C7",
      ui_pool_data_provider: "0x13c833256BD767da2320d727a3691BAff3770E39"
    },
    optimism: %{
      pool_addresses_provider: @aave_v3_canonical_provider,
      pool: @aave_v3_canonical_pool,
      oracle: "0xD81eb3728a631871a7eBBaD631b5f424909f0c77",
      ui_pool_data_provider: "0xa6741111f4CcB5162Ec6A825465354Ed8c6F7095"
    },
    base: %{
      pool_addresses_provider: "0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D",
      pool: "0xA238Dd80C259a72e81d7e4664a9801593F98d1c5",
      oracle: "0x2Cc0Fc26eD4563A5ce5e8bdcfe1A2878676Ae156",
      ui_pool_data_provider: "0xb84A20e848baE3e13897934bB4e74E2225f4546B"
    },
    polygon: %{
      pool_addresses_provider: @aave_v3_canonical_provider,
      pool: @aave_v3_canonical_pool,
      oracle: "0xb023e699F5a33916Ea823A16485e259257cA8Bd1",
      ui_pool_data_provider: "0xFa1A7c4a8A63C9CAb150529c26f182cBB5500944"
    },
    avalanche: %{
      pool_addresses_provider: @aave_v3_canonical_provider,
      pool: @aave_v3_canonical_pool,
      oracle: "0xEBd36016B3eD09D4693Ed4251c67Bd858c3c7C9C",
      ui_pool_data_provider: "0x3518E8927A7827CDdAf841872453003CA95906A3"
    },
    # TODO(Task 6): Sepolia addresses — last verified 2026-03-09 via
    # PoolAddressesProvider.getPool/getPriceOracle and BGD Labs aave-address-book
    # (src/AaveV3Sepolia.sol). Re-verify on each Aave upgrade.
    sepolia: %{
      pool_addresses_provider: "0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A",
      pool: "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951",
      oracle: "0x2da88497588bf89281816106C7259e31AF45a663",
      ui_pool_data_provider: "0x69529987FA4A075D0C00B0128fa848dc9ebbE9CE",
      faucet: "0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D"
    }
  }

  # --- address ---

  api(:address, "Look up a contract's EIP-55 checksummed address.",
    params: [
      contract: [kind: :value, description: "Contract key atom, e.g. :pool, :oracle"],
      opts: [kind: :value, default: [], description: "Options: [network: :ethereum]"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Checksummed hex address",
      example: "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"
    }
  )

  @spec address(atom(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def address(contract, opts \\ []) do
    network = Keyword.get(opts, :network, :ethereum)

    case @addresses do
      %{^network => %{^contract => hex}} -> Onchain.Address.checksum(hex)
      %{^network => %{}} -> {:error, {:unknown_contract, contract}}
      %{} -> {:error, {:unsupported_network, network}}
    end
  end

  # --- address! ---

  api(:address!, "Look up a contract's checksummed address. Raises on error.",
    params: [
      contract: [kind: :value, description: "Contract key atom, e.g. :pool, :oracle"],
      opts: [kind: :value, default: [], description: "Options: [network: :ethereum]"]
    ],
    returns: %{
      type: :string,
      description: "Checksummed hex address"
    }
  )

  @spec address!(atom(), keyword()) :: String.t()
  def address!(contract, opts \\ []) do
    case address(contract, opts) do
      {:ok, addr} -> addr
      {:error, reason} -> raise "address lookup failed: #{inspect(reason)}"
    end
  end

  # --- networks ---

  api(:networks, "List supported networks.",
    params: [],
    returns: %{
      type: "[atom()]",
      description: "List of network atoms",
      example: "[:ethereum]"
    }
  )

  @spec networks() :: [atom()]
  def networks, do: Map.keys(@addresses)

  # --- contracts ---

  api(:contracts, "List available contract keys for a network.",
    params: [
      opts: [kind: :value, default: [], description: "Options: [network: :ethereum]"]
    ],
    returns: %{
      type: "{:ok, [atom()]} | {:error, {:unsupported_network, atom()}}",
      description: "List of contract key atoms"
    }
  )

  @spec contracts(keyword()) :: {:ok, [atom()]} | {:error, {:unsupported_network, atom()}}
  def contracts(opts \\ []) do
    network = Keyword.get(opts, :network, :ethereum)

    case @addresses do
      %{^network => network_map} -> {:ok, Map.keys(network_map)}
      %{} -> {:error, {:unsupported_network, network}}
    end
  end
end
