---
sha: e8f6330b8074492723fd6c6bf1c22d8a91bef5cb
short_sha: e8f6330
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: clean — fast-path
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: ci: sobelow --skip in CI + skip entries; release 0.9.0, trim package files

**Reason for fast-path:** 22 LOC, no production-code paths (CI workflows + .sobelow-skips + mix.exs version/package).
**Author:** E.FU
**Files touched:** .github/workflows/code-scanning.yml, .github/workflows/harness.yml, .sobelow-skips, mix.exs
