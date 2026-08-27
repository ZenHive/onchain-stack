---
sha: 3c39dd1
short_sha: 3c39dd1
audited_at: 2026-06-05
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Onchain.RPC.batch/2 — JSON-RPC 2.0 array-batched requests (Task 51)

**Files touched:** lib/onchain/rpc.ex (+CHANGELOG/README/tests) · **LOC:** ±271 (delivery 3c39dd1 + review 8a7e1cd)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 4 | bug | rpc.ex decode_batch_responses | `Map.new(responses, &{&1["id"],&1})` raises on a non-map array item (e.g. `[1]`) before the graceful `other`/`nil` path | Filed → Task 81 |
| 2 | 3 | abstraction | rpc.ex send_batch_request | Transport (Finch.build, CartoucheFinch, ethereum_node default) is reimplemented, duplicating cartouche internals | Noted — defaults verified to match cartouche exactly (`mainnet.infura.io`, `CartoucheFinch`, client Finch). Upstreaming a Cartouche batch-send is a cartouche-PR candidate, out of onchain scope |

Correctness verified: out-of-order responses re-ordered by id; revert `:data` enrichment matches single-call path (`normalize_rpc_error` → `maybe_put_revert_data_hex`); empty list short-circuits; invalid `{method,params}` rejected loudly. Transport-config defaults confirmed identical to `Cartouche.RPC`/`Cartouche.Application` — no drift today.

## Codex second-opinion

Status: dual-reviewer. Raised finding 1 (verified real, filed). No byte-order/RLP/ABI path touched.
