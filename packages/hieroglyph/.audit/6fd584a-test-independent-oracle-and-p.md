---
sha: 6fd584a72b8e6bde5ec5914f52fb94ea30d00d54
short_sha: 6fd584a
audited_at: 2026-08-22
auditor_model: claude-opus-5
verdict: findings-applied
codex_status: unreachable (substitute second reasoner)
audited_by: audit-review v1
---

# Audit: test: independent-oracle and planted-mutant verification for the ABI wire format

**Original commit:** 6fd584a
**Author:** E.FU
**Files touched:** 20 (2 under `lib/`)
**LOC:** 37,651 insertions(+), 26 deletions(-) — the bulk is vendored JSON fixture data, audited for provenance rather than line-by-line

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 8 | revert-safety | hieroglyph.mutants.ex:89 | Mutating write sat outside the `try`; a failed write truncates without repair | applied |
| 2 | 8 | revert-safety | hieroglyph.mutants.ex | Only copy of the original was in RAM; a signal leaves `lib/` mutated, no recovery, no docs | applied |
| 3 | 7 | overclaim | docs/abi-verification-ledger.md:96 | "verifies the SHA-256 … after the revert" is false when the restore itself fails | applied |
| 4 | 7 | missing control | hieroglyph.mutants.ex:53 | No baseline run; a broken vector suite reads as a perfect kill rate | applied |
| 5 | 6 | vacuity | test/abi/ethers_corpus_test.exs | `assert compare(…) == []` passes on an emptied fixture; no count is pinned | applied |
| 6 | 6 | licensing | test/support/fixtures/ethers/ | MIT permission notice absent for redistributed third-party data | applied |
| 7 | 5 | reproducibility | vendor.py:19 | Tarball pinned by URL + version only; no content hash | applied |
| 8 | 5 | kill precision | hieroglyph.mutants.ex:145 | Compile-failure sniff missed the tokenizer's delimiter errors | applied |
| 9 | 4 | oracle independence | test/abi/abi_spec_test.exs:219 | A `decode(encode(x))` step in a file whose moduledoc forbids one | applied |
| 10 | 4 | fail-fast | hieroglyph.mutants.ex:101 | A failed restore only set a flag; the loop mutated the next file anyway | applied |
| 11 | 3 | corpus integrity | hieroglyph.mutants.ex:87 | Nothing asserted `replace` actually changes the file | applied |

## Assessment

This is the strongest work in the range, and the design decisions that matter are
right: the anchor check runs *before* any write, compilation is explicitly refused
as a kill oracle, the `vectors` and `suite` columns are kept apart, and the single
survivor is argued from an enumerated call-site table rather than waved through.
The two `lib/` fixes it carries — the static `T[k]` head-slot miscount and the
anonymous-event decode failure — are exactly the class of defect a `decode(encode(x))`
suite structurally cannot see, which is the justification for the whole task.

Two things did not hold up, both about the tool's own guarantees rather than the
ABI logic, and both now fixed:

**Revert safety.** `try/after` covers exceptions and nothing else. Nearly all of a
run's wall-clock time is spent inside `mix test` with `lib/` mutated on disk, and
the only copy of the original bytes was a variable in a process that Ctrl-C halts
without unwinding. The mutating write also sat *outside* the `try`, so a write that
failed partway left a truncated source file with no repair path — `File.write!`
truncates before it writes. There was no sidecar, no `at_exit`, and no
documentation telling a user to run `git checkout -- lib/`.

**Missing control.** Every mutant is graded by "did the vector files exit non-zero".
With no baseline pass asserted first, vector files failing for an unrelated reason
make *every* mutant read as `:killed` — a table showing a perfect kill rate while
proving nothing. A full run was saved from this by accident, because mutant 8
expects `:survivor` and would flip; but the ledger documents `--only` as a normal
invocation, and `--only` on any of mutants 1-7 removes that accidental canary.

## Auto-applied fixes

- `test/support/mix/tasks/hieroglyph.mutants.ex`
  - mutating write moved inside the `try`, with the truncation rationale recorded;
  - `.hieroglyph-mutants.orig` sidecar written before each mutation and removed
    only after the restore is verified byte-exact;
  - `assert_no_orphaned_sidecars!/0` — refuses to start when a previous run was
    killed mid-mutation, naming the recovery command;
  - `assert_baseline_green!/0` — the control run, aborting when the vector files
    do not pass on unmutated `lib/`;
  - a failed restore now aborts the run and names the sidecar, instead of setting
    a flag and mutating the next file;
  - `assert_mutation_bites!/3` — a no-op mutant is refused rather than recorded
    as a survivor;
  - `@compile_failure_markers` extended with `TokenMissingError` /
    `MismatchedDelimiterError`;
  - moduledoc sections for the control run and for interrupted-run recovery.
- `docs/abi-verification-ledger.md`: the SHA-256 sentence corrected, and the two
  properties stated precisely (revert covers exceptions not signals; a control run
  precedes the corpus).
- `CLAUDE.md` + regenerated `AGENTS.md`: same correction for the reviewer-facing copy.
- `test/abi/ethers_corpus_test.exs`: `corpus integrity` describe block pinning the
  vendored vector counts (443/368/376/414) so the oracle cannot go vacuous silently.
- `test/abi/abi_spec_test.exs`: the `ABI.encode/2` call at :219 replaced with a
  hand-written literal; moduledoc amended to name the one remaining self-referential
  assertion and explain why the external `0xa9059cbb` literal is what actually
  anchors it.
- `test/support/fixtures/ethers/LICENSE.ethers.md`: upstream MIT notice, verbatim
  from the tarball.
- `test/support/fixtures/ethers/vendor.py`: `TARBALL_INTEGRITY` pinned and verified
  on download, aborting on mismatch. The hash was taken from the npm registry
  packument **and re-derived from the downloaded bytes**; the check was tested in
  both directions (accepts the real tarball, rejects a tampered one).
- `test/support/fixtures/ethers/PROVENANCE.md`: integrity row, license pointer, and
  the reason the pin exists.
- `.gitignore`: `*.hieroglyph-mutants.orig` so a leaked sidecar can never be committed.

Verified after the changes: `mix hieroglyph.mutants --vectors --only offset-word-zeroed`
runs the control, kills the mutant, restores `lib/` byte-exactly and removes its
sidecar; a planted orphan sidecar aborts the run before any mutation. `mix ci`
exits 0; 458 tests, 98.88% coverage.

## Commit-hygiene note

The subject is `test:` but the commit carries two real `lib/` bug fixes. They are
documented accurately under `[Unreleased]` in the CHANGELOG, so consumers are
served; recorded here only because the subject understates the blast radius.

## Second-opinion status

Codex was dispatched and cancelled (broker pins the workspace root to the primary
checkout with write access — incompatible with this audit's isolation constraint).
A fresh-context Claude reasoner was substituted, read-only. Not a cross-family
opinion, and recorded as such. Its findings were verified in-session against the
files before being applied; two vendor.py doc-accuracy nits (priority 2) were
judged already covered by PROVENANCE's "a later rule sees only what earlier rules
kept" preamble and were dropped.
