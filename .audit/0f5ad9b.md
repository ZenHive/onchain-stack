# Audit 0f5ad9b

Reviewed `8644779..0f5ad9b` — task 2133 (EIP-712 conformance): the agent delivery
`8194455`, the reviewer fix `c3c6ff1`, and the two roadmap status commits. Inspected
`Cartouche.Typed`, the new `Cartouche.Hex.pad_right/2`, the conformance tests, the
ethers/viem fixture generator and its two committed vector files, the verification
ledger section, the cartouche README, and the package CHANGELOG.

The implementation itself is sound and stayed inside the task's declared scope. The
`encode_type/2` rewrite replaces the non-terminating queue with an explicit
seen-map traversal, dependencies are sorted by name, `bytesN` now right-pads per the
EIP, address/uint stay left-padded, arrays of structs thread the type map, and
`pad_right/2` was added beside `pad/2` rather than changing `pad/2`'s callers — which
task 2133's `out_of_scope` explicitly permitted and required. The dead `do_encode_type/4`
and its `@spec` were removed with it; no orphaned code path was left behind. No debug
output, no TODO markers, no `deps/` edits.

## Findings and fixes

1. **Fixed — undocumented width contract on a public function.** `c3c6ff1` added
   range validation to `Type.encode_data_value/3` (`ArgumentError` for a `uintN`/`intN`
   value outside the declared width, `FunctionClauseError` for a `bytesN` value longer
   than `N`) and tests for it, but left the `@doc` describing only the old
   pad-and-hash behaviour. Documented the contract and pinned both raises as doctests,
   including the fact that the two failure modes raise *different* exception types —
   `bytesN` over-width surfaces as a `Cartouche.Hex.pad_right/2` clause error while
   the integer widths raise `ArgumentError`. Recording the asymmetry beats hiding it;
   unifying it would be a behaviour change, not a hygiene fix, and is left alone.

2. **Fixed — typespec drift inside `Type.primitive()`.** The new `{:int, pos_integer()}`
   member landed next to pre-existing `{:uint, number()}` and `{:bytes, number()}`.
   `number()` admits floats, which no clause has ever accepted and which the new
   `is_integer(width)` guards now reject outright. Narrowed both to `pos_integer()`.

3. **Fixed — ledger omitted half of the validation it claims to pin.** The Task 2133
   section of `docs/verification-ledger.md` was updated for the `bytesN` rejection but
   still described only signed-integer range coverage, although
   `typed_test.exs` also pins unsigned range rejection. Added it.

4. **Fixed — duplicated version pins in the new fixture generator.** `generate-typed.cjs`
   repeated `6.17.0` / `2.55.19` in three places (the embedded `generationCommand`, the
   output-filename tuple, and the fixture `version` field), so bumping a pin in one place
   would silently disagree with the others — while the sibling `generate.cjs` in the same
   directory already solved this with named constants. Hoisted `ethersVersion` /
   `viemVersion`. Verified `node --check` passes and that the rebuilt `generationCommand`
   is byte-identical to the string committed in both fixture files, so a regeneration
   still reproduces the current vectors.

5. **Folded into task 9007 — release notes for a silent breaking change.** Task 2133
   flipped `bytesN` padding direction in `encode_data_value/2,3`, `deserialize_value!/2`
   and `serialize_value/2`. The old behaviour was wrong and the new one is right, but the
   change is not additive: a consumer that passed a short `bytesN` value now gets a
   different struct hash, digest and signature, with no error anywhere. Nothing in
   `packages/cartouche/CHANGELOG.md` records it, and the last entry there is `[0.9.1]`.
   Audit 408b2b6 filed task **9007** for the same class one commit range earlier (task
   2134's notes), so this was filed as a second instance and correctly rejected by the
   sibling-check gate as same-class. Rather than open a third, **9007 was widened** from
   "record task 2134's changes" to "reconcile Cartouche release notes against everything
   landed since 0.9.1", with acceptance criteria naming the 2133 padding flip as BREAKING,
   the additive parts of 2133, the version-bump consequence, and a sweep of
   `git log packages/cartouche` since the 0.9.1 cut so the class closes rather than
   recurring. Scores raised `d1/b2/u2 → d2/b7/u7` to match the breaking change now in
   scope. `CHANGELOG.md` itself was left untouched under the harness operational rule.

   Root cause worth naming: task 2133's own `acceptance_criteria` never asked for a
   CHANGELOG entry, so the reviewer had no written rule to reject against. Task 4059,
   still in progress in `onchain_aave`, *does* carry such a criterion ("CHANGELOG records
   the `:stable` removal as a breaking change"). This is the project's own
   domain-truth-as-acceptance-criteria rule working in one task and absent in the other,
   not an implementer lapse.

## Not findings

- `356a16a` marks task **4059** in progress with nothing landed in this range. That is a
  live `onchain_aave` dispatch wave, not an orphaned status change.
- `c3c6ff1` carries a `Co-authored-by: Cursor` trailer, which this repo's convention
  excludes. History is settled and this audit fixes forward only; noted, not rewritten.
- No reviewer rejections were recorded for this project, so there is no false-rejection
  finding to report.

## Cold-build witness

This worktree was intentionally un-warmed. `mix deps.get` in `packages/cartouche` fetched
the tree and left `mix.lock` unchanged; Hex reported pre-existing advisories on the
resolved tree, already tracked as task 9008 by the previous audit.

`cd packages/cartouche && mix check.dispatch` was then run on the audited base and again
after the fixes above. The post-fix run **passed, exit 0**: compile `--warnings-as-errors`,
`format --check-formatted`, `credo --strict`, `doctor --raise` (100% doc / moduledoc /
spec coverage), `ex_dna --max-clones 0`, `reach.check --arch --smells` (architecture OK,
no smells), `sobelow --config` (no findings), and the suite — **1,316 passed, 0 failed,
50 excluded, 0 skipped** (seed 287447). The count rose from 1,314 on the pre-fix run
because of the two doctests added in finding 1. The 50 exclusions are the package's
existing `integration` / `dev_node` dispatch configuration, unchanged here. Dialyzer,
coverage and `deps.audit.gated` are outside `check.dispatch` and were not run.

Summary: five findings, four fixed, one folded into a widened roadmap task. Fix-forward
hygiene pass; nothing here blocks or reverses the merge.
