---
sha: b3b294b25e4ab8014682f85c79546fa1c8541095
short_sha: b3b294b
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Poll fee-token balanceOf for funding confirmation; v0.6.0

**Original commit:** b3b294b — `Poll fee-token balanceOf for funding confirmation; v0.6.0`
**Author:** E.FU
**Files touched:** 9
**LOC:** ±197
**Source PR:** none — direct push to `main` (documented onchain workflow: routine work ff-merges directly, no PR). Not flagged.

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 3   | doc-gap  | CHANGELOG.md:13 | `:fee_token` listed as option on `fund_address/2`, but only `fresh_funded_wallet/1` reads it | applied (also flagged by codex) |

## Auto-applied fixes

- CHANGELOG.md:13 — scoped the `:fee_token` option to `fresh_funded_wallet/1` only. `fund_address/2` (faucet.ex:73-81) calls only `tempo_fundAddress` and passes opts to `rpc_request`, which reads only `:req_options`; `:fee_token` is consumed exclusively in `wait_for_funding/2`'s poll path, reachable only via `fresh_funded_wallet/1`. The moduledoc (faucet.ex:34-43) was already correct; only the CHANGELOG over-attributed.

## Discuss-tier resolutions

- (none)

## Verified clean (no fix needed)

- **`balance_of_selector/0` = `0x70a08231`** — correct keccak256-4 selector for `balanceOf(address)` (cross-checked by Codex against 4byte.directory; canonical ERC-20 selector).
- **`balance_of_calldata/1`** — `selector <> <<0::96, owner::binary-size(20)>>` correctly left-pads the 20-byte address to a 32-byte ABI word (12 zero bytes + 20 address bytes). Covered by tip20_test.exs assertion on selector/padding/address.
- **eth_call params** — `[%{to: fee_token, data: data_hex}, "latest"]` is correct JSON-RPC `eth_call` form; atom keys serialize to `"to"`/`"data"` strings via Jason.
- **Option handling** — no option leak. `rpc_request/4` reads only `:req_options`; residual keys (`:settle_ms`, `:poll_interval_ms`) in `rpc_opts` are inert.
- **Funding confirmation** — `balance > 0` correctly gates on the fee-token (pathUSD) balance, decoupling confirmation from gas-vs-pathUSD landing order. Malformed/negative/non-string eth_call results error loudly (parse_balance_hex), covered by three faucet tests.
- **Docs/version** — CHANGELOG v0.6.0 added, mix.exs bumped 0.5.0→0.6.0, both new public functions carry `@doc` + `@spec`, moduledoc Options section lists `:fee_token`.

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: 1 (Codex-only, verified in-session against the code — real doc gap)
Codex-only findings (verified): 1
Codex-only findings (discarded as over-flag): —
Note: Codex's `mix` verification commands failed in its sandbox (Hex load / Mix PubSub socket `:eperm`); it completed the audit via code-read + 4byte.directory reference. Selector confirmed correct.
