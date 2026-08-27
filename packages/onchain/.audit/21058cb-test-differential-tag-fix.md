---
sha: 21058cb439bc8933e4b479ff6bf40c621b510beb
short_sha: 21058cb
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: clean — fast-path
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: test: stop differential RPC suite flunking under --only/--include integration

**Reason for fast-path:** 9 LOC, no production-code paths (test module tags + test_helper + CHANGELOG).
**Author:** E.FU
**Files touched:** CHANGELOG.md, test/onchain/differential/rpc_cartouche_test.exs, test/test_helper.exs
