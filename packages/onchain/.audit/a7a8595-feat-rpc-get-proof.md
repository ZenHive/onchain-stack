---
sha: a7a8595
short_sha: a7a8595
audited_at: 2026-05-09
auditor_model: claude-opus-4-7
verdict: discuss-required (4 findings — 3 ROADMAP candidates, 1 doc-apply)
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat(rpc): Onchain.RPC.get_proof/3 (Task 49)

**Original commit:** a7a8595
**Files touched:** lib/onchain/rpc.ex (get_proof + parse_proof) + integration test
**LOC:** medium feature

## Findings

| # | Pri | Category | File:Line | Description | Suggested Resolution |
|---|-----|----------|-----------|-------------|---------------------|
| 1 | 7 | bug | lib/onchain/rpc/helpers.ex:80 (normalize_block) | EIP-1474 rejects `"0x"` / `"0x00"` block quantities — current helper accepts them | predates this commit — file as ROADMAP candidate (cross-cutting helper hardening) |
| 2 | 6 | bug | lib/onchain/rpc.ex:922 (parse_proof) | Missing `accountProof` / `storageProof[].proof` arrays default to `[]` instead of erroring on malformed RPC response | file as ROADMAP candidate (parser hardening) |
| 3 | 6 | bug | lib/onchain/rpc.ex:918 (parse_proof) | Malformed `balance` / `nonce` quantities silently become `nil` instead of raising/returning `{:error, ...}` | file as ROADMAP candidate (parser hardening) |
| 4 | 4 | doc-gap | lib/onchain/rpc.ex:723 (get_proof @doc) | Docs say `{:error, term}` but actual returns include `:invalid_storage_keys`, `:invalid_storage_key` atoms | apply: enumerate error atoms in @doc |

## Suggested fixes (NOT auto-applied this run)

- lib/onchain/rpc.ex:723 — enumerate `:invalid_storage_keys` / `:invalid_storage_key` in `get_proof/3` @doc

## ROADMAP candidates

- `normalize_block/1` EIP-1474 strictness (`"0x"` / `"0x00"` should be rejected as invalid block quantities)
- `parse_proof/1` hardening — error on missing arrays + malformed balance/nonce instead of silent defaults
- These three findings cluster as "RPC parser strictness" — could be one ROADMAP task with three sub-items

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: —
Codex-only findings (verified): 1, 2, 3, 4
