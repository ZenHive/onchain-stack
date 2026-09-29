## 7. Mutation campaign — muex 0.9.0

Section 3.3 planted eight mutants by hand and checked that the suite caught
seven of them. That is a spot check of eight sites chosen by the person who
already knew where the encoder was weak. This section replaces it with an
exhaustive sweep: every mutation all eighteen muex mutators can generate over
`lib/abi.ex` and `lib/abi/*.ex`, with no filtering and no sampling.

Reproduce with `.mutation/run.sh` (parameters in §7.3); grade the result with
`.mutation/known-answer.py` and `.mutation/verify-survivors.exs`.

### 7.1 Grading the tool before reading its output

A mutation score is a claim about the *test suite*, produced by a tool that can
fail in the direction that flatters it. muex ≤0.8.2 could not report a
surviving mutant on Elixir 1.20 at all: it matched the pre-1.20 ExUnit summary
wording, 1.20 prints `Result: N passed / Failed: N test`, the regex missed, a
fallback returned one failure, and `:survived` became unreachable — every
survivor was reported killed and every suite scored 100% (Oeditus/muex#20).

So the tool is graded first, in both directions, by `.mutation/gate-muex20.sh`.
It builds a two-mutant project where the answer is known and asserts muex
reports each verdict:

| Suite under test | Required verdict | muex 0.9.0 on this host |
|---|---|---|
| assertion that cannot fail (`assert true`) | `survived=2`, score 0% | `survived=2`, 0.0% |
| assertion on the mutated value | `killed=2`, score 100% | `killed=2`, 100.0% |

The second row is the one that matters. A tool that reports everything killed
passes the first row only. Both must hold before any campaign number is read.

The gate copies `.tool-versions` into its scratch project. Without it the
temporary project resolves the *global* default Elixir rather than the repo's
pinned 1.20.2, and since #20 is an Elixir-version-dependent parsing bug, the
gate would answer a question about the wrong toolchain.

### 7.2 Four defects in the measuring tool, found by this campaign

The gate proves muex can report both verdicts. It does not prove muex reports
them *for the right mutants*. Four defects surfaced while reading the first
campaign, all of which corrupt a score in the flattering direction, and all of
which are worked around here rather than patched under `deps/` — a measurement
produced by a hand-patched tool is not a durable record.

All three were reported upstream and independently reproduced against a muex
clone at `e4c44f8`, which is why they are stated here as facts about the tool
rather than as this repo's suspicions. That reproduction also supplied the
provenance for (b): it is a **regression** introduced by the fix for
Oeditus/muex#11 (commit `f5627af`), which replaced a correct
`Enum.map_join(".", ...)` + `"Elixir." <> ...` with the separator-less join.

**(a) Trivial Compiler Equivalence is unsound for a nested `defmodule`.**
`Muex.Tce.compile_binary/2` keeps only the first module the compiler returns
(`[{module, binary} | _]`). When the file's top-level module contains a nested
`defmodule`, that first module is the *inner* one, so both the original and the
mutant fingerprint the inner module's bytecode and every mutation outside it
compares equal — reported `equivalent`, dropped from the denominator, never
executed. `lib/abi/type_decoder.ex` nests `ABI.TypeDecoder.StrictViolation` at
line 17 and was the only file in the tree that tripped this: **672 of its 867
mutations** were dropped, including `@word_size_bytes 32 -> 33`, which plainly
changes behaviour. Minimal reproduction: `.mutation/tce-nested-module.exs`
(a flat module answers `false`, the same change under a nested module answers
`true`). A dropped mutant is worse than a survivor: a survivor is visible to
criterion 4 and gets a written disposition, a dropped one is invisible. So the
campaign runs `--no-tce`, and the equivalence question is answered afterwards
by `.mutation/equivalence.exs`, which is muex's design with the one line
corrected: fingerprint EVERY module the compile returns, keyed by name, and
compare the whole map.

Run over the 908 survivors, that certifies **11 as provably equivalent** — all
of them key-order swaps in a map literal, which the compiler normalises. The
direction of the proof is worth stating: `equivalent` is a proof that no test
can ever kill the mutant, while `distinguishable` proves only that the
bytecode differs. Evaluation order of two pure expressions shows up in the
instruction stream without being observable, so the remaining 897 are not
thereby "killable" — they are merely not settled by this tool, and go on to
get an argument instead.

**(b) Test selection builds malformed module atoms.**
`Muex.DependencyAnalyzer.module_from_parts/1` joins with no separator —
`Enum.join(["Elixir" | parts])` yields `:ElixirABITypeEncoder`, never
`:"Elixir.ABI.TypeEncoder"`. Every lookup misses, `fallback_to_all/2` fires,
and the full suite runs. That accidental miss is what makes most modules sound.
`ABI` is the exception: `test/abi/function_selector_real_world_test.exs` also
names it inside a `describe` string, which reaches a different branch that
produces the well-formed atom. So the lookup hits, the fallback never fires,
and **all 905 mutations in `lib/abi.ex` were graded against 2 of 15 test
files**. Confirmed by hand: replacing the body of `ABI.encode/2` with `nil` —
reported `survived` — fails 60 of 460 tests.

A `killed` verdict from a subset is sound; some test really did fail. Only
`survived` is suspect. `.mutation/verify-survivors.exs` therefore re-grades
every reported survivor against the full suite, reusing muex's own loader,
mutator, compiler and sandbox so no patch is hand-reproduced, and differing in
exactly one place: the test file list. It runs a control pass on unmutated
source first — without it, a sandbox that cannot run the suite reports every
mutant as killed and the whole re-grade reads as a clean bill of health.

Partial dependency detection is worse here than none at all.

**(d) `Sandbox.restore/2` leaves the mutated `.beam` behind.**
`Muex.Sandbox.apply_mutation/4` deletes the stale `.beam` so the child
`mix test` is forced to recompile the mutated module. `restore/2` does not: it
copies the original source back and leaves the *mutated* `.beam` in the
sandbox's `_build`, and a source Mix believes it has already compiled is not
recompiled — so the mutated `.beam` survives into the **next** mutant's test
run and grades it against the previous mutant's code.

The staleness gate is not mtime granularity, which is what this section first
claimed. Mix records **size, mtime and digest** per source inside the compile
manifest, and checks **size first and unconditionally**
(`mix/lib/mix/compilers/elixir.ex` on 1.20.3). Three consequences, each of
which changes what the defect can do:

  * A size-*changing* mutation is immune — `1 -> 999` never reproduces it, even
    with mtime pinned backwards. Only size-preserving mutants are exposed,
    which is most operator, boolean and single-digit-literal mutations, and is
    exactly the population this campaign is largest in.
  * The window is the mutation write's second against the restore's second, so
    the whole child `mix test` has to fit inside one second. That is much wider
    than a manifest-write-to-restore window, which is why it fires without any
    clock pinning; the rate is proportional to 1 / child-run-duration, and this
    suite runs in well under a second.
  * Deleting the `.beam` at restore does **not** close it. `missing_beam_file?`
    is only consulted inside the `last_mtime != mtime` branch, so a missing
    beam alone never forces a recompile — it converts the false kill into an
    `UndefinedFunctionError` false kill, which is harder to diagnose. That was
    the obvious fix, and it is refuted.

(Mechanism, immunity boundary and refutation established by the muex
maintainers' own static and dynamic reproduction, muex `e4c44f8` on Elixir
1.20.3 / OTP 29, where the defect fired naturally in 4 of 8 back-to-back ~0.6 s
cycles. Their fix — `File.touch!(path, max(os_time, previous_mtime + 1))` at
both swap sites — is on `fix/sandbox-restore-forces-recompile`.)

This one breaks the direction rule the other three obey. Every failure above
corrupts toward a false *survivor*; this corrupts toward a false **kill**,
because what leaks in is a mutation that already killed something. Measured:
`lib/abi/type_decoder.ex:349`, `1..element_count` → `element_count..1`, was
reported killed. Applied by hand to the real tree it passes all 531 tests — the
swap is length-preserving and the mapper discards the range values, so nothing
it does can fail anything. Its predecessor in the queue was a
`type_encoder.ex:418` message mutant that kills exactly one test, and the false
kill reported exactly one failure.

`.mutation/verify-survivors.exs` now stamps every write — mutation and restore
alike — with a strictly increasing mtime, so Mix always sees a source newer
than its manifest and recompiles unconditionally. The first attempt at that fix
was itself defective in the opposite direction and is written up in §7.6,
because the way it was caught is the reusable part.

The consequence for **muex's own numbers** is the part that does not fit in a
re-grade. muex restores between mutants exactly as the first version of this
harness did, so the mechanism that manufactures a kill is present in the
campaign itself — and re-grading only the survivors cannot see it, by
construction. §7.7 closes that with a sample of the campaign's kills rather
than leaving it as a caveat.

**(c) A campaign that died still exited zero.**
The 2026-08-27 08:06 run took a SIGTERM at minute 38, wrote nothing but the
shutdown notice, and exited 0 — which the runner reported as a clean campaign
over an empty file. `.mutation/run.sh` now grades its own artifact: no parsable
summary means no campaign, whatever muex claimed on the way out.

### 7.3 Campaign parameters

| | |
|---|---|
| muex | 0.9.0 (`~> 0.9` floor; 0.8.2 cannot report a survivor on Elixir 1.20) |
| Elixir | 1.20.2 / OTP 29, pinned by `.tool-versions` |
| files | `lib/abi.ex`, `lib/abi/*.ex` |
| mutators | all 18, named explicitly rather than defaulted |
| exhaustiveness | `--no-filter`, `--no-optimize`, no `--max-mutations` |
| equivalence | `--no-tce` (see §7.2a) |
| concurrency | 8 (see §7.7) |

`src/` (yecc/leex output) and `lib/mix/tasks/` are out of scope: the first is
generated — mutate the `.xrl`/`.yrl` instead — and the second is tooling, not
the wire format. `--coverage-guided` is deliberately not used: it exists to
make a slow suite affordable, this suite runs in well under a second, and it
adds a false-survivor path (`:no_coverage`) for no gain.

**The campaign and the survivor set were measured against different suites, and
the numbers must be read accordingly.** The campaign ran against the 460-test
baseline; the tests this task adds to kill survivors then took the suite to
531, and the re-grade of §7.6 runs every survivor against all 531. So the
campaign's score is a snapshot of the suite *before* this task's work, the
survivor set is what withstands the suite *after* it, and the difference
between the two is not drift — it is the task's output. Re-running the campaign
on the current tree would produce a higher score than the one tabulated above;
that number is deliberately not back-filled, because the tabulated one is what
the survivor list was derived from.

### 7.4 The known answer

Criterion 2 requires the campaign to reproduce the §3.3 corpus before any other
number is read: the seven sites the vectors kill must come back killed, and
`mod-negative-branch` must come back survived or provably equivalent.
`.mutation/known-answer.py` re-resolves each corpus `find:` anchor to a current
line span and cross-references the campaign's verdicts at those sites.

An anchor may span several source lines. muex attributes a mutation to the line
carrying the mutated token, which for a multi-line anchor is rarely the first
line — matching on the first line alone reported a phantom disagreement on
`event-signature-annotates-indexed`, whose anchor begins on a bare
`function_selector` line while all four mutations land on the two `|>` lines
below it. The comparison is against the span.

Result: **8 of 8 agree, 0 disagreements.**

One class gap is worth recording rather than scoring: the planted
`event-signature-annotates-indexed` mutant adds an argument
(`FunctionSelector.encode()` → `encode(true)`), and no muex mutator changes a
call's arity. The hand-planted corpus covers a mutation class the tool cannot
generate, which is an argument for keeping §3.3 rather than retiring it.

### 7.5 Dispositioning the survivors

Criterion 4 requires every survivor to be dispositioned in writing as one of:
killed by a test added in this task, provably equivalent with the argument, or
an accepted gap with the reason. At this scale that is done by CLASS — each
survivor is mapped to exactly one class by an ordered rule, each class carries
its argument here, and `.mutation/disposition.py` is the coverage gate: it
exits non-zero if a single survivor falls through to `unreviewed`, so "none
left unclassified" is a check that runs rather than a claim in prose.

The classes, most-specific first:

**provably-equivalent** — certified by `.mutation/equivalence.exs` (§7.2a):
the mutant compiles to byte-identical BEAM, so no test can distinguish it.
A machine-checked proof outranks every argued class, so this rule runs first.

**argued-equivalent** — no bytecode proof, but a written argument that no test
*can* kill it, in `.mutation/argued-equivalent.json`. Each group carries one
argument and a list of `{file, line, mutator}` selectors, and
`.mutation/disposition.py` fails on a selector that matches no surviving
mutant — so an argument cannot outlive the mutant it was written for, which is
how a disposition file rots into fiction. The groups:

| group | argument, in one line |
|---|---|
| `opts-default-list` | `opts \\ []` → `[:mutated]`; every consumer reads via `Keyword.get/3` or `opts[:key]`, both of which skip a non-tuple element |
| `bodiless-head-argument-swap` | parameter names exchanged on a bodiless multi-clause head, which binds nothing and emits no code |
| `bodiless-head-deletion` | the same heads deleted outright; they declare no default and attach only `@doc`/`@spec` |
| `bitstring-modifier-order` | muex's `-()` node is a bitstring type-specifier list, whose members are order-independent by the language definition |
| `map-literal-key-order` | first two entries of a map literal or struct pattern exchanged; a map is unordered |
| `discarded-range-values` | `1..n` reversed under a mapper that ignores its argument; only the length is observable |
| `clause-shadowed-array-length` | `len > 0` → `len >= 0`; the only newly-admitted value is 0 and the clause above matches 0 first |
| `shadowed-zero-size-bytes` | the same shape for `{:bytes, size}`, shadowed by the `{:bytes, 0}` clause |
| `mod-zero-branch` | the `ABI.Math.mod/2` guard weakenings; equivalent for every `n >= 1`, which is the whole of `@spec`'s `pos_integer()` |
| `guard-conjunct-unreachable` | `bits <= 256` → `<= 257`; the `rem(bits, 8) == 0` conjunct in the same guard rejects 257 |
| `disjunct-collapses-to-true` | `min_words == 0` → `== -1`; where it mattered the other disjunct was already unconditionally true |
| `read-width-identity` | `decode_uint(data, 8)` → `9`; both read a full word and both check one padding byte |
| `identical-accumulator-seeds` | the two swapped tuple elements are the same literal `<<>>` |
| `pad-rounds-to-word` | a divisor perturbation that stays inside 1..32 bytes, which `Math.pad/4` rounds to the same word |
| `redundant-word-size-fast-path` | a `validate_left_padding!/5` clause the general clause already answers identically |
| `discarded-return-value` | `Enum.each` → `Enum.map`, `:ok` → `:error`, a deleted `case` clause — all in positions whose value nothing reads |
| `unreachable-default` | a `Map.get/3` default the grammar can never reach |
| `vestigial-filter` | `|> Enum.filter(& &1)` over a list that cannot contain a falsy element |

Five of these sites host BOTH an equivalent and a killable mutant, which is the
single most useful thing the argued tier records. `type_encoder.ex:614` is
equivalent at `256 -> 257` and killable at `256 -> 255`; `math.ex:41` is
equivalent at `x < 1` and killable at `x < -1`; `type_decoder.ex:309` is
equivalent at `8 -> 9` and killable at `8 -> 7`; `:335` is equivalent at
`size > -1` and killable at `32 -> 33`. So the selectors pin the exact
mutation, not the line: a per-line disposition would have written off four real
defects.

Two sites in that list were first dispositioned WRONG, both by reasoning from a
mutator's *name* instead of reading the source it generates, and both are kept
here because the correction is the transferable part.

`type_decoder.ex:582` was recorded as equivalent under three mutators and
killable under a fourth, `FunctionCall: remove @() call`, on the reading that
removing `@` from `@word_size_bits` leaves a bare variable — which would make
`defp validate_left_padding!(_data, word_size_bits, ...)` a catch-all head and
disable strict padding validation outright. Printing what muex actually emits
shows the opposite: the mutator substitutes **`nil`**, giving
`defp validate_left_padding!(_data, nil, ...)`, a head no call can match. The
clause is dead, the general clause answers identically, and the mutant is
equivalent like its three neighbours. All four now sit in
`redundant-word-size-fast-path`.

`type_encoder.ex:631` was recorded as killable at `/ -> identity`. It is not:
the mutant evaluates `ceil(1)`, and `Math.pad/4` rounds 1 up to a full 32-byte
word, so the output is byte-identical. It moved into `pad-rounds-to-word`.

The rule both corrections produce: a mutator's name is a label, not a
specification. `Literal: 1 to 2` is the sharpest case — it rewrites every
structurally-equal occurrence **on the target line** at once (identical
literals on other lines stay independent), so `Bitwise.bsl(1, bits - 1)`
becomes `bsl(2, bits - 2)`, an arithmetic identity, and muex emits two
byte-identical copies of it. Two guaranteed-equivalent survivors in the
denominator, from one line. That group is `literal-rewrite-is-identity`.

Two of these are worth separating from the rest, because "equivalent" is doing
different work in each.

`mod-zero-branch` is equivalence **on the declared domain**, not unconditional.
`mod(0, 0)` distinguishes every one of the three mutants from the original: the
literal `mod(0, _n)` clause returns 0 without dividing, while the widened guards
route x = 0 into a `rem/2` and raise. `@spec mod(integer(), pos_integer())`
excludes n = 0 and all four internal call sites pass a literal 32 or 256, so
nothing in the library can reach it — but a caller who ignores the spec can.
Recorded as a restriction rather than glossed, because the alternative is a
test asserting a value for a zero modulus.

`vestigial-filter` is not an equivalence so much as a **discovery**: the mutant
is unobservable precisely because the code it mutates is dead. The honest
disposition is that the filter should be deleted, tracked as its own task so a
measurement does not quietly edit `lib/`.

**manifest-metadata** — mutations inside a Descripex `api(...)` block: the
agent-facing description strings and option atoms rendered into
`api_manifest.json`. These are not the wire format, and `mix test` — the only
thing muex runs — is the wrong gate for them. The right one is
`mix hieroglyph.manifest --check`, a `mix ci` step muex never invokes. That is
asserted rather than assumed: `.mutation/gate-manifest.sh` edits one `api()`
description and checks both directions.

| tree | `mix hieroglyph.manifest --check` |
|---|---|
| unmutated | exit 0 |
| one `api()` description edited | exit 1, "api_manifest.json is stale" |

Accepted gap, with the reason being that the guard exists and fires — just not
in the suite muex measures.

**error-message** — mutations inside a `raise`. A changed error string cannot
change an encoded byte. The exception is the interpolated *bounds* inside an
overflow message, which are the diagnostic contract a caller reads; those are
killed by exact-message tests added in this task rather than dismissed.

**guard** — a `when` clause on a private dispatch head, weakened or removed.

### 7.6 The score is not deterministic

A mutation score reads like a measurement of a fixed object. It is not: the
suite contains a StreamData property test (`test/abi/roundtrip_property_test.exs`),
so the data a mutant is exposed to differs from run to run and a given mutant's
verdict is a random variable.

Demonstrated on `lib/abi/type_decoder.ex:533` (`Arithmetic: * to /`), run three
times against the property test alone: **survived, killed, survived**. The
campaign reported it survived; the serial re-grade killed it. Neither is wrong.

Two consequences, both recorded rather than smoothed over:

  * A survivor list is reproducible only up to the ExUnit seed. Re-running the
    campaign will not reproduce this section's survivor set exactly, and a
    small diff is expected behaviour, not drift.
  * A single `survived` observation is weak evidence, so every survivor is
    re-graded serially against the full suite before it is dispositioned.

#### The re-grade harness needed grading too

§7.1 grades muex before reading its output. The same standard has to apply to
`.mutation/verify-survivors.exs`, which is also a measuring instrument, and it
failed that standard twice. Both defects were invisible to reading the code and
visible only to measurement, and each was found by the same two probes: apply a
mutation by hand and see what the real suite does, then run the harness twice
over identical input and see whether it agrees with itself.

| version | recompile discipline | failure | direction |
|---|---|---|---|
| v1 | none — inherits muex's `restore/2` | mutated `.beam` leaks into the next mutant | false **kill** |
| v2 | `touch(path, os_time + 5)` after every write | not monotonic: a full-suite iteration takes ~2 s, so the restore's future stamp outlives the next `apply_mutation`'s ordinary write, Mix skips the recompile, and the mutant runs against the **unmutated** tree | false **survival** |
| v3 | strictly increasing counter, every write | — | none observed |

v2 is the instructive one, because its symptom looks like data rather than like
a bug: verdicts alternated strictly by queue position. Re-running eleven
identical inputs killed the odd-numbered ones and spared the even-numbered
ones; a second re-run reproduced the parity, not the verdicts. The known-answer
probe settled it — `lib/abi.ex:674` `0x08 -> 0x07` breaks the built-in
`Error(string)` selector table and fails three tests when applied by hand,
while the harness reported it survived.

Under v3 the same eleven inputs produce byte-identical verdicts across
consecutive runs (10 killed, 1 survived). The numbers recorded in §7.5 come
from the v3 run; the v1 and v2 outputs are discarded rather than merged, for
the reason given immediately below.

An earlier version of this section drew a stronger conclusion from that
asymmetry — that a kill in *any* pass could be recorded as a kill, since a kill
is positive evidence while a survival is only its absence. §7.2d retracts it.
That rule is only sound while kills cannot be manufactured, and the restore bug
manufactures them; worse, a union rule makes a single false kill permanent,
because no later pass can retract one. So the dispositions rest on **one**
re-grade made with the fix (`results/verified-authoritative.json`), not on the
union of several. The earlier `verified-pass*.json` runs are kept only as the
evidence trail for the bug that invalidated them.

A second, separate source of noise appears in the sandbox: a run occasionally
fails with `module ABI.TypeDecoder is not loaded and could not be found`. muex
classifies that as `invalid`, not `survived`, so it does not fabricate a
survivor directly -- but it shows a sandbox whose mutated module is sometimes
not loaded, and a worker testing unmutated code is exactly how a false survivor
would arise. Measured here at roughly 0.5% (3 false survivors in ~653).

The obvious explanation is a concurrency race, and that explanation is wrong:
the same nondeterminism reproduces upstream at `--concurrency 1`. An earlier
draft left it there, as an open property of the tool, and added that its
*direction* was at least established — toward a false survivor, never a false
kill. That addition was wrong, and it is the sentence this campaign most needed
to retract.

The serial flicker the maintainers had been carrying open — identical
`--concurrency 1` runs differing by one or two kills, **always toward more
killed**, only in multi-file runs — matches the restore defect of §7.2d on
direction, seriality and magnitude, and is now filed as its candidate
mechanism. So the tool has a known nondeterminism that manufactures *kills*,
and the "survivors only" framing above does not cover it.

What survives from that framing is narrower but still load-bearing. A survivor
that outlives the re-grade is not proven unkillable — it is merely still
standing, which is why each one goes on to need an argument. And the campaign's
kills, which no survivor re-grade can inspect, are sampled instead (§7.7).

### 7.7 Concurrency

cartouche runs its muex campaigns strictly serially, because muex 0.8.x could
only isolate a worker's `_build` when it could infer the app name from build
markers, and parallel workers raced on a shared `_build` (Oeditus/muex#23).
That rule is not inherited here on authority. 0.9.0 reads the app name from the
`app:` literal in `mix.exs` (#26), so each sandbox gets its own build tree.

The rule was re-derived by measurement instead: the 49 mutations of
`lib/abi/parser.ex` were run at `--concurrency 1` and again at
`--concurrency 8`.

| | total | killed | survived | invalid | score |
|---|---|---|---|---|---|
| `--concurrency 1` | 49 | 33 | 12 | 4 | 73.33 |
| `--concurrency 8` | 49 | 33 | 12 | 4 | 73.33 |

Zero per-mutation verdict disagreements — but that comparison is **too small to
license the conclusion on its own**, and it is recorded here with that caveat
rather than as a clean result. False survivors turn up at roughly 0.5% (§7.6);
over 49 mutations the expected count is 0.25, so this table would have looked
identical whether a race was present or absent. It is a consistency check that
found nothing, not a clean bill of health — and since the 0.5% reproduces at
`--concurrency 1` upstream, the flag is not what would have to be fixed anyway.

What the comparison does support is a bound on the *direction* of this
particular failure: a worker reading another worker's build tree runs
*unmutated* code, which corrupts toward a false **survivor**, never a false
kill. That bound is why every survivor is re-graded serially by
`.mutation/verify-survivors.exs` before it is dispositioned.

It does **not** license the wider claim that kills are trustworthy, and an
earlier draft of this section made that claim. The restore defect of §7.2d runs
the other way: a mutant graded against its predecessor's still-loaded `.beam`
is reported killed by a failure it did not cause, and muex's own runner
restores between mutants exactly as the first version of the re-grade harness
did. So the campaign's 2748 kills are subject to a mechanism that manufactures
kills, and re-grading only the survivors cannot see it.

That is a gap in this campaign, closed by sampling rather than left open. RESULT
PENDING — `.mutation/results/verified-killsample.json`.

### 7.8 What the campaign JSON does not account for

Two subtractive steps run between mutation generation and execution, and
neither appears in the JSON report — muex logs both only under `--verbose`,
which costs a full re-run to recover a number that needs no test execution at
all. `.mutation/accounting.exs` regenerates the mutations exactly as
`Muex.do_run/2` does and counts each stage, running no tests:

  * `maybe_drop_unlocatable/2` removes mutations reported at `line: 0` unless
    `--keep-metadata-mutations` is passed. muex documents those as
    compile-time/invalid mutants; they cannot be dispositioned by site.
  * `drop_equivalent/2` removes AST-pattern-equivalent mutants. This layer is
    always on and is **not** the same as `--tce`: TCE runs per mutant inside
    the worker and surfaces as a status in the JSON, while this one deletes the
    mutation before the pool ever sees it.

`invalid` is a third category that is reported but is not a verdict: the mutant
did not compile, so it says nothing about the tests. It is excluded from the
score denominator, which is `killed + survived + timeout`.
