---
sha: 8701bb9
short_sha: 8701bb9
audited_at: 2026-06-05
auditor_model: claude-opus-4-8
verdict: clean — fast-path
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: fix(rpc): declare :telemetry direct dep so dialyzer resolves span/3

**Reason for fast-path:** 1 LOC, 0 lib/ paths (mix.exs dep pin; salvage of Task 52)
**Files touched:** mix.exs
