# Onchain Core Roadmap

**Vision:** Pure Elixir Ethereum library — read + write primitives, no native deps.

**Task tracking:** This file is rendered by `rmap` from `roadmap/tasks.toml`. Don't hand-edit the task tables inside `<!-- TASKS:BEGIN -->` / `<!-- TASKS:END -->` marker pairs — they're regenerated on every `rmap render`. Edit `roadmap/tasks.toml` or use `rmap status` / `rmap mark` / `rmap new`, then `rmap render`. Prose outside the marker pairs is byte-preserved. The pre-rmap hand-edited roadmap (with full done-task history and design narrative) is archived at [ROADMAP.hand.md.bak](ROADMAP.hand.md.bak).

**Completed work:** See [CHANGELOG.md](CHANGELOG.md) — done tasks (Phases 1–3, 8, 11; Code Health 36–48, 55–62, 67–68, 71–73; RPC Composition 49/50/53/59/62) are not duplicated here.

**Sibling roadmaps:**
- [onchain_aave/ROADMAP.md](../onchain_aave/ROADMAP.md) — Aave V3 protocol wrappers
- [onchain_evm/ROADMAP.md](../onchain_evm/ROADMAP.md) — Rust NIFs: revm, Solidity parsing, trace, codegen
- [onchain_js/ROADMAP.md](../onchain_js/ROADMAP.md) — JS bridge: npm packages on the BEAM via QuickBEAM
- [onchain_tempo/ROADMAP.md](../onchain_tempo/ROADMAP.md) — Tempo chain primitives

> **Philosophy:** Pure functions first. Consumers call from their own state. No forced state management.
>
> **Parallel work (`parallel` marker):** parallel-safe tasks are dependency-independent. Per the worktree workflow, flip status to in_progress, work in a worktree under `~/_DATA/worktrees/onchain/<id>/`, then commit. Note: Tasks **51 / 52 / 54 / 57** converge on `lib/onchain/rpc.ex` — avoid parallel sessions across those rows even though some carry no `parallel` marker.

---

## Phase 7: DEX Infrastructure

> On-chain DEX trading support. Swap routing across liquidity pools and MEV protection.

<!-- TASKS:BEGIN phase=7 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 28 `[P]` | ✅ | 🎁 **dex** · *Onchain.DEX.Router* · DEX swap routing (optimal path across pools) [D:7/B:8/U:7 → Eff:1.07?] 📋 |
| Task 29 `[P]` | ✅ | 🎁 **dex** · *Onchain.MEV* · MEV protection (private transaction submission) [D:6/B:8/U:7 → Eff:1.25?] 📋 |
| Task 80 | ✅ | 🎁 **dex** · *Onchain.MEV* · Audit-surfaced: Onchain.MEV accepts block tags where a concrete block is required [D:3/B:4/U:4 → Eff:1.33?] 📋 |
<!-- TASKS:END -->

---

## Phase 9: Account Abstraction (ERC-4337)

<!-- TASKS:BEGIN phase=9 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 69 `[P]` | ✅ | 🎁 **account_abstraction** · *Onchain.AA* · ERC-4337 UserOperation construction, signing, and bundler RPC [D:7/B:8/U:7 → Eff:1.07?] 📋 |
| Task 79 | ✅ | 🎁 **account_abstraction** · *Onchain.AA* · Audit-surfaced: ERC-4337 to_rpc_params validation can diverge from user_op_hash [D:4/B:5/U:5 → Eff:1.25?] 📋 |
<!-- TASKS:END -->

---

## Phase 10: RPC Composition Layer

> Per the scope split with cartouche, onchain is home for everything buildable on top of `Cartouche.*` public surface: RPC method wrappers, observability facades, and helpers over cartouche structs. Each task is small; batch as needed — no consumer blocking.

<!-- TASKS:BEGIN phase=10 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 51 | ✅ | 🎁 **rpc_composition** · *Onchain.RPC* · Onchain.RPC.batch/2 — JSON-RPC 2.0 array-batched requests [D:4/B:6/U:5 → Eff:1.38?] 📋 |
| Task 52 | ✅ | 🎁 **rpc_composition** · *Onchain.RPC* · Telemetry events around Onchain.RPC request path [D:3/B:5/U:5 → Eff:1.67?] 🚀 |
| Task 54 | ✅ | 🎁 **rpc_composition** · *Onchain.RPC* · Opt-in retry/backoff wrapper over Signet.RPC.send_rpc/3 [D:4/B:5/U:4 → Eff:1.12?] 📋 |
| Task 81 | ✅ | 🎁 **rpc_composition** · *Onchain.RPC* · Audit-surfaced: RPC batch + block decode crash on malformed node responses [D:2/B:3/U:4 → Eff:1.75?] 🚀 |
| Task 82 | ✅ | 🎁 **rpc_composition** · Add eth_estimateGas RPC helper + auto-estimate gas in send_transaction [D:3/B:5/U:6 → Eff:1.83?] 🚀 |
<!-- TASKS:END -->

