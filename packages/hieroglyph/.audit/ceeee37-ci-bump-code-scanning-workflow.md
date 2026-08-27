---
sha: ceeee37fcd5482799c9ab0d5dff94f48a07923ac
short_sha: ceeee37
audited_at: 2026-08-22
auditor_model: claude-opus-5
verdict: clean — fast-path
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: ci: bump code-scanning workflow actions (checkout@v7, cache@v6)

**Reason for fast-path:** <100 LOC changed and no `lib/` or `src/` path touched.
**Author:** E.FU
**Files touched:** .github/workflows/code-scanning.yml
**LOC:** 1 file changed, 2 insertions(+), 2 deletions(-)

**Auditor note:** Action-version bump inside a workflow that `a3a1d14` later deleted; see `.audit/a3a1d14-ci-remove-the-github-actions-w.md`.
