---
sha: 8915686
short_sha: 8915686
audited_at: 2026-05-09
auditor_model: claude-opus-4-7
verdict: discuss-required (4 findings — 1 verified coverage regression, 1 enrichment-flow concern)
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat(rpc): surface revert data hex for decode_error/2 (Task 73)

**Original commit:** 8915686
**Files touched:** lib/onchain/rpc/helpers.ex, lib/onchain/rpc.ex, test/onchain/rpc/helpers_test.exs (rewritten), AGENTS.md (deleted)
**LOC:** medium

## Findings

| # | Pri | Category | File:Line | Description | Suggested Resolution |
|---|-----|----------|-----------|-------------|---------------------|
| 1 | 5 | bug (codex hypothesis) | lib/onchain/rpc/helpers.ex:31 | Codex claims `do_rpc/3` enriches only maps already containing `:revert`, but `Cartouche.RPC.send_rpc/3` may not return `:revert` (only call_trx/estimate_gas do per cartouche docs) → enrichment may never trigger | needs verification — file as ROADMAP candidate to test enrichment actually fires for `eth_call` revert path |
| 2 | 7 | coverage-regression | test/onchain/rpc/helpers_test.exs | **VERIFIED**: file shrunk from 221 LOC → 94 LOC; old coverage of `ensure_hex_address/1`, `ensure_hex_data/1`, `normalize_block/1`, `ensure_tx_hash/1`, `to_rpc_opts/1`, `rename_key/3` dropped; only `maybe_put_revert_data_hex/1` + `parse_block_response/1` remain | file as ROADMAP candidate — restore helper test coverage (may have moved to other test files; needs audit) |
| 3 | 3 | doc-gap | lib/onchain/rpc.ex:25 | `@doc` claims optional `:error_abi` / `:error_params` flow through `call/3` + cartouche's `:errors` opt, but `to_rpc_opts/1` only forwards `[:rpc_url, :timeout]` | apply: either strip claim or wire forwarding |
| 4 | 4 | doc-gap (deletion) | repo root | `AGENTS.md` deleted (3174 lines) in this commit | likely intentional (AGENTS.md is a Codex/Cursor convention; user may have moved off it) — drop unless restoration was unintentional |

## Suggested fixes (NOT auto-applied this run)

- lib/onchain/rpc.ex:25 — reconcile @doc with `to_rpc_opts/1` actual forwarded keys

## ROADMAP candidates

- Verify revert-data enrichment fires end-to-end for `eth_call` revert (finding 1)
- Restore helper coverage that was dropped from `helpers_test.exs` (finding 2) — verified 94 LOC current state, 6 helpers no longer covered

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: —
Codex-only findings (verified): 1, 2, 3, 4
Notes: Finding 2 verified by direct file inspection — `wc -l test/onchain/rpc/helpers_test.exs` = 94, `describe` blocks only cover `maybe_put_revert_data_hex/1` and `parse_block_response/1`
