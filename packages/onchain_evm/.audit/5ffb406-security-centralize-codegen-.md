---
sha: 5ffb4060c57427a3a9090c4bb1b11a60d016ce25
short_sha: 5ffb406
audited_at: 2026-06-25
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: security — centralize codegen atom creation + make CI honor sobelow skips

**Original commit:** 5ffb406 — `security: centralize codegen atom creation + make CI honor sobelow skips`
**Author:** E.FU
**Files touched:** 4 (.github/workflows/code-scanning.yml, .sobelow-skips, CHANGELOG.md, lib/onchain/contract/generator.ex)
**Stat:** +29/−24

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 3 | doc-gap | .github/workflows/code-scanning.yml:64 | Comment said skipped File.read findings are ".sol paths", but `.sobelow-skips` also suppresses `Onchain.Solidity.parse_abi_file/1` ABI-JSON paths (Codex) | **applied** — broadened comment to ".sol/ABI-JSON file paths" |

## Auto-applied fixes

- .github/workflows/code-scanning.yml: broadened the `--skip` comment to cover ABI-JSON file paths (LOW-tier, comment-only).

## Discuss-tier resolutions

(none)

## Codex second-opinion

Status: dual-reviewer — **No atom-exhaustion bug.** Codex verified the 11 old `String.to_atom` sites are replaced 1:1 with `to_identifier_atom/1`, and all callers still derive atoms from compile-time-parsed ABI/Solidity identifiers, not runtime user input — confirmed false positive, correctly centralized. Sobelow verification (via compiled beams, Hex unavailable for `mix sobelow` directly): without `--skip`, exactly 5 baseline findings; with `--skip`, none. `.sobelow-skips` line numbers match current source (incl `generator.ex:322`).

Claude concurs: the `to_identifier_atom/1` helper is well-documented (`@doc false`, compile-time-only, bounded by the contract), atom growth bounded, `String.to_existing_atom` genuinely impossible (the macro creates the identifiers). The skip-file regeneration (16→6 lines, collapsing 11 DOS.StringToAtom entries to 1) is correct. CHANGELOG entry present.

Corroborated findings: #1 (comment accuracy)
Codex-only findings (over-flag): none
