---
sha: 74b59ae72d6529ef414a40cdb3cd653a235edfc2
short_sha: 74b59ae
audited_at: 2026-08-24
auditor_model: claude-opus-5
verdict: clean — fast-path
codex_status: not-dispatched
audited_by: audit-review v1
---

# Audit: docs: refresh README and SECURITY.md for the 0.8.0 release

**Reason for fast-path:** 24 LOC, no production-code paths touched.
**Files touched:** README.md, SECURITY.md
**Note:** Checked against reality rather than taken on trust: mix.exs is 0.8.0, hex lists 0.8.0 as current, the envelope list (V1/V_2930/V2/V3/V4) matches lib/cartouche/transaction/, and every module added to the table exists (Filter, Erc20, VM, Sleuth, OpenChain, Solana.Token/TokenProgram/ATA/PDA). SECURITY.md's supported line moved 0.4.x -> 0.8.x, consistent with the pre-1.0 current-line-only policy stated above it.
