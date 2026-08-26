# Onchain Aerodrome Roadmap

**Vision:** Aerodrome Finance bindings, Sugar-backed reads, a built-in price layer, and denominator-honest analytics for Elixir on Base (chain 8453). Correctness is graded by deployed contracts, never by our own encoders.

**Core dependency:** [onchain](../onchain) provides RPC, ABI, multicall, signing and address utilities.

**Sibling roadmaps:**
- [onchain/ROADMAP.md](../onchain/ROADMAP.md) — core Ethereum primitives
- [onchain_aave/ROADMAP.md](../onchain_aave/ROADMAP.md) — the sibling protocol wrapper this package's shape is modelled on
- [onchain_evm/ROADMAP.md](../onchain_evm/ROADMAP.md) — Rust NIFs: revm, Solidity parsing, codegen

> Canonical source is `roadmap/tasks.toml` (managed by `rmap`); this file is rendered. Per-task detail (`body`, acceptance criteria, out-of-scope) lives in the source — `rmap show <id>` to read it. Edit tasks via `rmap` commands, not by hand-editing the tables below.

---

## Status

Scaffold. The address registry, nine Sourcify-captured deployed ABIs and the `.reach.exs` layer contract are in place and verified against live Base state. Nothing else is implemented yet.

Three facts shape the whole plan and are worth reading before picking up any task:

1. **The layer gate does not yet enforce what it claims.** `mix reach.check --arch` builds a dependency edge only when *both* endpoints resolve to a declared layer, so an analytics module calling `Onchain.RPC` today produces zero violations — and one rule (`{:bindings, :types}`) forbids exactly the dependency the layer table requires. Task 1 fixes both and lands before anything else.
2. **`decode_structs: true` is unreachable** through this package's own wrappers: hex-released `onchain` 0.13.0 exposes `Onchain.Contract.call/5` and `Onchain.ABI.decode_response/2` at 2-arity with no opts forwarding. The package therefore decodes positionally into hand-written structs, with per-struct field-order tests as the drift defence.
3. **Base EVM simulation is blocked** (revm rejects any chain id but 1), but the math is still gradeable: `SlipstreamHelper` exposes tick and liquidity math as `pure` functions reachable by plain `eth_call`, so the Elixir ports are differentially swept against deployed bytecode.

---

## Milestones

<!-- MILESTONES:BEGIN -->
### v0_1 — Full read surface, analytics and prices

- **target_version:** 0.1.0
- **status:** 🔄 active
- **hypothesis:** Tests whether the complete Aerodrome read surface — Sugar reads, a built-in price layer, and denominator-tagged analytics — can ship with correctness graded by deployed contracts rather than by our own code, given that Base EVM simulation is structurally blocked.
- **pinned tasks:** 0/27 done

### v0_2 — Write surface without simulation

- **target_version:** 0.2.0
- **status:** ⬜ pending
- **hypothesis:** Tests whether a full Router/Gauge/NFPM/Voter write surface can ship with honest evidence when no local EVM can execute it — calldata graded against an independent encoder and real on-chain reverts, never against our own encoder.
- **pinned tasks:** 0/8 done
<!-- MILESTONES:END -->

---

## 🎯 Current Focus

<!-- FOCUS:BEGIN -->
**Focus phase:** 1 — Foundations & Layer Gate (0 of 5 done · 0 in progress)

**Last shipped:** no recent shipments

**Up next:** Task 2 — Onchain.Aerodrome.Epoch — weekly ve(3,3) epoch arithmetic [D:3/B:7/U:9 → Eff:2.67] 🎯
<!-- FOCUS:END -->

---

## Foundations & Layer Gate

