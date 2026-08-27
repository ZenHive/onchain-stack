---
sha: 50a0477
short_sha: 50a0477
audited_at: 2026-05-09
auditor_model: claude-opus-4-7
verdict: discuss-required (3 findings — 1 reclassified, 1 ROADMAP candidate, 1 trivial)
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat(rpc,abi): v0.5.3 surface-area polish (Tasks 50, 58, 60, 61)

**Original commit:** 50a0477
**Files touched:** lib/onchain/rpc.ex, lib/onchain/abi.ex + tests
**LOC:** ±large

## Findings

| # | Pri | Category | File:Line | Description | Suggested Resolution |
|---|-----|----------|-----------|-------------|---------------------|
| 1 | 8 | bug (codex hypothesis) | lib/onchain/rpc.ex:284, :701 | Codex claims EIP-1474 lists `blockhash` lowercase; alias accepts `"blockHash"` camelCase | **Codex training-bias** — EIP-234 introduces `blockHash` (camelCase) in spec; current code matches standard. Drop or file as low-pri verification |
| 2 | discuss-design | bug | lib/onchain/rpc.ex:672 | Nil block bounds count as conflicts — `Map.has_key?(opts, :block_hash)` flags `%{block_hash: hash, from_block: nil}` as mutually exclusive | file as ROADMAP candidate — one-line fix: `Map.get(opts, :block_hash) != nil` |
| 3 | discuss-trivial | doc-gap | test/onchain/rpc_test.exs:165 | describe label says `syncing/2` but fn is `syncing/1` | apply: typo |

## Suggested fixes (NOT auto-applied this run)

- test/onchain/rpc_test.exs:165 — fix `syncing/2` → `syncing/1` describe label
- lib/onchain/rpc.ex:672 — surface for design discussion: should nil block bounds count as conflicts?

## ROADMAP candidates

- Block-bound conflict detection: nil-vs-omitted-key semantics in `validate_log_filter_opts/1`

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: —
Codex-only findings (verified): 2, 3
Codex-only findings (re-classified as training-bias): 1 — EIP-234 confirms `blockHash` camelCase is correct
