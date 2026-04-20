# Onchain Aave Roadmap

**Vision:** Aave V3 protocol wrappers for Elixir — read positions, execute actions, monitor health.

**Core dependency:** [onchain](../onchain) provides RPC, ABI, signing, address utilities.

**Sibling roadmaps:**
- [onchain/ROADMAP.md](../onchain/ROADMAP.md) — Core Ethereum primitives
- [onchain_evm/ROADMAP.md](../onchain_evm/ROADMAP.md) — Rust NIFs: revm, Solidity parsing, trace, codegen

---

## Status

All foundational V3 tasks are complete. This package provides full Aave V3 read + write coverage across mainnet and 6 chains. A small cleanup backlog (Tasks 36–39) was captured during the v0.1.0 staged-review pass; see below. A follow-on **Math Validation** backlog (Tasks 40–43) was added 2026-04-20 to expand `Aave.Math` with WadRayMath + MathUtils and cross-validate both against Solidity (via `onchain_evm`) and against Aave's frontend math (`@aave/math-utils` via `onchain_js`). The **Aave V4 Support** phase opened 2026-04-20 after V4 went live on Ethereum mainnet on 2026-03-30 with the Hub-and-Spoke architecture; Task 44 scoping completed 2026-04-20 (see [V4_SCOPING.md](V4_SCOPING.md)) and produced implementation Tasks 45–52.

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

**Task 42 — V4 cross-validation via revm.** V4 is live on Ethereum mainnet as of 2026-03-30 (AIP executed; Snapshot passed 2026-03-23, 100% support). Repeat Task 41's harness against V4's math library: pin a mainnet block post-launch, call the V4 math contracts directly via `Onchain.EVM.simulate_call/3`, assert equality with a V4-specific Elixir port. Depends on Task 40 (WadRayMath port) — V4's math library may have diverged from V3; port the V4-specific variants under `Onchain.Aave.Math.V4` if so. `state_overrides["code"]` bytecode injection is now a secondary fallback (e.g. for variants we want to test before mainnet exposure), not the primary path. V4 contract addresses (Hubs, Spokes, `EXTERNAL_LIBRARIES LIQUIDATION_LOGIC`, etc.) come from [V4_SCOPING.md](V4_SCOPING.md) — the Aave address book does not flag a separate "math library" constant, so the first step is locating the WadRayMath-equivalent call site (likely the `LIQUIDATION_LOGIC` external library at `0x88dF535473C5adf1f57789734A05E555F7Deb8DB`, or inlined in Hub/Spoke bytecode).

