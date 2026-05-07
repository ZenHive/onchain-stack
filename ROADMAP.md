# Onchain JS Roadmap

**Vision:** Run battle-tested npm packages on the BEAM via QuickBEAM — no Node.js required.

**Completed work:** See [CHANGELOG.md](CHANGELOG.md) for finished tasks.

**Parent library:** [onchain/ROADMAP.md](../onchain/ROADMAP.md) — core Ethereum primitives

---

## Current Focus

**Phase 1: Foundation** — QuickBEAM runtime lifecycle, npm setup, browser stubs. Everything else depends on this.

> **Philosophy:** Pure functions first. Wrap JS libraries with clean Elixir APIs. Consumers shouldn't need to know JS is involved.

### 📋 Current Tasks
| Task | Status | D | B | U | Eff | Notes |
|------|--------|---|---|---|-----|-------|
| 1 | ⬜ | 3 | 7 | 8 | 2.50 🎯 | QuickBEAM foundation (runtime lifecycle, npm setup, browser stubs) |

---

## Phase 1: Foundation

| # | Task | Status | D | B | U | Eff | Notes |
|---|------|--------|---|---|---|-----|-------|
| 1 | QuickBEAM foundation | ⬜ | 3 | 7 | 8 | 2.50 🎯 | Runtime lifecycle, npm setup, browser stubs |

**Task descriptions:**

**1 — QuickBEAM foundation.** Add quickbeam + npm deps. Create `OnchainJs.Runtime` module with runtime lifecycle management: start with browser stubs, load bundles, supervised runtime in application tree. Include integration test that starts a runtime, evaluates JS, and stops cleanly.

---

## Phase 2: Ethereum JS Tools

| # | Task | Status | D | B | U | Eff | Notes |
|---|------|--------|---|---|---|-----|-------|
| 2 | solc-js compilation (`.sol` → ABI + bytecode) | ⬜ | 4 | 9 | 8 | 2.13 🎯 | Closes codegen pipeline; also feeds onchain Sleuth |
| 3 | Uniswap v3 SDK routing (optimal swap paths, price impact) | ⬜ | 5 | 8 | 7 | 1.50 📋 | JS SDK handles tick math + multi-hop |
| 4 | DeFiSaver recipe builder (`@defisaver/sdk`) | ⬜ | 5 | 8 | 7 | 1.50 📋 | Flash loan recipes → encoded calldata |
| 5 | 1inch Fusion SDK (DEX aggregation) | ⬜ | 5 | 7 | 6 | 1.30 📋 | Complement to Task 3 |

**Task descriptions:**

**2 — solc-js compilation.** Load solc-js via QuickBEAM, expose `OnchainJs.Solc.compile/2` that takes `.sol` source and returns `{:ok, %{abi: [...], bytecode: "0x..."}}`. Two consumers:
- **onchain_evm codegen pipeline** — generate `.sol` → compile to bytecode → deploy via Signer.
- **onchain Sleuth** (see [onchain/ROADMAP.md](../onchain/ROADMAP.md) Task 62) — compile a custom read-only `.sol` query to bytecode, hand off to `Onchain.Sleuth.query/3` which ships it in an `eth_call` for one-shot execution against live chain state.

Both paths use the same output (`bytecode` field). Sleuth takes the creation bytecode directly; deployment flows prepend it with constructor args and send via Signer.

**3 — Uniswap v3 SDK routing.** Load `@uniswap/v3-sdk` + `@uniswap/smart-order-router` via QuickBEAM. Expose `OnchainJs.Uniswap.route/4` for optimal swap paths. JS SDK handles tick math and multi-hop routing out of the box.

**4 — DeFiSaver recipe builder.** Load `@defisaver/sdk` via QuickBEAM. Expose recipe construction: flash loan → action sequence → repay, returning encoded calldata.

**5 — 1inch Fusion SDK.** Load `@1inch/fusion-sdk` via QuickBEAM. DEX aggregation across multiple protocols.

---

## Phase 3: Cross-Validation & Utilities

| # | Task | Status | D | B | U | Eff | Notes |
|---|------|--------|---|---|---|-----|-------|
| 6 | Aave math-utils cross-validation | ⬜ | 3 | 5 | 4 | 1.50 📋 | Validate onchain_aave math against canonical JS |
| 7 | Merkle proof construction (airdrops, whitelists, storage proofs) | ⬜ | 3 | 6 | 5 | 1.83 🚀 | `merkletreejs` via QuickBEAM |

**Task descriptions:**

**6 — Aave math-utils cross-validation.** Load `@aave/math-utils` via QuickBEAM and run the same calculations through both JS and onchain_aave's math modules. Property-based tests comparing outputs across implementations.

**7 — Merkle proof construction.** Load `merkletreejs` via QuickBEAM. Expose `OnchainJs.Merkle.build_tree/1` and `prove/2` for airdrop claims and storage proofs.

---

## Key Design Decisions

1. **Separate library** — QuickBEAM (Zig NIF) violates onchain's "pure Elixir, no native deps" principle
2. **Follows portfolio pattern** — each native runtime (Rust, Zig) gets its own package
3. **Consumers opt in** — only projects that need JS bridge compile Zig NIFs
4. **onchain_evm can depend on onchain_js** — for solc-js compilation in codegen pipeline
5. **Clean Elixir APIs** — consumers shouldn't need to know JS is involved under the hood
