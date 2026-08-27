---
sha: 254789f
short_sha: 254789f
audited_at: 2026-05-09
auditor_model: claude-opus-4-7
verdict: discuss-required (4 doc-drift findings — not auto-applied this run)
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: refactor(deps): migrate :signet → :cartouche (Task 67)

**Original commit:** 254789f
**Files touched:** 16 lib + 8 test + mix.exs + ROADMAP/CHANGELOG (rename pass)
**LOC:** ±312

## Findings

| # | Pri | Category | File:Line | Description | Suggested Resolution |
|---|-----|----------|-----------|-------------|---------------------|
| 1 | 4 | doc-gap | ROADMAP.md (Task 63 prose) | Says `to_signet_opts(opts)` — helper renamed to `to_rpc_opts/1` (cf `lib/onchain/rpc/helpers.ex`) | apply rename in ROADMAP prose |
| 2 | 4 | doc-gap | ROADMAP.md (Task 65 prose) | "signet itself — already in deps" — actual dep is cartouche; "signet-as-oracle" mentions also stale | apply: rephrase "signet" oracle references; the differential-test oracle candidate should be cartouche, not signet |
| 3 | 3 | doc-gap | ROADMAP.md (Task 54 prose, Phase 10) | "Opt-in retry/backoff wrapper over `Signet.RPC.send_rpc/3`" + "patching signet" prose | apply: `Cartouche.RPC.send_rpc/3` + "patching cartouche" |
| 4 | 3 | doc-gap | ROADMAP.md (EIP Tracking § 432-442) | Codex flagged "EIP-4844/EIP-7702 → signet Phase 10" as stale | **discuss-design** — `../signet/` repo retains its historical name per ROADMAP:362; references to that repo are intentional, not drift. Verify intent before changing |

## Suggested fixes (NOT auto-applied this run)

- ROADMAP.md prose: `to_signet_opts(opts)` → `to_rpc_opts(opts)`; `Signet.RPC.send_rpc/3` → `Cartouche.RPC.send_rpc/3`; `signet itself` (Task 65 oracle candidate) → `cartouche itself`; "patching signet" → "patching cartouche"
- LEAVE: `../signet/ROADMAP.md` repo references — sibling design-discussion repo retained the name intentionally

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: —
Codex-only findings (verified): 1, 2, 3 (all real doc drift)
Codex-only findings (re-classified): 4 (Codex flagged as drift; verification shows it's intentional repo naming)
