---
sha: a8e31cf
short_sha: a8e31cf
audited_at: 2026-06-05
auditor_model: claude-opus-4-8
verdict: clean
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Opt-in retry/backoff wrapper over RPC send (Task 54)

**Files touched:** lib/onchain/rpc.ex, lib/onchain/rpc/helpers.ex (+docs/tests) · **LOC:** ±169 (delivery a8e31cf + review de65249)

## Findings

No correctness defects. Retry is opt-in (`retry: false`/absent → single attempt); retries only transport `{:rpc_error, _}` WITHOUT a JSON-RPC `:code` (node application errors return immediately) — verified. Policy validated (non-neg integers). `Process.sleep` is production backoff (legitimate, not a test sleep), and `sleep_before_retry(0)` skips the delay. Well tested (default, retry-to-success, exhausted, no-retry-on-app-error).

Minor (not applied): backoff is constant, not exponential; Descripex `api()` per-function opt lists don't repeat `:retry` (documented in moduledoc). Both Codex-noted low-pri, no action.

## Codex second-opinion

Status: dual-reviewer. No Category-1 bug. Noted to_rpc_opts coupling + `:retry` not in per-fn api metadata + a stale "Signet.RPC" ROADMAP title reference — all low, left as-is.
