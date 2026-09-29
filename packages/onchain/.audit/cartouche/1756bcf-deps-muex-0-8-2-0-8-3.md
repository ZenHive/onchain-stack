---
sha: 1756bcf65ddf3ca73212c1cd4d9d912033c19ffc
short_sha: 1756bcf
audited_at: 2026-08-24
auditor_model: claude-opus-5
verdict: clean — fast-path
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: deps: muex 0.8.2 -> 0.8.3

**Reason for fast-path:** 2 LOC, no production-code paths touched.
**Files touched:** mix.lock
**Note:** Lockfile-only bump of a `only: [:dev, :test], runtime: false` dependency; ships nothing to a consumer, so no CHANGELOG entry is owed. The mix.exs constraint moved in ce3cb60 and the version claim was re-audited in .audit/fb11b1b-roadmap-task-119-blocked-on-mu.md.
