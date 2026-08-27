---
sha: 505d42731cb072db307a93fade793b681502f801
short_sha: 505d427
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Add security policy, Dependabot, and Sobelow code-scanning workflow

**Original commit:** 505d427 — `Add security policy, Dependabot, and Sobelow code-scanning workflow`
**Author:** E.FU
**Files touched:** 3 (.github/dependabot.yml, .github/workflows/code-scanning.yml, SECURITY.md)
**LOC:** +134 (config/docs only; full audit because LOC ≥ 100, but no lib/ runtime code)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 4 | 8   | bug      | harness.yml:68 | "exit=Low" Sobelow gate runs bare `mix sobelow` (exits 0 → never gates) | applied: `--exit low` (codex) |
| 5 | 3   | discuss  | code-scanning.yml:37 | Actions tag-pinned (`@v4`) not SHA-pinned | documented, not applied (codex, over-flagged) |
| 6 | 4   | bug      | code-scanning.yml:70 | `if: always()` uploads SARIF even when compile failed before file existed | applied: `hashFiles` guard (codex) |

## Auto-applied fixes

- **.github/workflows/harness.yml:68** — `mix sobelow` → `mix sobelow --exit low`. The step is named
  "exit=Low" and code-scanning.yml:6 cites it as "the hard gate", but bare `mix sobelow` returns exit 0
  even with findings (Sobelow only fails the build with `--exit`; there is no `.sobelow-conf` setting
  the threshold). The claimed gate silently did not gate. Verified the repo is **sobelow-clean** before
  enabling, so turning the gate on does not break CI for the publish. (`--exit` defaults to `low`; spelled
  explicitly.) Fix lands in harness.yml — outside the commit's own diff, but it is the file the in-range
  commit's comment depends on; documenting without fixing would leave a real CI gate broken at publish.
- **.github/workflows/code-scanning.yml:70** — `if: always()` → `if: always() && hashFiles('sobelow.sarif') != ''`.
  If `mix deps.get`/`mix compile` fail before the Sobelow step, `sobelow.sarif` never exists and the
  always-on upload adds a misleading secondary failure. The guard uploads only when the report was produced.

## Not-applied finding (rationale)

- **#5 — SHA-pin actions (codex pri 7 → downgraded to discuss-3).** Codex over-flagged. Pinning actions to
  major-version tags (`@v4`, `@v1`) **with Dependabot github-actions updates enabled in this same commit**
  is a standard, defensible supply-chain posture — Dependabot bumps the tags (and the later commits
  bf5f800 / 767f347 / ce32a25 are exactly those bumps). SHA-pinning is stricter but is a maintainer policy
  choice, reversible, and not a defect. Recorded; not churned.

## Verified correct (no action)

- `permissions:` scoped minimally (`contents: read`, `security-events: write`). No `${{ github.event.* }}`
  interpolated into `run:` → no script-injection surface. `concurrency` cancel-in-progress correct.
  SECURITY.md `0.3.x` table was accurate **at this commit** (release was 0.3.0); its later staleness is
  attributed to the 3a1c24b release audit. dependabot.yml ecosystems/schedule correct.

## Discuss-tier resolutions

- (none requiring Claude+Codex dialogue — #5 resolved by verification as an over-flag)

## Codex second-opinion

Status: dual-reviewer (job task-mqs13dso-gc0cu2, 4m5s)
Corroborated findings (≥2 reasoners): —
Codex-only findings (verified + applied): 4 (sobelow gate), 6 (SARIF upload guard)
Codex-only findings (verified, downgraded + not applied): 5 (SHA-pin — acceptable posture w/ Dependabot)
Codex-only findings (discarded as over-flag): —
