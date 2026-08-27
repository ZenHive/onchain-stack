---
sha: 51713e0
short_sha: 51713e0
audited_at: 2026-05-09
auditor_model: claude-opus-4-7
verdict: discuss-required (5 findings — not auto-applied this run)
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: md updates, version management

**Original commit:** 51713e0
**Files touched:** mix.exs, CHANGELOG.md, ROADMAP.md, CLAUDE.md
**LOC:** docs + version pin

## Findings

| # | Pri | Category | File:Line | Description | Suggested Resolution |
|---|-----|----------|-----------|-------------|---------------------|
| 1 | 6 | doc-gap | mix.exs:59 vs CHANGELOG.md:29-32 | ex_ast pinned at `~> 0.11.0` in mix.exs; CHANGELOG mentions `0.10.1` / `~> 0.10.1` | apply: reconcile CHANGELOG to current pin |
| 2 | 5 | doc-gap | CHANGELOG.md:33 | "lock-only" bumps unverifiable in this repo — `mix.lock` is gitignored (per memory `project_mix_lock_gitignored.md`) | apply: note that lock-only entries are local-only |
| 3 | 5 | doc-gap | ROADMAP.md:81 | Future-release text mentions v0.5.4/v0.6.0 — already shipped per Current Focus | apply: rephrase to "future patch/minor" without naming tags |
| 4 | 4 | doc-gap | ROADMAP.md (Phase 10 tasks) | Future tasks still reference `Signet.RPC.send_rpc/3` | duplicate of 254789f findings — fold into one ROADMAP rename pass |
| 5 | 4 | doc-gap | CLAUDE.md:77 | ERC721 Module Layout omits `name`, `symbol`, `get_approved`, `approved_for_all?` | apply: update Module Layout entry |

## Suggested fixes (NOT auto-applied this run)

- mix.exs:59 vs CHANGELOG.md:29-32 — reconcile ex_ast version
- CHANGELOG.md:33 — annotate lock-only bumps as local
- ROADMAP.md:81 — drop concrete v0.5.4/v0.6.0 tags
- ROADMAP.md Phase 10 — fold signet→cartouche pass with 254789f findings
- CLAUDE.md:77 — expand ERC721 Module Layout entry

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: —
Codex-only findings (verified): 1, 2, 3, 4, 5
