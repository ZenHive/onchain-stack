# Onchain Aave Roadmap

**Vision:** Aave V3 protocol wrappers for Elixir — read positions, execute actions, monitor health.

**Core dependency:** [onchain](../onchain) provides RPC, ABI, signing, address utilities.

**Sibling roadmaps:**
- [onchain/ROADMAP.md](../onchain/ROADMAP.md) — Core Ethereum primitives
- [onchain_evm/ROADMAP.md](../onchain_evm/ROADMAP.md) — Rust NIFs: revm, Solidity parsing, trace, codegen

---

## Status

All foundational tasks are complete. This package provides full Aave V3 read + write coverage across mainnet and 6 chains. A small cleanup backlog (Tasks 36–39) was captured during the v0.1.0 staged-review pass; see below. A follow-on **Math Validation** backlog (Tasks 40–43) was added 2026-04-20 to expand `Aave.Math` with WadRayMath + MathUtils and cross-validate both against Solidity (via `onchain_evm`) and against Aave's frontend math (`@aave/math-utils` via `onchain_js`). A separate **Aave V4 Support** backlog (Task 44+) opened 2026-04-20 after V4 went live on Ethereum mainnet on 2026-03-30 with the Hub-and-Spoke architecture.

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
| 37 | ~~Named module attributes for canonical Aave V3 pool/provider addresses~~ | ✅ | 1 | 5 | 4 | 4.50 🎯 | `Onchain.Aave.Contracts` — see [CHANGELOG](CHANGELOG.md#task-37-named-canonical-aave-v3-addresses) |
| 38 | Consolidate Pool write integration test helpers + name testnet magic numbers | ⬜ | 2 | 4 | 3 | 1.75 🚀 | `test/onchain/aave/pool_write_integration_test.exs` |
| 39 | Move per-module `@dialyzer` suppressions into `.dialyzer_ignore.exs` | ⬜ | 2 | 3 | 4 | 1.75 🚀 | `lib/onchain/aave/{pool,oracle,ui_pool_data_provider}.ex` |

**Task 36 — Pool write helper extraction.** `supply`, `withdraw`, `borrow`, `repay` in `pool.ex` share identical `with`-chain structure (validate asset → validate obo/to → lookup address → encode calldata → send). Extract a private `send_pool_tx/4` taking the ABI sig + args. Consider whether `Faucet.mint` should share the same path. Keep backwards-compatible public APIs.

**Task 38 — Test helper consolidation.** `pool_write_integration_test.exs` duplicates the approve+supply preamble across borrow and repay describe blocks. Extract `supply_weth_collateral!/4`. While there, add `TODO:`-tagged rationale for `@gas_limit_*` constants (testnet-calibrated) and `@oracle_jitter_tolerance "0.05"` (empirical 5% slack).

**Task 39 — Centralize dialyzer suppressions.** `pool.ex`, `oracle.ex`, `ui_pool_data_provider.ex` each carry per-module `@dialyzer` suppressions for the `Signet.Hex` / `ABI.decode_response` `no_return()` cascade. Move them into `.dialyzer_ignore.exs` so the underlying upstream issue is tracked in one place. See also: sibling `onchain` — a `FIXME(upstream)` on the `Signet.Hex` spec would remove the need entirely.

---

## Math Validation

Added 2026-04-20 after surveying Aave's math references. Two oracles at two different layers:

- **revm via `onchain_evm`** — canonical for *protocol-level* math (WadRayMath, interest accrual). Validates our Elixir port against actual on-chain Solidity bytecode. Version-agnostic (V2/V3/V4).
- **`@aave/math-utils` via `onchain_js`** (QuickBEAM) — canonical for *off-chain aggregation* (`formatUserSummaryAndIncentives`, estimated APY over time, weighted averages across reserves). Validates that our Elixir matches what Aave's frontend shows users. V2/V3 only (no V4 JS lib as of 2026-04-20 — re-check before acting on Task 43; Aave's frontend will need one for V4 eventually).

They cover different failure modes: revm catches drift from the contracts, JS catches drift from the UI. Use both where the relevant Elixir code exists.

The revm NIF surface (`Onchain.EVM.simulate_call/3`, `simulate_transaction/3`, `simulate_batch/2`) already supports everything needed: mainnet/Sepolia forks at a pinned block, `state_overrides` for balance/nonce/code/storage injection per address (enables bytecode injection for pre-deployment V4), caller/gas/timeout options, and raw hex output decoded via existing `Onchain.ABI.decode_response/2`.

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 40 | Port Aave V3 WadRayMath + MathUtils to Elixir | ⬜ | 5 | 8 | 7 | 1.50 📋 | `Onchain.Aave.Math` |
| 41 | Cross-validate `Aave.Math` via revm against on-chain Aave V3 | ⬜ | 4 | 7 | 6 | 1.63 🚀 | `test/onchain/aave/math_revm_test.exs` (new) |
| 42 | V4 math cross-validation via revm (V4 live on mainnet 2026-03-30) | ⬜ | 4 | 7 | 7 | 1.75 🚀 | `Onchain.Aave.Math.V4` |
| 43 | Cross-validate aggregation helpers via `@aave/math-utils` (QuickBEAM) | 🔶 | 4 | 6 | 4 | 1.25 📋 | `Onchain.Aave.Summary` (future) |

