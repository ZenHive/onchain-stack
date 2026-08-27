---
sha: a1ae1367950a8eb1d9ee0b43ae899634444b3f29
short_sha: a1ae136
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: clean
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: docs: unlink hidden modules from ENS/RPC moduledocs for clean hexdocs

**Original commit:** a1ae136 — `docs: unlink hidden modules from ENS/RPC moduledocs for clean hexdocs`
**Author:** E.FU
**Files touched:** 2 (lib/onchain/ens.ex, lib/onchain/rpc.ex)
**LOC:** ±4

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| — | — | — | — | No findings | — |

## Notes

Touches `lib/` so the tiny-commit fast-path did not apply, but the change is
purely documentation: it replaces backtick module references to `@moduledoc false`
modules (`Onchain.ENS.Normalize`, `Onchain.RPC.Helpers.maybe_put_revert_data_hex/1`)
with prose, so ExDoc stops emitting broken cross-reference links for hidden modules.
No code, control flow, or public surface changed. Correct hexdocs-hygiene practice.

## Codex second-opinion

Status: not-dispatched — doc-only diff (4 lines, no runtime code). Per the
token-economy rationale a Codex dispatch on a moduledoc-prose edit costs more than
the diff and finds nothing; single-reviewer (Claude) pass.
