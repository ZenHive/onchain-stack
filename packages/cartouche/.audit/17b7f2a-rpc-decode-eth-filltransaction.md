---
sha: 17b7f2a4500b47d374eda714c73a1f5eb933c7f9
short_sha: 17b7f2a
audited_at: 2026-08-24
auditor_model: claude-opus-5
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: rpc: decode eth_fillTransaction from the spec `tx` object, not geth's raw

**Original commit:** 17b7f2a — `rpc: decode eth_fillTransaction from the spec `tx` object, not geth's raw`
**Author:** E.FU
**Files touched:** 7
**LOC:** +465 / −74

No source PR — direct commit on `main` (this repo lands harness deliveries and hand-built
work straight to the default branch; no PR review trail exists for the range, and none is
expected here). Categories 1–6 applied by Claude; Codex second opinion dispatched
(`task-mt7abirf-t900eu`, dual-reviewer).

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 7 | bug | lib/cartouche/rpc.ex:2854 | Response `chainId` silently beats a conflicting `chain_id:` option | applied — refuse the conflict (also flagged by codex, rated 10) |
| 2 | 3 | bug | lib/cartouche/rpc.ex:2882 | Unknown chain atom escapes as `KeyError`, reported as a response-decode failure | applied — `parse_option_chain_id/1` funnels it into the option's own refusal |
| 3 | 4 | doc-gap | lib/cartouche/transaction.ex:38 | `@type t` records nothing about `v` carrying the chain id, now a load-bearing non-nilable invariant | applied |
| 4 | 3 | doc-gap | lib/cartouche/transaction.ex:105 | `api(:new)` returns description still says "empty signature slots" | applied |
| 5 | 4 | acceptance | roadmap/tasks.toml (task 126) | Criterion 3 was deliberately overruled but the task records criteria as met | applied — refined via `rmap status 126 done --implemented "..."` |
| 6 | — | discuss | lib/cartouche/rpc.ex:2909 | `quantity/1` accepts non-canonical QUANTITY (`"0x01"`, `"0x00"`, uppercase) | dropped, rationale below (codex-only) |
| 7 | — | discuss | lib/cartouche/transaction.ex:174,320 | Removing the nil guards makes `V1.encode/1` / `get_signature/1` raise on nil fields | dropped, rationale below (codex-only) |

## Finding 1 — the substantive one

`legacy_chain_id/3` was a `cond` in which a well-formed `chainId` in the response won
unconditionally over a caller-supplied `chain_id:`. The commit already refuses every other
disagreement on this path — a malformed `chainId`, chain id `0`, an ambiguous `raw`, a
missing chain id — on the stated grounds that guessing signs a digest the encoded payload
does not match. A well-formed *conflict* was the one case left silent, and it is the same
hazard: `Cartouche.Signer` takes the chain id from its caller, not from the struct, so a
caller passing `chain_id: 42` against a node answering `chainId: "0x1"` gets a `V1` whose
`v` is 1, signs the EIP-155 digest for 42, and recovers to an address that never signed it.
Reproduced by Codex against the live path.

Now a `case` over `{response, option}`: `{nil, nil}` raises missing, `{nil, o}` → option,
`{r, nil}` → response, `{id, id}` → id, `{r, o}` raises `conflicting_chain_id_message/2`.
Three tests added (conflict refused, agreement accepted, unknown atom refused by naming the
option); all three fail on reversion.

**Tier: HIGH** (core signing path). Second-grader dispatched to Codex per the stake-gated
ladder — verdict **approve**: case exhaustive and only returns positive integers, `{id, id}`
reachable and correct, `KeyError` rescue narrowly scoped to `Chain.parse_id/1`, fail-closed
is right on a signing path, new tests genuinely coupled to the fix. RPC 125 / transaction
141 tests, dialyzer 0, credo all green in the grader's own run.

## Auto-applied fixes

- `lib/cartouche/rpc.ex`: `legacy_chain_id/3` refuses a response↔option chain-id conflict; new `conflicting_chain_id_message/2`; `parse_option_chain_id/1` rescues `KeyError` from `Chain.parse_id/1`; `@doc` and `api(:fill_transaction)` opts description state the refusal.
- `lib/cartouche/transaction.ex`: `@type t` comment on `v` recording the chain-id-until-signed invariant; `api(:new)` returns description corrected.
- `test/rpc_test.exs`: three tests (conflict / agreement / unknown chain atom).
- `roadmap/tasks.toml` + rendered `roadmap/data.json`: task 126 `implemented` records the overruled criterion.

## Dropped codex-only findings

- **Non-canonical QUANTITY accepted** (`"0x01"`, `"0x00"`, uppercase hex) — dropped.
  `execution-apis`' `uint` pattern is a constraint on what a node should *emit*; being
  lenient on what cartouche *reads* is deliberate and hazard-free here. Every accepted form
  is unambiguous, and `"0x00"` → `0` is the intended "counts as absent" reading, already
  refused downstream. Rejecting them would break real clients for no safety gain.
- **Nil signature fields now raise** — dropped. `V1.t()` is non-nilable by design as of this
  commit, and every public constructor (`new/7`, `from_json/1`, `decode/1`, the RPC fill
  path) produces integers. A struct with nil `v`/`r`/`s` is out-of-type input, and failing
  loudly on it is the posture the commit deliberately adopted; the previous
  `{:error, "transaction missing signature"}` was the coercion that hid the bug.

## Reviewed clean

- `type` dispatch cannot disagree: `put_unsigned_signature_fields/2`'s `type not in [nil, "0x0"]` guard and `deserialize_rpc_transaction/1`'s dispatch use the same literal set, so an off-spec `"0x00"` raises "unsupported transaction envelope type" on both sides rather than routing a legacy body through the typed branch.
- `assert_unsigned_raw!/1` cannot accept a signed envelope: legacy requires `r: 0, s: 0` with a positive integer `v`; typed requires all three signature fields `nil`, which only the short signing-preimage body decodes to.
- `quantity/1` rejects negatives, floats, bare `"0x"`, and non-hex digits; `decode_result/4`'s catch-all rescue turns every raise on this path into `{:error, _}` rather than a crash.
- CHANGELOG 0.8.0 entry: written before publication (hex 0.8.0 was cut from `fb11b1b`, 2026-08-24 13:34 UTC), so amending the section was legitimate, not a post-release edit.
- ROADMAP: tasks 125 and 126 flipped to `done` in the follow-up commit `96a6aac`.

## Codex second-opinion

Status: dual-reviewer (`task-mt7abirf-t900eu`)
Corroborated findings: 1 (codex-rated 10, claude-rated 7), 5
Codex-only findings (verified, applied): —
Codex-only findings (verified, dropped as over-flag): 2 (non-canonical quantity; nil-field raise)
Claude-only findings: 2, 3, 4