<!-- TASKS:BEGIN phase=1 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 1 | ⬜ | 🎁 **foundations** · 🚀 **v0_1** · *Onchain.Aerodrome* · Close the reach layer-gate holes so analytics-never-touches-the-network is enforced, not documented [D:5/B:9/U:8 → Eff:1.7] 🚀 |
| Task 2 `[P]` | ⬜ | 🎁 **foundations** · 🚀 **v0_1** · *Onchain.Aerodrome.Epoch* · Onchain.Aerodrome.Epoch — weekly ve(3,3) epoch arithmetic [D:3/B:7/U:9 → Eff:2.67] 🎯 |
| Task 3 | ⬜ | 🎁 **foundations** · 🚀 **v0_1** · *Onchain.Aerodrome.Bindings.Abi* · Decode strategy and Bindings.Abi signature plumbing from priv/abis [D:5/B:8/U:8 → Eff:1.6] 🚀 |
| Task 4 | ⬜ | 🎁 **foundations** · 🚀 **v0_1** · *Mix.Tasks.Aerodrome.CaptureFixtures* · Golden-fixture capture harness: pinned-block eth_call fixtures and an offline loader [D:4/B:7/U:8 → Eff:1.88] 🚀 |
| Task 5 `[P]` | ⬜ | 🎁 **foundations** · 🚀 **v0_1** · *Onchain.Aerodrome.RPCCase* · Onchain.Aerodrome.RPCCase — the first multi-endpoint portability test seam in the family [D:4/B:7/U:8 → Eff:1.88] 🚀 |
<!-- TASKS:END -->

---

## Types

<!-- TASKS:BEGIN phase=2 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 6 `[P]` | ⬜ | 🎁 **types** · 🚀 **v0_1** · *Onchain.Aerodrome.Types.Lp* · Types.Lp, .Position, .Swap and .Token — the pool and token structs, with ABI drift tests [D:5/B:8/U:8 → Eff:1.6] 🚀 |
| Task 7 `[P]` | ⬜ | 🎁 **types** · 🚀 **v0_1** · *Onchain.Aerodrome.Types.VeNFT* · Types.VeNFT, .Vote, .Relay, .LpEpoch and .Reward — the veAERO structs, with ABI drift tests [D:5/B:8/U:8 → Eff:1.6] 🚀 |
<!-- TASKS:END -->

---

## Bindings

<!-- TASKS:BEGIN phase=3 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 8 | ⬜ | 🎁 **bindings** · 🚀 **v0_1** · *Onchain.Aerodrome.Bindings.LpSugar* · Bindings.LpSugar — the full read surface and the count()-driven pagination driver [D:6/B:9/U:9 → Eff:1.5] 🚀 |
| Task 9 `[P]` | ⬜ | 🎁 **bindings** · 🚀 **v0_1** · *Onchain.Aerodrome.Bindings.RewardsSugar* · Bindings.RewardsSugar and Bindings.VeSugar [D:4/B:7/U:7 → Eff:1.75] 🚀 |
| Task 10 `[P]` | ⬜ | 🎁 **bindings** · 🚀 **v0_1** · *Onchain.Aerodrome.Bindings.RelaySugar* · Bindings.RelaySugar and Bindings.TokenSugar [D:3/B:6/U:6 → Eff:2.0] 🎯 |
| Task 11 `[P]` | ⬜ | 🎁 **bindings** · 🚀 **v0_1** · *Onchain.Aerodrome.Bindings.Factories* · Bindings.Factories — PoolFactory, CLFactory and SlipstreamHelper [D:4/B:6/U:6 → Eff:1.5] 🚀 |
| Task 12 `[P]` | ⬜ | 🎁 **bindings** · 🚀 **v0_1** · *Onchain.Aerodrome.Bindings.Voter* · Bindings.Voter — the read surface (epochs, weights, gauge and pool registry) [D:3/B:6/U:6 → Eff:2.0] 🎯 |
<!-- TASKS:END -->

---

## Pure Math

