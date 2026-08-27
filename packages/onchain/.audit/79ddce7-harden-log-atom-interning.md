---
sha: 79ddce766720701648b08ab907b4c28f072b98b6
short_sha: 79ddce7
audited_at: 2026-06-24
auditor_model: claude-opus-4-8
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: security: harden Onchain.Log.decode_event/2 atom-interning trust boundary

**Original commit:** 79ddce7 — `security: harden Onchain.Log.decode_event/2 atom-interning trust boundary`
**Author:** E.FU
**Files touched:** 5 lib (log.ex, transfer.ex, ens.ex, fees.ex, erc7730/binding.ex) + tests + CHANGELOG
**LOC:** ±168

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 5 | bug/compat | lib/onchain/log.ex:55 (@atom_segment) | Guard rejected valid Solidity `$` identifiers (`Evt(uint256 $amount)` → invalid_signature) | Applied — regex now allows `$` (codex) |
| 2 | 4 | doc-gap | lib/onchain/log.ex (decode_event!/2) | Bang variant's public docs omit the trust-boundary warning decode_event/2 carries | Applied — added warning (codex) |
| 3 | 8 | security | lib/onchain/log.ex (build_param) | Bounded-but-valid names still mint atoms across repeated calls | Dropped — documented deliberate residual, rationale below (codex) |
| 4 | 3 | tooling | lib/onchain/log.ex (sobelow) | `mix sobelow` reports DOS.StringToAtom despite the skip comment | Dropped — false positive, rationale below (codex) |

## Auto-applied fixes

- **log.ex (Finding 1):** `@atom_segment` `^[a-zA-Z_][a-zA-Z0-9_\[\]]*$` →
  `^[a-zA-Z_$][a-zA-Z0-9_$\[\]]*$`. `$` is valid in the Solidity identifier grammar
  (https://docs.soliditylang.org/en/latest/grammar.html), so a developer-authored
  signature using it must not be falsely rejected. Still bounded by the existing
  32-param + 64-byte caps — no new atom-spray surface. Regression test added.
- **log.ex (Finding 2):** `decode_event!/2` `api(...)` signature param now carries the
  same "MUST be developer-controlled / atom-table DoS vector" warning as `decode_event/2`
  (it delegates to the same interning path).

## Dropped findings (verified, not applied)

- **Finding 3 (cross-call atom minting, pri 8) — dropped: already a documented,
  deliberate residual.** The commit's own moduledoc "Security" section states the bound
  "mitigates but does not structurally eliminate the vector … does not stop an attacker
  looping distinct valid names across many calls. The only structural fix is string keys,
  a breaking change deliberately not taken." Codex re-flagged exactly this documented
  limitation. The trust contract (signature MUST be developer-controlled) is the accepted
  mitigation; the structural fix (string-keyed output) is a breaking change correctly
  deferred. No new action — already the explicit design decision recorded in-code.
- **Finding 4 (sobelow DOS.StringToAtom, pri 3) — dropped: false positive (wrong
  invocation).** Codex ran `mix sobelow` (no `--skip`), which always prints
  documented-skipped findings (expected, per host CLAUDE.md). The PostToolUse hook's
  invocation `mix sobelow --skip` reports ZERO findings for log.ex — the site is already
  suppressed. Verified `mix sobelow --skip --format compact` returns empty after editing
  log.ex. No `.sobelow-skips` change needed.

## HIGH-tier second-grader

log.ex `decode_event` is a security-boundary path → HIGH tier. Codex (different family;
Claude implemented) graded the `$`-regex + doc fix: **approve** — widening stays bounded
by the existing param-count/length caps; tests 77/77; credo clean. Local dialyzer 0
warnings, compile --warnings-as-errors clean.

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: — (Claude's first pass rated the hardening solid; Codex surfaced
the `$`/doc gaps and re-raised the documented residual)
Codex-only findings (verified + applied): 1, 2
Codex-only findings (dropped with rationale): 3 (documented deliberate residual), 4 (FP)
