---
sha: d9c57fccb3e021e8b035532d95300f14ab02dd5a
short_sha: d9c57fc
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: feat: eth_estimateGas RPC helper + auto-estimate gas in send_transaction (Task 82)

**Original commit:** d9c57fc — `feat: eth_estimateGas RPC helper + auto-estimate gas in send_transaction (Task 82)`
**Author:** E.FU
**Files touched:** 2 lib (rpc.ex, signer.ex) + tests + docs
**LOC:** ±770

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 7 | bug | lib/onchain/signer.ex (resolve_gas_limit→estimate_params) | Auto-estimate path crashed on malformed calldata (atom → FunctionClauseError; "0x"-string → spurious garbage-data RPC) before build_transaction/3's validation ran | Applied — extracted `normalize_calldata/1` (codex) |
| 2 | 4 | bug | lib/onchain/signer.ex apply_headroom | `ceil(gas * 1.25)` float math overflows on an absurd node estimate | Applied — integer math `div(gas*5+3,4)` (codex) |
| 3 | 6 | discuss-design | lib/onchain/signer.ex estimate_params | Estimate omits signed fee fields; GASPRICE-dependent estimate could differ from submit | Reversible divergence — kept current behavior, rationale below (codex) |
| 4 | 4 | doc-gap | lib/onchain/signer.ex send_transaction/3 | @doc didn't mention omitted :gas_limit triggers RPC estimation + can error | Applied — updated opts description (codex) |

All four were Codex-only findings (Claude's first pass rated the commit clean);
each verified against the actual code before applying — none were over-flags.

## Auto-applied fixes

- **signer.ex (Finding 1):** new private `normalize_calldata/1` returns the exact
  error tuples `build_transaction/3` always produced (`{:invalid_calldata, _}`,
  `{:hex_calldata, _, msg}`). `build_transaction/3` now delegates to it; `send_transaction/3`
  normalizes calldata up front (before `resolve_gas_limit`) so the estimate path
  receives a guaranteed binary — no crash, no spurious RPC on `"0x"`-strings.
  `calldata_to_hex/1` removed (estimate_params now hex-encodes the normalized binary).
- **signer.ex (Finding 2):** `@gas_estimate_multiplier 1.25` (float) → `@gas_headroom_numerator 5`
  / `@gas_headroom_denominator 4`; `apply_headroom/1` = `div(gas*5 + 3, 4)` = exact
  ceil(gas·1.25) with no float arithmetic.
- **signer.ex (Finding 4):** `send_transaction/3` + `send_transaction!/3` opts docs now
  state auto-estimation + estimate-error propagation.
- **Tests:** two regression tests in `signer_test.exs` — non-binary and `"0x"`-string
  calldata on the no-`:gas_limit` path return the proper error without crashing/RPC.

## Discuss-tier resolutions

- **Finding 3 (fee fields omitted) — reversible divergence, kept current behavior.**
  Claude+Codex split: Codex flagged estimate≠submit; resolution taken is to KEEP
  omitting fee fields. Rationale: passing `maxFeePerGas`/`gasPrice` to `eth_estimateGas`
  can trigger node-side balance checks that *fail* the estimate, a worse failure mode
  than the rare GASPRICE-opcode-dependent estimation divergence it would avoid.
  Documented inline in `estimate_params/4`. Additive/reversible — forwarding fees later
  forecloses nothing. Codex grader confirmed the tradeoff "defensible."

## HIGH-tier second-grader

signer.ex is signing/money code → HIGH tier. Codex (different family; Claude implemented)
graded the final fix diff: **approve** — error-tuple shapes preserved, integer headroom
verified exact, no new credo/test failures (77/77). Local `mix dialyzer.json` 0 warnings,
`mix compile --warnings-as-errors` clean.

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: — (all four Codex-originated; Claude verified each)
Codex-only findings (verified + applied): 1, 2, 4
Codex-only findings (verified, kept-as-is with rationale): 3
Codex-only findings (discarded as over-flag): —
