---
sha: b45a0f7
short_sha: b45a0f7
audited_at: 2026-05-09
auditor_model: claude-opus-4-7
verdict: discuss-required (4 findings — not auto-applied this run)
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat(fees,rpc): Onchain.Fees + Onchain.RPC.fee_history (Task 53)

**Original commit:** b45a0f7
**Files touched:** lib/onchain/fees.ex (new), lib/onchain/rpc.ex (fee_history), lib/onchain/rpc/helpers.ex, integration tests
**LOC:** medium-large feature

## Findings

| # | Pri | Category | File:Line | Description | Suggested Resolution |
|---|-----|----------|-----------|-------------|---------------------|
| 1 | 5 | bug | lib/onchain/rpc/helpers.ex:123 | `ensure_reward_percentiles/1` rejects floats via `is_integer/1`; Execution API defines `array<number>` — `[50.0]` correctly typed but rejected | apply: relax to `is_number/1` (one-token surgical fix) |
| 2 | 4 | doc-gap | lib/onchain/fees.ex:23 + CHANGELOG.md:11 | Docs claim `buffer: 2.0` buys "~12-block headroom"; EIP-1559 caps base-fee growth at 12.5%/block → 2× ≈ 6 blocks, 12 blocks needs ≈4.11× | apply: correct doc + CHANGELOG numbers |
| 3 | discuss-trivial | extraction | lib/onchain/fees.ex:68 + others | Magic numbers (`1.2`, `50`, `1024`, `0..100`) — extract `@default_buffer`, `@default_reward_percentiles`, `@max_fee_history_blocks` | apply if cheap, else file as ROADMAP cleanup |
| 4 | discuss-trivial | doc-gap | test/onchain/rpc_integration_test.exs:214 | Test comment says next-block base fee at index 0 — actually it's the last entry per EIP-1559 | apply: fix comment |

## Suggested fixes (NOT auto-applied this run)

- lib/onchain/rpc/helpers.ex:123 — `is_integer/1` → `is_number/1` for percentile values
- lib/onchain/fees.ex:23 + CHANGELOG.md:11 — correct buffer math (12-block headroom requires ~4.11×, not 2×)
- lib/onchain/fees.ex — extract magic numbers as module attrs
- test/onchain/rpc_integration_test.exs:214 — base-fee-history index comment

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: —
Codex-only findings (verified): 1, 2, 3, 4