<!-- TASKS:BEGIN phase=4 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 13 | ⬜ | 🎁 **math** · 🚀 **v0_1** · *Onchain.Aerodrome.Math.Tick* · Math.Tick — port Slipstream TickMath and grade it over a swept int24 domain [D:6/B:10/U:8 → Eff:1.5] 🚀 |
| Task 14 `[P]` | ⬜ | 🎁 **math** · 🚀 **v0_1** · *Onchain.Aerodrome.Math.Liquidity* · Math.Liquidity — amounts and liquidity conversion plus signed and unsigned deltas, differentially graded [D:5/B:8/U:7 → Eff:1.5] 🚀 |
| Task 15 `[P]` | ⬜ | 🎁 **math** · 🚀 **v0_1** · *Onchain.Aerodrome.Math.Stable* · Math.Stable — the Solidly stable invariant and v2 constant-product quoting [D:5/B:7/U:7 → Eff:1.4] 📋 |
| Task 16 | ⬜ | 🎁 **math** · 🚀 **v0_1** · *Onchain.Aerodrome.Math.Price* · Math.Price — decimals-aware price conversion from sqrtX96, reserves and the stable invariant [D:4/B:8/U:8 → Eff:2.0] 🎯 |
<!-- TASKS:END -->

---

## Price Layer

<!-- TASKS:BEGIN phase=5 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 17 | ⬜ | 🎁 **price** · 🚀 **v0_1** · *Onchain.Aerodrome.Analytics.Price* · Types.Price and .PriceMap plus Analytics.Price — pure spot pricing and numeraire route resolution [D:5/B:8/U:8 → Eff:1.6] 🚀 |
| Task 18 | ⬜ | 🎁 **price** · 🚀 **v0_1** · *Onchain.Aerodrome.Sugar.Prices* · Bindings.Chainlink and Sugar.Prices — anchor feeds with a staleness policy, materialising a PriceMap [D:5/B:8/U:8 → Eff:1.6] 🚀 |
<!-- TASKS:END -->

---

## Analytics

<!-- TASKS:BEGIN phase=6 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 19 `[P]` | ⬜ | 🎁 **analytics** · 🚀 **v0_1** · *Onchain.Aerodrome.Analytics.Pool* · Analytics.Pool — pool typing, TVL, staked share and verified fee-unit semantics [D:4/B:7/U:8 → Eff:1.88] 🚀 |
| Task 20 `[P]` | ⬜ | 🎁 **analytics** · 🚀 **v0_1** · *Onchain.Aerodrome.Analytics.Position* · Analytics.Position — principal, range state and valuation, cross-graded against Sugar's own amounts [D:5/B:8/U:8 → Eff:1.6] 🚀 |
| Task 21 | ⬜ | 🎁 **analytics** · 🚀 **v0_1** · *Onchain.Aerodrome.Analytics.APR* · Analytics.APR — separate fee and emission rates, each carrying its denominator as data [D:5/B:8/U:9 → Eff:1.7] 🚀 |
| Task 22 | ⬜ | 🎁 **analytics** · 🚀 **v0_1** · *Onchain.Aerodrome.Analytics.APR* · APR invariant enforcement, the 7.53 percent golden, and the tiered coverage gate [D:6/B:10/U:8 → Eff:1.5] 🚀 |
<!-- TASKS:END -->

---

## Read API

<!-- TASKS:BEGIN phase=7 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 23 `[P]` | ⬜ | 🎁 **read_api** · 🚀 **v0_1** · *Onchain.Aerodrome.Sugar.Pools* · Sugar.Pools and Sugar.Tokens — the ergonomic pool and token read API [D:4/B:8/U:8 → Eff:2.0] 🎯 |
| Task 24 `[P]` | ⬜ | 🎁 **read_api** · 🚀 **v0_1** · *Onchain.Aerodrome.Sugar.Positions* · Sugar.Positions, .VeNfts, .Rewards and .Relays — the account-scoped read API [D:4/B:7/U:7 → Eff:1.75] 🚀 |
<!-- TASKS:END -->

---

## Evidence & Release

