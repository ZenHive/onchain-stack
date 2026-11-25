# Task 46 — stopped, not completed

**The survivor disposition was stopped on 2026-11-25 (task 1046) and will not
be resumed.** Task 9031 replaced the mutated codec bodies — the handwritten
`ABI.TypeEncoder` / `ABI.TypeDecoder` value codecs and the yecc/leex parser —
with the alloy NIF (shipped in `ac9ce9f5`). Dispositioning survivors inside
code that no longer exists produces no durable record.

What was measured, and nothing more:

* The campaign ran under **muex 0.9.0** (Elixir 1.20.2 / OTP 29, all 18
  mutators, `--no-filter --no-optimize --no-tce`) against the pre-9031 tree.
  The lock has moved since (0.11.2 when task 1046 was filed, 0.13.1 now); the
  campaign was not re-run on either.
* Known answer: 8/8 corpus sites agree, 0 disagreements. The Oeditus/muex#20
  gate reports `survived=2`.
* The authoritative v3 re-grade input holds 1272 mutants; 229 of them were
  graded before the stop (`results/auth-v3-partial.log`, not
  committed). Two v3 runs over the same 11 inputs agree exactly
  (`results/verified-unrev.json`). The campaign's 2748 reported kills were
  never sampled for false kills.
* No survivor count, score or false-kill rate was produced, and none is
  claimed. The unmeasured ledger draft (`ledger-section-7-draft.md`) was
  deleted rather than inserted; it survives in git history (last present at
  `5beef7c`).

The part that outlives the swap is the public-API finding below ("Open work"):
task 1046 pinned the four public guards as tests in
`test/abi/public_error_contract_test.exs`, with expected outcomes observed at
`e669099f`. Everything after this section is the original handoff, kept as
history; its "Next session" list is void.

## Acceptance criteria

| # | criterion | state |
|---|---|---|
| 1 | Oeditus/muex#20 reproduction reports `survived=2` on the installed muex, recorded with the version | **done** |
| 2 | Task-44 corpus known answer reproduced, disagreements investigated first | **done** — 8/8 agree, 0 disagreements |
| 3 | Campaign over `lib/abi/*.ex`, all 18 mutators, no filtering or sampling, from a committed script | **done** — `.mutation/run.sh` |
| 4 | Every survivor dispositioned in writing; none unclassified | **stopped** — the codec bodies were replaced by 9031 |
| 5 | Ledger gains a campaign section: version, mutator set, per-module counts, each survivor disposition | **stopped** — the draft was deleted unmeasured; the ledger's §7 records the stop |
| 6 | `mix ci` passes, touched modules stay at or above current coverage | **not run** |

## The one thing that must be redone first

`.mutation/verify-survivors.exs` re-grades reported survivors against the full
suite. Two earlier versions of it were defective, in opposite directions, and
**every disposition number produced before the current version is void**:

| version | failure | direction | artifacts it produced |
|---|---|---|---|
| v1 | inherited muex's `restore/2` defect: the mutated `.beam` leaks into the next mutant | false **kills** | `results/verified.json`, `verified-pass1..5.json` |
| v2 | `touch(path, os_time + 5)` after every write is not monotonic across iterations, so the mutant ran against the **unmutated** tree | false **survivals**, alternating by queue position | `results/verified-v2-DISCARDED.json` |
| v3 (current) | strictly increasing stamp on every write | none observed | — |

v3 is validated the way muex itself was: a known answer plus a repeat run.
`lib/abi.ex:674` `0x08 -> 0x07` breaks the built-in `Error(string)` selector
table and fails 3 tests when applied by hand; v2 called it survived, v3 calls
it killed. Two consecutive v3 runs over the same 11 inputs agree exactly.

Those `verified.json` / `verified-pass*.json` / `verified-v2-DISCARDED.json`
files are on disk but **not committed** — the findings are written up above
with their named reproductions, and 1.5 MB of defective machine output does not
belong in a published library's history. **They are not disposition input.** `disposition.py` reads only
`results/verified-authoritative.json`, which does not currently exist — it
raises rather than falling back, so there is no silent path back to the bad
numbers.

