---
sha: 46beb399423655a84e556a7786d5ea7fddf7389a
short_sha: 46beb39
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: release: cartouche 0.4.1 (fix EIP-1559 access-list signing; tesla 1.18.2 pin)

**Original commit:** 46beb39 — `release: cartouche 0.4.1 (fix EIP-1559 access-list signing; tesla 1.18.2 pin)`
**Author:** E.FU
**Files touched:** 5 (CHANGELOG.md, lib/cartouche/transaction.ex, mix.exs, mix.lock, test/transaction_test.exs)
**LOC:** ±57
**Provenance:** direct ff-merge to development (repo convention: no PRs for routine work).

## Summary

Security-critical EIP-1559 (V2) signing fix. Moves access-list normalization out of
the signed branch's redundant `List.update_at(8, &normalize_access_list/1)` and into
the shared `unsigned_rlp_list/1` builder, so the **unsigned** encoding path (from which
the signing digest is derived) normalizes tuple access-list entries too. Previously,
signing any EIP-1559 tx with a non-empty access list raised in ExRLP (tuples are not
encodable). Verified correct by both reviewers.

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | —   | bug-fix (the commit) | lib/cartouche/transaction.ex:832 | normalization moved to shared unsigned builder; index 8 confirmed = access_list | verified correct, no change |
| 2 | discuss | bug (codex) | lib/cartouche/transaction.ex:839 | `normalize_access_list/1` not idempotent on already-`[address, storage]`-list entries | **dropped** — see resolution below |

## Auto-applied fixes

- (none — the audited commit is itself the fix; it is correct and well-tested)

## Discuss-tier resolutions

- **(dropped, rationale):** Codex flagged `normalize_access_list/1` as non-idempotent —
  it accepts only `{address, storage}` tuples or bare-binary addresses, and would raise
  on an already-RLP-shaped `[address, [storage_keys]]` list entry. **Not applied.** The
  shape is unreachable through the public API: the struct's `access_list` is populated
  only by `V2.new/9` (tuples) and `decode_access_list/1` (lib/cartouche/transaction.ex:1040,
  which emits `{pad_address(address), [...]}` tuples). The `@spec` (line 836) correctly
  documents tuple|bare-binary input. The fix in this very commit removed the only
  double-call site (the redundant signed-branch `List.update_at(8, …)`), so the function
  is never invoked on its own output. Adding a defensive `[address, storage] -> ...` clause
  would guard an API-unreachable state — defensive cruft per the minimalism rule. Reversible
  if a future API ever lets callers inject pre-normalized lists; no migration cost to defer.

## Verification

- Index 8 of `unsigned_rlp_list/1` is `access_list` (0-indexed field order confirmed: chain_id,
  nonce, max_priority_fee, max_fee, gas_limit, destination, amount, data, access_list).
- Signed V2 path (transaction.ex:799) sources normalization from the shared builder — no
  double-normalization, no missed normalization.
- Empty-access-list backwards-compat: unchanged golden tests (transaction_test.exs:256, :276).
- Non-empty tuple regression: new round-trip test (transaction_test.exs:299).
- Codex independently ran `mix test.json test/transaction_test.exs` → 122 tests, 0 failures.

## Codex second-opinion

Status: dual-reviewer (job task-mqrhiz3e-anttdm, 2m41s)
Corroborated findings: verification points (index 8, no double-norm, digest path) — full agreement
Codex-only findings (verified): #2 (non-idempotency) — verified real-but-unreachable, dropped with rationale
Codex-only findings (discarded as over-flag): —
