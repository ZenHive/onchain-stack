---
sha: f1dc5532816c5958584b58b45e11a5e10838a6f3
short_sha: f1dc553
audited_at: 2026-06-25
auditor_model: claude-opus-4-8
verdict: clean
codex_status: not-dispatched — lockfile only
audited_by: audit-review v1
---

# Audit: deps: bump transitive rand to 0.8.6 / 0.9.3 (GHSA-cq8v-f236-94qc)

**Original commit:** f1dc553 — `deps: bump transitive rand to 0.8.6 / 0.9.3 (GHSA-cq8v-f236-94qc)`
**Author:** E.FU
**Files touched:** 2
**Stat:** 2 files changed, 27 insertions(+), 27 deletions(-)

## Findings

(none) — transitive `rand` 0.8.6 / 0.9.3 security bump (GHSA-cq8v-f236-94qc), Cargo.lock entries only in both native crates. No source change.

## Notes

Security advisory remediation. NIFs recompile clean per commit message. No CHANGELOG entry — transitive lockfile-only; the consolidated 0.3.0 notes do not enumerate transitive lock bumps (acceptable; the user-facing dep line is documented).

## Codex second-opinion

Status: not-dispatched (lockfile-only, no code surface)
