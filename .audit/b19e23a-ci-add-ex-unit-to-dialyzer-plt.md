---
sha: b19e23aa96c2ebdd690968554411e7f58e3b4707
short_sha: b19e23a
audited_at: 2026-06-25
auditor_model: claude-opus-4-8
verdict: clean — fast-path
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: ci: add :ex_unit to dialyzer PLT so test-support flunk/1 resolves

**Reason for fast-path:** <100 LOC, no production-code paths (lib/src/native) touched.
**Files touched:** mix.exs
