---
sha: fa01eef
short_sha: fa01eef
audited_at: 2026-05-09
auditor_model: claude-opus-4-7
verdict: discuss-required (4 findings — not auto-applied this run)
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat(abi): Onchain.ABI.decode_call/3 + decode_error/2 (Tasks 71, 72)

**Original commit:** fa01eef
**Files touched:** lib/onchain/abi.ex + tests + CHANGELOG/ROADMAP
**LOC:** medium feature

## Findings

| # | Pri | Category | File:Line | Description | Suggested Resolution |
|---|-----|----------|-----------|-------------|---------------------|
| 1 | 6 | doc-gap | lib/onchain/abi.ex:191 | `decode_structs: true` @doc misses hieroglyph 1.4.0's requirement that field-name atoms must already exist before decoding (otherwise ArgumentError on `String.to_existing_atom`) | apply: add caveat |
| 2 | 7 | doc-gap | CHANGELOG.md:12 | CHANGELOG says return is `{:decode_error, _}` — actual impl returns `{:error, {:decode_error, term()}}` | apply: fix CHANGELOG line to match `{:error, {:decode_error, _}}` envelope |
| 3 | 8 | actionable-todo | ROADMAP.md:183 | Task 73 (revert-data plumbing) was open at commit time — should have been triggered when decode_error/2 landed | drop — resolved downstream by 8915686 (Task 73 ✅) |
| 4 | discuss-design | extraction | lib/onchain/abi.ex:203 | `decode_call/3` + `decode_error/2` duplicate hex-decode + upstream + error-envelope + rescue → private helper candidate | file as ROADMAP candidate |

## Suggested fixes (NOT auto-applied this run)

- lib/onchain/abi.ex:191 — document hieroglyph 1.4.0 atom existence requirement for `decode_structs: true`
- CHANGELOG.md:12 — fix error envelope shape

## ROADMAP candidates

- Extract shared decode-with-error-envelope helper for `decode_call/3` + `decode_error/2`

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: —
Codex-only findings (verified): 1, 2, 4
Codex-only findings (resolved downstream): 3
