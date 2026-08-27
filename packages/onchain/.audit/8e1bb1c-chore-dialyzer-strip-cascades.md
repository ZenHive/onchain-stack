---
sha: 8e1bb1c
short_sha: 8e1bb1c
audited_at: 2026-05-09
auditor_model: claude-opus-4-7
verdict: discuss-required (1 finding — not auto-applied this run)
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: chore(dialyzer): strip upstream-cascade suppressions from 11 modules (Task 43)

**Original commit:** 8e1bb1c
**Files touched:** 11 lib modules + .dialyzer_ignore.exs
**LOC:** ±49

## Findings

| # | Pri | Category | File:Line | Description | Suggested Resolution |
|---|-----|----------|-----------|-------------|---------------------|
| 1 | 6 | env | — | Dialyzer agent-sandbox failed during dual-review | environmental — drop, not a real finding |
| 2 | 4 | missing-todo | lib/onchain/rpc/helpers.ex:21 | Upstream ticket refs (cartouche ROADMAP Tasks 14+15+35) lack `TODO:` marker | apply: prefix `# TODO(upstream): ...` so credo surfaces it |

## Suggested fixes (NOT auto-applied this run)

- lib/onchain/rpc/helpers.ex:21 — add `TODO:` prefix to upstream refs

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: —
Codex-only findings (verified): 2
Codex-only findings (discarded as env): 1
