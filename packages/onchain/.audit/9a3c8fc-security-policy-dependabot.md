---
sha: 9a3c8fc4d99837e1b8e2f51cab7f9e051b350ff0
short_sha: 9a3c8fc
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: clean
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: Add security policy, Dependabot, and Sobelow code-scanning workflow

**Original commit:** 9a3c8fc — `Add security policy, Dependabot, and Sobelow code-scanning workflow`
**Author:** E.FU
**Files touched:** 3 (.github/dependabot.yml, .github/workflows/code-scanning.yml, SECURITY.md)
**LOC:** ±130

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| — | — | — | — | No actionable findings | — |

## Notes (reviewed, not flagged)

- **dependabot.yml** — v2 schema, `mix` + `github-actions` ecosystems, weekly,
  `open-pull-requests-limit: 5`. Correct.
- **code-scanning.yml** — `permissions: {contents: read, security-events: write}`
  is the correct least-privilege set for SARIF upload; `setup-beam` pins from
  `.tool-versions` (strict); cache key includes `mix.lock` hash; `mix compile`
  precedes the SARIF run so build output can't pollute stdout; `continue-on-error`
  + `if: always()` upload tolerates findings. Sound.
- **Known GitHub limitation (not a defect):** SARIF upload from a *fork* PR fails
  because `GITHUB_TOKEN` is read-only and `security-events: write` is not granted to
  fork PRs. Standard for code-scanning workflows; same-repo pushes/PRs work. Left as-is.
- **SECURITY.md** — accurate scope (signing/tx-construction/untrusted-decode in
  scope; upstream deps out of scope), private-advisory reporting path. Correct.

No CHANGELOG entry filed: governance/CI tooling, not a library code/API change that
a consumer tracks. Consistent with the repo's CHANGELOG convention (completed
roadmap tasks + library changes only).

## Codex second-opinion

Status: not-dispatched — no Elixir runtime code in the diff (YAML + Markdown).
Single-reviewer (Claude) pass; YAML workflow correctness reviewed inline.
