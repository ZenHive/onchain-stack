# Aave V4 Scoping

**Captured:** 2026-04-20 during Task 44
**Purpose:** enumerate the Aave V4 mainnet contract surface as the basis for follow-on wrapper tasks (see ROADMAP.md Tasks 45+). This doc is the **source of truth for V4 addresses and ABI pointers** — downstream tasks should link here rather than duplicating the data. Which chains and instances exist *now* (including deployments this snapshot does not list) is in [V4_DEPLOYMENTS.md](V4_DEPLOYMENTS.md).

V4 went live on Ethereum mainnet on **2026-03-30** (AIP executed; Snapshot passed 2026-03-23, 100% support). Deployment uses a **Hub-and-Spoke architecture** that is materially different from V3's single-`Pool` model — this is not a drop-in interface addition. Most user-facing V4 work lands as new wrapper modules under `Onchain.Aave.V4.*` alongside the V3 tree, while shared support modules like `Contracts` are extended in place.

---

## Sources

**Governance / announcements**
- Blog: https://aave.com/blog/aave-v4-live-ethereum
- ARFC (activation proposal): https://governance.aave.com/t/arfc-aave-v4-activation-on-ethereum-mainnet/24293
- Hub-and-Spoke Initial Configurations: https://governance.aave.com/t/aave-v4-hub-and-spoke-initial-configurations/24233
- Snapshot vote: https://snapshot.org/#/s:aavedao.eth/proposal/0x55e85a32828da36122b9c8d50548696d7c748fd41c775f5bf06bdf0f2e32a265

**Contracts / ABIs**
- Canonical source repo: https://github.com/aave/aave-v4 (Solidity source + audits under `/audits`)
- Address book (entries we consume): https://github.com/bgd-labs/aave-address-book — `src/AaveV4Ethereum.sol` + `safe.csv`
- ABI-bearing interface files (in `aave-v4/src/`):
  - `hub/interfaces/` → `IHub.sol`, `IHubBase.sol`, `IHubConfigurator.sol`, `IBasicInterestRateStrategy.sol`, `IAssetInterestRateStrategy.sol`
  - `spoke/interfaces/` → `ISpoke.sol`, `ISpokeConfigurator.sol`, `ITokenizationSpoke.sol`, `ITreasurySpoke.sol`, `IAaveOracle.sol`, `IPriceFeed.sol`, `IPriceOracle.sol`
  - `position-manager/interfaces/` → `IConfigPositionManager.sol`, `IGiverPositionManager.sol`, `ITakerPositionManager.sol`, `INativeTokenGateway.sol`, `ISignatureGateway.sol`
  - `config-engine/interfaces/` → `IAaveV4ConfigEngine.sol`
  - `access/interfaces/` → `IAccessManagerEnumerable.sol`

The bgd-labs CSV (`safe.csv`, 5238 rows, 150 of them prefixed `AaveV4Ethereum`) is the same source used for V3 verification per CLAUDE.md. Every address below was pulled from it.

---

## Architecture Summary

V4 splits V3's monolithic `Pool` into three layers:

1. **Hubs** (routing + rate environment + credit-line source) — `IHub`. There are three: Core, Prime, Plus. A Hub owns stablecoin inventory and emits credit lines to its member Spokes.
2. **Spokes** (risk-isolated borrow venues) — `ISpoke`. Each Spoke has its own collateral set, borrowable set, liquidation params, oracle, and per-Spoke add/draw caps. e-Mode is now per-Spoke (one collateral, one borrowable) rather than a mode flag on a shared pool.
3. **Tokenization Spokes** (ERC-4626 supply-only positions) — `ITokenizationSpoke`. Every supply position is its own tokenization contract, per (Hub, asset) pair.

Supporting contracts: `IHubConfigurator`, `ISpokeConfigurator`, `IAaveV4ConfigEngine`, `IAccessManagerEnumerable`, and a family of Position Managers.

