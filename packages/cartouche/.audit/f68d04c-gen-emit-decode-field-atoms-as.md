---
sha: f68d04c6a726c49e4dd6c019958a7d7ff13f225c
short_sha: f68d04c
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: gen: emit decode-field atoms as compile-time literal, not runtime String.to_atom

**Original commit:** f68d04c — `gen: emit decode-field atoms as compile-time literal, not runtime String.to_atom`
**Author:** E.FU
**Files touched:** 5 (.sobelow-skips, lib/mix/cartouche.gen.ex, test/mix/cartouche_gen_test.exs, test/support/.../block_number.ex, rock.ex)
**LOC:** ±313
**PR:** none (direct push to `development`, per onchain-workspace convention)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 7 | bug/hygiene (Cat 1) | .sobelow-skips | Commit appended new skip fingerprints while retaining stale line-shifted ones; file accumulated ~33 entries for ~6 real findings | Applied: clean regen → 6 entries (also incorporates the +5-line shift from this audit's gen edit) |
| 2 | 2 | doc nit (Cat 6) | lib/mix/cartouche.gen.ex (collector comment) | Comment implies an exact decode field set; collector actually emits a safe superset (scans all ABI returns, not only exec_vm decode paths) | Dropped — cosmetic single-reasoner; superset is harmless (extra interned atoms) and the imprecision is immaterial |
| 3 | — | discuss→drop (Cat 1) | lib/mix/cartouche.gen.ex `selector_return_field_atoms/1` | Catch-all `rescue _ -> []` could silently emit incomplete atoms if collection failed after a successful parse | Dropped with rationale (see below) |

## Auto-applied fixes

- **.sobelow-skips**: clean regeneration (`rm .sobelow-skips && mix sobelow --mark-skip-all`). The committed file had badly drifted — `--mark-skip-all` only marks *unskipped* findings, so every generator line-shift since the last clean regen appended a new fingerprint without removing the superseded one. f68d04c itself removed many runtime `String.to_atom` call sites yet left their stale skip fingerprints behind (13 `String.to_atom` skips for 2 real findings). Clean regen yields exactly the 6 current findings; verified idempotent against the CI drift check (`cp; mix sobelow --mark-skip-all; diff` → no diff). Note: this audit's own edit to `cartouche.gen.ex` shifted File.*/String.to_atom lines, which independently required the skip refresh.

## Discuss-tier resolutions

- **Finding #3 (rescue swallows needed atoms) — dropped, single-reviewer (Codex-only), verified false-positive.** `field_name_atoms/1` and its helpers are total (every clause has a fallback), so the `rescue` realistically only catches a `parse_specification_item/1` failure. Codex itself verified that a selector which fails to parse also fails to generate its decode function (via the same parse in `get_encode_call/4`), so there is no "generated decode function with a missing atom" crash path. Confirmed in-session by reading `field_name_atom/1`, `type_field_name_atoms/1`, and `name_to_atom/1` — all total. No code change.

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: #1 (Codex flagged `.sobelow-skips` drift; Claude confirmed and quantified)
Codex-only findings (verified): #1 (drift), #3 (rescue — verified as non-issue)
Codex-only findings (discarded as over-flag): #2 (cosmetic comment nit), #3 (theoretical rescue path)

## Notes

- Core correctness question (does the generation-time collector reproduce the exact atom set the old runtime walk interned?) answered YES by both reviewers: ABI return-field names are statically determined by the ABI spec (not decoded runtime data), and `collect_return_field_atoms/1` performs the same named-field/tuple/array recursion the old walk did. No `String.to_existing_atom/1`-at-decode crash risk.
- Confirmed `lib/cartouche/contract/{i_console,sleuth}.ex` do not use the exec_vm/decode_structs path at all, so they need no `@decode_field_atoms` and are not stale w.r.t. this generator change.
