# Onchain Aave Roadmap

**Vision:** Protocol-correct Aave V3 and V4 wrappers for Elixir — read positions, execute actions, and verify behavior against deployed contracts.

**Core dependency:** [onchain](../onchain) provides RPC, ABI, signing, address utilities.

**Sibling roadmaps:**
- [onchain/ROADMAP.md](../onchain/ROADMAP.md) — Core Ethereum primitives
- [onchain_evm/ROADMAP.md](../onchain_evm/ROADMAP.md) — Rust NIFs: revm, Solidity parsing, trace, codegen

> Canonical source is `roadmap/tasks.toml` (managed by `rmap`); this file is rendered. Per-task detail (`body`, acceptance criteria, out-of-scope) lives in the source — `rmap show <id>` to read it. Edit tasks via `rmap` commands, not by hand-editing the tables below.

---

## Status

The V3 core, math-validation suite, V4 wrapper modules, and read-path multicall work are shipped. The current correctness gate is independent deployed-state evidence for the V4 read and PositionManager write surfaces. The active v0.5 milestone then closes the remaining V3 position-management and reserve-read gaps without claiming complete protocol coverage prematurely.

---

## Milestones

<!-- MILESTONES:BEGIN -->
### v0_5 — Live-evidenced V3/V4 surface

- **target_version:** 0.5.0
- **status:** 🔄 active
- **hypothesis:** Tests whether onchain_aave can express core V3 position-management and V4 Hub-and-Spoke flows with reproducible evidence against deployed Aave contracts.
- **pinned tasks:** 1/5 done
<!-- MILESTONES:END -->

---

## 🎯 Current Focus

<!-- FOCUS:BEGIN -->
**Focus phase:** 5 — Aave V4 Support (10 of 13 done · 0 in progress)

**Last shipped:** Task 52 — Prove V4 reads and PositionManager writes against deployed mainnet state on 2026-08-23

**Up next:** Task 69 — Re-sync the V4 address registry with the deployed surface and stop hardcoding three Hubs [D:4/B:9/U:9 → Eff:2.25] 🎯
<!-- FOCUS:END -->

**Active path:** Task 52 proves the shipped V4 wrappers against pinned deployed state, including stateful PositionManager success and authorization-error paths.

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

## Math Validation ✅

Completed protocol-level differential validation against Aave Solidity executed through revm. Consumer-specific off-chain aggregation validation will belong to the task that introduces such a consumer rather than remaining as a conditional blocker.

The validation work used two authorities at different layers:

- **revm via `onchain_evm`** — canonical for *protocol-level* math (WadRayMath, interest accrual). Validates our Elixir port against actual on-chain Solidity bytecode. Version-agnostic (V2/V3/V4).
- **`@aave/math-utils` via `onchain_js`** (QuickBEAM) — authority for off-chain aggregation behavior when matching Aave's frontend is part of a future consumer contract.

They cover different failure modes: revm catches drift from the contracts, JS catches drift from the UI. The revm NIF surface (`Onchain.EVM.simulate_call/3`, `simulate_transaction/3`, `simulate_batch/2`) already supports everything needed: mainnet/Sepolia forks at a pinned block, `state_overrides` for balance/nonce/code/storage injection per address (enables bytecode injection for pre-deployment V4), caller/gas/timeout options, and raw hex output decoded via `Onchain.ABI.decode_response/2`.

<!-- TASKS:BEGIN phase=3 -->
> 6 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-3-math-validation).
<!-- TASKS:END -->

---

## Cleanup Backlog (from initial-commit review) ✅

Discovered during the v0.1.0 staged-review pass. Deprioritized below Math Validation — polish, not a capability gate.

<!-- TASKS:BEGIN phase=4 -->
> 4 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-4-cleanup-backlog).
<!-- TASKS:END -->

---

## Aave V4 Support

V4 went live on Ethereum mainnet on 2026-03-30 with a Hub-and-Spoke architecture: **three Hubs** (Core, Prime, Plus), **ten Hub Spokes** plus a standalone Treasury Spoke, **thirty-one Tokenization Spokes** (ERC-4626 supply-only vaults per (Hub, asset) pair), **five Position Managers**, and a per-Spoke oracle model. V4's contract surface differs materially from V3's single-`Pool` model — this is not a drop-in interface addition.

