---
sha: b67f5cc
short_sha: b67f5cc
audited_at: 2026-06-05
auditor_model: claude-opus-4-8
verdict: discuss-required
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: defrpc macro — codegen named JSON-RPC wrappers from declarative specs (Task 63)

**Files touched:** lib/onchain/rpc/codegen.ex (new), .doctor.exs (new), mix.exs (+docs) · **LOC:** ±284 (delivery b67f5cc + review a4d9d64)

## Findings — HEADLINE: the macro is dead code

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 7 | doc-gap/bug | rpc/codegen.ex | `defrpc`/`defrpc_bang` have **zero call sites** outside the macro module — all wrappers still hand-written. Acceptance criterion #2 ("Existing 11 wrappers reimplemented through it") UNMET | Filed → **Task 76**; CHANGELOG corrected in this audit commit |
| 2 | 7 | doc-gap | CHANGELOG.md | Claimed wrappers "now expand from declarative specs" — materially false | **Applied** — corrected to state the macro is defined but not yet wired up |
| 3 | 5 | doc-gap | tasks.toml task 63 | `verified = true` is inaccurate for the unmet criterion | Noted in Task 76; original entry left as historical record |

**Verification:** `grep -rn 'defrpc' lib/` → only definitions in codegen.ex; `block_number`, `chain_id`, `syncing`, `get_balance`, `get_transaction_count`, `get_code`, `eth_send_raw_transaction` (+ `!`) are all hand-written `def`s. The `Onchain.RPC.Codegen` module, `nimble_options` dep, and `.doctor.exs` ignore entry exist solely to support an uninvoked macro. The macro itself is well-written (NimbleOptions-validated, three arg shapes) — it was just never integrated. Acceptance criterion #4 even pre-authorizes killing the prototype.

## Codex second-opinion

Status: dual-reviewer. Independently flagged (pri6/7) that defrpc is unused and the CHANGELOG/ROADMAP/`verified` claims are false. Corroboration count = 2 (Claude grep + Codex). This is the strongest finding of the batch.