**Task 40 — WadRayMath + MathUtils port.** Port Aave V3's `rayMul`, `rayDiv`, `wadMul`, `wadDiv`, `calculateLinearInterest`, `calculateCompoundedInterest` from Solidity (`aave-v3-core/contracts/protocol/libraries/math/`) to Elixir over `Decimal.t()`. Preserve Aave's rounding semantics (half-up at the ray/wad midpoint — not trivial). Prerequisite for Task 41; the current `Math` module holds only trivial `div_pow10` scale conversions with nothing worth oracle-validating.

**Task 41 — revm cross-validation.** Add `{:onchain_evm, path: "../onchain_evm"}` as a test-only dep. Either deploy a thin Solidity wrapper that exposes Aave V3's `WadRayMath` + `MathUtils` internal functions as public entrypoints, or call through an already-deployed Aave V3 library/contract that exercises them. For each function: generate inputs (including edge cases — overflow boundaries, rounding midpoints, zero, max-uint), encode via `Onchain.ABI.encode_call/2`, fire through `Onchain.EVM.simulate_call/3` on a pinned mainnet block, decode, assert equality with the Elixir port within zero tolerance. Property-based tests via StreamData.

**Task 42 — V4 cross-validation via revm.** V4 is live on Ethereum mainnet as of 2026-03-30 (EthCC launch, governance passed 2026-03-24). Repeat Task 41's harness against V4's math library: pin a mainnet block post-launch, call the V4 math contracts directly via `Onchain.EVM.simulate_call/3`, assert equality with a V4-specific Elixir port. Depends on Task 40 (WadRayMath port) — V4's math library may have diverged from V3; port the V4-specific variants under `Onchain.Aave.Math.V4` if so. `state_overrides["code"]` bytecode injection is now a secondary fallback (e.g. for variants we want to test before mainnet exposure), not the primary path. **Coordinate with Task 44** — the V4 contract-surface scoping feeds the address list used here.

**Task 43 — Aggregation helpers via JS (gated on helpers existing).** When `onchain_aave` grows off-chain aggregation helpers (e.g. `Onchain.Aave.Summary.format_user_summary/2`, projected APY, weighted reserve averages — anything Aave's UI computes off-chain), validate them against `@aave/math-utils` via `onchain_js` (QuickBEAM). Load the npm bundle, call `formatUserSummaryAndIncentives` and friends with identical inputs, compare to Elixir output within a documented tolerance (BigNumber→Decimal conversion may introduce sub-wei noise). Gated (🔶) because the helpers don't exist yet — add the task to the active backlog when the first one lands. V2/V3 only today; re-check V4 JS availability before acting.

---

## Aave V4 Support

V4 went live on Ethereum mainnet on 2026-03-30 (governance passed 2026-03-24 with 100% support) with a Hub-and-Spoke architecture. The launch surface includes **three Hubs** (Core, Prime, Plus — not just Core + Prime), **multiple Spoke families** (e-Mode and beyond, per [Hub-and-Spoke Initial Configurations](https://governance.aave.com/t/aave-v4-hub-and-spoke-initial-configurations/24233)), and new **tokenized positions**. V4's contract surface differs materially from V3's single-`Pool` model — this is not a drop-in interface addition.

Sources: [aave.com/blog/aave-v4-live-ethereum](https://aave.com/blog/aave-v4-live-ethereum), [ARFC activation thread](https://governance.aave.com/t/arfc-aave-v4-activation-on-ethereum-mainnet/24293), [initial configurations](https://governance.aave.com/t/aave-v4-hub-and-spoke-initial-configurations/24233). Surface details below are **partial** — Task 44 must re-read sources before acting.

The responsible first step is scoping, not implementation. Jumping straight to "add `Onchain.Aave.V4.Pool`" without reading the actual V4 addresses and ABIs would be guessing.

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 44 | Research V4 Hub-and-Spoke contract surface and scope the V4 support phase | ⬜ | 3 | 7 | 8 | 2.50 🎯 | `ROADMAP.md` (scoping only) |

**Task 44 — V4 scoping.** Start by re-reading the official launch sources linked above; the Hub/Spoke names cited in this section are **partial** and should not be treated as exhaustive. Enumerate **all live V4 surface** at mainnet launch: every Hub (Core, Prime, Plus, plus any added by governance since), every Spoke family (e-Mode and others documented in "Hub-and-Spoke Initial Configurations"), tokenized positions, oracle wiring, and any new periphery contracts. Pull addresses from Aave's address book and ABIs from the published artifacts. Compare the surface to V3's `Pool` + `UiPoolDataProvider` shape we currently wrap. Produce a follow-on task list scoped against concrete V4 surface: which V3 modules extend cleanly (e.g. `Contracts` registry), which need V4-specific siblings (e.g. `Onchain.Aave.V4.Hub`, `V4.Spoke`), and which concepts are genuinely new (Liquidity Hub routing, Spoke-specific liquidation rules, tokenized positions). Output goes back into this ROADMAP as Tasks 45+. Keep this task scoped to *research + planning*; no Elixir code written under Task 44.

---

## Future Directions

Potential expansions — not yet scoped or scored:

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
