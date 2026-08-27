---
sha: bff9a7b
short_sha: bff9a7b
audited_at: 2026-06-05
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: Telemetry events around Onchain.RPC request path (Task 52)

**Files touched:** lib/onchain/rpc.ex, mix.exs · **LOC:** ±121 (delivery bff9a7b + dep-fix 8701bb9)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 5 | doc-gap | CHANGELOG.md | No [Unreleased] entry for the telemetry feature | **Applied** — added "Added — telemetry on the RPC request path (Task 52)" |
| 2 | 4 | doc-gap | rpc.ex @moduledoc | Telemetry event name/metadata undocumented for consumers | **Applied** — added "## Telemetry" moduledoc section |

Implementation is clean: `:telemetry.span/3` wraps `do_rpc/3` (local override of Helpers.do_rpc via `import … except`); stop metadata distinguishes :ok/:error. `:telemetry ~> 1.4` added as a direct dep (8701bb9) so dialyzer resolves span/3. No logic defect.

## Codex second-opinion

Status: dual-reviewer. Corroborated both doc gaps (CHANGELOG entry missing, moduledoc lacks event contract). No Category-1 bug; no byte-encoding path touched.