---

## Phase 12: Code Health

> RPC return-shape unification, the `defrpc` codegen cluster (63 → 64 → 66, dependency-chained), ENS enhancements, differential testing, subscription hardening, and ERC-7730 clear-signing.

<!-- TASKS:BEGIN phase=12 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 57 | ✅ | 🎁 **rpc_shapes** · *Onchain.RPC* · Unify get_block_* / get_transaction_* RPC return shapes [D:4/B:6/U:6 → Eff:1.5?] 🚀 |
| Task 63 | ✅ | 🎁 **rpc_codegen** · *Onchain.RPC* · defrpc macro — codegen named JSON-RPC wrappers from declarative specs [D:4/B:6/U:5 → Eff:1.38?] 📋 |
| Task 64 | ✅ | 🎁 **rpc_codegen** · *Onchain.RPC.Specs* · Vendor openrpc.json + emit Onchain.RPC.Specs lookup feeding defrpc [D:4/B:6/U:5 → Eff:1.38?] 📋 |
| Task 66 | ✅ | 🎁 **rpc_codegen** · *Mix.Task (dev-only)* · Tree-sitter scrape of Erigon Go source for trace_* / ots_* method enumeration [D:5/B:4/U:3 → Eff:0.7?] ⚠️ |
| Task 41 `[P]` | ✅ | 🎁 **ens** · *Onchain.ENS* · ENS enhancements: CCIP-Read, ENSIP-10 wildcard, UTS-46/ENSIP-15 normalization, multi-coin [D:6/B:6/U:5 → Eff:0.92?] ⚠️ |
| Task 65 `[P]` | ✅ | 🎁 **differential_testing** · *test/onchain/differential/* · Differential test harness: Onchain.RPC vs reference impl (signet first) [D:6/B:5/U:3 → Eff:0.67?] ⚠️ |
| Task 70 `[P]` | ✅ | 🎁 **subscription_hardening** · *Onchain.Subscription* · Harden Onchain.Subscription.lookup_or_buffer/3 against unsolicited sub_id keys [D:3/B:4/U:3 → Eff:1.17?] 📋 |
| Task 74 `[P]` | ✅ | 🎁 **erc_standards** · *Onchain.ERC7730* · ERC-7730 clear-signing descriptor parser + binding evaluator [D:6/B:7/U:6 → Eff:1.08?] 📋 |
| Task 75 | ✅ | 🎁 **rpc_shapes** · Stop dialyzer cold-building the PLT per harness worktree (it OOM'd the host twice) [D:2/B:3/U:5 → Eff:2.0?] 🎯 |
| Task 76 | ✅ | 🎁 **rpc_codegen** · *Onchain.RPC* · Audit-surfaced: Task 63 defrpc macro is unused — wrappers still hand-written [D:4/B:5/U:5 → Eff:1.25?] 📋 |
| Task 77 | ✅ | 🎁 **erc_standards** · *Onchain.ERC7730.Formatter* · Audit-surfaced: ERC-7730 tokenAmount renders wrong token symbol (clear-signing safety) [D:4/B:7/U:6 → Eff:1.62?] 🚀 |
| Task 78 | ✅ | 🎁 **erc_standards** · *Onchain.ERC7730.Binding* · Audit-surfaced: ERC-7730 binding/descriptor hardening (domain match, EIP-712 type, malformed input) [D:5/B:5/U:5 → Eff:1.0?] 📋 |
| Task 83 | ✅ | 🎁 **rpc_composition** · *Onchain.RPC* · Migrate HTTP transport off cartouche's removed Finch seams (cartouche 0.5.0) [D:4/B:8/U:8 → Eff:2.0?] 🎯 |
| Task 84 | ⬜ | 🎁 **differential_testing** · 🔒 Mutation-grade RPC construction and DEX math invariants [D:6/B:9/U:7 → Eff:1.33] 📋 |
| Task 85 `[P]` | ✅ | 🎁 **rpc_composition** · Onchain.RPC block-level reads — receipts, transaction counts, transactions by index, and the block access list [D:4/B:7/U:6 → Eff:1.62] 🚀 |
| Task 86 `[P]` | ⬜ | 🎁 **rpc_composition** · Onchain.RPC.get_storage_values — eth_getStorageValues batched multi-account slot reads [D:3/B:6/U:5 → Eff:1.83] 🚀 |
| Task 87 | ⬜ | 🎁 **differential_testing** · 🔒 Mutation-adequacy campaign over the signing, key and address surface [D:5/B:8/U:3 → Eff:1.1] 📋 |
| Task 88 | ✅ | 🎁 **abi_decode_hardening** · 🔒 Expose hieroglyph's strict decode mode through the Onchain.ABI, Contract and Log decode surface [D:4/B:7/U:6 → Eff:1.62] 🚀 |
| Task 89 | ⬜ | 🎁 **signer_backend_contract** · 🔒 Route Onchain.Signer.sign_transaction through cartouche's {backend, config} carrier instead of the legacy MFA [D:3/B:7/U:6 → Eff:2.17] 🎯 |
| Task 90 | ⬜ | 🎁 **subscription_hardening** · HTTP log/block/pending polling over Cartouche.Filter, so subscribers work on the RPC URL this library defaults to [D:5/B:6/U:5 → Eff:1.1] 📋 |
| Task 91 | ✅ | 🎁 **node_portability** · Normalize node-capability refusals into typed errors instead of passing the raw JSON-RPC code through [D:3/B:7/U:7 → Eff:2.33] 🎯 |
| Task 92 | ⬜ | 🎁 **node_portability** · Onchain.RPC node introspection — eth_config and eth_capabilities so a consumer can discover what their node actually serves [D:4/B:7/U:6 → Eff:1.62] 🚀 |
| Task 93 | ⬜ | 🎁 **rpc_composition** · Onchain.RPC.create_access_list — compute the EIP-2930 access list that Signer.build_transaction already accepts but cannot produce [D:4/B:6/U:5 → Eff:1.38] 📋 |
<!-- TASKS:END -->

---

## Agent Routing

Every pending task carries an `assignee` (which agent executes it) and, for `claude` tasks, a `model` pin. Token-protective split — **Opus only where the work is genuinely hard** (deep spec/wire-format, macro/DSL design, signing): Tasks 28, 41, 63, 69, 74. **Sonnet** for medium judgment: 29, 57. **Codex** for spec-driven impl / codegen / test harnesses / telemetry: 51, 52, 54, 64, 65, 66. **Cursor** for bounded hardening: 70.

> **Antigravity (agy) is temporarily out of the routing pool** — disabled by an adapter bug. Task 52 (telemetry), originally routed to `antigravity`, is reassigned to `codex` (its `rpc_composition` bundle-mates 51/54 already run codex). Re-route to `antigravity` once the bug is fixed.

Drive dispatch with `rmap ready --fields id,title,assignee,model,dep_layer` (the parallel-safe set) or `rmap delegate <id>` (renders a native prompt for the task's assignee).

---

## Key Design Decisions

1. **Pure Elixir** — no native deps, no Rustler (NIF work lives in onchain_evm)
2. **Cartouche as sole Ethereum dep** — RPC, ABI, signing, crypto all in one (transitively pulls in `hieroglyph` for ABI)
3. **Consumers configure RPC URL** — `config :cartouche, ...` or pass URL per-call
4. **Standard error tuples** — `{:ok, result} | {:error, {:tag, reason}}`
5. **Plain structs** — `defstruct` + `@enforce_keys`, no private macro deps
6. **Descripex from day one** — All public modules use `api()` macro for self-describing functions
7. **Five-package family** — onchain (core), onchain_aave (Aave), onchain_evm (Rust NIFs), onchain_js (QuickBEAM), onchain_tempo (Tempo chain)
8. **Always update docs after completing a task** — ROADMAP.md, CHANGELOG.md, README.md, CLAUDE.md
9. **Integration tests use mainnet RPCs** — `ETHEREUM_API_URL` or `ETH_RPC_URL` env vars

> **EIP tracking, the defi-skills proposals (P1/P2/P3, pending accept/reject), the Task 48 won't-fix rationale, and the full done-task narrative live in [ROADMAP.hand.md.bak](ROADMAP.hand.md.bak)** — promote any of them into `roadmap/tasks.toml` via `rmap new` when a consumer needs them.
