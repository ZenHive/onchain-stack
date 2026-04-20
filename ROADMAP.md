# Onchain Aave Roadmap

**Vision:** Aave V3 protocol wrappers for Elixir — read positions, execute actions, monitor health.

**Core dependency:** [onchain](../onchain) provides RPC, ABI, signing, address utilities.

**Sibling roadmaps:**
- [onchain/ROADMAP.md](../onchain/ROADMAP.md) — Core Ethereum primitives
- [onchain_evm/ROADMAP.md](../onchain_evm/ROADMAP.md) — Rust NIFs: revm, Solidity parsing, trace, codegen

---

## Status

All foundational tasks are complete. This package provides full Aave V3 read + write coverage across mainnet and 6 chains. A small cleanup backlog (Tasks 36–39) was captured during the v0.1.0 staged-review pass; see below. A follow-on **Math Validation** backlog (Tasks 40–43) was added 2026-04-20 to expand `Aave.Math` with WadRayMath + MathUtils and cross-validate both against Solidity (via `onchain_evm`) and against Aave's frontend math (`@aave/math-utils` via `onchain_js`).

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

## Math Validation

Added 2026-04-20 after surveying Aave's math references. Two oracles at two different layers:

- **revm via `onchain_evm`** — canonical for *protocol-level* math (WadRayMath, interest accrual). Validates our Elixir port against actual on-chain Solidity bytecode. Version-agnostic (V2/V3/V4).
- **`@aave/math-utils` via `onchain_js`** (QuickBEAM) — canonical for *off-chain aggregation* (`formatUserSummaryAndIncentives`, estimated APY over time, weighted averages across reserves). Validates that our Elixir matches what Aave's frontend shows users. V2/V3 only (V4 JS lib does not exist as of 2026-04-20).

They cover different failure modes: revm catches drift from the contracts, JS catches drift from the UI. Use both where the relevant Elixir code exists.

The revm NIF surface (`Onchain.EVM.simulate_call/3`, `simulate_transaction/3`, `simulate_batch/2`) already supports everything needed: mainnet/Sepolia forks at a pinned block, `state_overrides` for balance/nonce/code/storage injection per address (enables bytecode injection for pre-deployment V4), caller/gas/timeout options, and raw hex output decoded via existing `Onchain.ABI.decode_response/2`.

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 40 | Port Aave V3 WadRayMath + MathUtils to Elixir | ⬜ | 5 | 8 | 7 | 1.50 📋 | `Onchain.Aave.Math` |
| 41 | Cross-validate `Aave.Math` via revm against on-chain Aave V3 | ⬜ | 4 | 7 | 6 | 1.63 🚀 | `test/onchain/aave/math_revm_test.exs` (new) |
| 42 | V4 math cross-validation (blocked on V4 deployment or bytecode availability) | 🔶 | 4 | 7 | 5 | 1.50 📋 | `Onchain.Aave.Math.V4` (future) |
| 43 | Cross-validate aggregation helpers via `@aave/math-utils` (QuickBEAM) | 🔶 | 4 | 6 | 4 | 1.25 📋 | `Onchain.Aave.Summary` (future) |

**Task 40 — WadRayMath + MathUtils port.** Port Aave V3's `rayMul`, `rayDiv`, `wadMul`, `wadDiv`, `calculateLinearInterest`, `calculateCompoundedInterest` from Solidity (`aave-v3-core/contracts/protocol/libraries/math/`) to Elixir over `Decimal.t()`. Preserve Aave's rounding semantics (half-up at the ray/wad midpoint — not trivial). Prerequisite for Task 41; the current `Math` module holds only trivial `div_pow10` scale conversions with nothing worth oracle-validating.

**Task 41 — revm cross-validation.** Add `{:onchain_evm, path: "../onchain_evm"}` as a test-only dep. Either deploy a thin Solidity wrapper that exposes Aave V3's `WadRayMath` + `MathUtils` internal functions as public entrypoints, or call through an already-deployed Aave V3 library/contract that exercises them. For each function: generate inputs (including edge cases — overflow boundaries, rounding midpoints, zero, max-uint), encode via `Onchain.ABI.encode_call/2`, fire through `Onchain.EVM.simulate_call/3` on a pinned mainnet block, decode, assert equality with the Elixir port within zero tolerance. Property-based tests via StreamData.

**Task 42 — V4 cross-validation (blocked).** When V4 is deployed or its compiled bytecode is published, repeat Task 41's harness against V4's math library. Two execution paths: (a) call the deployed address directly if V4 is live, (b) inject bytecode at a chosen address via `state_overrides["code"]` if not. The NIF supports both today — the block is external (V4 availability), not internal.

**Task 43 — Aggregation helpers via JS (gated on helpers existing).** When `onchain_aave` grows off-chain aggregation helpers (e.g. `Onchain.Aave.Summary.format_user_summary/2`, projected APY, weighted reserve averages — anything Aave's UI computes off-chain), validate them against `@aave/math-utils` via `onchain_js` (QuickBEAM). Load the npm bundle, call `formatUserSummaryAndIncentives` and friends with identical inputs, compare to Elixir output within a documented tolerance (BigNumber→Decimal conversion may introduce sub-wei noise). Gated (🔶) because the helpers don't exist yet — add the task to the active backlog when the first one lands. V2/V3 only; V4 has no JS lib.

---

## Future Directions

Potential expansions — not yet scoped or scored:

- **Aave V4 support** — when V4 ships, add new pool/oracle interfaces alongside V3. Note (2026-04-20): V4 has no JS math library; revm via `onchain_evm` (Task 42 above) is the validation path when V4 is reachable on mainnet
- **Flash loan wrappers** — typed flash loan construction and callback helpers
- **Governance module** — Aave governance proposal reading and voting
- **Liquidation helpers** — health factor monitoring, liquidation call wrappers
- **More chains** — expand `Contracts` registry as Aave deploys to new L2s

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
