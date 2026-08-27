---
sha: 5ee4d738824f6d53c4684577b298dfb6d4e8b53d
short_sha: 5ee4d73
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: Add security policy, Dependabot, and Sobelow code-scanning workflow

**Original commit:** 5ee4d73 — `Add security policy, Dependabot, and Sobelow code-scanning workflow`
**Author:** E.FU
**Files touched:** 3 (.github/dependabot.yml, .github/workflows/code-scanning.yml, SECURITY.md)
**LOC:** ±132
**Provenance:** direct ff-merge to development (repo convention: no PRs for routine work). Classified full (LOC ≥ 100) but no `lib/` change.

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 3   | doc-gap  | CLAUDE.md:61  | Sobelow-workflow section enumerated CI sobelow surface but omitted new code-scanning.yml | **applied** |
| 2 | —   | clean    | .github/workflows/code-scanning.yml | SARIF flow correct: separate compile keeps stdout clean, `continue-on-error` + `if: always()` upload, `security-events: write` perm | no fix |
| 3 | —   | clean    | SECURITY.md | advisory URL matches repo (ZenHive/cartouche); scope sections accurate for a signing substrate | no fix |
| 4 | —   | clean    | .github/dependabot.yml | mix + github-actions ecosystems, weekly, PR-limit 5 | no fix |

## Auto-applied fixes

- CLAUDE.md:61 — added one clause noting `.github/workflows/code-scanning.yml` uploads
  `mix sobelow --format sarif` to GitHub code-scanning (reporting only, `continue-on-error`,
  not a gate), completing the documented sobelow-CI surface. LOW tier (doc); regenerated
  AGENTS.md from CLAUDE.md (the cross-family reviewer reads AGENTS.md). The regen also folded
  in pre-existing CLAUDE.md/includes drift that had accumulated since AGENTS.md was last
  generated — the file is auto-generated, so bringing it to truth is the correct action.

## Discuss-tier resolutions

- (none)

## Codex second-opinion

Status: not-dispatched (CI-config + docs only, no `lib/` production code — single-reviewer Claude pass; YAML/workflow correctness verified directly)