<!-- TASKS:BEGIN phase=8 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 32 `[P]` | ⬜ | 🎁 **evidence_release** · 🚀 **v0_1** · *Onchain.Aerodrome.AbiDrift* · Runnable ABI-drift detector: re-fetch every priv/abis entry and diff selector sets [D:4/B:7/U:7 → Eff:1.75] 🚀 |
| Task 33 | ⬜ | 🎁 **evidence_release** · 🚀 **v0_1** · *Onchain.Aerodrome* · Live integration proof of the full read, analytics and price surface across two endpoints [D:4/B:8/U:9 → Eff:2.12] 🎯 |
| Task 34 | ⬜ | 🎁 **evidence_release** · 🚀 **v0_1** · *OnchainAerodrome* · 📝 Cut 0.1.0: CHANGELOG, README status, SECURITY scope, descripex roster and a hex build dry run [D:3/B:6/U:7 → Eff:2.17] 🎯 |
<!-- TASKS:END -->

---

## Write Surface

<!-- TASKS:BEGIN phase=9 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 25 | ⬜ | 🎁 **write** · 🚀 **v0_2** · *Onchain.Aerodrome.Contracts* · 🔒 Capture Router, Gauge and NFPM ABIs from Sourcify and extend the registry with two-source-verified addresses [D:5/B:9/U:8 → Eff:1.7] 🚀 |
| Task 26 `[P]` | ⬜ | 🎁 **write** · 🚀 **v0_2** · *Onchain.Aerodrome.CalldataFixture* · 🔒 Golden-calldata evidence harness: an independent cast oracle plus eth_call impersonation, proven on Voter [D:5/B:8/U:8 → Eff:1.6] 🚀 |
| Task 27 `[P]` | ⬜ | 🎁 **write** · 🚀 **v0_2** · *Onchain.Aerodrome.Write.Voter* · 🔒 Write.Voter — vote, reset, poke, claims, managed deposits and distribute [D:5/B:7/U:6 → Eff:1.3] 📋 |
| Task 28 | ⬜ | 🎁 **write** · 🚀 **v0_2** · *Onchain.Aerodrome.Write.Router* · 🔒 Write.Router — swap and liquidity calldata builders with Signer opt-in [D:6/B:8/U:7 → Eff:1.25] 📋 |
| Task 29 `[P]` | ⬜ | 🎁 **write** · 🚀 **v0_2** · *Onchain.Aerodrome.Write.Gauge* · 🔒 Write.Gauge — stake, unstake and claim calldata builders [D:4/B:7/U:7 → Eff:1.75] 🚀 |
| Task 30 `[P]` | ⬜ | 🎁 **write** · 🚀 **v0_2** · *Onchain.Aerodrome.Write.NFPM* · 🔒 Write.NFPM — Slipstream concentrated-liquidity position lifecycle [D:6/B:8/U:7 → Eff:1.25] 📋 |
| Task 31 | ⬜ | 🎁 **write** · 🚀 **v0_2** · *Onchain.Aerodrome.CalldataFixture* · 🔒 Mutation-survivor audit: prove the golden-calldata comparators actually discriminate [D:5/B:9/U:6 → Eff:1.5] 🚀 |
| Task 35 | ⬜ | 🎁 **write** · 🚀 **v0_2** · *OnchainAerodrome* · 📝 Cut 0.2.0: live write-surface evidence capstone, CHANGELOG, SECURITY scope and descripex roster for Write.* [D:4/B:7/U:7 → Eff:1.75] 🚀 |
<!-- TASKS:END -->

---

## Key Design Decisions

