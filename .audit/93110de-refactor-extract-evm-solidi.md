---
sha: 93110de107ea0587bada99395396cd8df3c63d41
short_sha: 93110de
audited_at: 2026-06-25
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: refactor — extract EVM/Solidity validation into cover-able sibling modules

**Original commit:** 93110de — `refactor: extract EVM/Solidity validation into cover-able sibling modules`
**Author:** E.FU
**Files touched:** 5 (lib/onchain/evm.ex, lib/onchain/evm/params.ex, lib/onchain/solidity.ex, lib/onchain/solidity/resolver.ex, test/onchain/evm/params_test.exs)
**Stat:** +856/−617

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 5 | doc-gap | CHANGELOG.md | `Onchain.EVM.Params` / `Onchain.Solidity.Resolver` extraction not recorded under release notes (Codex) | **applied** — added "Cover-able validation siblings" bullet to [0.3.0] |
| 2 | 4 | doc-gap | CLAUDE.md:44 (Module Layout) | Layout tree omitted the two new sibling modules; AGENTS.md inherits the stale tree (Codex) | **applied** — added `evm/params.ex` + `solidity/resolver.ex` to the tree; regenerated AGENTS.md |
| 3 | 3 | doc-gap | ROADMAP.md:152 (Module Structure) | Roadmap Module Structure block omits the sibling modules (Codex) | **noted, skipped** — ROADMAP.md is rmap-rendered; the Module Structure appendix is not task-derived, and hand-editing rmap output is forbidden (skill Step 9). Low value (pri 3) |

## Auto-applied fixes

- CHANGELOG.md ([0.3.0] ### Changed): added "Cover-able validation siblings" entry documenting the `Onchain.EVM.Params` + `Onchain.Solidity.Resolver` extraction and the cover-instrumentation rationale.
- CLAUDE.md (Module Layout): added `evm/params.ex` and `solidity/resolver.ex` entries.
- AGENTS.md: regenerated from updated CLAUDE.md (cross-family reviewer reads AGENTS.md).

All three applied fixes are LOW-tier (docs) — mechanical verification only.

## Discuss-tier resolutions

(none)

## Codex second-opinion

Status: dual-reviewer — **No behavioral-equivalence findings.** Codex confirmed the extracted Params/Resolver logic matches the pre-refactor inline logic: same validation order, same error tags, same param assembly. Verified on a clean clone of 93110de:
- `mix test.json --quiet --cover`: passed, 218 offline tests (30 integration excluded)
- Coverage: `Onchain.EVM.Params` 98.48%, `Onchain.Solidity.Resolver` 90.35%
- `mix credo --strict --format json`: 0 issues
- `mix dialyzer.json`: 0 warnings

Claude independently spot-checked `Onchain.EVM.Params` — validation order and error tags preserved; `:value` still accepts any binary (consistent with open Task 46, not a regression).

Corroborated findings: #1, #2, #3 (all three doc-gaps independently noted by Claude + Codex)
Codex-only findings (over-flag): none