**Breaking changes vs V3 (confirmed from the three governance sources):**
- Stable rate borrowing is gone — only variable rate (`:interest_rate_mode` option on V3's `Pool.borrow/4` becomes meaningless under V4).
- `getUserAccountData/1` at the Pool is gone — per-user health lives at the Spoke and is shaped per Spoke's collateral/borrow set.
- Oracle is per-Spoke (`IAaveOracle` as a Spoke property), not a single `AaveOracle` across the protocol. The V3 fallback-oracle / base-currency-unit concept still exists but is scoped to each Spoke.
- Deposits mint ERC-4626 shares (Tokenization Spokes), not V3-style aTokens.

---

## Infrastructure (top-level)

| Name | Address | Interface |
|------|---------|-----------|
| Access Manager | [0x08aE3BE30958cDd1847ec58fFfd4C451a87fDF01](https://etherscan.io/address/0x08aE3BE30958cDd1847ec58fFfd4C451a87fDF01) | `IAccessManagerEnumerable` |
| Hub Configurator | [0x1F0753480bB03EaA00863224602267B7E0525C3d](https://etherscan.io/address/0x1F0753480bB03EaA00863224602267B7E0525C3d) | `IHubConfigurator` |
| Spoke Configurator | [0x9BFFf48BFb5A7AE70c348d4d4cb97E8DEFa5389a](https://etherscan.io/address/0x9BFFf48BFb5A7AE70c348d4d4cb97E8DEFa5389a) | `ISpokeConfigurator` |
| Config Engine | [0xe8096f931734286a95b6A63eFFCEFD3C56F3f6a9](https://etherscan.io/address/0xe8096f931734286a95b6A63eFFCEFD3C56F3f6a9) | `IAaveV4ConfigEngine` |
| Liquidation Logic (ext lib) | [0x88dF535473C5adf1f57789734A05E555F7Deb8DB](https://etherscan.io/address/0x88dF535473C5adf1f57789734A05E555F7Deb8DB) | — (external library) |
| Treasury Spoke | [0xB9B0b8616f6Bf6841972a52058132BE08d723155](https://etherscan.io/address/0xB9B0b8616f6Bf6841972a52058132BE08d723155) | `ITreasurySpoke` |

## Position Managers

User-facing gateways that wrap Hub/Spoke calls with ergonomic operations (permit/signature, native ETH gateway, position configuration).

| Name | Address | Interface |
|------|---------|-----------|
| Config Position Manager | [0x51305839CE822a7b4b12AA7D86eA7005052d575c](https://etherscan.io/address/0x51305839CE822a7b4b12AA7D86eA7005052d575c) | `IConfigPositionManager` |
| Giver Position Manager | [0x17A54b8d6D9C68e7fa1C7112AC998EA1BA51d11e](https://etherscan.io/address/0x17A54b8d6D9C68e7fa1C7112AC998EA1BA51d11e) | `IGiverPositionManager` |
| Taker Position Manager | [0x6c044c0D3801499bCAbfAd458B70880bc518e9F7](https://etherscan.io/address/0x6c044c0D3801499bCAbfAd458B70880bc518e9F7) | `ITakerPositionManager` |
| Native Token Gateway | [0xe68ab4F90Fe026B9873F5F276eD2d7efBbbE42Be](https://etherscan.io/address/0xe68ab4F90Fe026B9873F5F276eD2d7efBbbE42Be) | `INativeTokenGateway` |
| Signature Gateway | [0xfbC184337Dc6595D8bf62968Bda46e7De7AF9c3d](https://etherscan.io/address/0xfbC184337Dc6595D8bf62968Bda46e7De7AF9c3d) | `ISignatureGateway` |

## Hubs

| Hub | Address | Role |
|-----|---------|------|
| Core Hub | [0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9](https://etherscan.io/address/0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9) | Primary liquidity + routing venue. Default rate environment. Sends credit lines to Plus Hub. |
| Prime Hub | [0x943827DCA022D0F354a8a8c332dA1e5Eb9f9F931](https://etherscan.io/address/0x943827DCA022D0F354a8a8c332dA1e5Eb9f9F931) | Suppliers wanting collateral unavailable for borrowing (non-borrowable collateral environment). |
| Plus Hub | [0x06002e9c4412CB7814a791eA3666D905871E536A](https://etherscan.io/address/0x06002e9c4412CB7814a791eA3666D905871E536A) | Strategy-heavy stablecoin venue (Ethena ecosystem). Draws stablecoins from Core via credit lines. |

Interface: `IHub` + `IHubBase`.

## Spokes

Each Spoke is a self-contained borrow venue with its own `IAaveOracle`. Hub membership is implied by which Hub owns the Spoke's credit lines.

### Core Hub Spokes

| Spoke | Address | Oracle | Role |
|-------|---------|--------|------|
| Main Spoke | [0x94e7A5dCbE816e498b89aB752661904E2F56c485](https://etherscan.io/address/0x94e7A5dCbE816e498b89aB752661904E2F56c485) | [0x99B2B6CEa9C3D2fd8F4d90f86741C44B212a6127](https://etherscan.io/address/0x99B2B6CEa9C3D2fd8F4d90f86741C44B212a6127) | General-purpose (WETH, wstETH, weETH, WBTC, cbBTC, USDT, USDC, LINK, AAVE) |
| Lido Spoke (e-Mode) | [0xe1900480ac69f0B296841Cd01cC37546d92F35Cd](https://etherscan.io/address/0xe1900480ac69f0B296841Cd01cC37546d92F35Cd) | [0x664D73b6C3591333Fd79510f7ce9ef81228824F5](https://etherscan.io/address/0x664D73b6C3591333Fd79510f7ce9ef81228824F5) | wstETH collateral → WETH borrow |
| EtherFi Spoke (e-Mode) | [0xbF10BDfE177dE0336aFD7fcCF80A904E15386219](https://etherscan.io/address/0xbF10BDfE177dE0336aFD7fcCF80A904E15386219) | [0xd8B153FaAA8f2b1bC774916FEd333A4F3dE48792](https://etherscan.io/address/0xd8B153FaAA8f2b1bC774916FEd333A4F3dE48792) | weETH collateral → WETH borrow |
| Kelp Spoke (e-Mode) | [0x3131FE68C4722e726fe6B2819ED68e514395B9a4](https://etherscan.io/address/0x3131FE68C4722e726fe6B2819ED68e514395B9a4) | [0x37C316996C714Bf906743071e04E62220b3271ac](https://etherscan.io/address/0x37C316996C714Bf906743071e04E62220b3271ac) | rsETH collateral → WETH borrow |
| Lombard BTC Spoke | [0x7EC68b5695e803e98a21a9A05d744F28b0a7753D](https://etherscan.io/address/0x7EC68b5695e803e98a21a9A05d744F28b0a7753D) | [0x198Cac7f54FFc7d709Ac0FEc4B6454CE73e21D3D](https://etherscan.io/address/0x198Cac7f54FFc7d709Ac0FEc4B6454CE73e21D3D) | LBTC collateral → WBTC / cbBTC borrow |
| Gold Spoke | [0x65407b940966954b23dfA3caA5C0702bB42984DC](https://etherscan.io/address/0x65407b940966954b23dfA3caA5C0702bB42984DC) | [0x0083421fd178749af2201ddA5A7C3feB5790B80c](https://etherscan.io/address/0x0083421fd178749af2201ddA5A7C3feB5790B80c) | XAUt collateral → stablecoin borrow |
| Forex Spoke | [0xD8B93635b8C6d0fF98CbE90b5988E3F2d1Cd9da1](https://etherscan.io/address/0xD8B93635b8C6d0fF98CbE90b5988E3F2d1Cd9da1) | [0xB3CE6E7b6d389a66eA4a3777bA07219d00FB3a9D](https://etherscan.io/address/0xB3CE6E7b6d389a66eA4a3777bA07219d00FB3a9D) | USDC / USDT / EURC multi-stablecoin |

### Prime Hub Spokes

| Spoke | Address | Oracle | Role |
|-------|---------|--------|------|
| Bluechip Spoke | [0x973a023A77420ba610f06b3858aD991Df6d85A08](https://etherscan.io/address/0x973a023A77420ba610f06b3858aD991Df6d85A08) | [0xdA1266a7b8620819dAE3F8bd6B546Da36e505bB8](https://etherscan.io/address/0xdA1266a7b8620819dAE3F8bd6B546Da36e505bB8) | Non-borrowable collateral (WETH, wstETH, WBTC, cbBTC) |

### Plus Hub Spokes

| Spoke | Address | Oracle | Role |
|-------|---------|--------|------|
| Ethena Ecosystem Spoke | [0xba1B3D55D249692b669A164024A838309B7508AF](https://etherscan.io/address/0xba1B3D55D249692b669A164024A838309B7508AF) | [0xc390dbe9fc00D6db73C52d375642b47008C33c90](https://etherscan.io/address/0xc390dbe9fc00D6db73C52d375642b47008C33c90) | PT-sUSDe / sUSDe / USDe collateral; credit-line backed by Core |
| Ethena Correlated Spoke | [0x58131E79531caB1d52301228d1f7b842F26B9649](https://etherscan.io/address/0x58131E79531caB1d52301228d1f7b842F26B9649) | [0x9b91a0943CADf554742E8Fb358B1cC4ae4F85F01](https://etherscan.io/address/0x9b91a0943CADf554742E8Fb358B1cC4ae4F85F01) | PT-sUSDe / PT-USDe / sUSDe / USDe → USDe only |

Interface: `ISpoke` (each Spoke); `IAaveOracle` (each Spoke's oracle).

## Tokenization Spokes

ERC-4626 supply-only vaults, one per (Hub, underlying-asset). Interface: `ITokenizationSpoke`.

### Core Hub (17)

| Asset | Address |
|-------|---------|
| AAVE | [0x0A65197b16C5969F92672051c9C9C0C75B369135](https://etherscan.io/address/0x0A65197b16C5969F92672051c9C9C0C75B369135) |
| cbBTC | [0x33B41B74366F55327d959FfF6D6b6fBc2853dbB1](https://etherscan.io/address/0x33B41B74366F55327d959FfF6D6b6fBc2853dbB1) |
| EURC | [0x6D9e2Cdd61CaF69af99b275704B6e272C41c6718](https://etherscan.io/address/0x6D9e2Cdd61CaF69af99b275704B6e272C41c6718) |
| frxUSD | [0x2226749630775ee20230Ad65214fB339087eF30D](https://etherscan.io/address/0x2226749630775ee20230Ad65214fB339087eF30D) |
| GHO | [0x58C14a5E061c9bC6926c5b853445290F296C2F7B](https://etherscan.io/address/0x58C14a5E061c9bC6926c5b853445290F296C2F7B) |
| LBTC | [0x7961F140B570490849DB878AE222570ea838799d](https://etherscan.io/address/0x7961F140B570490849DB878AE222570ea838799d) |
| LINK | [0xE69C2045095C8Ab3E2a7d77de2328faE5baF797c](https://etherscan.io/address/0xE69C2045095C8Ab3E2a7d77de2328faE5baF797c) |
| RLUSD | [0xC8a125AE4275a78AADc53B46Ca10566Bc9B249E0](https://etherscan.io/address/0xC8a125AE4275a78AADc53B46Ca10566Bc9B249E0) |
| rsETH | [0x45a04Ca1A5cbEeA4B44356c75EDd29b33eB2527a](https://etherscan.io/address/0x45a04Ca1A5cbEeA4B44356c75EDd29b33eB2527a) |
| USDC | [0x531E90a2376902DE8915789Fcc1075e3B0c153E7](https://etherscan.io/address/0x531E90a2376902DE8915789Fcc1075e3B0c153E7) |
| USDG | [0xAC2435E3C25e8246870D33ce0a26988A46d5DB68](https://etherscan.io/address/0xAC2435E3C25e8246870D33ce0a26988A46d5DB68) |
| USDT | [0x5eC44a70F309854fe04d495cFE1B5dA63DD1cc73](https://etherscan.io/address/0x5eC44a70F309854fe04d495cFE1B5dA63DD1cc73) |
| WBTC | [0x82A9CC4656784E55Ef2E78F704028B5E1Bfc1732](https://etherscan.io/address/0x82A9CC4656784E55Ef2E78F704028B5E1Bfc1732) |
| weETH | [0x559cEc2C840D9DBB18936Afc5E5341D78bfC7Cbe](https://etherscan.io/address/0x559cEc2C840D9DBB18936Afc5E5341D78bfC7Cbe) |
| WETH | [0x7320CF22Ac095bA2a2e0a652F77efB836c2E751b](https://etherscan.io/address/0x7320CF22Ac095bA2a2e0a652F77efB836c2E751b) |
| wstETH | [0xcb0E7dA9c635628f6d4827355AeCa75aB8d3560f](https://etherscan.io/address/0xcb0E7dA9c635628f6d4827355AeCa75aB8d3560f) |
| XAUt | [0x4E712562fcb5337011398B6C630f55b60641cd5e](https://etherscan.io/address/0x4E712562fcb5337011398B6C630f55b60641cd5e) |

### Prime Hub (7)

| Asset | Address |
|-------|---------|
| cbBTC | [0xD38098faf52D8E915EdED84fBF30F81C17906938](https://etherscan.io/address/0xD38098faf52D8E915EdED84fBF30F81C17906938) |
| GHO | [0x900fD46d565d1ac8995928c0179052ec02a6D0E1](https://etherscan.io/address/0x900fD46d565d1ac8995928c0179052ec02a6D0E1) |
| USDC | [0x486415fb1F8b062c89ED548f871cf64304AACb31](https://etherscan.io/address/0x486415fb1F8b062c89ED548f871cf64304AACb31) |
| USDT | [0x46c588DD8453aC259c1f6a54b4C9A93C2aC3762D](https://etherscan.io/address/0x46c588DD8453aC259c1f6a54b4C9A93C2aC3762D) |
| WBTC | [0x5AE3d87De89CA6Ce501e8317887F71EABED69E18](https://etherscan.io/address/0x5AE3d87De89CA6Ce501e8317887F71EABED69E18) |
| WETH | [0x2087513383330B961A3753B47627Bbf149F31c70](https://etherscan.io/address/0x2087513383330B961A3753B47627Bbf149F31c70) |
| wstETH | [0xFCD3D3C69cd032DE0cc78fE529B7447D2fe7F666](https://etherscan.io/address/0xFCD3D3C69cd032DE0cc78fE529B7447D2fe7F666) |

### Plus Hub (7)

| Asset | Address |
|-------|---------|
| GHO | [0xA54382db40EC602c0a173A08f9E86Ed40F9D4D10](https://etherscan.io/address/0xA54382db40EC602c0a173A08f9E86Ed40F9D4D10) |
| PT-sUSDe (7MAY2026) | [0x90774889c22D2F2Adf44da1f04C7c95542590df4](https://etherscan.io/address/0x90774889c22D2F2Adf44da1f04C7c95542590df4) |
| PT-USDe (7MAY2026) | [0xdd2Eb78BF9e6aC5068B95aD2d451e8c9Af10ac81](https://etherscan.io/address/0xdd2Eb78BF9e6aC5068B95aD2d451e8c9Af10ac81) |
| sUSDe | [0x24f8c062e1E0451736C1D6E023510DA262a41df4](https://etherscan.io/address/0x24f8c062e1E0451736C1D6E023510DA262a41df4) |
| USDC | [0xc94bdd83D2c7655C280655D60954e79E88D4F949](https://etherscan.io/address/0xc94bdd83D2c7655C280655D60954e79E88D4F949) |
| USDe | [0x502Cd81da6a8F1785eb2eEE72713B7388E16A854](https://etherscan.io/address/0x502Cd81da6a8F1785eb2eEE72713B7388E16A854) |
| USDT | [0x80835EB50694EE0e519743f67e5401e6FD300006](https://etherscan.io/address/0x80835EB50694EE0e519743f67e5401e6FD300006) |

## Spoke Price Feeds

63 entries total under `AaveV4Ethereum SPOKE_PRICE_FEEDS`. Distribution by Spoke family:

| Spoke family | Price feeds |
|--------------|-------------|
| Main | 14 |
| Ethena (Correlated + Ecosystem) | 14 |
| Bluechip | 11 |
| Gold | 8 |
| Forex | 7 |
| Lombard | 3 |
| EtherFi | 2 |
| Kelp | 2 |
| Lido | 2 |

Per-feed addresses are not enumerated here — pull them from `safe.csv` grep `"AaveV4Ethereum SPOKE_PRICE_FEEDS"` or from the `bgd-labs/aave-address-book` Solidity exports. Relevant structure: each (Spoke, asset) pair has one price feed, sometimes shared across Spoke families (e.g. Chainlink WETH/USD is reused).

## Underlying Assets (21)

Listed once per protocol under `AaveV4Ethereum ASSETS <SYMBOL> UNDERLYING`:

AAVE, cbBTC, EURC, frxUSD, GHO, LBTC, LINK, PT-sUSDe (7MAY2026), PT-USDe (7MAY2026), RLUSD, rsETH, sUSDe, USDC, USDe, USDG, USDT, WBTC, weETH, WETH, wstETH, XAUt.

These are the canonical ERC-20 addresses, independent of Aave. Same list already covered by the broader onchain token registry — the V4 wrapper does not need to re-declare them, just reference them.

---

## V3 → V4 Module Mapping

How each current `onchain_aave` V3 module maps to V4:

| V3 module | V4 mapping | Decision |
|-----------|------------|----------|
| `Onchain.Aave.Contracts` | **Extend** — add a V4 address namespace. Keys: `:v4_access_manager`, `:v4_hub_configurator`, `:v4_spoke_configurator`, `:v4_config_engine`, `:v4_liquidation_logic`, `:v4_treasury_spoke`, `:v4_core_hub`, `:v4_prime_hub`, `:v4_plus_hub`, `:v4_main_spoke`, `:v4_lido_spoke`, etc.; plus per-Spoke oracle keys and per-(Hub,asset) tokenization spoke keys. For tokenization spokes consider a nested lookup like `v4_tokenization_spoke(:core, :weth)` to avoid 31 flat atoms. | Single module, V4 keys added alongside V3 keys. Task 45 decides key shape. |
| `Onchain.Aave.Pool` | **Replaced**, not extended. V4 has no `Pool` — user-facing ops go through Position Managers + Hub + Spoke. Build new modules: `Onchain.Aave.V4.Hub`, `Onchain.Aave.V4.Spoke`, `Onchain.Aave.V4.TokenizationSpoke`, `Onchain.Aave.V4.PositionManager.*`. | V4 sibling tree under `Onchain.Aave.V4.*`. V3 `Pool` stays untouched. |
| `Onchain.Aave.UiPoolDataProvider` | **Unknown** — no direct V4 analog visible in the address book. V3's UiPoolDataProvider bundled many reads; in V4 the equivalent is likely per-Spoke reads through `ISpoke` + per-Hub reads through `IHub`, with no separate UI contract. Verify by inspecting `IHub` / `ISpoke` interfaces before deciding. | Deferred to Task 46 (read-surface selection) — no V4 equivalent address captured here. If genuinely absent, consumers build reads module-by-module; we can ship a convenience aggregator later. |
| `Onchain.Aave.Oracle` | **Sibling** — V4's `IAaveOracle` is Spoke-scoped, not protocol-scoped. A `Onchain.Aave.V4.Oracle` module would take a Spoke address instead of a network. The per-asset price-feed pattern (Chainlink aggregator lookup) is similar enough to V3 that most function shapes carry over. | V4 sibling module that takes Spoke address. |
| Types — `UserAccountData` | **Sibling** — V4 has no protocol-wide user account data; health factor is per-Spoke. `Onchain.Aave.V4.Types.SpokeUserData` or similar. | V4 type; V3 type unchanged. |
| Types — `AggregatedReserveData` (40 fields) | **Sibling, highest-risk port** — V4 reserves are Spoke-local with different metadata (no stable rate fields, credit-line references, tokenization-spoke share price). A direct extension would be wrong. | V4 type needed; likely its own task given V3's had 40 fields. |
| Types — `UserReserveData`, `BaseCurrencyInfo` | **Sibling or drop.** Likely supplanted by `ISpoke` direct reads + `IAaveOracle` base-currency reads. | Assess during Task 46 (read-surface selection). |
| `Onchain.Aave.Faucet` | **Not applicable yet** — no V4 testnet faucet discovered in the address book. Sepolia V4 may not exist yet; deferred. | No V4 faucet work under current tasks. |

## Genuinely New Concepts (no V3 analog)

1. **Credit lines** (`IHub` credit-line methods). Core Hub funds Plus Hub / Bluechip Spoke with stablecoin allocations bounded by a cap. Querying "available borrow at Spoke X" now requires reading both the Spoke's add/draw cap and the Hub's credit-line cap.
2. **Position Managers** as ergonomic intermediaries. V3 users call `Pool.supply` directly; V4 users call Position Manager methods that internally coordinate Hub + Spoke + Tokenization-Spoke steps. Our wrapper should expose Position Manager entrypoints as primary, not raw Hub/Spoke, for the common flows.
3. **Tokenization Spokes as ERC-4626**. Supply positions are fungible vault shares, not aTokens. Interoperates with the broader ERC-4626 ecosystem (routers, vaults, integrators).
4. **Per-Spoke e-Mode**. V3's `eMode` was a user mode flag; V4 replaces it with dedicated Spokes per (collateral, borrowable) pair. Wrapping e-Mode no longer means handling a category ID — it means calling the right Spoke contract.
5. **Access Manager instead of Pool-admin pattern**. V4 uses OpenZeppelin-style role-based access, not V3's `PoolAdmin` + `RiskAdmin` roles. Read-only consumers are unaffected; any admin tooling (not currently in scope) would diverge.

---

## Open Questions (resolved by Task 46)

1. **`IHub` / `ISpoke` read surface + getUserAccountData mapping.** Completed. See "V4 Read Surface Diff vs V3 IPool + IUiPoolDataProvider" below. Minimum read set that mirrors `getUserAccountData` behavior: `ISpoke.getUserAccountData(address)` (per-Spoke) plus supporting `getUser*` / `getReserve*` / `getLiquidation*` reads on the Spoke and price reads on its `IAaveOracle`. Hub reads are additive for credit-line / liquidity accounting (no V3 Pool equivalent).
2. **Tokenization spoke key shape.** Deferred to Task 45 (per plan).
3. **UiPoolDataProvider analog.** Completed. No V4 analog exists (no address in bgd-labs/aave-address-book AaveV4Ethereum entries; no `I*DataProvider` or equivalent bulk contract in `aave-v4/src/{hub,spoke,config-engine}/interfaces/`). V4 expects direct or multicall reads against `ISpoke` (per market/Spoke) + `IHub` + `IAaveOracle` + `ITokenizationSpoke` (ERC-4626). Aave Interface / pro.aave.com usage not required for this diff (contracts show the surface); downstream wrappers will compose or later add an aggregator if needed.
4. **Multi-chain rollout.** Deferred (not in scope for read-surface diff).
5. **Coordination with Task 42 (V4 math cross-validation via revm).** Deferred (not in scope for read-surface diff).

---

## V4 Read Surface Diff vs V3 IPool + IUiPoolDataProvider (Task 46)

**Sources fetched (raw GitHub, 2026-04):**  
- V4: `aave/aave-v4/src/{hub,spoke,config-engine}/interfaces/` → `IHub.sol` (incl `IHubBase`), `ISpoke.sol`, `ITokenizationSpoke.sol`, `IAaveOracle.sol` (incl `IPriceOracle`), `IPriceFeed.sol`, `ISpokeConfigurator.sol`, `IHubConfigurator.sol`, `IAaveV4ConfigEngine.sol` (config mostly writes), interest rate strategies.  
- V3: `aave/aave-v3-core/.../IPool.sol`; `aave/aave-v3-periphery/.../IUiPoolDataProviderV3.sol`.  
- Cross-checked against current `Onchain.Aave.Pool` (wraps `getUserAccountData`), `UiPoolDataProvider` (bulk `getReserves*` / `getUserReservesData`), and types.

**Key structural diffs (confirmed in interfaces):**
- V3 `IPool.getUserAccountData(address)` is global (aggregates all reserves). V4 equivalent is `ISpoke.getUserAccountData(address)` — per-Spoke only (Spoke defines its collateral/borrow set + e-Mode). Return shape differs (see table).
- V3 bulk reserve/user data lives in `IUiPoolDataProviderV3` (one contract, huge `AggregatedReserveData` with 40+ fields incl rates, caps, eMode, prices). V4 has no such contract or bulk entrypoint; enumerate via `ISpoke.getReserveCount()` + `getReserve(reserveId)` / `get*` per-ID + `IAaveOracle.get*Price`.
- V3 aToken balances via scaled amounts + `getUserReservesData`. V4 supply positions are ERC-4626 shares on per-(Hub,asset) `ITokenizationSpoke`.
- V4 introduces Hub/Spoke credit-line accounting (drawn/premium shares, offsets, deficits, caps, previews for add/draw/restore) with no V3 Pool analog.
- No stable rates in V4 (V3 `stableBorrowRate*` fields and modes gone).
- Oracle is Spoke-scoped (`IAaveOracle` per Spoke) vs V3 single oracle.

**Mapping table (view/pure reads only; writes and events omitted). "Replaces" = provides equivalent user/reserve/price/liquidity data under new model. "New" = no V3 IPool/UI equivalent (Hub credit lines, Spoke risk-premium, tokenization shares, per-Spoke e-Mode scoping). "No V3 equiv" = structural (constants, multicall helpers).**

| V4 Interface | V4 Read Function | Classification | V3 Equivalent | Notes |
|--------------|------------------|----------------|---------------|-------|
| ISpoke | `getUserAccountData(address user)` | replaces (scoped) | `IPool.getUserAccountData` (the 6-tuple) | Core match for Task 46. Returns `UserAccountData {riskPremium, avgCollateralFactor, healthFactor, totalCollateralValue, totalDebtValueRay, activeCollateralCount, borrowCount}`. Per-Spoke (not Pool-global). No "availableBorrowsBase" or split LTV/threshold in same shape; health calc scoped to Spoke's reserves + dynamic config. |
| ISpoke | `getUser*` (getUserReserveStatus, getUserSuppliedAssets/Shares, getUserDebt/TotalDebt, getUserPremiumDebtRay, getUserPosition, getUserLastRiskPremium, getLiquidationBonus) | replaces (per-reserve/user) | `IUiPoolDataProvider.getUserReservesData`, `IPool.getUserConfiguration`, direct aToken/debt token balances | Per-reserve (by reserveId) + aggregate counts on UserAccountData. `getUserPosition` is the V4 analog of V3 UserReserveData (drawn/premium/supplied shares + dynamicConfigKey). |
| ISpoke | `getReserve*` (getReserveCount, getReserveSuppliedAssets/Shares, getReserveDebt/TotalDebt, getReserveId, getReserve, getReserveConfig, getDynamicReserveConfig) | replaces (per-reserve) | `IUiPoolDataProvider.getReservesData` (parts), `IPool.getReserveData`, `getReserveNormalized*`, `getConfiguration` | Spoke-local reserve metadata. No stable rate fields. Dynamic configs (collateralFactor, maxLiqBonus, liqFee) versioned by key (vs V3 mostly static per reserve + eMode). |
| ISpoke | `getLiquidationConfig`, `isPositionManager*` | replaces (config) | parts of `IUiPoolDataProvider` (liq bonus/thresholds), V3 eMode/liquidation params | Per-Spoke liquidation params (targetHf, hfForMaxBonus, bonusFactor). Position managers are V4 concept (approval for delegated actions). |
| ISpoke | `ORACLE()`, `MAX_USER_RESERVES_LIMIT()`, `getLiquidationLogic()`, typehashes, `SET_USER...` | new / no direct | (N/A; V3 had addresses provider, MAX_NUMBER_RESERVES) | Spoke-scoped oracle accessor; user reserve caps (collateral + borrow counted separately). |
| IAaveOracle (IPriceOracle) | `getReservePrice(uint256 reserveId)`, `getReservesPrices(uint256[])` | replaces | V3 `AaveOracle.getAssetPrice`, price fields inside UI `AggregatedReserveData` | Per-reserveId (not asset address). Reverts on <=0 price. Spoke-scoped instance. `decimals()` and `spoke()` accessors. |
| IAaveOracle | `getReserveSource(uint256 reserveId)` | replaces (support) | priceOracle field in UI reserve data | Returns the `IPriceFeed` (Chainlink-style) for the reserve. |
| IHubBase | `getAsset*` (getAssetId, getAssetUnderlyingAndDecimals, getAssetDrawnIndex, getAddedAssets/Shares, getAssetOwed/TotalOwed, getAssetPremiumRay/Data, getAssetLiquidity, getAssetDeficitRay) | new | (no V3 Pool/Hub equiv) | Hub-level liquidity + owed accounting across spokes. Drawn/premium split is new (V3 had stable/variable debt). |
| IHubBase | `getSpoke*` (getSpokeAddedAssets/Shares, getSpokeOwed/TotalOwed, getSpokePremiumRay/Data, getSpokeDrawnShares, getSpokeDeficitRay) | new | (no V3 equiv) | Per-spoke view of its position at the Hub (caps live in SpokeData on IHub). |
| IHubBase | `preview*By*` (previewAdd/Remove/Draw/Restore ByAssets/ByShares) | new | (no direct; V3 had implicit 1:1 aToken) | Preview share/asset math for Hub add/remove/draw/restore flows. Defaults 1:1; IR strategy can affect. |
| IHub | `getAsset*` (getAssetCount, getAsset, getAssetConfig, getAssetAccruedFees, getAssetSwept, getAssetDrawnRate) | new | (no V3 equiv) | Full Asset struct (liquidity, shares, rates, deficit, irStrategy, etc.). Accrued fees + swept are reinvestment/fee concepts. |
| IHub | `getSpoke*` (getSpokeCount, isSpokeListed, getSpokeAddress, getSpoke, getSpokeConfig) | new | (no V3 equiv; V3 had reserve list) | Spoke registry + caps/riskPremiumThreshold/active/halted per (asset, spoke). |
| IHub | `isUnderlyingListed`, `get*` constants (MAX_ALLOWED_*) | new / support | `IPool.MAX_NUMBER_RESERVES`, some config getters | Listing + cap/threshold/decimal bounds. |
| ITokenizationSpoke (IERC4626 +) | `asset()`, `totalAssets()`, `totalSupply()`, `balanceOf()`, `convertTo*`, `max*`, `preview*` (deposit/mint/withdraw/redeem) | replaces (vault) | V3 aToken `balanceOf` + `scaledBalanceOf` + `getUserReservesData.scaledATokenBalance`; `IUi` liquidity fields | ERC-4626 supply-only position token per (Hub, asset). Replaces aToken entirely. Shares are the "supplied" position. |
| ITokenizationSpoke | `hub()`, `assetId()`, `MAX_ALLOWED_SPOKE_CAP()`, permit/typehash/DOMAIN_SEPARATOR helpers | new | (aToken had permit in V3 but different) | Links to Hub/asset; EIP-2612 + intent nonces for gasless deposit/withdraw. |
| (all) | Multicall / EIP712 intent helpers (ISpoke inherits IMulticall/IIntentConsumer; tokenization sig methods) | new | (V3 had some permit on aToken/Pool) | Batch reads and signed intents are first-class in V4 surface. |

**Open questions (a)(b) resolved above.** The read surface for V4 wrappers (Tasks 47–50) should prioritize:
- `Onchain.Aave.V4.Spoke` (or `V4.Position`) exposing `get_user_account_data/2` (taking spoke addr) + per-reserve user/reserve getters + liquidation config.
- `Onchain.Aave.V4.Hub` for liquidity/credit-line reads (new; used for caps, available at spoke, deficit, etc.).
- `Onchain.Aave.V4.Oracle` (Spoke-scoped, thin wrapper over IAaveOracle).
- `Onchain.Aave.V4.TokenizationSpoke` (ERC-4626 reads; key shape per Task 45).
- New types: `SpokeUserAccountData`, `SpokeReserveData`, etc. (no reuse of V3 `UserAccountData` or `AggregatedReserveData`).
- No single "UiPoolDataProviderV4" wrapper until/unless an aggregator appears; use multicall for bulk.

Consumers needing "full position across all V4 spokes" will enumerate relevant spokes (from address book or on-chain spoke lists) and aggregate client-side.

---

## Pointer to Follow-On Work

Tasks 45+ live in [ROADMAP.md](ROADMAP.md#aave-v4-support). Each follow-on task references this file for concrete addresses and ABI interface pointers; do not duplicate the data into the tasks themselves.
