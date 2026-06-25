---
sha: a430a4cf4d107d9e3a9b1aefa96a71ef5eb0355e
short_sha: a430a4c
audited_at: 2026-06-25
auditor_model: claude-opus-4-8
verdict: clean — fast-path
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: ci: stop caching _build so Rustler rebuilds both NIFs every run

**Reason for fast-path:** <100 LOC, no production-code paths (lib/src/native) touched.
**Files touched:** .github/workflows/harness.yml
