---
sha: 7456273323bd755019629d472b6740ac613806d8
short_sha: 7456273
audited_at: 2026-08-22
auditor_model: claude-opus-5
verdict: clean — fast-path
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: ci: set version-type strict — setup-beam rejects version-file without it

**Reason for fast-path:** <100 LOC changed and no `lib/` or `src/` path touched.
**Author:** E.FU
**Files touched:** .github/workflows/code-scanning.yml, .github/workflows/harness.yml
**LOC:** 2 files changed, 4 insertions(+), 1 deletion(-)

**Auditor note:** `setup-beam` version-type fix inside a workflow that `a3a1d14` later deleted; see the a3a1d14 report.
