---
sha: 8fc851e1b8fff73b0a6042a09e8996bf1740c404
short_sha: 8fc851e
audited_at: 2026-05-09
auditor_model: claude-opus-4-7
verdict: clean (findings resolved downstream)
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Generic JSON-RPC passthrough (Task 59)

**Original commit:** 8fc851e — `Generic JSON-RPC passthrough (Task 59)`
**Files touched:** 6 (lib/onchain/rpc.ex + tests + ROADMAP/CHANGELOG/README)
**LOC:** ±252

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | discuss-trivial | doc-gap | CLAUDE.md:69 | Module Layout omits `call/3` / `call!/3` surface | resolved downstream — current CLAUDE.md `rpc.ex` row includes "generic call/3 passthrough" |
| 2 | discuss-trivial | doc-gap | ROADMAP.md:44 | `[Unreleased]` summary stale post-Task 59 | resolved downstream by later release-plan rewrites |

## Auto-applied fixes

(none — both findings already resolved by later commits in the audited range)

## Discuss-tier resolutions

(none requiring dialogue — codex findings were valid at commit time but resolved by subsequent commits)

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: —
Codex-only findings (verified): 1, 2 (both at-time-of-commit; verified resolved in current state)
Codex-only findings (discarded as over-flag): —
