---
sha: ee89999227890b284573647435c759c7fc4cc03a
short_sha: ee89999
audited_at: 2026-08-23
auditor_model: claude-opus-5
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: rpc: recover sendTransaction signer and drop unused live helper

**Original commit:** ee89999 — `rpc: recover sendTransaction signer and drop unused live helper`
**Files touched:** 3 (lib/cartouche/rpc.ex, test/rpc_dev_node_test.exs, test/support/live.ex)
**LOC:** ±45

**Scope note.** This commit is the follow-up fix to `e0e240e` and completes the
same delivery (roadmap tasks 121 + 124). Both were audited as one net state;
the full finding table, applied fixes, verification evidence, declined
findings and the HIGH-tier second-grader pass live in
`.audit/e0e240e-harness-agent-delivery-task-1.md`. Nothing in this commit was
audited in isolation, and nothing was skipped.

## Findings

Its own contribution — that the `eth_sendTransaction` test recovers the signing
account from the broadcast transaction rather than only asserting a 32-byte
hash — was verified against a live anvil and holds: `recover_signer!/2` routes
V1 through `V1.recover_signer/2` with the node's chain id and V2 through
`V2.recover_signer/1`, and `flunk/1`s on any other envelope. The dropped live
helper has no remaining callers (`grep` over `test/`).

No findings specific to this commit. See the referenced report.

## Codex second-opinion

Status: dual-reviewer (net-state dispatch shared with e0e240e)
