---
sha: 3472738
short_sha: 3472738
audited_at: 2026-05-09
auditor_model: claude-opus-4-7
verdict: discuss-required (3 findings — 2 ROADMAP candidates, 1 already tracked)
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat(subscription): pre-registration buffer + pending-tx integration test (Tasks 38, 39)

**Original commit:** 3472738
**Files touched:** lib/onchain/subscription.ex + integration tests
**LOC:** ±226

## Findings

| # | Pri | Category | File:Line | Description | Suggested Resolution |
|---|-----|----------|-----------|-------------|---------------------|
| 1 | 5 | bug | lib/onchain/subscription.ex:420 | `lookup_or_buffer/3` buffers every unknown sub_id — unbounded keys | drop — already tracked as Task 70 in ROADMAP |
| 2 | discuss-design | bug | lib/onchain/subscription.ex:436 | `register_and_drain/3` overwrites on sub_id collision via `Map.put` (silently replaces previous type) | file as ROADMAP candidate — collision handling policy |
| 3 | discuss-design | doc-gap | lib/onchain/subscription.ex:416 | New helpers are `def + @doc false` — semi-public; should either document state contract or be `defp` | file as ROADMAP candidate — internal API surface clarification |

## Suggested fixes (NOT auto-applied this run)

- (none for direct apply — finding 1 already tracked, 2+3 require design discussion)

## ROADMAP candidates

- Sub_id collision handling in `register_and_drain/3` — what's the contract when two subscriptions land with the same id? overwrite, error, or drop?
- Internal API surface for subscription helpers (`def + @doc false` ambiguity vs `defp`)

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: —
Codex-only findings (verified): 2, 3
Codex-only findings (already tracked): 1
