---
sha: 9fb42c4
short_sha: 9fb42c4
audited_at: 2026-05-09
auditor_model: claude-opus-4-7
verdict: discuss-required (4 findings — none auto-applied per session scope)
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat(sleuth): add Onchain.Sleuth deploy-as-call primitive (Task 62)

**Original commit:** 9fb42c4
**Files touched:** lib/onchain/sleuth.ex (new) + 4 tests + docs
**LOC:** ±322

## Findings

| # | Pri | Category | File:Line | Description | Suggested Resolution |
|---|-----|----------|-----------|-------------|---------------------|
| 1 | 5 | bug | lib/onchain/sleuth.ex:41 + lib/onchain.ex (modules list) | `Onchain.Sleuth` not registered in root `Onchain.describe/0` discovery chain — `Onchain.describe(:sleuth)` silently omits | apply: add `Onchain.Sleuth` to discoverable modules list |
| 2 | 6 | bug | test/onchain/sleuth_integration_test.exs:45 | Race condition: integration test compares `Sleuth.query/5` vs `Contract.call/5`, both using default `"latest"` block — block landing between calls produces false mismatch on USDC balance | apply: pin block once before both calls, pass `block:` to both |
| 3 | 8 | doc-gap | ROADMAP.md (Task 62 description) | Completed Task 62 row documents stale draft API `query/4` / `query!/4` — actual shipped is `query/5` with `constructor_types` + `constructor_args` | apply: update ROADMAP signature |
| 4 | discuss-trivial | extraction | test/onchain/sleuth_integration_test.exs:68 | Magic number `10` for historic block lookback | apply: extract `@historic_block_offset 10` |

## Suggested fixes (NOT auto-applied this run — see session scope)

- lib/onchain.ex: add `Onchain.Sleuth` to `Discoverable` modules list
- test/onchain/sleuth_integration_test.exs: pin block number, replace magic `10`
- ROADMAP.md: update Task 62 row to `query/5` + `constructor_types` + `constructor_args`

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: —
Codex-only findings (verified): 1, 2, 3, 4 (all real)
Codex-only findings (discarded as over-flag): —
