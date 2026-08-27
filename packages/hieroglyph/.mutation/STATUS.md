# Task 46 — where this stands

Roadmap task 46 is **not complete**. This file is the handoff: what is settled,
what is not, and what the next session must not mistake for a result.

## Acceptance criteria

| # | criterion | state |
|---|---|---|
| 1 | Oeditus/muex#20 reproduction reports `survived=2` on the installed muex, recorded with the version | **done** |
| 2 | Task-44 corpus known answer reproduced, disagreements investigated first | **done** — 8/8 agree, 0 disagreements |
| 3 | Campaign over `lib/abi/*.ex`, all 18 mutators, no filtering or sampling, from a committed script | **done** — `.mutation/run.sh` |
| 4 | Every survivor dispositioned in writing; none unclassified | **blocked on the re-grade below** |
| 5 | Ledger gains a campaign section: version, mutator set, per-module counts, each survivor disposition | drafted, not inserted — `.mutation/ledger-section-7-draft.md` |
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

## Next session, in order

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
