# Onchain Aave Roadmap

**Vision:** Aave V3 protocol wrappers for Elixir — read positions, execute actions, monitor health.

**Core dependency:** [onchain](../onchain) provides RPC, ABI, signing, address utilities.

**Sibling roadmaps:**
- [onchain/ROADMAP.md](../onchain/ROADMAP.md) — Core Ethereum primitives
- [onchain_evm/ROADMAP.md](../onchain_evm/ROADMAP.md) — Rust NIFs: revm, Solidity parsing, trace, codegen

> Canonical source is `roadmap/tasks.toml` (managed by `rmap`); this file is rendered. Per-task detail (`body`, acceptance criteria, out-of-scope) lives in the source — `rmap show <id>` to read it. Edit tasks via `rmap` commands, not by hand-editing the tables below.

---

## Status

All foundational V3 tasks are complete. This package provides full Aave V3 read + write coverage across mainnet and 6 chains. A small cleanup backlog (Tasks 36–39) was captured during the v0.1.0 staged-review pass. A follow-on **Math Validation** backlog (Tasks 40–43) was added 2026-04-20 to expand `Aave.Math` with WadRayMath + MathUtils and cross-validate both against Solidity (via `onchain_evm`) and against Aave's frontend math (`@aave/math-utils` via `onchain_js`). Task 40 landed 2026-04-21 (integer-native port of WadRayMath + MathUtils; source pinned to `aave-v3-origin@1e3d70c`); Task 41 landed 2026-04-22 (revm cross-validation harness with zero-tolerance equality across deterministic + StreamData property vectors for all 8 Layer-2 functions). Task 42 (V4 math revm harness, reusing Task 41's shape) is now the active path. The **Aave V4 Support** phase opened 2026-04-20 after V4 went live on Ethereum mainnet on 2026-03-30 with the Hub-and-Spoke architecture; Task 44 scoping completed 2026-04-20 (see [V4_SCOPING.md](V4_SCOPING.md)) and produced implementation Tasks 45–52.

---

## 🎯 Current Focus

<!-- FOCUS:BEGIN -->
**Focus phase:** 3 — Math Validation (2 of 5 done · 0 in progress)

**Last shipped:** no recent shipments

**Up next:** Task 42 — V4 math cross-validation via revm (V4 live on mainnet 2026-03-30) [D:4/B:7/U:7 → Eff:1.75] 🚀
<!-- FOCUS:END -->

**V3 Math Validation** — before shipping V4 support, cross-validate `Aave.Math` against Solidity source-of-truth (revm) and Aave's frontend math (JS). V3 revm validation is now complete; the harness is ready for V4 re-use.

**Active path:** Task 42 (V4 revm cross-validation) — primary path is direct calls against V4's deployed math contracts on mainnet, with Task 41's `state_overrides["code"]` wrapper-injection shape available as a secondary path for variants we want to exercise before mainnet exposure. JS validation (Task 43) stays 🔶 gated until off-chain aggregation helpers exist.

---

## Aave Core (Read) ✅

<!-- TASKS:BEGIN phase=1 -->
> 8 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-1-aave-core-read).
<!-- TASKS:END -->

---

## Aave Actions (Write) ✅

<!-- TASKS:BEGIN phase=2 -->
> 3 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-2-aave-actions-write).
<!-- TASKS:END -->

---

## Math Validation

Added 2026-04-20 after surveying Aave's math references. Two oracles at two different layers:

- **revm via `onchain_evm`** — canonical for *protocol-level* math (WadRayMath, interest accrual). Validates our Elixir port against actual on-chain Solidity bytecode. Version-agnostic (V2/V3/V4).
- **`@aave/math-utils` via `onchain_js`** (QuickBEAM) — canonical for *off-chain aggregation* (`formatUserSummaryAndIncentives`, estimated APY over time, weighted averages across reserves). Validates that our Elixir matches what Aave's frontend shows users. V2/V3 only (no V4 JS lib as of 2026-04-20 — re-check before acting on Task 43).