1. **`Onchain.Aerodrome.*` namespace**, with `OnchainAerodrome` as the descripex discovery root.
2. **Six layers, gate-enforced** — `types`, `base`, `bindings`, `analytics`, `read`, `write`. Analytics sits *below* the read API deliberately: APR, tick math and valuation take structs, not RPC options, so the entire analytics suite is testable with zero network.
3. **Positional decode, not `decode_structs`** — forced by the 2-arity wrappers in hex `onchain` 0.13.0, and safer anyway: no `String.to_existing_atom/1` on dynamic input. Field-order drift is caught by per-struct tests read from the captured ABI.
4. **Prices split on the pure/impure seam** — `Math.Price` (base) and `Analytics.Price` (pure resolver over structs) stay network-free; `Bindings.Chainlink` and `Sugar.Prices` do the fetching. A built-in price source without breaking the analytics guarantee.
5. **APR rates carry their denominators as data.** `fee_apr` and `emission_apr` are separate `%Rate{}` structs and are never summed — arithmetic on two of them raises, and a manifest test fails on any `total_apr`-shaped function.
6. **Money is integers; ratios are `Decimal`.** No floats on any money path.
7. **Writes return calldata by default.** Signing is opt-in and requires an explicit signer; no module reads a private key from the environment.
8. **Evidence comes from deployed contracts** — Sourcify-captured ABIs, pinned-block golden fixtures, `SlipstreamHelper` as a differential oracle, Foundry's `cast` as an independent calldata oracle, and real `eth_call` reverts. Never from our own encoder, and never from the frontend's headline number.

## Module Structure

```
lib/onchain_aerodrome.ex          # Descripex.Discoverable roster
lib/onchain/aerodrome/
  contracts.ex                    # address registry + verified constants
  epoch.ex                        # weekly ve(3,3) epoch arithmetic
  math/                           # tick, liquidity, stable-invariant, price
  types/                          # Lp, Position, Swap, Token, VeNFT, Vote,
                                  #   Relay, LpEpoch, Reward, Price, PriceMap
  bindings/                       # abi, lp_sugar, rewards_sugar, ve_sugar,
                                  #   relay_sugar, token_sugar, factories,
                                  #   slipstream_helper, voter, chainlink
  analytics/                      # price, pool, position, apr
  sugar/                          # pools, tokens, positions, ve_nfts,
                                  #   rewards, relays, prices
  write/                          # voter, router, gauge, nfpm
lib/mix/tasks/                    # fixture + golden generators (outside the layer graph)
priv/abis/                        # Sourcify-captured deployed ABIs + provenance
```

## Protocol context

A dated snapshot of protocol facts the task bodies do not repeat — official Python Sugar SDK (unsigned calldata, agent CLI), Coinbase tokenized stocks as ordinary B20 pool tokens, and the B20-multiplier / 24/5 Chainlink TRV denominator trap — lives in [`docs/protocol-context.md`](docs/protocol-context.md). Re-fetch before treating addresses or SDK versions as current.

## Future Directions

Potential expansions — not yet scoped or scored:

- **Simulation-backed write tests.** Blocked upstream: `onchain_evm`'s revm binding rejects any chain id but 1, so no Base fork test can run. If an OP-Stack `spec_id` mapping or a caller-supplied `:spec_id` option lands upstream, the calldata-golden substitute in phase 8 can be replaced by real execution, and mutation testing becomes meaningful.
- **Historical and epoch-indexed analytics** — APR series across epochs, which needs archive reads and a block-parameter surface on every binding.
- **TWAP pricing** from a CL pool's `observe()`, giving a manipulation-resistant alternative to single-block spot prices.
- **Velodrome on Optimism.** Same Sugar contract family, different addresses. Out of scope here by design, but the types and math layers would transfer nearly unchanged. Official 2026 Aero merge (Aerodrome + Velodrome) is the same item when addresses unify — recapture ABIs, do not rewrite types.
- **Upstreaming the multi-endpoint test seam** into `onchain` core, where all seventeen integration files currently share a single-endpoint helper.
- **B20 share-equivalent helpers / sugar-sdk compatibility suite.** Not v0.1. File via `rmap new` when a consumer needs them; the invariants are already in `docs/protocol-context.md`.
