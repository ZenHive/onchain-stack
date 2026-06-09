# Onchain JS Roadmap

**Vision:** Run battle-tested npm packages on the BEAM via QuickBEAM — no Node.js required.

**Completed work:** See [CHANGELOG.md](CHANGELOG.md) for finished tasks.

**Parent library:** [onchain/ROADMAP.md](../onchain/ROADMAP.md) — core Ethereum primitives

---

## Current Focus

**Phase 1: Foundation** — QuickBEAM runtime lifecycle, npm setup, browser stubs. Everything else depends on this.

> **Philosophy:** Pure functions first. Wrap JS libraries with clean Elixir APIs. Consumers shouldn't need to know JS is involved.

### 📋 Current Tasks

<!-- FOCUS:BEGIN -->
**Focus phase:** 1 — Foundation (0 of 1 done · 1 in progress)

**Last shipped:** no recent shipments

**Up next:** none — focus phase complete or all blocked
<!-- FOCUS:END -->

---

## Phase 1: Foundation

<!-- TASKS:BEGIN phase=1 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 1 | 🔄 | 🎁 **foundation** · QuickBEAM foundation [D:3/B:7/U:8 → Eff:2.5?] 🎯 |
<!-- TASKS:END -->

---

## Phase 2: Ethereum JS Tools

<!-- TASKS:BEGIN phase=2 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 2 | ⬜ | 🎁 **eth_tools** · *OnchainJs.Solc* · solc-js compilation (.sol → ABI + bytecode) [D:4/B:9/U:8 → Eff:2.12?] 🎯 |
| Task 3 | ⬜ | 🎁 **eth_tools** · *OnchainJs.Uniswap* · Uniswap v3 SDK routing (optimal swap paths, price impact) [D:5/B:8/U:7 → Eff:1.5?] 🚀 |
| Task 4 | ⬜ | 🎁 **eth_tools** · DeFiSaver recipe builder (@defisaver/sdk) [D:5/B:8/U:7 → Eff:1.5?] 🚀 |
| Task 5 | ⬜ | 🎁 **eth_tools** · 1inch Fusion SDK (DEX aggregation) [D:5/B:7/U:6 → Eff:1.3?] 📋 |
<!-- TASKS:END -->

---

## Phase 3: Cross-Validation & Utilities

<!-- TASKS:BEGIN phase=3 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 6 | ⬜ | 🎁 **cross_validation** · Aave math-utils cross-validation [D:3/B:5/U:4 → Eff:1.5?] 🚀 |
| Task 7 | ⬜ | 🎁 **cross_validation** · *OnchainJs.Merkle* · Merkle proof construction (airdrops, whitelists, storage proofs) [D:3/B:6/U:5 → Eff:1.83?] 🚀 |
<!-- TASKS:END -->

---

## Key Design Decisions

1. **Separate library** — QuickBEAM (Zig NIF) violates onchain's "pure Elixir, no native deps" principle
2. **Follows portfolio pattern** — each native runtime (Rust, Zig) gets its own package
3. **Consumers opt in** — only projects that need JS bridge compile Zig NIFs
4. **onchain_evm can depend on onchain_js** — for solc-js compilation in codegen pipeline
5. **Clean Elixir APIs** — consumers shouldn't need to know JS is involved under the hood
