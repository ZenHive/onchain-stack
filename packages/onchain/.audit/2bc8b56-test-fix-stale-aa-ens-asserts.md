---
sha: 2bc8b56ca82202a5495903671e6e8161a0559de9
short_sha: 2bc8b56
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: clean — fast-path
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: test: fix stale AA/ENS integration assertions; note sepolia_send --no-retry

**Reason for fast-path:** 21 LOC, no production-code paths (integration tests + CHANGELOG).
**Author:** E.FU
**Files touched:** CHANGELOG.md, test/onchain/aa_integration_test.exs, test/onchain/ens_integration_test.exs, test/onchain/signer_integration_test.exs
