---
sha: 3a1c24b8c144b72e62a086dfacbb9060c905b593
short_sha: 3a1c24b
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Estimate Builder gas per-tx via eth_estimateGas instead of static default

**Original commit:** 3a1c24b — `Estimate Builder gas per-tx via eth_estimateGas instead of static default`
**Author:** E.FU
**Files touched:** 7 (lib/onchain/tempo/transaction/builder.ex, CHANGELOG.md, ROADMAP.md, mix.exs, roadmap/{data.json,tasks.toml}, 2 test files)
**LOC:** ±422

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 5   | doc-gap  | README.md:15 | Install snippet `~> 0.2` vs released 0.4.0/0.5.0 | applied: `~> 0.5` (codex) |
| 2 | 5   | doc-gap  | SECURITY.md:13 | Supported-versions table `0.3.x` stale for imminent 0.5.0 publish | applied: `0.5.x` / `< 0.5` |
| 3 | 4   | bug      | builder.ex (4 with-chains) | Explicit `:gas_limit` now validated *after* the nonce RPC (was before) | documented, not applied (codex) |

## Auto-applied fixes

- README.md:15 — `{:onchain_tempo, "~> 0.2"}` → `"~> 0.5"` (matches the version being published).
- SECURITY.md:13-14 — supported-versions table `0.3.x`/`< 0.3` → `0.5.x`/`< 0.5` (the maintainer is publishing 0.5.0; the pre-1.0 "current release line only" policy now points at 0.5.x).

## Not-applied finding (rationale)

- **#3 — gas-limit validation ordering (builder.ex, codex pri 4).** Verified real: `:gas_limit`
  validation moved from an early `optional_opt` into `resolve_gas_limit` at the *end* of each
  `with` chain (after `resolve_nonce`'s RPC). So a malformed explicit `gas_limit` + unreachable
  node + omitted `:nonce` surfaces the nonce RPC error instead of the gas-limit validation error.
  **Not applied:** this is HIGH-tier signing/money-path code (a fix needs a second-grader dispatch
  per the Step 9 ladder), and the impact is error-*specificity* only in a rare three-way
  conjunction — the caller still gets an error, never a wrong/unsigned tx, and the normal
  reachable-node path validates `gas_limit` correctly. Reordering validation across four signing
  functions to sharpen one rare error message is net-negative risk on a critical path. Recorded for
  the maintainer; trivially addressable later by hoisting explicit-gas validation if desired.

## Verified correct (no action)

- `eth_estimateGas` param encoding: `value: :binary.decode_unsigned(value)` passes an **integer**;
  `Onchain.RPC.eth_estimate_gas/2` hex-encodes it via `put_estimate_quantity` → `Onchain.Hex.from_integer`.
  Correct contract (confirmed in deps/onchain/lib/onchain/rpc.ex). Not a bug.
- `apply_headroom`: `div(gas * 5 + 3, 4)` = correct integer ceil of 1.25×.
- `validate_calls` runs before `estimate_gas` destructures `[to, value, input]` in both multicall builders.
- Per-call estimate summation over-counts the shared intrinsic base (safe over-estimate), documented in-code.
- Error propagation: failed estimate → `{:error, _}`, no silent fallback. CHANGELOG + ROADMAP (Task 10 → ✅) correct.

## Discuss-tier resolutions

- (none — no discuss-design rows)

## Codex second-opinion

Status: dual-reviewer (job task-mqs13j13-dpi9rx, 3m23s)
Corroborated findings (≥2 reasoners): —
Codex-only findings (verified + applied): 1 (README drift)
Codex-only findings (verified, not applied): 3 (gas-limit ordering — HIGH-tier, pri-4 message specificity)
Claude-only findings (applied): 2 (SECURITY.md, restored after maintainer confirmed 0.5.0 publish)
Codex-only findings (discarded as over-flag): —
Note: Codex's mix-task runs failed in its sandbox ("corrupt atom table" / TCP :eperm); its findings were re-verified locally before action.
