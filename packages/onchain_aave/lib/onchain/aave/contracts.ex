defmodule Onchain.Aave.Contracts do
  @moduledoc """
  Aave V3 + V4 contract address registry.

  Pure-function lookup for known Aave protocol contract addresses. All other
  Aave modules (Pool, Oracle, UiPoolDataProvider) depend on this for addresses.

  ## Supported Networks

  Ethereum, Arbitrum, Optimism, Base, Polygon, Avalanche (all Aave V3 mainnet),
  and Sepolia (V3 testnet). Aave V4 is Ethereum-mainnet only as of 2026-04.

  ## V4 Address Shape

  V4's Hub-and-Spoke deployment exposes ~34 singleton contracts (infrastructure,
  Position Managers, Hubs, Spokes, per-Spoke oracles) plus 31 ERC-4626
  Tokenization Spokes. Singletons use flat `:v4_`-prefixed atoms resolved by
  `address/2` (e.g. `:v4_core_hub`, `:v4_main_spoke`, `:v4_main_spoke_oracle`).
  Tokenization Spokes use the nested `v4_tokenization_spoke/3` lookup keyed by
  `{hub, asset}` to avoid flooding the atom registry with 31 flat keys.

  V4 addresses are sourced from `V4_SCOPING.md` (the V4 source of truth).

  ## Error Format

  - Unknown contract: `{:error, {:unknown_contract, key}}`
  - Unknown V4 hub: `{:error, {:unknown_hub, hub}}`
  - Unknown V4 tokenization spoke: `{:error, {:unknown_tokenization_spoke, {hub, asset}}}`
  - Unsupported network: `{:error, {:unsupported_network, network}}`

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `address/2` | Look up a V3 or V4 singleton contract's checksummed address |
  | `address!/2` | Same, raises on error |
  | `v4_tokenization_spoke/3` | Look up a V4 ERC-4626 Tokenization Spoke by `{hub, asset}` |
  | `networks/0` | List supported networks |
  | `contracts/1` | List V3 contract keys for a network |
  | `v4_contracts/1` | List V4 singleton contract keys for a network |
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
    # Sepolia addresses (roadmap task 6) — last verified 2026-03-09 via
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

  # Aave V4 singleton contracts (Ethereum mainnet only — V4 went live
  # 2026-03-30). Sourced from V4_SCOPING.md, which is itself pulled from the
  # bgd-labs aave-address-book `AaveV4Ethereum` entries. Re-verify on upgrades.
  @v4_addresses %{
    ethereum: %{
      # Infrastructure (top-level)
      v4_access_manager: "0x08aE3BE30958cDd1847ec58fFfd4C451a87fDF01",
      v4_hub_configurator: "0x1F0753480bB03EaA00863224602267B7E0525C3d",
      v4_spoke_configurator: "0x9BFFf48BFb5A7AE70c348d4d4cb97E8DEFa5389a",
      v4_config_engine: "0xe8096f931734286a95b6A63eFFCEFD3C56F3f6a9",
      v4_liquidation_logic: "0x88dF535473C5adf1f57789734A05E555F7Deb8DB",
      v4_treasury_spoke: "0xB9B0b8616f6Bf6841972a52058132BE08d723155",
      # Position Managers
      v4_config_position_manager: "0x51305839CE822a7b4b12AA7D86eA7005052d575c",
      v4_giver_position_manager: "0x17A54b8d6D9C68e7fa1C7112AC998EA1BA51d11e",
      v4_taker_position_manager: "0x6c044c0D3801499bCAbfAd458B70880bc518e9F7",
      v4_native_token_gateway: "0xe68ab4F90Fe026B9873F5F276eD2d7efBbbE42Be",
      v4_signature_gateway: "0xfbC184337Dc6595D8bf62968Bda46e7De7AF9c3d",
      # Hubs
      v4_core_hub: "0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9",
      v4_prime_hub: "0x943827DCA022D0F354a8a8c332dA1e5Eb9f9F931",
      v4_plus_hub: "0x06002e9c4412CB7814a791eA3666D905871E536A",
      # Spokes
      v4_main_spoke: "0x94e7A5dCbE816e498b89aB752661904E2F56c485",
      v4_lido_spoke: "0xe1900480ac69f0B296841Cd01cC37546d92F35Cd",
      v4_etherfi_spoke: "0xbF10BDfE177dE0336aFD7fcCF80A904E15386219",
      v4_kelp_spoke: "0x3131FE68C4722e726fe6B2819ED68e514395B9a4",
      v4_lombard_btc_spoke: "0x7EC68b5695e803e98a21a9A05d744F28b0a7753D",
      v4_gold_spoke: "0x65407b940966954b23dfA3caA5C0702bB42984DC",
      v4_forex_spoke: "0xD8B93635b8C6d0fF98CbE90b5988E3F2d1Cd9da1",
      v4_bluechip_spoke: "0x973a023A77420ba610f06b3858aD991Df6d85A08",
      v4_ethena_ecosystem_spoke: "0xba1B3D55D249692b669A164024A838309B7508AF",
      v4_ethena_correlated_spoke: "0x58131E79531caB1d52301228d1f7b842F26B9649",
      # Per-Spoke oracles (IAaveOracle, one per Spoke)
      v4_main_spoke_oracle: "0x99B2B6CEa9C3D2fd8F4d90f86741C44B212a6127",
      v4_lido_spoke_oracle: "0x664D73b6C3591333Fd79510f7ce9ef81228824F5",
      v4_etherfi_spoke_oracle: "0xd8B153FaAA8f2b1bC774916FEd333A4F3dE48792",
      v4_kelp_spoke_oracle: "0x37C316996C714Bf906743071e04E62220b3271ac",
      v4_lombard_btc_spoke_oracle: "0x198Cac7f54FFc7d709Ac0FEc4B6454CE73e21D3D",
      v4_gold_spoke_oracle: "0x0083421fd178749af2201ddA5A7C3feB5790B80c",
      v4_forex_spoke_oracle: "0xB3CE6E7b6d389a66eA4a3777bA07219d00FB3a9D",
      v4_bluechip_spoke_oracle: "0xdA1266a7b8620819dAE3F8bd6B546Da36e505bB8",
      v4_ethena_ecosystem_spoke_oracle: "0xc390dbe9fc00D6db73C52d375642b47008C33c90",
      v4_ethena_correlated_spoke_oracle: "0x9b91a0943CADf554742E8Fb358B1cC4ae4F85F01"
    }
  }

  # Aave V4 ERC-4626 Tokenization Spokes, one per (Hub, underlying-asset).
  # Nested by network → hub → asset to keep 31 entries out of the flat atom
  # registry. Asset atoms are the downcased token symbol (PT tokens use
  # `:pt_susde` / `:pt_usde`). Sourced from V4_SCOPING.md.
  @v4_tokenization_spokes %{
    ethereum: %{
      core: %{
        aave: "0x0A65197b16C5969F92672051c9C9C0C75B369135",
        cbbtc: "0x33B41B74366F55327d959FfF6D6b6fBc2853dbB1",
        eurc: "0x6D9e2Cdd61CaF69af99b275704B6e272C41c6718",
        frxusd: "0x2226749630775ee20230Ad65214fB339087eF30D",
        gho: "0x58C14a5E061c9bC6926c5b853445290F296C2F7B",
        lbtc: "0x7961F140B570490849DB878AE222570ea838799d",
        link: "0xE69C2045095C8Ab3E2a7d77de2328faE5baF797c",
        rlusd: "0xC8a125AE4275a78AADc53B46Ca10566Bc9B249E0",
        rseth: "0x45a04Ca1A5cbEeA4B44356c75EDd29b33eB2527a",
        usdc: "0x531E90a2376902DE8915789Fcc1075e3B0c153E7",
        usdg: "0xAC2435E3C25e8246870D33ce0a26988A46d5DB68",
        usdt: "0x5eC44a70F309854fe04d495cFE1B5dA63DD1cc73",
        wbtc: "0x82A9CC4656784E55Ef2E78F704028B5E1Bfc1732",
        weeth: "0x559cEc2C840D9DBB18936Afc5E5341D78bfC7Cbe",
        weth: "0x7320CF22Ac095bA2a2e0a652F77efB836c2E751b",
        wsteth: "0xcb0E7dA9c635628f6d4827355AeCa75aB8d3560f",
        xaut: "0x4E712562fcb5337011398B6C630f55b60641cd5e"
      },
      prime: %{
        cbbtc: "0xD38098faf52D8E915EdED84fBF30F81C17906938",
        gho: "0x900fD46d565d1ac8995928c0179052ec02a6D0E1",
        usdc: "0x486415fb1F8b062c89ED548f871cf64304AACb31",
        usdt: "0x46c588DD8453aC259c1f6a54b4C9A93C2aC3762D",
        wbtc: "0x5AE3d87De89CA6Ce501e8317887F71EABED69E18",
        weth: "0x2087513383330B961A3753B47627Bbf149F31c70",
        wsteth: "0xFCD3D3C69cd032DE0cc78fE529B7447D2fe7F666"
      },
      plus: %{
        gho: "0xA54382db40EC602c0a173A08f9E86Ed40F9D4D10",
        pt_susde: "0x90774889c22D2F2Adf44da1f04C7c95542590df4",
        pt_usde: "0xdd2Eb78BF9e6aC5068B95aD2d451e8c9Af10ac81",
        susde: "0x24f8c062e1E0451736C1D6E023510DA262a41df4",
        usdc: "0xc94bdd83D2c7655C280655D60954e79E88D4F949",
        usde: "0x502Cd81da6a8F1785eb2eEE72713B7388E16A854",
        usdt: "0x80835EB50694EE0e519743f67e5401e6FD300006"
      }
    }
  }

  # --- address ---

  api(:address, "Look up a V3 or V4 singleton contract's EIP-55 checksummed address.",
    params: [
      contract: [
        kind: :value,
        description: "Contract key atom, e.g. :pool, :oracle, :v4_core_hub"
      ],
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

    case fetch_address(network, contract) do
      {:ok, hex} -> Onchain.Address.checksum(hex)
      {:error, _reason} = error -> error
    end
  end

  # Resolve a singleton contract key against the V3 registry first, then the
  # V4 registry. A network present in either registry but missing the key
  # yields :unknown_contract; a network absent from both yields
  # :unsupported_network.
  @spec fetch_address(atom(), atom()) :: {:ok, String.t()} | {:error, term()}
  defp fetch_address(network, contract) do
    v3 = Map.get(@addresses, network)
    v4 = Map.get(@v4_addresses, network)

    cond do
      is_map(v3) and is_map_key(v3, contract) -> {:ok, Map.fetch!(v3, contract)}
      is_map(v4) and is_map_key(v4, contract) -> {:ok, Map.fetch!(v4, contract)}
      is_map(v3) or is_map(v4) -> {:error, {:unknown_contract, contract}}
      true -> {:error, {:unsupported_network, network}}
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

  # --- v4_tokenization_spoke ---

  api(
    :v4_tokenization_spoke,
    "Look up a V4 ERC-4626 Tokenization Spoke address by {hub, asset}.",
    params: [
      hub: [kind: :value, description: "Hub atom: :core, :prime, or :plus"],
      asset: [kind: :value, description: "Underlying asset atom, e.g. :weth, :usdc, :pt_susde"],
      opts: [kind: :value, default: [], description: "Options: [network: :ethereum]"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Checksummed Tokenization Spoke address",
      example: "0x7320CF22Ac095bA2a2e0a652F77efB836c2E751b"
    }
  )

  @spec v4_tokenization_spoke(atom(), atom(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def v4_tokenization_spoke(hub, asset, opts \\ []) do
    network = Keyword.get(opts, :network, :ethereum)

    case @v4_tokenization_spokes do
      %{^network => %{^hub => %{^asset => hex}}} -> Onchain.Address.checksum(hex)
      %{^network => %{^hub => _assets}} -> {:error, {:unknown_tokenization_spoke, {hub, asset}}}
      %{^network => _hubs} -> {:error, {:unknown_hub, hub}}
      %{} -> {:error, {:unsupported_network, network}}
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

  # --- v4_contracts ---

  api(:v4_contracts, "List available V4 singleton contract keys for a network.",
    params: [
      opts: [kind: :value, default: [], description: "Options: [network: :ethereum]"]
    ],
    returns: %{
      type: "{:ok, [atom()]} | {:error, {:unsupported_network, atom()}}",
      description: "List of V4 singleton contract key atoms"
    }
  )

  @spec v4_contracts(keyword()) :: {:ok, [atom()]} | {:error, {:unsupported_network, atom()}}
  def v4_contracts(opts \\ []) do
    network = Keyword.get(opts, :network, :ethereum)

    case @v4_addresses do
      %{^network => network_map} -> {:ok, Map.keys(network_map)}
      %{} -> {:error, {:unsupported_network, network}}
    end
  end
end
