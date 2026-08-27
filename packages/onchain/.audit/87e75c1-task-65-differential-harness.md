---
sha: 87e75c1
short_sha: 87e75c1
audited_at: 2026-06-05
auditor_model: claude-opus-4-8
verdict: clean
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: Differential test harness: Onchain.RPC vs reference impl (Task 65)

**Files touched:** test/onchain/differential/* (+docs) · **LOC:** ±474 · **0 lib/ paths**

Test-only delivery (15 `@tag :differential` cases comparing Onchain.RPC against Cartouche.RPC.send_rpc/3 on the same node; env-gated by ONCHAIN_DIFFERENTIAL_TESTS + ETHEREUM_API_URL). No production code; Codex not dispatched (no runtime surface). Claude review: oracle/assertion design is sound, proof window capped to latest block (nodes cap proof history). Clean.
