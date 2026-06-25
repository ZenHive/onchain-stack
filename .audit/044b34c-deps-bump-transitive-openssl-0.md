---
sha: 044b34c1c909e88136f83680e416bdc6e520235d
short_sha: 044b34c
audited_at: 2026-06-25
auditor_model: claude-opus-4-8
verdict: clean
codex_status: not-dispatched — lockfile only
audited_by: audit-review v1
---

# Audit: deps: bump transitive openssl 0.10.81 / rustls-webpki 0.103.13

**Original commit:** 044b34c — `deps: bump transitive openssl 0.10.81 / rustls-webpki 0.103.13`
**Author:** E.FU
**Files touched:** 1
**Stat:** 1 file changed, 6 insertions(+), 7 deletions(-)

## Findings

(none) — transitive `openssl` 0.10.81 / `rustls-webpki` 0.103.13 bump clearing 12 Dependabot alerts (6 high). Cargo.lock only. `lru` left pinned at 0.12.5 (alloy-provider 0.7.3 constrains it) — explicitly noted in the commit and later resolved by Task 55 (de0f955) revm/alloy bump.

## Notes

Security advisory remediation, lockfile-only. NIFs recompile clean.

## Codex second-opinion

Status: not-dispatched (lockfile-only, no code surface)
