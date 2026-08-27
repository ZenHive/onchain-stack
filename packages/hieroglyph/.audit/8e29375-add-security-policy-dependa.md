---
sha: 8e29375
short_sha: 8e29375
audited_at: 2026-08-22
auditor_model: claude-opus-5
verdict: findings-applied
codex_status: unreachable
audited_by: audit-review v1
---

# Audit: Add security policy, Dependabot, and Sobelow code-scanning workflow

**Original commit:** 8e29375 · **Author:** E.FU · **LOC:** 3 files, 131 insertions(+)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 6 | doc-gap | SECURITY.md:12-15 | Supported-versions table pinned to 1.5.x; three releases have shipped since | applied |
| 2 | 5 | dead-config | .github/dependabot.yml:13-19 | `github-actions` ecosystem watches a directory `a3a1d14` emptied | applied |
| 3 | 4 | dead-config | (this commit's `code-scanning.yml`) | Sobelow scanning workflow deleted by `a3a1d14`; SECURITY.md still implies it runs | see a3a1d14 report |

## Assessment

`SECURITY.md` itself is good: it correctly scopes the threat model to a library
that decodes untrusted on-chain data and encodes fund-moving calldata, routes
reports to a private GitHub advisory rather than a public issue, and draws a
sensible in-scope / out-of-scope line.

Its supported-versions table had gone stale. It claimed `1.5.x` supported and
`< 1.5` unsupported, while the package is at 1.6.2 — so on a literal reading the
current release line was unsupported and a reporter on 1.6.x would be told their
version does not receive security fixes. Corrected to `1.6.x` / `< 1.6`.

The Sobelow code-scanning workflow this commit added no longer exists; `sobelow`
survives as a step inside `mix precommit` (`--skip --exit low`) and is green at
HEAD, but nothing runs it automatically. That belongs to the CI-removal finding
and is analysed in `.audit/a3a1d14-ci-remove-the-github-actions-w.md`.

## Auto-applied fixes

- `SECURITY.md`: supported line `1.5.x` → `1.6.x`.
- `.github/dependabot.yml`: dead `github-actions` ecosystem block removed; the
  `mix` block retained.

## Second-opinion status

Codex dispatched and cancelled (workspace-root/isolation conflict). Single-reviewer pass.
