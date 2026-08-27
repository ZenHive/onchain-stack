---
sha: 22ece277e16a4bd3b142309bf8e52e030461898e
short_sha: 22ece27
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: deps: migrate HTTP transport off cartouche's removed Finch seams to Req (cartouche 0.5.0; Task 83)

**Original commit:** 22ece27 — `deps: migrate HTTP transport off cartouche's removed Finch seams to Req (cartouche 0.5.0; Task 83)`
**Author:** E.FU
**Files touched:** 17 (lib: http.ex new, rpc.ex, ens.ex, mev.ex, rpc/helpers.ex; 6 test files; docs + roadmap)
**LOC:** ±368

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 6   | bug | lib/onchain/rpc/helpers.ex:178 | `to_rpc_opts/1` whitelist drops `:req_options`; per-call transport override silently ignored on batch + single-call paths | Applied: added `:req_options` to `Keyword.take`; + regression test |
| 2 | 2   | doc-gap (cosmetic) | CHANGELOG.md (v0.10.0) | "both rewritten paths use `method: :post`" — ENS CCIP gateway can be GET | Dropped (cosmetic, Codex-only): clause is accurate for the batch path + the common POST gateway; `gateway_http/4` takes method as a param |

## Auto-applied fixes

- **lib/onchain/rpc/helpers.ex:178** — added `:req_options` to the `to_rpc_opts/1`
  `Keyword.take` whitelist. The new `Onchain.HTTP.req_options/3` `@doc` advertises
  `call_opts[:req_options]` as the highest-precedence (level 4) transport override,
  and `Cartouche.RPC.send_rpc/3` documents the same for the single-call path — but
  every onchain RPC call (single-call **and** `batch/2`) routes opts through
  `to_rpc_opts/1`, which whitelisted only `[:rpc_url, :timeout, :errors, :retry]`
  and silently stripped `:req_options` before it could reach
  `Onchain.HTTP.req_options/3` (batch) or `Cartouche.RPC.send_rpc/3` (single-call).
  The fix threads it through both paths, matching documented intent. Tests passed
  before the fix because they inject the stub plug via the **app-config** seam
  (`config :onchain, Onchain.RPC` / `config :cartouche, Cartouche.RPC`), which is
  level 2 and unaffected — the per-call seam was untested, which is why the gap
  shipped.
- **test/onchain/rpc_batch_test.exs** — added regression test
  "honors a per-call :req_options transport override": deletes the app-config plug
  and injects the stub solely via per-call `req_options: [plug: ...]`. Fails without
  the fix (Codex empirically observed `:econnrefused`).

## Discuss-tier resolutions

- (none)

## Codex second-opinion

Status: dual-reviewer (jobId task-mqs05kjm-4co04f, 4m 18s)
Codex independently verified its own findings (`mix test.json`, `mix dialyzer.json`,
`mix credo --strict`, `mix run -e` repro of the batch req_options drop).
Corroborated/applied findings: 1 (Codex-found; Claude verified against
`to_rpc_opts/1` + cartouche `send_rpc/3` + `Onchain.HTTP.req_options/3` source).
Codex-only findings (discarded as over-flag / cosmetic): 2 (CHANGELOG `:post` nit).

## Stake-gated fix verification

Finding 1 fix classified MEDIUM (core RPC options-threading, not
security/crypto/signing/evaluator code). Grader: mechanical stack
(43/43 affected RPC tests green; PostToolUse credo + dialyzer on touched files) +
audit-session "would I approve in code-review?" re-read — approved (minimal,
contract-aligned, regression-covered, no new public surface).
