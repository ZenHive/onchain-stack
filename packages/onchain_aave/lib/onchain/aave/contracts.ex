defmodule Onchain.Aave.Contracts do
  @moduledoc """
  Aave V3 + V4 contract address registry.

  Pure-function lookup for known Aave protocol contract addresses. All other
  Aave modules (Pool, Oracle, UiPoolDataProvider) depend on this for addresses.

  ## Supported Networks

  Ethereum, Arbitrum, Optimism, Base, Polygon, Avalanche (all Aave V3 mainnet),
  and Sepolia (V3 testnet). Aave V4 supports Ethereum and Avalanche.

  ## V4 Address Shape

  Address-book labels use lowercase `:v4_`-prefixed atoms in `address/2`.
  Category prefixes are omitted for named contracts; array indices and asset
  paths retain their prefixes. Tokenization Spokes also resolve through
  `v4_tokenization_spoke/3` by `{hub, asset}`. Existing e-Spoke and PT aliases
  remain supported. See `V4_SCOPING.md` for the pinned source and naming rules.

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
    # Sepolia addresses (roadmap task 4006) — last verified 2026-03-09 via
    # PoolAddressesProvider.getPool/getPriceOracle and BGD Labs aave-address-book
    # (src/AaveV3Sepolia.sol). Re-verify on each Aave upgrade.
    sepolia: %{
      pool_addresses_provider: "0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A",
      pool: "0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951",
      oracle: "0x2da88497588bf89281816106C7259e31AF45a663",
      ui_pool_data_provider: "0x69529987FA4A075D0C00B0128fa848dc9ebbE9CE",
      faucet: "0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D"
    },
    # Base Sepolia (chain 84532) — verified 2026-09-23 against BGD Labs
    # aave-address-book src/AaveV3BaseSepolia.sol (POOL_ADDRESSES_PROVIDER, POOL,
    # ORACLE, UI_POOL_DATA_PROVIDER). The faucet is the one aave/interface's
    # market config points at for this market. Re-verify on each Aave upgrade.
    base_sepolia: %{
      pool_addresses_provider: "0xE4C23309117Aa30342BFaae6c95c6478e0A4Ad00",
      pool: "0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27",
      oracle: "0x943b0dE18d4abf4eF02A85912F8fc07684C141dF",
      ui_pool_data_provider: "0x3cB7B00B6C09B71998124196691e8bF2694De863",
      faucet: "0xD9145b5F45Ad4519c7ACcD6E0A4A82e83bB8A6Dc"
    }
  }

  # aave-dao/aave-address-book safe.csv at fdaecf26c96398e6a9b54c2b6477647fba293a91
  # Re-derived 2026-09-15; naming and compatibility aliases: V4_SCOPING.md.
  @v4_addresses %{
    ethereum: %{
      v4_access_manager: "0x08aE3BE30958cDd1847ec58fFfd4C451a87fDF01",
      v4_all_hubs_0: "0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9",
      v4_all_hubs_1: "0x06002e9c4412CB7814a791eA3666D905871E536A",
      v4_all_hubs_2: "0x943827DCA022D0F354a8a8c332dA1e5Eb9f9F931",
      v4_all_hubs_3: "0x62d63197660c080236193CA60b70E49A08E90368",
      v4_all_spokes_0: "0x973a023A77420ba610f06b3858aD991Df6d85A08",
      v4_all_spokes_1: "0x58131E79531caB1d52301228d1f7b842F26B9649",
      v4_all_spokes_2: "0xba1B3D55D249692b669A164024A838309B7508AF",
      v4_all_spokes_3: "0xD8B93635b8C6d0fF98CbE90b5988E3F2d1Cd9da1",
      v4_all_spokes_4: "0x65407b940966954b23dfA3caA5C0702bB42984DC",
      v4_all_spokes_5: "0x7EC68b5695e803e98a21a9A05d744F28b0a7753D",
      v4_all_spokes_6: "0x94e7A5dCbE816e498b89aB752661904E2F56c485",
      v4_all_spokes_7: "0xAD75cE6354f87F3135cE10621d385d8D1e2562C2",
      v4_all_spokes_8: "0x956d8e0A89cfa3744428C4641b5a53B56167a7f9",
      v4_all_spokes_9: "0xbF10BDfE177dE0336aFD7fcCF80A904E15386219",
      v4_all_spokes_10: "0x3131FE68C4722e726fe6B2819ED68e514395B9a4",
      v4_all_spokes_11: "0xe1900480ac69f0B296841Cd01cC37546d92F35Cd",
      v4_all_spokes_12: "0x774b9655413c34809c1f1b16b654465A89EBE989",
      v4_all_spokes_raw_0: "0xB9B0b8616f6Bf6841972a52058132BE08d723155",
      v4_all_spokes_raw_1: "0x973a023A77420ba610f06b3858aD991Df6d85A08",
      v4_all_spokes_raw_2: "0x58131E79531caB1d52301228d1f7b842F26B9649",
      v4_all_spokes_raw_3: "0xba1B3D55D249692b669A164024A838309B7508AF",
      v4_all_spokes_raw_4: "0xD8B93635b8C6d0fF98CbE90b5988E3F2d1Cd9da1",
      v4_all_spokes_raw_5: "0x65407b940966954b23dfA3caA5C0702bB42984DC",
      v4_all_spokes_raw_6: "0x7EC68b5695e803e98a21a9A05d744F28b0a7753D",
      v4_all_spokes_raw_7: "0x94e7A5dCbE816e498b89aB752661904E2F56c485",
      v4_all_spokes_raw_8: "0xAD75cE6354f87F3135cE10621d385d8D1e2562C2",
      v4_all_spokes_raw_9: "0x956d8e0A89cfa3744428C4641b5a53B56167a7f9",
      v4_all_spokes_raw_10: "0xbF10BDfE177dE0336aFD7fcCF80A904E15386219",
      v4_all_spokes_raw_11: "0x3131FE68C4722e726fe6B2819ED68e514395B9a4",
      v4_all_spokes_raw_12: "0xe1900480ac69f0B296841Cd01cC37546d92F35Cd",
      v4_all_spokes_raw_13: "0x774b9655413c34809c1f1b16b654465A89EBE989",
      v4_all_spokes_raw_14: "0x7320CF22Ac095bA2a2e0a652F77efB836c2E751b",
      v4_all_spokes_raw_15: "0xcb0E7dA9c635628f6d4827355AeCa75aB8d3560f",
      v4_all_spokes_raw_16: "0x559cEc2C840D9DBB18936Afc5E5341D78bfC7Cbe",
      v4_all_spokes_raw_17: "0x45a04Ca1A5cbEeA4B44356c75EDd29b33eB2527a",
      v4_all_spokes_raw_18: "0x5eC44a70F309854fe04d495cFE1B5dA63DD1cc73",
      v4_all_spokes_raw_19: "0x531E90a2376902DE8915789Fcc1075e3B0c153E7",
      v4_all_spokes_raw_20: "0x58C14a5E061c9bC6926c5b853445290F296C2F7B",
      v4_all_spokes_raw_21: "0xC8a125AE4275a78AADc53B46Ca10566Bc9B249E0",
      v4_all_spokes_raw_22: "0xAC2435E3C25e8246870D33ce0a26988A46d5DB68",
      v4_all_spokes_raw_23: "0x2226749630775ee20230Ad65214fB339087eF30D",
      v4_all_spokes_raw_24: "0x6D9e2Cdd61CaF69af99b275704B6e272C41c6718",
      v4_all_spokes_raw_25: "0x82A9CC4656784E55Ef2E78F704028B5E1Bfc1732",
      v4_all_spokes_raw_26: "0x33B41B74366F55327d959FfF6D6b6fBc2853dbB1",
      v4_all_spokes_raw_27: "0x7961F140B570490849DB878AE222570ea838799d",
      v4_all_spokes_raw_28: "0x4E712562fcb5337011398B6C630f55b60641cd5e",
      v4_all_spokes_raw_29: "0x0A65197b16C5969F92672051c9C9C0C75B369135",
      v4_all_spokes_raw_30: "0xE69C2045095C8Ab3E2a7d77de2328faE5baF797c",
      v4_all_spokes_raw_31: "0x90774889c22D2F2Adf44da1f04C7c95542590df4",
      v4_all_spokes_raw_32: "0xdd2Eb78BF9e6aC5068B95aD2d451e8c9Af10ac81",
      v4_all_spokes_raw_33: "0x24f8c062e1E0451736C1D6E023510DA262a41df4",
      v4_all_spokes_raw_34: "0x502Cd81da6a8F1785eb2eEE72713B7388E16A854",
      v4_all_spokes_raw_35: "0xc94bdd83D2c7655C280655D60954e79E88D4F949",
      v4_all_spokes_raw_36: "0xA54382db40EC602c0a173A08f9E86Ed40F9D4D10",
      v4_all_spokes_raw_37: "0x80835EB50694EE0e519743f67e5401e6FD300006",
      v4_all_spokes_raw_38: "0x2087513383330B961A3753B47627Bbf149F31c70",
      v4_all_spokes_raw_39: "0x5AE3d87De89CA6Ce501e8317887F71EABED69E18",
      v4_all_spokes_raw_40: "0xD38098faf52D8E915EdED84fBF30F81C17906938",
      v4_all_spokes_raw_41: "0xFCD3D3C69cd032DE0cc78fE529B7447D2fe7F666",
      v4_all_spokes_raw_42: "0x486415fb1F8b062c89ED548f871cf64304AACb31",
      v4_all_spokes_raw_43: "0x46c588DD8453aC259c1f6a54b4C9A93C2aC3762D",
      v4_all_spokes_raw_44: "0x900fD46d565d1ac8995928c0179052ec02a6D0E1",
      v4_all_spokes_raw_45: "0x7Df10B4A01350D2A1d95cFbE7c9207d7210A2663",
      v4_all_spokes_raw_46: "0xaed7c529bD2878170B61C758DfAa215AC7a4FD07",
      v4_all_spokes_raw_47: "0xa0e97e45C2f89003730E467Bd484fA3eEcE5B4Cf",
      v4_all_spokes_raw_48: "0x378B4a7c394E22bd562F66eB612165893533c124",
      v4_all_spokes_raw_49: "0x6493a23874b506D5Bb6038ea44aE9CC74cD00849",
      v4_all_tokenized_spokes_0: "0x7320CF22Ac095bA2a2e0a652F77efB836c2E751b",
      v4_all_tokenized_spokes_1: "0xcb0E7dA9c635628f6d4827355AeCa75aB8d3560f",
      v4_all_tokenized_spokes_2: "0x559cEc2C840D9DBB18936Afc5E5341D78bfC7Cbe",
      v4_all_tokenized_spokes_3: "0x45a04Ca1A5cbEeA4B44356c75EDd29b33eB2527a",
      v4_all_tokenized_spokes_4: "0x5eC44a70F309854fe04d495cFE1B5dA63DD1cc73",
      v4_all_tokenized_spokes_5: "0x531E90a2376902DE8915789Fcc1075e3B0c153E7",
      v4_all_tokenized_spokes_6: "0x58C14a5E061c9bC6926c5b853445290F296C2F7B",
      v4_all_tokenized_spokes_7: "0xC8a125AE4275a78AADc53B46Ca10566Bc9B249E0",
      v4_all_tokenized_spokes_8: "0xAC2435E3C25e8246870D33ce0a26988A46d5DB68",
      v4_all_tokenized_spokes_9: "0x2226749630775ee20230Ad65214fB339087eF30D",
      v4_all_tokenized_spokes_10: "0x6D9e2Cdd61CaF69af99b275704B6e272C41c6718",
      v4_all_tokenized_spokes_11: "0x82A9CC4656784E55Ef2E78F704028B5E1Bfc1732",
      v4_all_tokenized_spokes_12: "0x33B41B74366F55327d959FfF6D6b6fBc2853dbB1",
      v4_all_tokenized_spokes_13: "0x7961F140B570490849DB878AE222570ea838799d",
      v4_all_tokenized_spokes_14: "0x4E712562fcb5337011398B6C630f55b60641cd5e",
      v4_all_tokenized_spokes_15: "0x0A65197b16C5969F92672051c9C9C0C75B369135",
      v4_all_tokenized_spokes_16: "0xE69C2045095C8Ab3E2a7d77de2328faE5baF797c",
      v4_all_tokenized_spokes_17: "0x90774889c22D2F2Adf44da1f04C7c95542590df4",
      v4_all_tokenized_spokes_18: "0xdd2Eb78BF9e6aC5068B95aD2d451e8c9Af10ac81",
      v4_all_tokenized_spokes_19: "0x24f8c062e1E0451736C1D6E023510DA262a41df4",
      v4_all_tokenized_spokes_20: "0x502Cd81da6a8F1785eb2eEE72713B7388E16A854",
      v4_all_tokenized_spokes_21: "0xc94bdd83D2c7655C280655D60954e79E88D4F949",
      v4_all_tokenized_spokes_22: "0xA54382db40EC602c0a173A08f9E86Ed40F9D4D10",
      v4_all_tokenized_spokes_23: "0x80835EB50694EE0e519743f67e5401e6FD300006",
      v4_all_tokenized_spokes_24: "0x2087513383330B961A3753B47627Bbf149F31c70",
      v4_all_tokenized_spokes_25: "0x5AE3d87De89CA6Ce501e8317887F71EABED69E18",
      v4_all_tokenized_spokes_26: "0xD38098faf52D8E915EdED84fBF30F81C17906938",
      v4_all_tokenized_spokes_27: "0xFCD3D3C69cd032DE0cc78fE529B7447D2fe7F666",
      v4_all_tokenized_spokes_28: "0x486415fb1F8b062c89ED548f871cf64304AACb31",
      v4_all_tokenized_spokes_29: "0x46c588DD8453aC259c1f6a54b4C9A93C2aC3762D",
      v4_all_tokenized_spokes_30: "0x900fD46d565d1ac8995928c0179052ec02a6D0E1",
      v4_all_tokenized_spokes_31: "0x7Df10B4A01350D2A1d95cFbE7c9207d7210A2663",
      v4_all_tokenized_spokes_32: "0xaed7c529bD2878170B61C758DfAa215AC7a4FD07",
      v4_all_tokenized_spokes_33: "0xa0e97e45C2f89003730E467Bd484fA3eEcE5B4Cf",
      v4_all_tokenized_spokes_34: "0x378B4a7c394E22bd562F66eB612165893533c124",
      v4_all_tokenized_spokes_35: "0x6493a23874b506D5Bb6038ea44aE9CC74cD00849",
      v4_assets_weth_underlying: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
      v4_assets_wsteth_underlying: "0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0",
      v4_assets_weeth_underlying: "0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee",
      v4_assets_rseth_underlying: "0xA1290d69c65A6Fe4DF752f95823fae25cB99e5A7",
      v4_assets_usdt_underlying: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
      v4_assets_usdc_underlying: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
      v4_assets_gho_underlying: "0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f",
      v4_assets_rlusd_underlying: "0x8292Bb45bf1Ee4d140127049757C2E0fF06317eD",
      v4_assets_usdg_underlying: "0xe343167631d89B6Ffc58B88d6b7fB0228795491D",
      v4_assets_frxusd_underlying: "0xCAcd6fd266aF91b8AeD52aCCc382b4e165586E29",
      v4_assets_eurc_underlying: "0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c",
      v4_assets_wbtc_underlying: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
      v4_assets_cbbtc_underlying: "0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf",
      v4_assets_lbtc_underlying: "0x8236a87084f8B84306f72007F36F2618A5634494",
      v4_assets_xaut_underlying: "0x68749665FF8D2d112Fa859AA293F07A622782F38",
      v4_assets_aave_underlying: "0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9",
      v4_assets_link_underlying: "0x514910771AF9Ca656af840dff83E8264EcF986CA",
      v4_assets_pt_susde_7may2026_underlying: "0x3de0ff76E8b528C092d47b9DaC775931cef80F49",
      v4_assets_pt_usde_7may2026_underlying: "0xAeBf0Bb9f57E89260d57f31AF34eB58657d96Ce0",
      v4_assets_susde_underlying: "0x9D39A5DE30e57443BfF2A8307A4256c8797A3497",
      v4_assets_usde_underlying: "0x4c9EDD5852cd905f086C759E8383e09bff1E68B3",
      v4_assets_pt_usdg_24sep2026_underlying: "0xc1906aeCf868749a2DeE203F59b904c0cf212140",
      v4_assets_syrupusdg_underlying: "0x87b65C4aAFFA76881f9E96F3e7ED945ddFC3Cd7A",
      v4_assets_paxg_underlying: "0x45804880De22913dAFE09f4980848ECE6EcbAf78",
      v4_config_engine: "0xa1673fbD457747A05e91D9ef904Cb12827916B1E",
      v4_liquidation_logic: "0x88dF535473C5adf1f57789734A05E555F7Deb8DB",
      v4_core_hub: "0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9",
      v4_plus_hub: "0x06002e9c4412CB7814a791eA3666D905871E536A",
      v4_prime_hub: "0x943827DCA022D0F354a8a8c332dA1e5Eb9f9F931",
      v4_global_dollar_hub: "0x62d63197660c080236193CA60b70E49A08E90368",
      v4_hub_configurator: "0x1F0753480bB03EaA00863224602267B7E0525C3d",
      v4_core_weth_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_wsteth_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_weeth_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_rseth_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_usdt_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_usdc_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_gho_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_rlusd_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_usdg_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_frxusd_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_eurc_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_wbtc_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_cbbtc_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_lbtc_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_xaut_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_aave_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_core_link_ir_strategy: "0xAD88791B0F81D1FA242f637eB05bee0cbc53fe2f",
      v4_plus_pt_susde_7may2026_ir_strategy: "0x31280650661b8443723fa9739b3A164E3696af48",
      v4_plus_pt_usde_7may2026_ir_strategy: "0x31280650661b8443723fa9739b3A164E3696af48",
      v4_plus_susde_ir_strategy: "0x31280650661b8443723fa9739b3A164E3696af48",
      v4_plus_usde_ir_strategy: "0x31280650661b8443723fa9739b3A164E3696af48",
      v4_plus_usdc_ir_strategy: "0x31280650661b8443723fa9739b3A164E3696af48",
      v4_plus_gho_ir_strategy: "0x31280650661b8443723fa9739b3A164E3696af48",
      v4_plus_usdt_ir_strategy: "0x31280650661b8443723fa9739b3A164E3696af48",
      v4_prime_weth_ir_strategy: "0xDCd924047a4bDBFef9CCDDe845E5D45373Ad276D",
      v4_prime_wbtc_ir_strategy: "0xDCd924047a4bDBFef9CCDDe845E5D45373Ad276D",
      v4_prime_cbbtc_ir_strategy: "0xDCd924047a4bDBFef9CCDDe845E5D45373Ad276D",
      v4_prime_wsteth_ir_strategy: "0xDCd924047a4bDBFef9CCDDe845E5D45373Ad276D",
      v4_prime_usdc_ir_strategy: "0xDCd924047a4bDBFef9CCDDe845E5D45373Ad276D",
      v4_prime_usdt_ir_strategy: "0xDCd924047a4bDBFef9CCDDe845E5D45373Ad276D",
      v4_prime_gho_ir_strategy: "0xDCd924047a4bDBFef9CCDDe845E5D45373Ad276D",
      v4_global_dollar_pt_usdg_24sep2026_ir_strategy: "0xD7eC225DC053151100A0ef47b94a77AAD9C413b7",
      v4_global_dollar_usdc_ir_strategy: "0xD7eC225DC053151100A0ef47b94a77AAD9C413b7",
      v4_global_dollar_usdt_ir_strategy: "0xD7eC225DC053151100A0ef47b94a77AAD9C413b7",
      v4_global_dollar_usdg_ir_strategy: "0xD7eC225DC053151100A0ef47b94a77AAD9C413b7",
      v4_global_dollar_syrupusdg_ir_strategy: "0xD7eC225DC053151100A0ef47b94a77AAD9C413b7",
      v4_global_dollar_paxg_ir_strategy: "0xD7eC225DC053151100A0ef47b94a77AAD9C413b7",
      v4_giver_position_manager: "0x17A54b8d6D9C68e7fa1C7112AC998EA1BA51d11e",
      v4_taker_position_manager: "0x6c044c0D3801499bCAbfAd458B70880bc518e9F7",
      v4_config_position_manager: "0x51305839CE822a7b4b12AA7D86eA7005052d575c",
      v4_native_token_gateway: "0xe68ab4F90Fe026B9873F5F276eD2d7efBbbE42Be",
      v4_signature_gateway: "0xfbC184337Dc6595D8bf62968Bda46e7De7AF9c3d",
      v4_treasury_spoke: "0xB9B0b8616f6Bf6841972a52058132BE08d723155",
      v4_bluechip_spoke: "0x973a023A77420ba610f06b3858aD991Df6d85A08",
      v4_bluechip_spoke_oracle: "0xdA1266a7b8620819dAE3F8bd6B546Da36e505bB8",
      v4_ethena_correlated_spoke: "0x58131E79531caB1d52301228d1f7b842F26B9649",
      v4_ethena_correlated_spoke_oracle: "0x9b91a0943CADf554742E8Fb358B1cC4ae4F85F01",
      v4_ethena_ecosystem_spoke: "0xba1B3D55D249692b669A164024A838309B7508AF",
      v4_ethena_ecosystem_spoke_oracle: "0xc390dbe9fc00D6db73C52d375642b47008C33c90",
      v4_forex_spoke: "0xD8B93635b8C6d0fF98CbE90b5988E3F2d1Cd9da1",
      v4_forex_spoke_oracle: "0xB3CE6E7b6d389a66eA4a3777bA07219d00FB3a9D",
      v4_gold_spoke: "0x65407b940966954b23dfA3caA5C0702bB42984DC",
      v4_gold_spoke_oracle: "0x0083421fd178749af2201ddA5A7C3feB5790B80c",
      v4_lombard_btc_spoke: "0x7EC68b5695e803e98a21a9A05d744F28b0a7753D",
      v4_lombard_btc_spoke_oracle: "0x198Cac7f54FFc7d709Ac0FEc4B6454CE73e21D3D",
      v4_main_spoke: "0x94e7A5dCbE816e498b89aB752661904E2F56c485",
      v4_main_spoke_oracle: "0x99B2B6CEa9C3D2fd8F4d90f86741C44B212a6127",
      v4_paxg_gold_spoke: "0xAD75cE6354f87F3135cE10621d385d8D1e2562C2",
      v4_paxg_gold_spoke_oracle: "0x8CEcC12b23ED45EC2A9b9EB57EA6974c0cae850B",
      v4_usdg_pendle_spoke: "0x956d8e0A89cfa3744428C4641b5a53B56167a7f9",
      v4_usdg_pendle_spoke_oracle: "0x692cD2F7653680aFf316Ac309ce825FCF573B7Ee",
      v4_etherfi_espoke: "0xbF10BDfE177dE0336aFD7fcCF80A904E15386219",
      v4_etherfi_espoke_oracle: "0xd8B153FaAA8f2b1bC774916FEd333A4F3dE48792",
      v4_kelp_espoke: "0x3131FE68C4722e726fe6B2819ED68e514395B9a4",
      v4_kelp_espoke_oracle: "0x37C316996C714Bf906743071e04E62220b3271ac",
      v4_lido_espoke: "0xe1900480ac69f0B296841Cd01cC37546d92F35Cd",
      v4_lido_espoke_oracle: "0x664D73b6C3591333Fd79510f7ce9ef81228824F5",
      v4_usdg_maple_espoke: "0x774b9655413c34809c1f1b16b654465A89EBE989",
      v4_usdg_maple_espoke_oracle: "0x47a7cC7Fd47aCed15087a8b6e0ACFddCD63C811A",
      v4_spoke_configurator: "0x9BFFf48BFb5A7AE70c348d4d4cb97E8DEFa5389a",
      v4_bluechip_spoke_weth_price_feed: "0x5424384B256154046E9667dDFaaa5e550145215e",
      v4_bluechip_spoke_wbtc_price_feed: "0xDaa4B74C6bAc4e25188e64ebc68DB5050b690cAc",
      v4_bluechip_spoke_cbbtc_price_feed: "0xb41E773f507F7a7EA890b1afB7d2b660c30C8B0A",
      v4_bluechip_spoke_wsteth_price_feed: "0xe1D97bF61901B075E9626c8A2340a7De385861Ef",
      v4_bluechip_spoke_prime_usdc_price_feed: "0x3f73F03aa83B2A48ed27E964eD0fDb590332095B",
      v4_bluechip_spoke_prime_usdt_price_feed: "0x260326c220E469358846b187eE53328303Efe19C",
      v4_bluechip_spoke_gho_price_feed: "0xD110cac5d8682A3b045D5524a9903E031d70FCCd",
      v4_bluechip_spoke_core_usdc_price_feed: "0x3f73F03aa83B2A48ed27E964eD0fDb590332095B",
      v4_bluechip_spoke_frxusd_price_feed: "0x25DEd2f9aE6ae9416693AB63Abe3aB25493861FD",
      v4_bluechip_spoke_eurc_price_feed: "0xa6aB031A4d189B24628EC9Eb155F0a0f1A0E55a3",
      v4_bluechip_spoke_core_usdt_price_feed: "0x260326c220E469358846b187eE53328303Efe19C",
      v4_bluechip_spoke_usdg_price_feed: "0x83D20dEEdcd4aC1313496c8CBcAad0fa298c0CE4",
      v4_ethena_correlated_spoke_pt_usde_7may2026_price_feed: "0x0a72df02CE3E4185b6CEDf561f0AE651E9BeE235",
      v4_ethena_correlated_spoke_pt_susde_7may2026_price_feed: "0xa0dc0249c32fa79e8B9b17c735908a60b1141B40",
      v4_ethena_correlated_spoke_susde_price_feed: "0x42bc86f2f08419280a99d8fbEa4672e7c30a86ec",
      v4_ethena_correlated_spoke_usde_price_feed: "0xC26D4a1c46d884cfF6dE9800B6aE7A8Cf48B4Ff8",
      v4_ethena_ecosystem_spoke_pt_usde_7may2026_price_feed: "0x0a72df02CE3E4185b6CEDf561f0AE651E9BeE235",
      v4_ethena_ecosystem_spoke_pt_susde_7may2026_price_feed: "0xa0dc0249c32fa79e8B9b17c735908a60b1141B40",
      v4_ethena_ecosystem_spoke_susde_price_feed: "0x42bc86f2f08419280a99d8fbEa4672e7c30a86ec",
      v4_ethena_ecosystem_spoke_usde_price_feed: "0xC26D4a1c46d884cfF6dE9800B6aE7A8Cf48B4Ff8",
      v4_ethena_ecosystem_spoke_plus_usdc_price_feed: "0x3f73F03aa83B2A48ed27E964eD0fDb590332095B",
      v4_ethena_ecosystem_spoke_plus_usdt_price_feed: "0x260326c220E469358846b187eE53328303Efe19C",
      v4_ethena_ecosystem_spoke_gho_price_feed: "0xD110cac5d8682A3b045D5524a9903E031d70FCCd",
      v4_ethena_ecosystem_spoke_core_usdc_price_feed: "0x3f73F03aa83B2A48ed27E964eD0fDb590332095B",
      v4_ethena_ecosystem_spoke_frxusd_price_feed: "0x25DEd2f9aE6ae9416693AB63Abe3aB25493861FD",
      v4_ethena_ecosystem_spoke_core_usdt_price_feed: "0x260326c220E469358846b187eE53328303Efe19C",
      v4_forex_spoke_eurc_price_feed: "0xa6aB031A4d189B24628EC9Eb155F0a0f1A0E55a3",
      v4_forex_spoke_usdc_price_feed: "0x3f73F03aa83B2A48ed27E964eD0fDb590332095B",
      v4_forex_spoke_usdt_price_feed: "0x260326c220E469358846b187eE53328303Efe19C",
      v4_forex_spoke_rlusd_price_feed: "0xf0eaC18E908B34770FDEe46d069c846bDa866759",
      v4_forex_spoke_usdg_price_feed: "0x83D20dEEdcd4aC1313496c8CBcAad0fa298c0CE4",
      v4_forex_spoke_frxusd_price_feed: "0x25DEd2f9aE6ae9416693AB63Abe3aB25493861FD",
      v4_forex_spoke_gho_price_feed: "0xD110cac5d8682A3b045D5524a9903E031d70FCCd",
      v4_gold_spoke_xaut_price_feed: "0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6",
      v4_gold_spoke_usdc_price_feed: "0x3f73F03aa83B2A48ed27E964eD0fDb590332095B",
      v4_gold_spoke_rlusd_price_feed: "0xf0eaC18E908B34770FDEe46d069c846bDa866759",
      v4_gold_spoke_usdg_price_feed: "0x83D20dEEdcd4aC1313496c8CBcAad0fa298c0CE4",
      v4_gold_spoke_frxusd_price_feed: "0x25DEd2f9aE6ae9416693AB63Abe3aB25493861FD",
      v4_gold_spoke_eurc_price_feed: "0xa6aB031A4d189B24628EC9Eb155F0a0f1A0E55a3",
      v4_gold_spoke_gho_price_feed: "0xD110cac5d8682A3b045D5524a9903E031d70FCCd",
      v4_gold_spoke_usdt_price_feed: "0x260326c220E469358846b187eE53328303Efe19C",
      v4_lombard_btc_spoke_lbtc_price_feed: "0xf8c04B50499872A5B5137219DEc0F791f7f620D0",
      v4_lombard_btc_spoke_wbtc_price_feed: "0xDaa4B74C6bAc4e25188e64ebc68DB5050b690cAc",
      v4_lombard_btc_spoke_cbbtc_price_feed: "0xb41E773f507F7a7EA890b1afB7d2b660c30C8B0A",
      v4_main_spoke_weth_price_feed: "0x5424384B256154046E9667dDFaaa5e550145215e",
      v4_main_spoke_wsteth_price_feed: "0xe1D97bF61901B075E9626c8A2340a7De385861Ef",
      v4_main_spoke_weeth_price_feed: "0x87625393534d5C102cADB66D37201dF24cc26d4C",
      v4_main_spoke_wbtc_price_feed: "0xDaa4B74C6bAc4e25188e64ebc68DB5050b690cAc",
      v4_main_spoke_cbbtc_price_feed: "0xb41E773f507F7a7EA890b1afB7d2b660c30C8B0A",
      v4_main_spoke_aave_price_feed: "0xF02C1e2A3B77c1cacC72f72B44f7d0a4c62e4a85",
      v4_main_spoke_link_price_feed: "0xC7e9b623ed51F033b32AE7f1282b1AD62C28C183",
      v4_main_spoke_usdc_price_feed: "0x3f73F03aa83B2A48ed27E964eD0fDb590332095B",
      v4_main_spoke_usdt_price_feed: "0x260326c220E469358846b187eE53328303Efe19C",
      v4_main_spoke_eurc_price_feed: "0xa6aB031A4d189B24628EC9Eb155F0a0f1A0E55a3",
      v4_main_spoke_rlusd_price_feed: "0xf0eaC18E908B34770FDEe46d069c846bDa866759",
      v4_main_spoke_usdg_price_feed: "0x83D20dEEdcd4aC1313496c8CBcAad0fa298c0CE4",
      v4_main_spoke_frxusd_price_feed: "0x25DEd2f9aE6ae9416693AB63Abe3aB25493861FD",
      v4_main_spoke_gho_price_feed: "0xD110cac5d8682A3b045D5524a9903E031d70FCCd",
      v4_paxg_gold_spoke_paxg_price_feed: "0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6",
      v4_paxg_gold_spoke_usdg_price_feed: "0x83D20dEEdcd4aC1313496c8CBcAad0fa298c0CE4",
      v4_usdg_pendle_spoke_pt_usdg_24sep2026_price_feed: "0x89F6Eb404AbF19FE817426dD2E2E0F14D1a5712e",
      v4_usdg_pendle_spoke_usdc_price_feed: "0x3f73F03aa83B2A48ed27E964eD0fDb590332095B",
      v4_usdg_pendle_spoke_usdt_price_feed: "0x260326c220E469358846b187eE53328303Efe19C",
      v4_usdg_pendle_spoke_core_usdg_price_feed: "0x83D20dEEdcd4aC1313496c8CBcAad0fa298c0CE4",
      v4_usdg_pendle_spoke_global_dollar_usdg_price_feed: "0x83D20dEEdcd4aC1313496c8CBcAad0fa298c0CE4",
      v4_etherfi_espoke_weeth_price_feed: "0x87625393534d5C102cADB66D37201dF24cc26d4C",
      v4_etherfi_espoke_weth_price_feed: "0x5424384B256154046E9667dDFaaa5e550145215e",
      v4_kelp_espoke_rseth_price_feed: "0x7292C95A5f6A501a9c4B34f6393e221F2A0139c3",
      v4_kelp_espoke_weth_price_feed: "0x5424384B256154046E9667dDFaaa5e550145215e",
      v4_lido_espoke_wsteth_price_feed: "0xe1D97bF61901B075E9626c8A2340a7De385861Ef",
      v4_lido_espoke_weth_price_feed: "0x5424384B256154046E9667dDFaaa5e550145215e",
      v4_usdg_maple_espoke_global_dollar_usdg_price_feed: "0x83D20dEEdcd4aC1313496c8CBcAad0fa298c0CE4",
      v4_usdg_maple_espoke_syrupusdg_price_feed: "0x5A6FcB0ebc018b6FD94Fc5f5A9F0948d0D40f040",
      v4_usdg_maple_espoke_usdc_price_feed: "0x3f73F03aa83B2A48ed27E964eD0fDb590332095B",
      v4_usdg_maple_espoke_core_usdg_price_feed: "0x83D20dEEdcd4aC1313496c8CBcAad0fa298c0CE4",
      v4_core_weth_tokenization_spoke: "0x7320CF22Ac095bA2a2e0a652F77efB836c2E751b",
      v4_core_wsteth_tokenization_spoke: "0xcb0E7dA9c635628f6d4827355AeCa75aB8d3560f",
      v4_core_weeth_tokenization_spoke: "0x559cEc2C840D9DBB18936Afc5E5341D78bfC7Cbe",
      v4_core_rseth_tokenization_spoke: "0x45a04Ca1A5cbEeA4B44356c75EDd29b33eB2527a",
      v4_core_usdt_tokenization_spoke: "0x5eC44a70F309854fe04d495cFE1B5dA63DD1cc73",
      v4_core_usdc_tokenization_spoke: "0x531E90a2376902DE8915789Fcc1075e3B0c153E7",
      v4_core_gho_tokenization_spoke: "0x58C14a5E061c9bC6926c5b853445290F296C2F7B",
      v4_core_rlusd_tokenization_spoke: "0xC8a125AE4275a78AADc53B46Ca10566Bc9B249E0",
      v4_core_usdg_tokenization_spoke: "0xAC2435E3C25e8246870D33ce0a26988A46d5DB68",
      v4_core_frxusd_tokenization_spoke: "0x2226749630775ee20230Ad65214fB339087eF30D",
      v4_core_eurc_tokenization_spoke: "0x6D9e2Cdd61CaF69af99b275704B6e272C41c6718",
      v4_core_wbtc_tokenization_spoke: "0x82A9CC4656784E55Ef2E78F704028B5E1Bfc1732",
      v4_core_cbbtc_tokenization_spoke: "0x33B41B74366F55327d959FfF6D6b6fBc2853dbB1",
      v4_core_lbtc_tokenization_spoke: "0x7961F140B570490849DB878AE222570ea838799d",
      v4_core_xaut_tokenization_spoke: "0x4E712562fcb5337011398B6C630f55b60641cd5e",
      v4_core_aave_tokenization_spoke: "0x0A65197b16C5969F92672051c9C9C0C75B369135",
      v4_core_link_tokenization_spoke: "0xE69C2045095C8Ab3E2a7d77de2328faE5baF797c",
      v4_plus_pt_susde_7may2026_tokenization_spoke: "0x90774889c22D2F2Adf44da1f04C7c95542590df4",
      v4_plus_pt_usde_7may2026_tokenization_spoke: "0xdd2Eb78BF9e6aC5068B95aD2d451e8c9Af10ac81",
      v4_plus_susde_tokenization_spoke: "0x24f8c062e1E0451736C1D6E023510DA262a41df4",
      v4_plus_usde_tokenization_spoke: "0x502Cd81da6a8F1785eb2eEE72713B7388E16A854",
      v4_plus_usdc_tokenization_spoke: "0xc94bdd83D2c7655C280655D60954e79E88D4F949",
      v4_plus_gho_tokenization_spoke: "0xA54382db40EC602c0a173A08f9E86Ed40F9D4D10",
      v4_plus_usdt_tokenization_spoke: "0x80835EB50694EE0e519743f67e5401e6FD300006",
      v4_prime_weth_tokenization_spoke: "0x2087513383330B961A3753B47627Bbf149F31c70",
      v4_prime_wbtc_tokenization_spoke: "0x5AE3d87De89CA6Ce501e8317887F71EABED69E18",
      v4_prime_cbbtc_tokenization_spoke: "0xD38098faf52D8E915EdED84fBF30F81C17906938",
      v4_prime_wsteth_tokenization_spoke: "0xFCD3D3C69cd032DE0cc78fE529B7447D2fe7F666",
      v4_prime_usdc_tokenization_spoke: "0x486415fb1F8b062c89ED548f871cf64304AACb31",
      v4_prime_usdt_tokenization_spoke: "0x46c588DD8453aC259c1f6a54b4C9A93C2aC3762D",
      v4_prime_gho_tokenization_spoke: "0x900fD46d565d1ac8995928c0179052ec02a6D0E1",
      v4_global_dollar_pt_usdg_24sep2026_tokenization_spoke: "0x7Df10B4A01350D2A1d95cFbE7c9207d7210A2663",
      v4_global_dollar_usdc_tokenization_spoke: "0xaed7c529bD2878170B61C758DfAa215AC7a4FD07",
      v4_global_dollar_usdt_tokenization_spoke: "0xa0e97e45C2f89003730E467Bd484fA3eEcE5B4Cf",
      v4_global_dollar_usdg_tokenization_spoke: "0x378B4a7c394E22bd562F66eB612165893533c124",
      v4_global_dollar_paxg_tokenization_spoke: "0x6493a23874b506D5Bb6038ea44aE9CC74cD00849",
      v4_etherfi_spoke: "0xbF10BDfE177dE0336aFD7fcCF80A904E15386219",
      v4_etherfi_e_spoke: "0xbF10BDfE177dE0336aFD7fcCF80A904E15386219",
      v4_etherfi_spoke_oracle: "0xd8B153FaAA8f2b1bC774916FEd333A4F3dE48792",
      v4_etherfi_e_spoke_oracle: "0xd8B153FaAA8f2b1bC774916FEd333A4F3dE48792",
      v4_kelp_spoke: "0x3131FE68C4722e726fe6B2819ED68e514395B9a4",
      v4_kelp_e_spoke: "0x3131FE68C4722e726fe6B2819ED68e514395B9a4",
      v4_kelp_spoke_oracle: "0x37C316996C714Bf906743071e04E62220b3271ac",
      v4_kelp_e_spoke_oracle: "0x37C316996C714Bf906743071e04E62220b3271ac",
      v4_lido_spoke: "0xe1900480ac69f0B296841Cd01cC37546d92F35Cd",
      v4_lido_e_spoke: "0xe1900480ac69f0B296841Cd01cC37546d92F35Cd",
      v4_lido_spoke_oracle: "0x664D73b6C3591333Fd79510f7ce9ef81228824F5",
      v4_lido_e_spoke_oracle: "0x664D73b6C3591333Fd79510f7ce9ef81228824F5",
      v4_etherfi_spoke_weeth_price_feed: "0x87625393534d5C102cADB66D37201dF24cc26d4C",
      v4_etherfi_e_spoke_weeth_price_feed: "0x87625393534d5C102cADB66D37201dF24cc26d4C",
      v4_etherfi_spoke_weth_price_feed: "0x5424384B256154046E9667dDFaaa5e550145215e",
      v4_etherfi_e_spoke_weth_price_feed: "0x5424384B256154046E9667dDFaaa5e550145215e",
      v4_kelp_spoke_rseth_price_feed: "0x7292C95A5f6A501a9c4B34f6393e221F2A0139c3",
      v4_kelp_e_spoke_rseth_price_feed: "0x7292C95A5f6A501a9c4B34f6393e221F2A0139c3",
      v4_kelp_spoke_weth_price_feed: "0x5424384B256154046E9667dDFaaa5e550145215e",
      v4_kelp_e_spoke_weth_price_feed: "0x5424384B256154046E9667dDFaaa5e550145215e",
      v4_lido_spoke_wsteth_price_feed: "0xe1D97bF61901B075E9626c8A2340a7De385861Ef",
      v4_lido_e_spoke_wsteth_price_feed: "0xe1D97bF61901B075E9626c8A2340a7De385861Ef",
      v4_lido_spoke_weth_price_feed: "0x5424384B256154046E9667dDFaaa5e550145215e",
      v4_lido_e_spoke_weth_price_feed: "0x5424384B256154046E9667dDFaaa5e550145215e"
    },
    avalanche: %{
      v4_access_manager: "0xe069096bDAfF9bAD15b2f1079EaF0f1685a24522",
      v4_all_hubs_0: "0xd07369fAE4A5BB13c9Ce446B052c7867B1AbDf6e",
      v4_all_spokes_0: "0x435272CefF93a1E657E8ABfdf0A13e95900A3a56",
      v4_all_spokes_1: "0x6a37776B5E026dBdF043b4F933c323C84DD1B514",
      v4_all_spokes_2: "0x3b517594277c67307CF2d7CBE6FE1D4399B68c41",
      v4_all_spokes_raw_0: "0x2C4Aea1A5F000889c6DfFE8f52377aFc2CB113a6",
      v4_all_spokes_raw_1: "0x435272CefF93a1E657E8ABfdf0A13e95900A3a56",
      v4_all_spokes_raw_2: "0x6a37776B5E026dBdF043b4F933c323C84DD1B514",
      v4_all_spokes_raw_3: "0x3b517594277c67307CF2d7CBE6FE1D4399B68c41",
      v4_all_spokes_raw_4: "0x1604D602f8A05CBA2d8Ff5d14DE4C3498f15B6B4",
      v4_all_spokes_raw_5: "0x7cd3Ccc737f442050a861EC6b00768AE96B2F58E",
      v4_all_spokes_raw_6: "0x01D7f7B7CE2123192fECC20bd1caF3e4d9e4C10D",
      v4_all_spokes_raw_7: "0x2E4BA06fF97E10D09FA4F5a270e97301eae729A9",
      v4_all_spokes_raw_8: "0xF5c849468318c8D5670020fdb96ae135FED37070",
      v4_all_spokes_raw_9: "0x7b538a1840EAf2Ed92EEB67eE744AE627335e201",
      v4_all_spokes_raw_10: "0x6c27A7435040B7cC512319d5690BeEF234dfE76e",
      v4_all_tokenized_spokes_0: "0x1604D602f8A05CBA2d8Ff5d14DE4C3498f15B6B4",
      v4_all_tokenized_spokes_1: "0x7cd3Ccc737f442050a861EC6b00768AE96B2F58E",
      v4_all_tokenized_spokes_2: "0x01D7f7B7CE2123192fECC20bd1caF3e4d9e4C10D",
      v4_all_tokenized_spokes_3: "0x2E4BA06fF97E10D09FA4F5a270e97301eae729A9",
      v4_all_tokenized_spokes_4: "0xF5c849468318c8D5670020fdb96ae135FED37070",
      v4_all_tokenized_spokes_5: "0x7b538a1840EAf2Ed92EEB67eE744AE627335e201",
      v4_all_tokenized_spokes_6: "0x6c27A7435040B7cC512319d5690BeEF234dfE76e",
      v4_assets_wavax_underlying: "0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7",
      v4_assets_btc_b_underlying: "0x152b9d0FdC40C096757F570A51E494bd4b943E50",
      v4_assets_usdc_underlying: "0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E",
      v4_assets_usdt_underlying: "0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7",
      v4_assets_weth_e_underlying: "0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB",
      v4_assets_eurc_underlying: "0xC891EB4cbdEFf6e073e859e987815Ed1505c2ACD",
      v4_assets_savax_underlying: "0x2b2C81e08f1Af8835a78Bb2A90AE924ACE0eA4bE",
      v4_config_engine: "0x1F0C67Fde7FcaF7eCEA43b76A23461803972c45c",
      v4_liquidation_logic: "0x88dF535473C5adf1f57789734A05E555F7Deb8DB",
      v4_core_hub: "0xd07369fAE4A5BB13c9Ce446B052c7867B1AbDf6e",
      v4_hub_configurator: "0xbdf92ed96FF6D678469aFAFFa1e7d37B25beaa33",
      v4_core_wavax_ir_strategy: "0x446eb3913b3fd3a9219A07B0f6AbE98BD0fAeed4",
      v4_core_btcb_ir_strategy: "0x446eb3913b3fd3a9219A07B0f6AbE98BD0fAeed4",
      v4_core_usdc_ir_strategy: "0x446eb3913b3fd3a9219A07B0f6AbE98BD0fAeed4",
      v4_core_usdt_ir_strategy: "0x446eb3913b3fd3a9219A07B0f6AbE98BD0fAeed4",
      v4_core_wethe_ir_strategy: "0x446eb3913b3fd3a9219A07B0f6AbE98BD0fAeed4",
      v4_core_eurc_ir_strategy: "0x446eb3913b3fd3a9219A07B0f6AbE98BD0fAeed4",
      v4_core_savax_ir_strategy: "0x446eb3913b3fd3a9219A07B0f6AbE98BD0fAeed4",
      v4_giver_position_manager: "0x50c4C40aB6BaE46B372a251BEacE388439aa96b4",
      v4_taker_position_manager: "0x5A5A711560eb9293Ef6F4bc33CD8589b4A603D10",
      v4_config_position_manager: "0x50BE00C5EbF6CC230B8970f4205Cd0B5A70EaEB1",
      v4_native_token_gateway: "0xE4C7183A5f22c365140F41d733d8A8baD5A1a6bA",
      v4_signature_gateway: "0x6E3B91A951DA9b515a5E98F0c7D210a697382e7F",
      v4_treasury_spoke: "0x2C4Aea1A5F000889c6DfFE8f52377aFc2CB113a6",
      v4_main_spoke: "0x435272CefF93a1E657E8ABfdf0A13e95900A3a56",
      v4_main_spoke_oracle: "0x84B50B131a82dA689C0205C00d603c1c92A5f8a4",
      v4_forex_spoke: "0x6a37776B5E026dBdF043b4F933c323C84DD1B514",
      v4_forex_spoke_oracle: "0xECA623E8c923A103Eef75cd127Cc8Bf8fF886cf5",
      v4_avax_correlated_spoke: "0x3b517594277c67307CF2d7CBE6FE1D4399B68c41",
      v4_avax_correlated_spoke_oracle: "0xB2216B2B2DC77e027AfEaaAf965E323012757fA0",
      v4_spoke_configurator: "0x8F72573F1Aa0A1e39fFD2a2A69e9EDAa8B982642",
      v4_main_spoke_wavax_price_feed: "0x0A77230d17318075983913bC2145DB16C7366156",
      v4_main_spoke_btcb_price_feed: "0x2779D32d5166BAaa2B2b658333bA7e6Ec0C65743",
      v4_main_spoke_usdc_price_feed: "0xb0D7A8bbDcdb1203850b742bB4d7f57a1F1C8483",
      v4_main_spoke_usdt_price_feed: "0x5b7810a910B4a878AaA4800a824E5E5796838009",
      v4_main_spoke_wethe_price_feed: "0x976B3D034E162d8bD72D6b9C989d545b839003b0",
      v4_main_spoke_eurc_price_feed: "0x3368310bC4AeE5D96486A73bae8E6b49FcDE62D3",
      v4_forex_spoke_eurc_price_feed: "0x3368310bC4AeE5D96486A73bae8E6b49FcDE62D3",
      v4_forex_spoke_usdc_price_feed: "0xb0D7A8bbDcdb1203850b742bB4d7f57a1F1C8483",
      v4_forex_spoke_usdt_price_feed: "0x5b7810a910B4a878AaA4800a824E5E5796838009",
      v4_avax_correlated_spoke_savax_price_feed: "0xB2B332f27e4B7305649a228C31Ed9858c5a6bAD9",
      v4_avax_correlated_spoke_wavax_price_feed: "0x0A77230d17318075983913bC2145DB16C7366156",
      v4_core_wavax_tokenization_spoke: "0x1604D602f8A05CBA2d8Ff5d14DE4C3498f15B6B4",
      v4_core_btcb_tokenization_spoke: "0x7cd3Ccc737f442050a861EC6b00768AE96B2F58E",
      v4_core_usdc_tokenization_spoke: "0x01D7f7B7CE2123192fECC20bd1caF3e4d9e4C10D",
      v4_core_usdt_tokenization_spoke: "0x2E4BA06fF97E10D09FA4F5a270e97301eae729A9",
      v4_core_wethe_tokenization_spoke: "0xF5c849468318c8D5670020fdb96ae135FED37070",
      v4_core_eurc_tokenization_spoke: "0x7b538a1840EAf2Ed92EEB67eE744AE627335e201",
      v4_core_savax_tokenization_spoke: "0x6c27A7435040B7cC512319d5690BeEF234dfE76e"
    }
  }

  @v4_tokenization_spokes %{
    ethereum: %{
      core: %{
        weth: "0x7320CF22Ac095bA2a2e0a652F77efB836c2E751b",
        wsteth: "0xcb0E7dA9c635628f6d4827355AeCa75aB8d3560f",
        weeth: "0x559cEc2C840D9DBB18936Afc5E5341D78bfC7Cbe",
        rseth: "0x45a04Ca1A5cbEeA4B44356c75EDd29b33eB2527a",
        usdt: "0x5eC44a70F309854fe04d495cFE1B5dA63DD1cc73",
        usdc: "0x531E90a2376902DE8915789Fcc1075e3B0c153E7",
        gho: "0x58C14a5E061c9bC6926c5b853445290F296C2F7B",
        rlusd: "0xC8a125AE4275a78AADc53B46Ca10566Bc9B249E0",
        usdg: "0xAC2435E3C25e8246870D33ce0a26988A46d5DB68",
        frxusd: "0x2226749630775ee20230Ad65214fB339087eF30D",
        eurc: "0x6D9e2Cdd61CaF69af99b275704B6e272C41c6718",
        wbtc: "0x82A9CC4656784E55Ef2E78F704028B5E1Bfc1732",
        cbbtc: "0x33B41B74366F55327d959FfF6D6b6fBc2853dbB1",
        lbtc: "0x7961F140B570490849DB878AE222570ea838799d",
        xaut: "0x4E712562fcb5337011398B6C630f55b60641cd5e",
        aave: "0x0A65197b16C5969F92672051c9C9C0C75B369135",
        link: "0xE69C2045095C8Ab3E2a7d77de2328faE5baF797c"
      },
      plus: %{
        pt_susde_7may2026: "0x90774889c22D2F2Adf44da1f04C7c95542590df4",
        pt_usde_7may2026: "0xdd2Eb78BF9e6aC5068B95aD2d451e8c9Af10ac81",
        susde: "0x24f8c062e1E0451736C1D6E023510DA262a41df4",
        usde: "0x502Cd81da6a8F1785eb2eEE72713B7388E16A854",
        usdc: "0xc94bdd83D2c7655C280655D60954e79E88D4F949",
        gho: "0xA54382db40EC602c0a173A08f9E86Ed40F9D4D10",
        usdt: "0x80835EB50694EE0e519743f67e5401e6FD300006",
        pt_susde: "0x90774889c22D2F2Adf44da1f04C7c95542590df4",
        pt_usde: "0xdd2Eb78BF9e6aC5068B95aD2d451e8c9Af10ac81"
      },
      prime: %{
        weth: "0x2087513383330B961A3753B47627Bbf149F31c70",
        wbtc: "0x5AE3d87De89CA6Ce501e8317887F71EABED69E18",
        cbbtc: "0xD38098faf52D8E915EdED84fBF30F81C17906938",
        wsteth: "0xFCD3D3C69cd032DE0cc78fE529B7447D2fe7F666",
        usdc: "0x486415fb1F8b062c89ED548f871cf64304AACb31",
        usdt: "0x46c588DD8453aC259c1f6a54b4C9A93C2aC3762D",
        gho: "0x900fD46d565d1ac8995928c0179052ec02a6D0E1"
      },
      global_dollar: %{
        pt_usdg_24sep2026: "0x7Df10B4A01350D2A1d95cFbE7c9207d7210A2663",
        usdc: "0xaed7c529bD2878170B61C758DfAa215AC7a4FD07",
        usdt: "0xa0e97e45C2f89003730E467Bd484fA3eEcE5B4Cf",
        usdg: "0x378B4a7c394E22bd562F66eB612165893533c124",
        paxg: "0x6493a23874b506D5Bb6038ea44aE9CC74cD00849"
      }
    },
    avalanche: %{
      core: %{
        wavax: "0x1604D602f8A05CBA2d8Ff5d14DE4C3498f15B6B4",
        btcb: "0x7cd3Ccc737f442050a861EC6b00768AE96B2F58E",
        usdc: "0x01D7f7B7CE2123192fECC20bd1caF3e4d9e4C10D",
        usdt: "0x2E4BA06fF97E10D09FA4F5a270e97301eae729A9",
        wethe: "0xF5c849468318c8D5670020fdb96ae135FED37070",
        eurc: "0x7b538a1840EAf2Ed92EEB67eE744AE627335e201",
        savax: "0x6c27A7435040B7cC512319d5690BeEF234dfE76e"
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
      hub: [kind: :value, description: "Registered Hub atom, e.g. :core or :global_dollar"],
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
  def networks, do: Map.keys(Map.merge(@addresses, @v4_addresses))

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