They cover different failure modes: revm catches drift from the contracts, JS catches drift from the UI. The revm NIF surface (`Onchain.EVM.simulate_call/3`, `simulate_transaction/3`, `simulate_batch/2`) already supports everything needed: mainnet/Sepolia forks at a pinned block, `state_overrides` for balance/nonce/code/storage injection per address (enables bytecode injection for pre-deployment V4), caller/gas/timeout options, and raw hex output decoded via `Onchain.ABI.decode_response/2`.

<!-- TASKS:BEGIN phase=3 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 40 | ✅ | 🎁 **math_validation** · *Onchain.Aave.Math* · Port Aave V3 WadRayMath + MathUtils to Elixir [D:5/B:8/U:9 → Eff:1.7?] 🚀 |
| Task 40b | 🔶 | 🎁 **math_validation** · *Onchain.Aave.Math* · Port missing WadRayMath ceil/floor variants on demand [D:3/B:4/U:3 → Eff:1.17?] 📋 ⛔ Gated until a caller from Pool/TokenMath call paths in this repo needs the floor/ceil variants. |
| Task 41 | ✅ | 🎁 **math_validation** · *test/onchain/aave/math_revm_test.exs* · Cross-validate Aave.Math via revm against on-chain Aave V3 [D:4/B:7/U:6 → Eff:1.62?] 🚀 |
| Task 42 | ⬜ | 🎁 **math_validation** · *Onchain.Aave.Math.V4* · V4 math cross-validation via revm (V4 live on mainnet 2026-03-30) [D:4/B:7/U:7 → Eff:1.75?] 🚀 |
| Task 43 | 🔶 | 🎁 **math_validation** · *Onchain.Aave.Summary* · Cross-validate aggregation helpers via @aave/math-utils (QuickBEAM) [D:4/B:6/U:4 → Eff:1.25?] 📋 ⛔ Gated until onchain_aave grows off-chain aggregation helpers; no V4 JS lib as of 2026-04-20 (re-check before acting). |
<!-- TASKS:END -->

---

## Cleanup Backlog (from initial-commit review)

Discovered during the v0.1.0 staged-review pass. Deprioritized below Math Validation — polish, not a capability gate.

<!-- TASKS:BEGIN phase=4 -->
> 4 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-4-cleanup-backlog).
<!-- TASKS:END -->

---

## Aave V4 Support

V4 went live on Ethereum mainnet on 2026-03-30 with a Hub-and-Spoke architecture: **three Hubs** (Core, Prime, Plus), **ten Hub Spokes** plus a standalone Treasury Spoke, **thirty-one Tokenization Spokes** (ERC-4626 supply-only vaults per (Hub, asset) pair), **five Position Managers**, and a per-Spoke oracle model. V4's contract surface differs materially from V3's single-`Pool` model — this is not a drop-in interface addition.

**All V4 addresses, interface pointers, and the V3→V4 module mapping live in [V4_SCOPING.md](V4_SCOPING.md).** Tasks 45+ reference that document rather than inlining addresses.

**Dependency order:** 45 (registry) and 46 (surface selection) ship first. 47–50 can run in parallel once both land. 51 depends on 45–48. 52 is gated on V4 Sepolia becoming available; until then reads can be validated against mainnet via fork but writes have no testnet.

