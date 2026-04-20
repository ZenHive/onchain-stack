# Onchain Aave Roadmap

**Vision:** Aave V3 protocol wrappers for Elixir — read positions, execute actions, monitor health.

**Core dependency:** [onchain](../onchain) provides RPC, ABI, signing, address utilities.

**Sibling roadmaps:**
- [onchain/ROADMAP.md](../onchain/ROADMAP.md) — Core Ethereum primitives
- [onchain_evm/ROADMAP.md](../onchain_evm/ROADMAP.md) — Rust NIFs: revm, Solidity parsing, trace, codegen

---

## Status

All foundational tasks are complete. This package provides full Aave V3 read + write coverage across mainnet and 6 chains. A small cleanup backlog (Tasks 36–39) was captured during the v0.1.0 staged-review pass; see below.

---

## Aave Core (Read) ✅

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 6 | Contract address registry (mainnet + network param) | ✅ | 2 | 8 | 7 | 3.75 🎯 | `Onchain.Aave.Contracts` |
| 7 | Aave math conversions (to_usd, to_ltv, to_ray) | ✅ | 3 | 9 | 8 | 2.83 🎯 | `Onchain.Aave.Math` |
| 8 | Pool read calls (getUserAccountData) + integration tests | ✅ | 5 | 9 | 8 | 1.70 🚀 | `Onchain.Aave.Pool` |
| 9 | UserAccountData response struct | ✅ | 5 | 8 | 7 | 1.50 📋 | `Onchain.Aave.Types.UserAccountData` |
| 10 | UiPoolDataProvider calls + remaining type structs | ✅ | 5 | 8 | 7 | 1.50 📋 | `Onchain.Aave.UiPoolDataProvider` |
| 11 | Oracle + Chainlink price feeds | ✅ | 5 | 7 | 6 | 1.30 📋 | `Onchain.Aave.Oracle` |
| 8b | Split unit and integration tests into separate files | ✅ | 2 | 4 | 5 | 2.25 🚀 | `test/` |
| 21 | Multi-chain Aave addresses (Arbitrum, Optimism, Base, Polygon, Avalanche) | ✅ | 2 | 7 | 7 | 3.50 🎯 | `Onchain.Aave.Contracts` |

---

## Aave Actions (Write) ✅

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 14 | Pool write calls (supply, borrow, repay, withdraw) + unit tests | ✅ | 6 | 9 | 8 | 1.42 📋 | `Onchain.Aave.Pool` |
| 14b | Pool write Sepolia integration tests | ✅ | 4 | 7 | 6 | 1.63 🚀 | `Onchain.Aave.Pool` |
| 35 | Aave testnet faucet module (mint test ERC-20 tokens) | ✅ | 2 | 4 | 3 | 1.75 🚀 | `Onchain.Aave.Faucet` |

---

## Cleanup Backlog (from initial-commit review)

Discovered during the v0.1.0 staged-review pass. All deferred — library ships first, cleanup follows.

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 36 | Extract shared Pool write helper (`send_pool_tx/4` across supply/withdraw/borrow/repay) | ⬜ | 3 | 6 | 5 | 1.83 🚀 | `Onchain.Aave.Pool` |
| 37 | Named module attributes for canonical Aave V3 pool/provider addresses | ⬜ | 1 | 5 | 4 | 4.50 🎯 | `Onchain.Aave.Contracts` |
| 38 | Consolidate Pool write integration test helpers + name testnet magic numbers | ⬜ | 2 | 4 | 3 | 1.75 🚀 | `test/onchain/aave/pool_write_integration_test.exs` |
| 39 | Move per-module `@dialyzer` suppressions into `.dialyzer_ignore.exs` | ⬜ | 2 | 3 | 4 | 1.75 🚀 | `lib/onchain/aave/{pool,oracle,ui_pool_data_provider}.ex` |

**Task 36 — Pool write helper extraction.** `supply`, `withdraw`, `borrow`, `repay` in `pool.ex` share identical `with`-chain structure (validate asset → validate obo/to → lookup address → encode calldata → send). Extract a private `send_pool_tx/4` taking the ABI sig + args. Consider whether `Faucet.mint` should share the same path. Keep backwards-compatible public APIs.

**Task 37 — Named canonical addresses.** The Aave V3 canonical pool (`0x794a61358D6845594F94dc1DB02A252b5b4814aD`) and provider (`0xa97684ead0e402dC232d5A977953DF7ECBaB3CDb`) are inlined 4x in `contracts.ex` for arbitrum/optimism/polygon/avalanche. Extract to `@aave_v3_canonical_pool` / `@aave_v3_canonical_provider` module attributes. Documents the intent and prevents silent copy-paste drift.

**Task 38 — Test helper consolidation.** `pool_write_integration_test.exs` duplicates the approve+supply preamble across borrow and repay describe blocks. Extract `supply_weth_collateral!/4`. While there, add `TODO:`-tagged rationale for `@gas_limit_*` constants (testnet-calibrated) and `@oracle_jitter_tolerance "0.05"` (empirical 5% slack).

**Task 39 — Centralize dialyzer suppressions.** `pool.ex`, `oracle.ex`, `ui_pool_data_provider.ex` each carry per-module `@dialyzer` suppressions for the `Signet.Hex` / `ABI.decode_response` `no_return()` cascade. Move them into `.dialyzer_ignore.exs` so the underlying upstream issue is tracked in one place. See also: sibling `onchain` — a `FIXME(upstream)` on the `Signet.Hex` spec would remove the need entirely.

---

## Future Directions

Potential expansions — not yet scoped or scored:

- **Aave V4 support** — when V4 ships, add new pool/oracle interfaces alongside V3
- **Flash loan wrappers** — typed flash loan construction and callback helpers
- **Governance module** — Aave governance proposal reading and voting
- **Liquidation helpers** — health factor monitoring, liquidation call wrappers
- **More chains** — expand `Contracts` registry as Aave deploys to new L2s
- **Cross-validation** — QuickBEAM + `@aave/math-utils` to validate `Onchain.Aave.Math` (tracked as onchain core Task 40)

---

## Key Design Decisions

1. **`Onchain.*` namespace** — modules keep the same namespace as when they lived in the monolith
2. **Path dependency** — `{:onchain, path: "../onchain"}`
3. **Address registry pattern** — `Onchain.Aave.Contracts` centralizes all contract addresses per chain
4. **Math uses Decimal** — all USD/LTV/health factor conversions return `Decimal.t()` for precision
5. **Standard error tuples** — `{:ok, result} | {:error, {:tag, reason}}`
6. **Verify addresses against Aave Address Book** — `curl` the CSV from bgd-labs before adding

## Module Structure

```
lib/onchain/aave/
  contracts.ex                # address registry (mainnet + multi-chain)
  math.ex                     # to_usd, to_ltv, to_health_factor, to_ray
  pool.ex                     # read + write calls (getUserAccountData, supply, borrow, repay)
  oracle.ex                   # getAssetPrice + Chainlink
  ui_pool_data_provider.ex    # bulk reserve/user data
  faucet.ex                   # testnet faucet interactions
  types/
    user_account_data.ex
    aggregated_reserve_data.ex
    base_currency_info.ex
    user_reserve_data.ex
```
