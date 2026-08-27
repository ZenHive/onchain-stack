---
sha: ba785a4b45d4885d86c98e8875692014ae22cbfb
short_sha: ba785a4
audited_at: 2026-05-15
auditor_model: claude-opus-4-7
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Replace Faucet fixed-sleep settle with eth_getBalance poll loop (#1)

**Original commit:** ba785a4 — `Replace Faucet fixed-sleep settle with eth_getBalance poll loop (#1)`
**Author:** E.FU
**Files touched:** 6 (lib/onchain/tempo/faucet.ex, test/onchain/tempo/faucet_test.exs, CHANGELOG.md, ROADMAP.md, roadmap/tasks.toml, roadmap/data.json)
**LOC:** +205/-23

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 7 | bug | lib/onchain/tempo/faucet.ex:147 | `Process.sleep(interval_ms)` can overshoot the deadline by almost a full interval when `poll_interval_ms` > remaining budget | applied — cap sleep to `min(interval_ms, deadline - now)`, floor 1 ms |
| 2 | 5 | test-gap | test/onchain/tempo/faucet_test.exs | Malformed-balance error branches (`parse_balance_hex/1` fall-through, non-string response, `"0x-1"`) untested | applied — added 3 new test cases |
| 3 | 4 | bug | lib/onchain/tempo/faucet.ex:154 | `"0x-1"` parses to `{:ok, -1}`, violating `non_neg_integer()` spec; loops silently until timeout instead of erroring loudly | applied — added `n >= 0` guard in success branch |
| 4 | 4 | doc-gap | README.md:84 | README example comment still said "waits for settlement", out of sync with new poll-based behavior | applied — aligned with moduledoc wording |
| 5 | 3 | doc-gap | roadmap/tasks.toml task 6 | `done_at` field missing — repo convention sets it on every completed task. Universal rmap auto-fill gap; filed as rmap task 20 | applied — set `done_at = "2026-05-15"`, re-rendered data.json |

## Auto-applied fixes

- `lib/onchain/tempo/faucet.ex` `poll_balance/6` — cap `Process.sleep` to remaining deadline budget; floor at 1 ms so the scheduler still yields when the budget is nearly exhausted.
- `lib/onchain/tempo/faucet.ex` `parse_balance_hex/1` — guard the success branch with `n >= 0` so a negative hex value (protocol violation) reports the malformed-response error path immediately instead of silently looping until timeout.
- `test/onchain/tempo/faucet_test.exs` — added 3 new test cases covering: missing-`0x`-prefix string, non-string response, and `"0x-1"` (negative hex). Each asserts the `"unexpected eth_getBalance result"` error message.
- `README.md` — updated the inline example comment from "waits for settlement before returning" to "polls for confirmation before returning" to match the moduledoc and CHANGELOG entry.
- `roadmap/tasks.toml` — added `done_at = "2026-05-15"` to task 6; re-ran `rmap render` so `data.json` and `ROADMAP.md` reflect the field.

## Discuss-tier resolutions

(none — every finding had a clear actionable fix; no `discuss-design` rows)

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: — (independent reviewer pass; Codex caught the deadline-overshoot bug and the negative-hex spec violation; Claude caught the README drift and the `done_at` gap; both passed on the untested malformed-balance branches)
Codex-only findings (verified): 1 (deadline overshoot), 3 (negative hex), and the test-gap framing of finding 2
Codex-only findings (discarded as over-flag): —

## Notes

- Offline test suite green after fixes: 95 passed / 0 failed / 3 excluded (integration). Doctor 100% doc + spec coverage. Credo strict clean.
- Integration suite against live Moderato confirmed green by the user earlier in the session (88 tests, 11.4 s) before the audit's bug fixes — those fixes preserve all observable success paths and only narrow error semantics, so the integration suite remains expected-green.
- Tier classification per `task-prioritization.md`: faucet is an integration-test helper, not critical-tier (signing/money). Standard ≥80% coverage applies. Post-audit coverage on `Onchain.Tempo.Faucet` is well above floor.
- `shipped_in` deliberately left unset on task 6: the change is under CHANGELOG `[Unreleased]`. Will be filled when v0.3.0 (or equivalent) cuts.