<!-- TASKS:BEGIN phase=5 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 44 | ✅ | 🎁 **v4_support** · *V4_SCOPING.md* · Research V4 Hub-and-Spoke contract surface and scope the V4 support phase [D:3/B:7/U:8 → Eff:2.5?] 🎯 |
| Task 45 | ✅ | 🎁 **v4_support** · *Onchain.Aave.Contracts* · Extend Onchain.Aave.Contracts with V4 address keys [D:4/B:7/U:8 → Eff:1.88?] 🚀 |
| Task 46 `[P]` | ⬜ | 🎁 **v4_support** · *V4_SCOPING.md* · Select V4 read surface by diffing IHub/ISpoke/IAaveOracle/ITokenizationSpoke against V3 IPool [D:3/B:6/U:7 → Eff:2.17?] 🎯 |
| Task 47 `[P]` | ⬜ | 🎁 **v4_support** · *Onchain.Aave.V4.Hub* · Implement Onchain.Aave.V4.Hub read wrapper [D:4/B:6/U:5 → Eff:1.38?] 📋 |
| Task 48 `[P]` | ⬜ | 🎁 **v4_support** · *Onchain.Aave.V4.Spoke* · Implement Onchain.Aave.V4.Spoke reads + V4 types [D:5/B:7/U:7 → Eff:1.4?] 📋 |
| Task 49 `[P]` | ⬜ | 🎁 **v4_support** · *Onchain.Aave.V4.Oracle* · Implement Onchain.Aave.V4.Oracle wrapper (Spoke-scoped) [D:3/B:5/U:5 → Eff:1.67?] 🚀 |
| Task 50 `[P]` | ⬜ | 🎁 **v4_support** · *Onchain.Aave.V4.TokenizationSpoke* · Implement Onchain.Aave.V4.TokenizationSpoke reads (ERC-4626 share accounting) [D:3/B:5/U:5 → Eff:1.67?] 🚀 |
| Task 51 | ⬜ | 🎁 **v4_support** · *Onchain.Aave.V4.PositionManager* · Implement Onchain.Aave.V4.PositionManager ergonomic write wrappers (supply/borrow/repay analogs) [D:5/B:8/U:7 → Eff:1.5?] 🚀 |
| Task 52 | 🔶 | 🎁 **v4_support** · *test/onchain/aave/v4/* · V4 integration tests (mainnet forked reads; gated on Sepolia V4 deployment for writes) [D:4/B:6/U:5 → Eff:1.38?] 📋 ⛔ Write tests gated until Aave deploys V4 on a testnet — none exists as of 2026-04-20. |
<!-- TASKS:END -->

---

## V3 Write Surface Gaps

Consumer patterns observed on-chain that the current V3 write surface doesn't cover.

<!-- TASKS:BEGIN phase=6 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 53 | ⬜ | 🎁 **v3_write_gaps** · *Onchain.Aave.DebtToken* · Onchain.Aave.DebtToken — wrap approveDelegation + borrowAllowance on variable/stable debt tokens [D:3/B:6/U:6 → Eff:2.0?] 🎯 |
| Task 54 | ⬜ | 🎁 **v3_write_gaps** · *(cross-cutting research)* · Mine defi-skills:intent-to-transaction action surface for onchain_aave coverage gaps [D:3/B:8/U:7 → Eff:2.5?] 🎯 |
<!-- TASKS:END -->

---

## Read-Path Multicall Adoption

<!-- TASKS:BEGIN phase=7 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 55 | ⬜ | 🎁 **multicall** · *Onchain.Aave.** · Adopt Onchain.Multicall in Aave batch read paths [D:3/B:6/U:6 → Eff:2.0?] 🎯 |
<!-- TASKS:END -->

---

## Future Directions

Potential expansions — not yet scoped or scored:

- **Flash loan wrappers** — typed flash loan construction and callback helpers
- **Governance module** — Aave governance proposal reading and voting
- **Liquidation helpers** — health factor monitoring, liquidation call wrappers
- **More chains** — expand `Contracts` registry as Aave deploys to new L2s
- **Safe + delegatecall automation ergonomics.** Real-world Aave V3 automation often goes: `EOA → Gnosis Safe → DELEGATECALL → automation-proxy contract → protocol storage writes`. Observed on-chain (tx `0x32c9f2a0…5347`, block 24932739 — owner deactivated two DeFi Saver sub IDs in one call). Implication for V4 design (Task 51 `PositionManager`): the primary user-facing write surface should compose cleanly when executed under DELEGATECALL from a Safe. A likely future "`Onchain.Aave.Safe` helper module" if we grow Safe-aware calldata builders.
- **Debt-swap CREATE2 adapter + CoW solver pattern.** Aave V3's "Swap debt" UI (observed 2026-04-22) composes: (a) `approveDelegation` on the debt-token to a counterfactual CREATE2 adapter, (b) a CoW Protocol solver submits the settlement tx and pays gas, (c) inside settlement the adapter flash-loans, swaps, borrows via the allowance, and repays. An eventual `Onchain.Aave.DebtSwap` helper would need CREATE2 salt derivation compatible with Aave's UI factory, a CoW order builder, and solver/order-book integration — a large surface. For now `Onchain.Aave.DebtToken` (Task 53) plus a documented "submit flash-loan adapter call yourself" path is the pragmatic scope.

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
