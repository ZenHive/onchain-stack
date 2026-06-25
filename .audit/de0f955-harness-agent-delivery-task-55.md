---
sha: de0f95575238a0d5b7fa87fb41048ef3d1fbc364
short_sha: de0f955
audited_at: 2026-06-25
auditor_model: claude-opus-4-8
verdict: discuss-required — HIGH-tier core-NIF regression surfaced to user (not auto-applied)
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: harness agent delivery — task 55 Bump revm 19→41 + alloy 0.7→2.1

**Original commit:** de0f955 — `harness: agent delivery — task 55 Bump revm 19→41 + alloy 0.7→2.1 in native/onchain_evm`
**Author:** harness
**Files touched:** Cargo.toml, Cargo.lock, src/lib.rs (native/onchain_evm)
**Stat:** src/lib.rs +138/−66; Cargo.toml dependency rewrite; Cargo.lock churn

> ⚠️ **Ships in 0.3.0, which 36ad558 prepped for hex publish.** The nonce regression below would publish to consumers unless fixed before `mix hex.publish`.

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 9 | bug | native/onchain_evm/src/lib.rs:429 (`build_tx`) | revm 41 makes `TxEnv.nonce` a required `u64` (was `Option<u64>`, None=skip-check in revm 19); single-tx paths default it to `0` with no `disable_nonce_check`, so simulating from a high-nonce EOA now regresses to `NonceTooLow`. **Corroborated: Claude + Codex.** | **SURFACED to user — STOP.** HIGH-tier core NIF; cannot behavior-verify in-session (live RPC + cold revm-41 recompile). Proposed fix below |
| 2 | 7 | bug/fidelity | native/onchain_evm/src/lib.rs:515 (`Context::mainnet()`) | revm 41 default spec is the latest hardfork (OSAKA); pinned historical-block forks execute under the wrong hardfork unless spec is derived from the block. Codex-only. | Likely **pre-existing** (revm 19 also defaulted to latest-at-the-time); not introduced by this commit. Recorded; bundle into the user discussion |
| 3 | 5 | bug | native/onchain_evm/src/lib.rs:577 (`do_simulate_batch`) | `simulate_batch([])` now calls `current_nonce` → one RPC `basic_ref` read for an empty no-op batch (could error/timeout); previously returned `{:ok, []}` with no RPC. Codex-only, verified real by Claude. | SURFACED with #1 (same file, same recompile) |
| 4 | 3 | extraction | native/onchain_evm/src/lib.rs:515 | Three repeated `Context::mainnet().with_db(...).build_mainnet()` sites; extract a helper before fixing shared spec/nonce config. Codex-only. | Pairs with the #1/#2 fix |

## Auto-applied fixes

(none in this commit) — all four findings are in the core revm NIF. Per the Step 9 stake-gated ladder, fixes inside core runtime / NIF code are HIGH-tier and require mechanical-stack-green + a second-grader read before landing. The mechanical stack cannot be satisfied in this audit session: (a) a cold revm-41 / alloy-2.1 recompile is prohibitively slow here, and (b) the nonce/hardfork behavior is only exercised by `@moduletag :integration` tests that require live RPC (`ETHEREUM_API_URL`). Applying a blind, uncompiled, untested change to the money-path NIF is exactly what the HIGH-tier gate exists to prevent. → surfaced to user.

## Discuss-tier resolutions

**Finding #1 (nonce regression) — proposed fix for user review:**

`simulate_call` / `simulate_transaction` model `eth_call` / `eth_estimateGas`, which on a real node do **not** validate nonce. The correct restoration of revm-19 behavior is to disable the nonce check on the read-only single-tx paths (the batch path, which `transact_commit`s sequentially, correctly manages nonces via `current_nonce` + offset and should keep doing so). Concretely, configure the context cfg with `disable_nonce_check = true` (verify the exact revm 41 cfg-mutation API — `Context::mainnet().modify_cfg_chained(|c| c.disable_nonce_check = true)` or equivalent against the installed crate source) for `do_simulate_call` and `do_simulate_transaction`. Consider `disable_balance_check` too for full `eth_call` parity (separate decision). **Add an integration test that simulates from a known high-nonce EOA and asserts success** — the current golden tests only use nonce-0 addresses (`0x0`, `0x1`), which is why this regression landed green (see `.audit/145f50c-*.md`).

**Finding #3 (empty-batch RPC read):** guard `current_nonce` behind `if !calls.is_empty()` (or early-return `{:ok, []}` before building the DB).

**Finding #2 (hardfork spec):** decide whether to derive `SpecId` from the forked block (correct historical fidelity) or document "executes under latest-hardfork semantics" as a known limitation. Pre-existing — not a blocker for the bump, but worth a tracked decision.

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: #1 (nonce regression — Claude + Codex independently, Codex pri 9)
Codex-only findings (verified): #2 (hardfork default), #3 (empty-batch RPC read), #4 (extraction)
Codex verification notes: could not run `cargo build` (sandbox could not create `target/debug`) or `mix test.json` (Hex unavailable); verified revm 41 / alloy 2.1 API shapes from local crate sources in `~/.cargo/registry/src`. docs.rs DNS unavailable.

**Recommendation to user:** fix #1 (+ #3) and add the high-nonce integration test **before** `mix hex.publish` of 0.3.0. Re-open Task 55 or file a follow-up if you want it tracked (audit-review does not file rmap tasks unprompted).
