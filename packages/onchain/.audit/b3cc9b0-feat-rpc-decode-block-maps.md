---
sha: b3cc9b0b8ffe9c62b27d1ffaf645a9c2c481c779
short_sha: b3cc9b0
audited_at: 2026-06-05
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat(rpc): decode get_block_by_number maps like transactions (Task 57)

**Files touched:** lib/onchain/rpc.ex, lib/onchain/rpc/helpers.ex, lib/onchain/block.ex (+docs/tests) · **LOC:** ±297

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 4 | bug | helpers.ex parse_block_response | Invalid hex `number` ("0xZZ") → nil, masked as pending-like | Filed → Task 81 (malformed-node robustness) |
| 2 | 4 | bug | helpers.ex parse_block_transactions/parse_withdrawals | Non-binary/non-map list member raises FunctionClauseError | Filed → Task 81 |

Both are malformed-node-input robustness nits; a spec-compliant node never triggers them. Decode of compliant responses (atom keys, integer quantities, miner checksummed, tx hashes/objects) is correct. Breaking change documented with migration in CHANGELOG v0.6.0; ROADMAP/README/CLAUDE.md updated. Doc set complete.

## Codex second-opinion

Status: dual-reviewer. Corroborated low-severity robustness items (1,2) + a CHANGELOG `full_transactions` doc nuance (the wrapper hard-codes `false`). No high-severity bug; no valid-input defect.
