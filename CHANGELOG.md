# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## [Unreleased]

### Task 44: V4 Hub-and-Spoke scoping

**Completed** | [D:3/B:7/U:8 → Eff:2.50] 🎯

Enumerated the Aave V4 Ethereum mainnet contract surface (live since 2026-03-30) into [V4_SCOPING.md](V4_SCOPING.md): three Hubs (Core, Prime, Plus), ten Hub Spokes plus a standalone Treasury Spoke, thirty-one Tokenization Spokes as ERC-4626 supply vaults, five Position Managers, a per-Spoke oracle model, and supporting infrastructure (Access Manager, Hub/Spoke Configurators, Config Engine, Liquidation Logic). Every address pulled from `bgd-labs/aave-address-book` (`AaveV4Ethereum` namespace). Interface pointers resolve into `github.com/aave/aave-v4/src/{hub,spoke,position-manager,config-engine,access}/interfaces/`.

Produced V3→V4 module mapping and opened implementation Tasks 45–52 in ROADMAP. Key decisions: extend `Onchain.Aave.Contracts` rather than create a parallel V4 registry (Task 45); build V4 siblings under `Onchain.Aave.V4.*` because V4 has no `Pool` analog (Tasks 47–51); replace V3's single `AggregatedReserveData` with Spoke-scoped V4 types (Task 48). Task 42 (V4 math cross-validation via revm) updated to reference the concrete `EXTERNAL_LIBRARIES LIQUIDATION_LOGIC` address discovered during scoping as the likely WadRayMath call-site.

No Elixir code written under Task 44 per the research-only scope.

### Task 37: Named canonical Aave V3 addresses

**Completed** | [D:1/B:5/U:4 → Eff:4.50] 🎯

Extracted the CREATE2-shared V3 canonical pool (`0x794a61358D6845594F94dc1DB02A252b5b4814aD`) and pool-addresses-provider (`0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb`) into `@aave_v3_canonical_pool` / `@aave_v3_canonical_provider` module attributes in `Onchain.Aave.Contracts`. Arbitrum, Optimism, Polygon, and Avalanche now reference the attributes instead of inlining the literals four times each. Documents the shared-deployment intent and makes copy-paste drift syntactically impossible. Public API and stored values unchanged — `address/2` returns identical checksummed strings.

---

## v0.1.0 — Initial Release (Split from onchain)

Extracted from [onchain](../onchain) v0.3.0 monolith as a standalone package.

**What's included:**

- **Onchain.Aave.Contracts** — address registry for mainnet + 6 chains (Arbitrum, Optimism, Base, Polygon, Avalanche, Sepolia)
- **Onchain.Aave.Math** — to_usd, to_ltv, to_health_factor, to_ray conversions
- **Onchain.Aave.Pool** — read (getUserAccountData) + write (supply, borrow, repay, withdraw)
- **Onchain.Aave.Oracle** — getAssetPrice + Chainlink fallback
- **Onchain.Aave.UiPoolDataProvider** — bulk reserve/user data
- **Onchain.Aave.Faucet** — testnet faucet interactions
- **Types** — UserAccountData, AggregatedReserveData, BaseCurrencyInfo, UserReserveData

**Why:** Consumers who only need core Ethereum primitives no longer pull in Aave protocol dependencies. Zero code changes for existing consumers — only `mix.exs` deps change.

**Initial-commit review pass:**
- Corrected `CLAUDE.md` env var name for Sepolia write tests (`ETH_SEPOLIA_PRIVATE_KEY`, was `SIGNER_PRIVATE_KEY`)
- Converted stale verification-date comment on Sepolia addresses into `TODO(Task 6): …` so Credo tracks re-verification on Aave upgrades
- Bumped patches: `credo` 1.7.17→1.7.18, `ex_unit_json` 0.4.2→0.4.3, `onchain` 0.5.0→0.5.1
- Captured cleanup backlog as Tasks 36–39 in `ROADMAP.md`
