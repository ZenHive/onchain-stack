---
sha: e0e240e146f17f12bb5aa2ffe6b26974e250406d
short_sha: e0e240e
audited_at: 2026-08-23
auditor_model: claude-opus-5
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: harness: agent delivery — tasks 121 + 124 (coalesced)

**Original commit:** e0e240e — `harness: agent delivery — task 121 Coalesced tasks: …`
**Files touched:** 10
**LOC:** ±1468

**Scope note.** `ee89999` is this commit's follow-up fix and lands the same
delivery. Both were audited as one net state (`git diff acd9ded..HEAD -- lib/
test/ mix.exs`); auditing `e0e240e` alone would have surfaced findings that
`ee89999` had already resolved. `.audit/ee89999-*.md` carries the same finding
set by reference.

**PR context:** none. This repo lands harness runs by ff-merge to `main` with no
PR (per `onchain-workspace.md` § Branch & Workflow Conventions), so there is no
bot-review trail and the third-reasoner bot lane is structurally absent. Not
filed as a direct-push finding — it is the documented workflow, not a lapse.

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 8 | bug | lib/cartouche/rpc.ex:2763 | V2 sign/send/fill drop `accessList`, `type`, `chainId` | applied + live regression test |
| 2 | 8 | bug | lib/cartouche/filter.ex:234 | `terminate/2` uninstall inherits 30 s timeout, exceeds 5 s shutdown budget | applied + socket regression test |
| 3 | 7 | doc-gap | lib/cartouche/rpc.ex:14 | `eth_sign` documented as signing a digest; spec says EIP-191 over a message | applied |
| 4 | 6 | test-gap | test/filter_test.exs:498 | Live filter assertions vacuous on an empty list | applied |
| 5 | 5 | doc-gap | CLAUDE.md:53 | `precommit.full` listing missed `--exclude dev_node` | applied (+ AGENTS.md regen) |
| 6 | 4 | doc-gap | lib/cartouche/filter/log.ex:2 | `@moduledoc false` on the public return type of `RPC.get_filter_logs/2` | applied |
| 7 | 6 | bug | lib/cartouche/rpc.ex:2705 | `fill_transaction/2` cannot decode a spec-conforming `raw`-less result | error named; gap filed as Task 125 |
| 8 | 3 | doc-gap | test/test_helper.exs:5 | `:dev_node` lane undocumented beside `:debug_namespace` | applied |
| 9 | 3 | extraction | test/support/live.ex:66 | Dev-node timeouts/retries/chain id hardcoded | applied |
| 10 | 3 | doc-gap | lib/cartouche/rpc.ex:2602 | `send_transaction/2` spec tighter than sibling `send_trx/2` | applied |

## Auto-applied fixes

- `lib/cartouche/rpc.ex` — `to_transaction_params/2` for `%V2{}` now sends
  `type`, `chainId` (omitted when nil, never JSON `null`) and `accessList`.
  New `encode_access_list/1` emits the `AccessListEntry` shape with **lowercase**
  `address` / `hash32` values (`Hex.encode_hex/1`, not the module's usual
  uppercase `encode_big_hex/1`), and `encode_quantity/1` emits a conformant
  `uint`. `to_call_params/2` is untouched, so `eth_call` / `eth_estimateGas`
  are unaffected.
- `lib/cartouche/filter.ex` — `@uninstall_timeout 2_000` applied via
  `Keyword.put_new/3` in `uninstall_filter/1`; a caller's own `:timeout` wins.
- `lib/cartouche/rpc.ex` — `eth_sign` moduledoc, `api/3` metadata, `@doc` and
  parameter renamed `digest` → `message`; the historical-danger note now says
  early implementations signed bytes verbatim rather than implying current
  nodes do.
- `lib/cartouche/rpc.ex` — `decode_filled_transaction/1` and
  `decode_signed_transaction/1` raise named `ArgumentError`s;
  `send_transaction/2` spec `{:ok, <<_::256>>}` → `{:ok, binary()}`.
- `lib/cartouche/filter/log.ex` — real moduledoc.
- `test/filter_test.exs` — new `StallingUninstallServer` (raw `:gen_tcp`;
  `Req.Test` plugs run in-process so `receive_timeout` is inert against them)
  proving the uninstall gives up inside the shutdown budget. Integration tests
  rewritten: the log filter now pins WETH9 at mainnet block 18 000 000 so
  `get_filter_logs/2` is deterministically non-empty; the block filter polls up
  to 60 s and fails if the node is not following the chain; the pending filter
  states in its name that payload shape is only asserted when the node shares
  its mempool.
