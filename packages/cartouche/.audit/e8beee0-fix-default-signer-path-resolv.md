---
sha: e8beee0f6feb7c7208736529148be74bcdaac99b
short_sha: e8beee0
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: fix: default-signer path resolves nil chain id to the configured chain instead of crashing

**Original commit:** e8beee0 — `fix: default-signer path resolves nil chain id to the configured chain instead of crashing`
**Author:** E.FU
**Files touched:** 4 (CHANGELOG.md, lib/cartouche/signer.ex, test/support/client.ex, test/transaction_test.exs)
**LOC:** ±34
**PR:** none (direct push to `development`, per onchain-workspace convention)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 4 | doc-gap (Cat 6) | lib/cartouche/transaction.ex:1815 | `build_signed_trx/7` `chain_id` option metadata omits the new nil→app-chain default behavior | Applied: extended description |
| 2 | 4 | doc-gap (Cat 6) | lib/cartouche/transaction.ex:1901 | Same gap for `build_signed_trx_v2/9` | Applied (same edit, both occurrences) |

## Auto-applied fixes

- **lib/cartouche/transaction.ex** (both `build_signed_trx*` `api()` blocks): `chain_id` option description now states the `nil` default resolves to the application-configured chain (`config :cartouche, :chain_id`). These are Descripex `api()` metadata read by AI-agent consumers, so the accuracy gap directly tracks the behavior change this commit introduced.

## Discuss-tier resolutions

- (none)

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: — (both findings Codex-surfaced; Claude verified accurate)
Codex-only findings (verified): #1, #2 — verified by reading the option metadata against the new `Chain.chain_id_value/1` routing.
Codex-only findings (discarded as over-flag): —

## Notes

- **No Category 1 bug in the fix.** Verified the nil path is correct: `encode_eip155/3` now routes through `Chain.chain_id_value/1`, whose `nil` clause returns `Cartouche.Application.chain_id/0`, which resolves the configured `:chain_id` atom to an **integer** via `parse_id/1`. So the downstream `chain_id * 2 + 35 + recid` arithmetic in `encode_eip155` receives an integer (5 for `:goerli` in test config), not an atom — no `ArithmeticError`. The change aligns EIP-155 signature `v` with how `V1.new`/`V2.new` already default the unsigned tx's chain id; Codex independently confirmed this alignment.
- The widened specs (`integer() | atom() | nil`) correctly reflect the new accepted input; `MIX_ENV=test mix dialyzer` is clean.
- The two replaced tests previously asserted the *crash* (`catch_exit`); they now assert successful sign + recover. This removes a test that ratified the bug — not a NEVER-HIDE-FAILURES violation (the new tests fail if the fix regresses).