**All V4 addresses, interface pointers, and the V3→V4 module mapping live in [V4_SCOPING.md](V4_SCOPING.md).** Tasks 45+ reference that document rather than inlining addresses.

**Current gate:** Task 52 validates the shipped read wrappers and PositionManager writes against pinned Ethereum mainnet state. Forked-mainnet execution supplies reproducible stateful write evidence without depending on a particular testnet lifecycle.

<!-- TASKS:BEGIN phase=5 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 44 | ✅ | 🎁 **v4_support** · *V4_SCOPING.md* · Research V4 Hub-and-Spoke contract surface and scope the V4 support phase [D:3/B:7/U:8 → Eff:2.5?] 🎯 |
| Task 45 | ✅ | 🎁 **v4_support** · *Onchain.Aave.Contracts* · Extend Onchain.Aave.Contracts with V4 address keys [D:4/B:7/U:8 → Eff:1.88?] 🚀 |
| Task 46 `[P]` | ✅ | 🎁 **v4_support** · *V4_SCOPING.md* · Select V4 read surface by diffing IHub/ISpoke/IAaveOracle/ITokenizationSpoke against V3 IPool [D:3/B:6/U:7 → Eff:2.17?] 🎯 |
| Task 47 `[P]` | ✅ | 🎁 **v4_support** · *Onchain.Aave.V4.Hub* · Implement Onchain.Aave.V4.Hub read wrapper [D:4/B:6/U:5 → Eff:1.38?] 📋 |
| Task 48 `[P]` | ✅ | 🎁 **v4_support** · *Onchain.Aave.V4.Spoke* · Implement Onchain.Aave.V4.Spoke reads + V4 types [D:5/B:7/U:7 → Eff:1.4?] 📋 |
| Task 49 `[P]` | ✅ | 🎁 **v4_support** · *Onchain.Aave.V4.Oracle* · Implement Onchain.Aave.V4.Oracle wrapper (Spoke-scoped) [D:3/B:5/U:5 → Eff:1.67?] 🚀 |
| Task 50 `[P]` | ✅ | 🎁 **v4_support** · *Onchain.Aave.V4.TokenizationSpoke* · Implement Onchain.Aave.V4.TokenizationSpoke reads (ERC-4626 share accounting) [D:3/B:5/U:5 → Eff:1.67?] 🚀 |
| Task 51 | ✅ | 🎁 **v4_support** · *Onchain.Aave.V4.PositionManager* · Implement Onchain.Aave.V4.PositionManager ergonomic write wrappers (supply/borrow/repay analogs) [D:5/B:8/U:7 → Eff:1.5?] 🚀 |
| Task 52 | ✅ | 🎁 **v4_support** · 🚀 **v0_5** · *test/onchain/aave/v4/* · 🔒 Prove V4 reads and PositionManager writes against deployed mainnet state [D:6/B:9/U:9 → Eff:1.5] 🚀 |
| Task 57 | ✅ | 🎁 **v4_support** · *Onchain.Aave.V4.Hub* · Wrap remaining IHub preview converters and Hub bound constants [D:3/B:4/U:5 → Eff:1.5] 🚀 |
| Task 66 | ⬜ | 🎁 **v4_support** · *Onchain.Aave.V4.TokenizationSpoke* · Execute the V4 Tokenization Spoke: ERC-4626 writes and the share token's ERC-20 surface [D:5/B:8/U:8 → Eff:1.6] 🚀 |
| Task 67 | ⬜ | 🎁 **v4_support** · *Onchain.Aave.V4.PositionManager* · Wrap V4 position configuration and position-manager authorization, and close the Taker fork-evidence gap [D:4/B:8/U:8 → Eff:2.0] 🎯 |
| Task 69 | ⬜ | 🎁 **v4_support** · *Onchain.Aave.Contracts* · Re-sync the V4 address registry with the deployed surface and stop hardcoding three Hubs [D:4/B:9/U:9 → Eff:2.25] 🎯 |
<!-- TASKS:END -->

---

## V3 Write Surface Gaps

Consumer patterns observed on-chain that the current V3 write surface doesn't cover.

<!-- TASKS:BEGIN phase=6 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 53 | ✅ | 🎁 **v3_write_gaps** · *Onchain.Aave.DebtToken* · Onchain.Aave.DebtToken — wrap approveDelegation + borrowAllowance on variable/stable debt tokens [D:3/B:6/U:6 → Eff:2.0?] 🎯 |
| Task 54 | ✅ | 🎁 **v3_write_gaps** · *(cross-cutting research)* · Mine defi-skills:intent-to-transaction action surface for onchain_aave coverage gaps [D:3/B:8/U:7 → Eff:2.5?] 🎯 |
| Task 58 | ⬜ | 🎁 **v3_write_gaps** · 🚀 **v0_5** · *Onchain.Aave.Pool* · Onchain.Aave.Pool — eMode: setUserEMode, getUserEMode, category config, and enumeration via getEModes [D:5/B:8/U:7 → Eff:1.5] 🚀 |
| Task 59 | ⬜ | 🎁 **v3_write_gaps** · 🚀 **v0_5** · *Onchain.Aave.Pool* · Retire stable-rate APIs and resolve variable debt tokens through the dedicated Pool getter [D:4/B:8/U:7 → Eff:1.88] 🚀 |
| Task 60 | ⬜ | 🎁 **v3_write_gaps** · 🚀 **v0_5** · *Onchain.Aave.Pool* · Onchain.Aave.Pool — setUserUseReserveAsCollateral and repayWithATokens [D:4/B:7/U:7 → Eff:1.75] 🚀 |
| Task 61 | ⬜ | 🎁 **v3_write_gaps** · 🚀 **v0_5** · *Onchain.Aave.Pool* · Expose typed direct reserve data and normalized index reads [D:4/B:5/U:5 → Eff:1.25] 📋 |
| Task 62 | ⬜ | 🎁 **v3_write_gaps** · Make the integration gate settle: bound math_revm runtime so --include integration terminates [D:4/B:7/U:8 → Eff:1.88] 🚀 |
<!-- TASKS:END -->

---

## Read-Path Multicall Adoption ✅

<!-- TASKS:BEGIN phase=7 -->
> 1 task. See [CHANGELOG.md](CHANGELOG.md#phase-7-read-path-multicall-adoption).
<!-- TASKS:END -->

---

## Event & Revert Decoding

Decode what the deployed protocol says back. hieroglyph ≥ 1.5 carries the full ABI event/error surface (`decode_event/4`, `encode_event_topics/2`, built-in `Error(string)`/`Panic(uint256)` recognition, strict decode mode); onchain core carries `Onchain.Log.decode_event/2` and `RPC.eth_get_logs`. This phase turns those into Aave-level capabilities: Pool event logs with topic filters, structured revert reasons on write failures, and strict decoding of RPC responses (the last blocked on onchain task 88 exposing decode options).

<!-- TASKS:BEGIN phase=8 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 63 | ⬜ | 🎁 **event_error_decoding** · *Onchain.Aave.Events* · Decode deployed Aave V3 Pool events from logs with topic-filter fetch [D:5/B:8/U:7 → Eff:1.5] 🚀 |
| Task 64 | ⬜ | 🎁 **event_error_decoding** · Surface decoded revert reasons on Aave write and call failures [D:4/B:7/U:7 → Eff:1.75] 🚀 |
| Task 65 | 🔶 | 🎁 **event_error_decoding** · Adopt strict ABI decoding across Aave response decode paths [D:3/B:6/U:5 → Eff:1.83] 🚀 ⛔ onchain task 88 must land first: Onchain.ABI.decode_response/2 and Onchain.Contract.call accept no decode options today, so strict mode is unreachable from this repo |
| Task 68 | ⬜ | 🎁 **event_error_decoding** · *Onchain.Aave.Events* · Decode V4 Hub, Spoke and Tokenization Spoke events from logs [D:5/B:8/U:7 → Eff:1.5] 🚀 |
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