## Next session, in order (void since the stop above)

1. Re-run the authoritative re-grade. ~95 minutes for 1272 mutants; run it in
   the background and do not run `mix` against the main tree while it holds the
   sandbox.
   ```
   MIX_ENV=test mix run .mutation/verify-survivors.exs \
       .mutation/results/authoritative-input.json
   ```
   A partial v3 log (229 of 1272 graded) is at `results/auth-v3-partial.log`
   for comparison, not for reuse.
2. `./.mutation/disposition.py` — drive `unreviewed` to zero and clear any
   `STALE ARGUMENTS`. The staleness gate is deliberate: an equivalence argument
   whose mutant is now killed must be deleted, not left standing.
3. Bound the false-kill rate the restore defect can produce in the campaign's
   own 2748 kills — a survivor re-grade cannot see them by construction:
   ```
   ./.mutation/sample-kills.py 100          # fixed seed, already generated
   MIX_ENV=test mix run .mutation/verify-survivors.exs \
       .mutation/results/killsample-input.json --status killed
   ```
   The draft's §7.7 carries a `RESULT PENDING` marker waiting on this number.
4. `MIX_ENV=test mix run .mutation/accounting.exs` for the `line: 0` and
   AST-equivalent drop counts §7.8 describes. §7.8 currently quotes no figures;
   if the script does not produce them, the section comes out rather than
   shipping an unmeasured claim.
5. `./.mutation/disposition.py --write`, then insert
   `.mutation/ledger-section-7-draft.md` into `docs/abi-verification-ledger.md`
   as §7, renumbering the present `## 7. Re-running` to `## 8.`
6. `mix ci`, then task 46 to done.

## Open work this task uncovered but did not do

* The `guard` class of survivors splits in two, and the split is the remaining
  disposition work. Guards on **private** heads are equivalent on the reachable
  domain (every internal caller is type-correct). Guards on **public** heads —
  `ABI.decode_error/3`, `ABI.get_abi_item/3`, `ABI.Event.encode_event_topics/2`,
  `ABI.TypeEncoder.encode_packed/2` — are reachable with a wrong argument type
  and are killable by tests pinning `FunctionClauseError`. Those tests are worth
  writing; they pin a public error contract. Size the work off the v3 survivor
  list, not off the v2 one.
  **Done by task 1046:** `test/abi/public_error_contract_test.exs` kills
  `lib/abi.ex:687`, `lib/abi.ex:1136`, `lib/abi/event.ex:139` and
  `lib/abi/type_encoder.ex:349` (all `Guard: replace guard with true`, campaign
  line numbers) against the current `Onchain.ABI.*` facades.
* `lib/abi.ex:1240` carries a dead `Enum.filter(& &1)` over a list that cannot
  contain a falsy element (ledger group `vestigial-filter`). It should be
  deleted, as its own rmap task — a measurement task must not quietly edit
  `lib/`.
* `ABI.encode_packed/2` reports `"unsupported type :address"` for a
  wrong-length address binary, because the length-checked clause falls through
  to the catch-all. The message is misleading. Not touched here for the same
  reason.

## muex upstream

Four defects were found in the measuring tool and reported. Their status, as of
the maintainers' last message:

| defect | status |
|---|---|
| TCE unsound for nested `defmodule` | fix PR prepared, `fix/tce-nested-module-fingerprint` |
| `DependencyAnalyzer` builds malformed module atoms | fix PR prepared, `fix/dependency-analyzer-module-atoms` |
| `Sandbox.restore/2` leaves the mutated `.beam` | confirmed and fixed, `fix/sandbox-restore-forces-recompile` |
| a campaign killed by SIGTERM still exited 0 | issue body only |

All await their operator. Until the restore fix lands, the workaround for our
own re-grades is exactly what v3 does.

**Do not patch `deps/muex`.** Task 46's `out_of_scope` rules it out, and the
reason is durability: a measurement produced by a hand-patched tool is not a
verification record.