- `test/rpc_dev_node_test.exs` — new live test asserting a V2 access list and
  envelope type survive `eth_signTransaction`.
- `test/support/live.ex`, `test/test_helper.exs`, `CLAUDE.md`, `AGENTS.md`,
  `CHANGELOG.md` — as listed above.

## Verification

- `mix check.dispatch` exit 0 — 1266 offline tests pass, credo/format clean.
- `mix test.json --only dev_node` — 8/8 pass against a locally booted anvil.
- Negative check on finding 1: with the `accessList` line removed the new live
  test fails `left: []` vs the supplied list — the node was signing an envelope
  the caller never built. The fix is live-verified, not merely plausible.

## Discuss-tier resolutions

- **Codex `discuss` — the three expiry test clients duplicate one state
  machine.** Declined. Explicit per-kind fixtures are the readable form for
  wire-shape stubs, and `ex_dna --max-clones 0` (in the gate) already passes on
  them, so this is preference, not duplication debt.
- **Codex pri 5 — `sign/3` and `send_transaction/2` omit bare `:invalid_hex`
  from their specs.** Declined as scoped. `send_rpc/3` can return the bare atom
  and *every* `decode: :hex` wrapper in this module omits it, including the
  pre-existing `send_trx/2`. Correcting one pair would misrepresent it as
  specific to this diff; it is a repo-wide spec question. The tighter
  `<<_::256>>` half **was** applied, since that one was inconsistent with its
  own sibling.
- **Codex pri 3 — the `new_pending_transaction_filter/1` doctest returns
  `"0xpend1ng"`, not valid hex.** Declined. It is an opaque mock filter id
  echoed back verbatim, never decoded; renaming it churns four files for no
  behavioural gain.

## Deferred, with a task (finding 7)

`execution-apis` types `FillTransactionResult` as a required, unsigned `tx` and
**no** `raw`; geth's `{raw, tx}` pair — the only shape cartouche decodes — is a
geth extension. Against a conforming node `fill_transaction/2` therefore fails,
before and after this audit. It is not fixable here: a filled transaction has no
`v`/`r`/`s`, every envelope's `from_json/1` requires them, and widening that
shared decoder would push the non-nilable-signature-field inconsistency into the
`eth_getBlockBy*` path. Choosing an unsigned-envelope representation changes a
public method's contract, so it is **Task 125**, and only the error message was
sharpened here. Task 124's criterion is met for the geth shape (proven by the
unit test) and silent about the conforming one — incomplete rather than wrong,
so tasks 121 and 124 were left `done` untouched.

## Second-grader pass (HIGH tier — signing-path change)

Finding 1 touches money/authorization-shaped code, so it went to a
cross-family grader (Codex) per the stake-gated ladder. It took three rounds.

1. **Reject** — `Hex.encode_big_hex/1` emits uppercase, violating the
   lowercase-only `address` / `hash32` / `uint` patterns in
   `execution-apis` base-types; and `chainId: nil` serialized to a JSON `null`
   against an optional-but-non-null field. Both real. Corrected: the new fields
   encode through `Hex.encode_hex/1` and a new `encode_quantity/1`, and
   `put_chain_id/2` omits the key rather than nulling it. The grader also
   surfaced the `FillTransactionResult` gap (finding 7), which was confirmed
   against the spec and scoped out.
2. **Reject** — the two new helpers had been defined *between* the `%V2{}` and
   `%Call{}` clauses of `to_transaction_params/2`, splitting the clause group
   and emitting a compiler warning. Correct, and a genuine miss: the earlier
   green `mix check.dispatch` predated those helpers. Both moved below the
   final clause; the gate now exits 0 with no warnings.
3. Final pass on the corrected diff.

The rejections are recorded because they are the evidence that the ladder did
its job: the audit session was implementer and grader of its own fix, and two
defects it had not seen were caught before the work landed.

## Codex second-opinion

Status: dual-reviewer
Corroborated findings: 2, 3 (Claude + Codex)
Codex-only findings (verified, applied): 1, 4, 9
Codex-only findings (verified, declined with rationale): 3 above
Claude-only findings: 5, 6, 8
