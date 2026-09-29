---
sha: 3e2ecb88cecbf4d0840074440a0e5f2aeae05acd
short_sha: 3e2ecb8
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: test: refresh Rock + BlockNumber fixtures to current generator output

**Original commit:** 3e2ecb8 — `test: refresh Rock + BlockNumber fixtures to current generator output`
**Author:** E.FU
**Files touched:** 2
**LOC:** ±448
**PR:** none (direct push to `development`, per onchain-workspace convention — completed harness runs ff-merge directly; not flagged)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 7 | spec-gap (Cat 6) | test/support/cartouche/contract/rock.ex:71 | `decode_stumble_error/1` regenerated with `@spec :: []`, but it decodes `Stumble(uint256)` → `[non_neg_integer()]` | Applied: root-caused to generator; fixed generator + regenerated (alt: hand-edit fixture only — rejected, would re-drift on next regen) |
| 2 | — | observation | (commit-level) | Cosmetic doc/spec enrichment refresh; tension with CLAUDE.md "don't churn passing fixtures for doc richness" | Noted only — already committed; no action |

## Auto-applied fixes

- **lib/mix/cartouche.gen.ex** `build_decode_error_fn/1`: keyed the error-decoder return spec off `input_types` instead of `return_types`. Solidity errors carry *inputs*, never returns, so `selector.returns` was `nil` → `normalize_return_types(nil) → []` → every generated error decoder got `:: []`. Now mirrors `build_decode_call_fn/1` (both decode input params). This is the root cause of finding #1.
- **test/support/cartouche/contract/rock.ex:71**: `@spec decode_stumble_error(binary()) :: [non_neg_integer()]` (regenerated; verified the *only* diff vs committed is this single line).
- **test/mix/cartouche_gen_test.exs**: added a regression assertion that `decode_bad_thing_error/1` (the existing `BadThing(uint256)` error fixture in the suite) emits `:: [non_neg_integer()]` — no prior test checked error-decoder specs, which is why the bug shipped.

## Discuss-tier resolutions

- (none)

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: — (Codex independently surfaced finding #1, rated 7; Claude confirmed in-session)
Codex-only findings (verified): finding #1 — verified by reading `build_decode_error_fn` vs `build_decode_call_fn`, confirming `selector.returns` is nil for errors, and regenerating to observe the exact one-line correction.
Codex-only findings (discarded as over-flag): —

## Notes

- `dialyzer` tolerated the wrong `:: []` (it is a valid subtype of `ABI.decode`'s `[any()] | map() | {:error,_}` success typing), which is why `mix ci` stayed green — the defect was a *spec-accuracy* gap (misleading to consumers and to Descripex `api()` introspection), not a gate break. The fix is likewise dialyzer-clean (verified `MIX_ENV=test mix dialyzer` → 0 warnings).
- Blast radius confirmed minimal: `rock.ex` is the only committed generated file with an error decoder carrying params (i_console/sleuth/block_number have none).
