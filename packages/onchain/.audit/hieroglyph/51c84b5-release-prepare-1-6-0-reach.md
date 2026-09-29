---
sha: 51c84b5
short_sha: 51c84b5
audited_at: 2026-08-22
auditor_model: claude-opus-5
verdict: discuss-required
codex_status: unreachable (substitute second reasoner)
audited_by: audit-review v1
---

# Audit: release: prepare 1.6.0 — reach/mix_audit gates, decode_event totality fixes, Elixir 1.18 floor

**Original commit:** 51c84b5
**Author:** E.FU
**Files touched:** 18 (5 under `lib/`)
**LOC:** 433 insertions(+), 67 deletions(-)

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 8 | bug (security) | lib/abi/type_decoder.ex:487-505 | Element-count guard degenerates for one class of element type | **escalated — not fixed** |
| 2 | 8 | bug (totality) | lib/abi/event.ex:303 | Indexed-topic path sits outside every `malformed_data` rescue | **escalated — not fixed** |
| 3 | 7 | bug (data loss) | lib/abi/event.ex:324-348 | Name-keyed result map collapses duplicate parameter names | **escalated — not fixed** |
| 4 | 5 | doc-gap | lib/abi/event.ex:46-48, :62, :244-250 | `@doc`/`@type`/`api()` advertise a closed error set the code deliberately breaks | escalated with #2/#3 |
| 5 | 4 | behaviour | lib/abi/event.ex:366 | Narrowed rescue lets `FunctionClauseError` escape for hand-built selectors | escalated with #2 |
| 6 | 5 | coverage | lib/abi/event.ex | `ABI.Event` at 89.77%, below the project's own 95% critical tier | **applied** |
| 7 | 2 | doc-drift | mix.exs:9-11 | 1.18-floor comment names one `Enum.sum_by/2` site; this commit added another | not applied (cosmetic) |

Findings 1-3 were raised by the second reasoner and **independently reproduced by
this audit** inside the worktree before being recorded. They are real, and they are
present in published 1.6.2 — not introduced by the audit.

## What the commit got right (verified, not assumed)

- The `Enum.reduce`+`Enum.reverse` → `Enum.map_reduce/3` rewrite in
  `decode_type({:tuple, types}, …)` is **exactly order-equivalent**. Old code
  reversed three times (net: types order); new code reverses zero times (net:
  types order). `rest`/`data` threading is unchanged, and the non-dynamic branch
  correctly does not advance `data`. An inversion would be caught immediately by
  the heterogeneous-tuple doctests and by the 1,601-vector corpus.
- `Map.get(item, "name", nil)` → `Map.get(item, "name")` is a no-op: `Map.get/2`
  is defined as `Map.get(map, key, nil)`.
- The Elixir 1.18 floor is justified. `Enum.sum_by/2` is `since: "1.18.0"` and has
  four call sites in shipped code; `mix.exs` declares `~> 1.18`.
- The `named_types` positional-index fallback genuinely closes the `KeyError` /
  `FunctionClauseError` pair it targets on the **data** path.
- For selectors produced by `parse_specification/1`, the narrowed rescue whitelist
  `[MatchError, CaseClauseError, RuntimeError]` is sufficient on the data path —
  a 40,000-case fuzz over parser-produced type strings found no escape.

## Findings 1-3 — why they were escalated rather than auto-applied

All three are real. None was auto-applied, for three different reasons:

**#1 (element-count guard).** A fix was written, tested, and **reverted**. The
guard's payload-derived bound degenerates for element types of zero static width,
and the obvious repair — charging such elements a one-word floor — breaks a
legitimate round-trip that the encoder really produces and that an existing test
(`test/abi/type_decoder_test.exs:46`) pins deliberately, citing the depth-5
composite property that surfaced it. So the correct bound is a design decision
with more than one defensible answer (an absolute count cap, parse-time rejection
of zero-width element types, or accepting the exposure and documenting it), and
picking one by guess inside an audit commit is not appropriate for a wire-format
decoder. The mechanical gate rejecting my fix is exactly the stake-gated ladder
working; the fix was reverted and the tree left green.

Per `critical-rules.md` § "NEVER BROADCAST AN UNPATCHED VULNERABILITY IN A
COMMITTED FILE", the reproducing type string, payload shape and measured
amplification are **deliberately not recorded here**. They were delivered to the
operator out-of-band in the audit return message. This report records only that a
bound exists which does not constrain the allocation it is meant to constrain.

**#2 (topics-path totality).** `decode_indexed_topics/3` runs outside any
`malformed_data` rescue, so a topic that is not exactly 32 bytes raises out of
`decode_event/4` — from a plain `parse_specification/1` selector, on data that
comes straight from `eth_getLogs`. This contradicts `@type decode_error`'s "closed
error set" and the `api()` `returns` declaration. Not auto-applied because the
right resolution is a public-contract choice: widen the rescue to cover the topics
path, or narrow the documented contract to admit raising. Both are defensible;
the second is cheaper and the first is what the docs already promise.

**#3 (duplicate parameter names).** `Map.new` over name→value pairs collapses
duplicates. Solidity emits `name: ""` for unnamed parameters, so an event with two
unnamed non-indexed inputs returns one entry instead of two — silent data loss,
reproduced. Not auto-applied because every repair changes the public return shape
(index-key the empties, return a list, or error), which is a genuine fork the
maintainer owns. Note the commit's own `named_types` code comment shows the author
considered the missing-`:name` case and moved past the empty-`:name` case.

## Auto-applied fixes

- `test/abi/event_test.exs`: new `encode_event_topics/2 argument validation`
  describe block covering the four previously unexercised raise branches
  (indexed-arity mismatch, fixed-array size mismatch, tuple size mismatch, and the
  list-shaped tuple clause). `ABI.Event` coverage 89.77% → 100.0%; project total
  97.19% → 98.88%. These were the only lines keeping a critical-tier module below
  the project's own 95% bar, and the project-wide gate could not see it because
  the threshold is measured across all modules.

## Second-opinion status

Codex was dispatched and cancelled: its broker pins the job workspace root to the
primary checkout with write access, which conflicts with this audit's isolation
constraint. A fresh-context Claude reasoner was substituted, scoped read-only to
the worktree. This is **not** a cross-family second opinion and is recorded as
such. Its three substantive findings were all independently reproduced here before
being accepted; its two lowest-priority items (a `bytes0` mis-listing in a comment,
and the `mix.exs` floor comment naming one call site) were judged cosmetic.
