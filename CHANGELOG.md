# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## [Unreleased]

### Task 39: Centralize dialyzer cascade suppressions

**Completed** | [D:2/B:3/U:4 → Eff:1.75] 🚀

Moved per-module `@dialyzer` blocks out of `pool.ex`, `oracle.ex`, `ui_pool_data_provider.ex`, and `faucet.ex` into `.dialyzer_ignore.exs` as file + warning-type tuples (`:pattern_match`, `:no_return`, `:invalid_contract`). One upstream-tracking `TODO(upstream:signet)` comment in `.dialyzer_ignore.exs` documents the `Signet.Hex` spec mismatch that produces the cascade — when upstream ships a fix, one block deletes instead of four. Trade-off: file-level granularity instead of per-function. Acceptable because the affected modules are thin wrappers around `Onchain.ABI` with no other realistic source for those warning types. `mix dialyzer.json --summary-only` stays at 0.

### Task 38: Consolidate Pool write integration test helpers

**Completed** | [D:2/B:4/U:3 → Eff:1.75] 🚀

Extracted `supply_weth_collateral!/4` from `test/onchain/aave/pool_write_integration_test.exs` to remove the duplicated approve-WETH-then-supply-WETH preamble shared by the supply/withdraw and borrow/repay tests. Added `TODO:`-prefixed rationale to gas-limit constants (testnet-calibrated headroom), `@oracle_jitter_tolerance` (empirical 5% Chainlink drift slack), and the WETH/faucet threshold/amount constants (cumulative-run sizing). Test behavior unchanged.

### Task 36: Extract shared Pool write helper

**Completed** | [D:3/B:6/U:5 → Eff:1.83] 🚀

Pulled the pool-address lookup + ABI encode + Signer dispatch shared by `Onchain.Aave.Pool.{supply,withdraw,borrow,repay}/4` into a private `send_pool_tx/4` helper. Each write function shrinks to argument validation followed by one helper call. Public API unchanged. `Faucet.mint/4` follows the same shape but stays separate — sharing across two call sites isn't worth promoting the helper to a shared module.

### Roadmap reprioritization: V3 Math Validation before V4 implementation

Reframed ROADMAP.md to gate V4 work on V3 math verification. Added a "🎯 Current Focus" section naming Tasks 40 → 41 as the active path; Task 43 (JS aggregation cross-validation) stays 🔶 gated until off-chain aggregation helpers exist. Bumped Task 40 (WadRayMath + MathUtils port) from U:7 → U:9 (Eff 1.50 📋 → 1.70 🚀) because it gates both Task 41 (V3 revm validation) and Task 42 (V4 revm validation) — it is now the verification bridge rather than isolated math work. Moved the Cleanup Backlog (Tasks 36, 38, 39) below Math Validation to reflect that it is polish, not a capability gate. No code changes.

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
