---
sha: a82235d
short_sha: a82235d
audited_at: 2026-06-05
auditor_model: claude-opus-4-8
verdict: discuss-required
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: ERC-7730 clear-signing descriptor parser + binding evaluator (Task 74)

**Files touched:** lib/onchain/erc7730.ex, erc7730/{descriptor,binding,formatter}.ex (new, +docs/tests) · **LOC:** ±2172

## Findings — clear-signing correctness cluster

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 7 | bug | formatter.ex:314 | `from_metadata/2` ignores its `_token` arg → renders a tokenAmount with the descriptor's `metadata.token` symbol even when the field references a DIFFERENT token (e.g. DAI shown as "USDC"). Safety-relevant for clear-signing | Filed → **Task 77** |
| 2 | 6 | bug | binding.ex:167 | `match_domain/2` skips constrained domain keys the payload omits → a descriptor constraining `domain.name` still matches a payload lacking it | Filed → Task 78 |
| 3 | 6 | bug | binding.ex:198 | EIP-712 format-key matched via ABI `FunctionSelector.decode`; `types_from_selector` yields `%{}` for bare type names → type-aware coercion lost; nested `encodeType` keys → :no_format_match | Filed → Task 78 |
| 4 | 4 | bug | binding.ex:184 | Duplicate format keys with same selector silently pick the first | Filed → Task 78 |
| 5 | 4 | bug | descriptor.ex | Codex: parse raises (FunctionClause/BadMap/Protocol.Undefined) on `"format":1`, `"excluded":"#.x"`, `"params":"bad"`; loads {:ok} on `"deployments":[]` | Filed → Task 78 (verify each) |

**Verification:** Claude read formatter.ex + binding.ex and confirmed findings 1–3 against source (the `_token` is genuinely unused; the `not is_nil(actual_value)` guard genuinely skips missing keys; format-key parsing genuinely reuses ABI selector decode). Findings 4–5 are Codex-flagged and tracked for source verification in Task 78. Given this is a freshly-landed clear-signing/security module, the fixes need careful design + tests — filed as follow-ups rather than risk spot-patches in the audit commit.

## Codex second-opinion

Status: dual-reviewer. Surfaced the full cluster (pri9–3) incl. the wrong-token render and EIP-712/encodeType handling. Refs: EIP-7730. High-value pass — multiple real correctness gaps a single reviewer's confidence filter under-flagged.
