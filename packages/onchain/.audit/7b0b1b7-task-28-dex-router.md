---
sha: 7b0b1b7
short_sha: 7b0b1b7
audited_at: 2026-06-05
auditor_model: claude-opus-4-8
verdict: clean
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: DEX swap routing — optimal path across pools (Task 28)

**Files touched:** lib/onchain/dex/router.ex (new), lib/onchain.ex (+docs/tests) · **LOC:** ±764 (delivery 7b0b1b7 + review f231c2e)

## Findings

No correctness defects in the routing/quoting math. Verified:
- v2 `amount_out_v2` matches canonical Uniswap getAmountOut; arbitrary-precision integers (no overflow).
- v3 QuoterV2 struct `(address,address,uint256,uint24,uint160)` = (tokenIn,tokenOut,amountIn,fee,sqrtPriceLimitX96) and return `(uint256,uint160,uint32,uint256)` match IQuoterV2; `fee_bps*100` → uint24 tier correct (30bps→3000, 5bps→500).
- Greedy per-hop is globally optimal along a fixed token path (output monotonic in input); all token paths enumerated and max-taken. No-split-routing documented.

Codex low-pri (not actioned): unknown `protocol` / bad `pool.address` crash-or-drop on malformed Pool structs (the `@type` constrains to v2/v3; "let it crash" on contract violation acceptable); name `*100`/`sqrtPriceLimit 0` constants (cosmetic). `verified=false` in tasks.toml honestly records the integration test wasn't run (RPC tunnel down).

## Codex second-opinion

Status: dual-reviewer. Two malformed-Pool robustness notes (pri6/7 — downgraded; contract-violation inputs) + a constant-extraction nit + the README bang-variant claim (handled repo-wide in this audit). No math/wire defect.
