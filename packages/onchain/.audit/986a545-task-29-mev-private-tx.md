---
sha: 986a545
short_sha: 986a545
audited_at: 2026-06-05
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: MEV protection — private transaction submission (Task 29)

**Files touched:** lib/onchain/mev.ex (new, +docs/tests) · **LOC:** ±520

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 4 | bug | mev.ex normalize_block | `max_block_number`/`block_number` accept block TAGS ("latest") via normalize_block; Flashbots requires a concrete hex quantity | Filed → Task 80 |
| 2 | 4 | doc-gap | mev.ex @moduledoc | Error Format omits `{:error, {:invalid_bundle, input}}` (non-list bundle) | **Applied** — added to the error list |

Request shaping is pure + unit-tested; `eth_sendPrivateTransaction`/`eth_sendBundle` param shapes verified against Flashbots docs (Codex cross-checked). `:endpoint` required (no public-node fallback) — correct for MEV. Tx-hex/empty-bundle/missing-block validation ordered before endpoint. Transport reuses Cartouche.RPC.send_rpc. No signing performed here (auth headers passed through).

## Codex second-opinion

Status: dual-reviewer. Raised finding 1 (block-tag laxity, verified, filed) + the invalid_bundle doc gap (applied). Refs: Flashbots RPC docs.