**Task 43 — Aggregation helpers via JS (gated on helpers existing).** When `onchain_aave` grows off-chain aggregation helpers (e.g. `Onchain.Aave.Summary.format_user_summary/2`, projected APY, weighted reserve averages — anything Aave's UI computes off-chain), validate them against `@aave/math-utils` via `onchain_js` (QuickBEAM). Load the npm bundle, call `formatUserSummaryAndIncentives` and friends with identical inputs, compare to Elixir output within a documented tolerance (BigNumber→Decimal conversion may introduce sub-wei noise). Gated (🔶) because the helpers don't exist yet — add the task to the active backlog when the first one lands. V2/V3 only today; re-check V4 JS availability before acting.

---

## Aave V4 Support

V4 went live on Ethereum mainnet on 2026-03-30 with a Hub-and-Spoke architecture: **three Hubs** (Core, Prime, Plus), **ten Hub Spokes** (Core: Main, Lido e-Mode, EtherFi e-Mode, Kelp e-Mode, Lombard BTC, Gold, Forex; Prime: Bluechip; Plus: Ethena Ecosystem, Ethena Correlated) **plus a standalone Treasury Spoke**, **thirty-one Tokenization Spokes** (ERC-4626 supply-only vaults per (Hub, asset) pair), **five Position Managers**, and a per-Spoke oracle model. V4's contract surface differs materially from V3's single-`Pool` model — this is not a drop-in interface addition.

**All V4 addresses, interface pointers, and the V3→V4 module mapping live in [V4_SCOPING.md](V4_SCOPING.md).** Tasks 45+ reference that document rather than inlining addresses.

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 44 | Research V4 Hub-and-Spoke contract surface and scope the V4 support phase | ✅ | 3 | 7 | 8 | 2.50 🎯 | `V4_SCOPING.md` — see [CHANGELOG](CHANGELOG.md#task-44-v4-hub-and-spoke-scoping) |
| 45 | Extend `Onchain.Aave.Contracts` with V4 address keys | ⬜ | 4 | 7 | 8 | 1.88 🚀 | `Onchain.Aave.Contracts` |
| 46 | Select V4 read surface by diffing `IHub`/`ISpoke`/`IAaveOracle`/`ITokenizationSpoke` against V3 `IPool` | ⬜ `[P]` | 3 | 6 | 7 | 2.17 🎯 | `V4_SCOPING.md` (research) |
| 47 | Implement `Onchain.Aave.V4.Hub` read wrapper | ⬜ `[P]` | 4 | 6 | 5 | 1.38 📋 | `Onchain.Aave.V4.Hub` |
| 48 | Implement `Onchain.Aave.V4.Spoke` reads + V4 types | ⬜ `[P]` | 5 | 7 | 7 | 1.40 📋 | `Onchain.Aave.V4.Spoke` |
| 49 | Implement `Onchain.Aave.V4.Oracle` wrapper (Spoke-scoped) | ⬜ `[P]` | 3 | 5 | 5 | 1.67 🚀 | `Onchain.Aave.V4.Oracle` |
| 50 | Implement `Onchain.Aave.V4.TokenizationSpoke` reads (ERC-4626 share accounting) | ⬜ `[P]` | 3 | 5 | 5 | 1.67 🚀 | `Onchain.Aave.V4.TokenizationSpoke` |
| 51 | Implement `Onchain.Aave.V4.PositionManager` ergonomic write wrappers (supply/borrow/repay analogs) | ⬜ | 5 | 8 | 7 | 1.50 📋 | `Onchain.Aave.V4.PositionManager.*` |
| 52 | V4 integration tests (mainnet forked reads; gated on Sepolia V4 deployment for writes) | 🔶 | 4 | 6 | 5 | 1.38 📋 | `test/onchain/aave/v4/*` |

Dependency order: 45 (registry) and 46 (surface selection) ship first. 47–50 can run in parallel once both land. 51 depends on 45–48. 52 is gated on V4 Sepolia becoming available; until then reads can be validated against mainnet via fork but writes have no testnet.

**Task 45 — V4 address registry.** Extend `Onchain.Aave.Contracts` to expose every V4 address enumerated in [V4_SCOPING.md](V4_SCOPING.md) — infrastructure, Position Managers, Hubs, Spokes, Tokenization Spokes, per-Spoke oracles. Decide the key shape: flat atoms for the ~20 singleton contracts (e.g. `:v4_core_hub`), nested lookup for the 31 Tokenization Spokes (e.g. `Contracts.v4_tokenization_spoke(:core, :weth, network: :ethereum)`) to avoid flooding the atom registry. Preserve the existing V3 lookup API (don't break `address/2` callers). Tests: look up representative addresses end-to-end. Prerequisite for every other V4 task.

**Task 46 — V4 read surface selection.** Read the V4 interface files from `github.com/aave/aave-v4/src/{hub,spoke,config-engine}/interfaces/` (enumerated in [V4_SCOPING.md § Sources](V4_SCOPING.md#sources)) and diff against V3's `IPool` + `IUiPoolDataProvider`. Produce a mapping table: for each V4 function, whether it replaces a V3 function, is new, or has no V3 equivalent. Output feeds Tasks 47–50. Open questions from scoping to resolve: (a) does V4 have a UiPoolDataProvider analog, (b) which Hub/Spoke reads reproduce V3's `getUserAccountData` semantics. Research task, no Elixir code.

**Task 47 — V4.Hub reads.** Wrap the Hub-level reads selected in Task 46 — likely: member Spokes, credit-line inventory and caps, Hub rate environment / utilization. Three Hubs, one module. Unit tests only at this stage.

**Task 48 — V4.Spoke reads + V4 types.** Wrap Spoke reads (collateral set, borrowable set, per-Spoke caps, per-user health/position data). Most complex V4 read module; ship the V4 type structs (`V4.Types.SpokeUserData`, `V4.Types.SpokeReserveData` — shaped per Task 46's findings). If the module + types together exceed a single session's scope, split on the axis `V4.Types.*` → separate task.

**Task 49 — V4.Oracle.** `Onchain.Aave.V4.Oracle` takes a Spoke address (not a network) because V4 oracles are Spoke-scoped. Mirror the V3 `Oracle` function shape where possible: `get_asset_price/2`, `get_asset_prices/2`, `get_source_of_asset/2`, `get_base_currency*`, `get_fallback_oracle/1`, plus direct Chainlink aggregator reads. Unit tests.

**Task 50 — V4.TokenizationSpoke reads.** Tokenization Spokes are ERC-4626 vaults — wrap `totalAssets`, `convertToAssets`, `convertToShares`, `previewDeposit`, `previewRedeem`, and any V4-specific metadata exposed by `ITokenizationSpoke`. Also ship a `lookup(hub, asset)` helper given there are 31 of these. Unit tests.

**Task 51 — V4.PositionManager writes.** Primary user-facing write surface. Wrap the Giver / Taker / Config / NativeTokenGateway / SignatureGateway entrypoints for the common supply/borrow/repay/withdraw flows. Likely needs to be split across two sessions if all five managers land at once — start with Giver + Taker (the primary supply/borrow flow) and gate the rest as a follow-on if scope grows. Depends on Tasks 47 + 48 (needs to know what Hub/Spoke state to reference).

**Task 52 — V4 integration tests (gated).** Full read-path tests against a mainnet-forked RPC for Hubs, Spokes, Oracles, Tokenization Spokes. Writes stay gated (🔶) until Aave deploys V4 on a testnet — none exists as of 2026-04-20. When a V4 testnet does appear, add Sepolia-style write integration tests mirroring `pool_write_integration_test.exs`.

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
