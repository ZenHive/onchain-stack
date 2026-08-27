---
sha: 1901f4051a79509fb9b3e338ca0f484753ba6f21
short_sha: 1901f40
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Add pre-broadcast tx simulation; v0.7.0

**Original commit:** 1901f40 — `Add pre-broadcast tx simulation; v0.7.0`
**Author:** E.FU
**Files touched:** 9 (lib/onchain/tempo/rpc.ex, lib/onchain/tempo/transaction.ex, mix.exs, CHANGELOG.md, CLAUDE.md, AGENTS.md, 3 test files)
**LOC:** +1369 / −32
**Source PR:** none resolved (direct push to default branch) — Cat 6 priority-4 note below

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 5 | doc-gap | README.md:15 | Install pin `~> 0.5` while releasing 0.7.0 | applied: → `~> 0.7` (codex) |
| 2 | 4 | doc-gap | README.md:29 | Module table omits new `simulate/3` | applied: noted eth_simulateV1 (codex) |
| 3 | 4 | doc-gap | lib/onchain/tempo/transaction.ex:301,266 | `@doc`/comment say `tempo_simulateV1`; code uses `eth_simulateV1` | applied: → `eth_simulateV1` (codex) |
| 4 | 4 | process | (whole commit) | Direct-push, no PR review trail recorded | noted only |

## Auto-applied fixes

- README.md:15 — dep pin `~> 0.5` → `~> 0.7` (matched to released version)
- README.md:29 — RPC module row now mentions `pre-broadcast eth_simulateV1`
- lib/onchain/tempo/transaction.ex:301 — `simulate_request/1` `@doc` corrected `tempo_simulateV1` → `eth_simulateV1` (the method the implementation actually calls; commit body documents that `tempo_simulateV1` is not deployed)
- lib/onchain/tempo/transaction.ex:266 — field-index comment corrected likewise

## Discuss-tier resolutions

- (none)

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: — (Claude-side audit found no Cat 1-5 issues; Codex found no Cat 1 bug)
Codex-only findings (verified + applied): 1, 2, 3 — all confirmed against the live files before applying
Codex-only findings (discarded as over-flag): —

### Correctness review (no findings — both reasoners)

- **`eth_simulateV1` params `[payload]` without block tag** — NOT a bug. Codex confirmed against geth's `ns-eth` docs + `internal/ethapi/api.go`: `blockNrOrHash` is optional and defaults to latest. Independently confirmed live: the Moderato integration test (`moderato_test.exs`) calls `simulate/3` against the real node and `flunk()`s if `eth_simulateV1` is unimplemented — it passes, so the wire format is ground-truth-verified.
- **`sender/1` placeholder reset** — verified the reset (`fee_token`→`<<>>`, `fee_payer_signature`→`<<0x00>>`, only when fee-payer sig is the decoded list, i.e. co-signed) reproduces exactly the client signing preimage in `cosign_fee_payer` (base fields with both placeholders). Field indices 10/11 are stable across the key-auth-present (15-field) and key-auth-absent (14-field) forms.
- **`classify_simulate_error` range guard** `code <= -38_000 and code > -39_000` correctly matches the closed range [-38999, -38000] (the eth_simulateV1 execution-error band), reporting those as `{:ok, {:revert, _}}` so a fail-open caller cannot leak the DoS.
- **Tail-call fold** — `parse_call/1` guarantees `to`/`input` are binaries and `value` an integer, so the `to_hex_data`/`to_hex_quantity` encoders cannot crash on nil. Fold direction (LAST call → top-level `to`/`value`/`input`) matches the documented intent (avoid empty-`to` CREATE).
- **Tests** — thorough unit coverage of every `simulate/3` branch (success, revert-on-status-0x0, -38013 execution error, returnData fallback, -32601 unsupported, transport error, no-results, malformed result) plus 2 live integration tests. No hidden-failure (`assert true`) patterns; integration tests `flunk` loudly rather than skip.

Verification gap (recorded, not blocking): Codex could not run `mix test.json` (local Hex/SCM resolution failed in its sandbox) and could not locate the mpp-rs `build_simulate_payload` source to cross-check fold direction beyond the commit's own tests/docs.
