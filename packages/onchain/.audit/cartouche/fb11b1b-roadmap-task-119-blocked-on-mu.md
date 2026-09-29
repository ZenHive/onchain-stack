---
sha: fb11b1b107d8da1699cf16d80f2e7bc2b260ab1e
short_sha: fb11b1b
audited_at: 2026-08-24
auditor_model: claude-opus-5
verdict: findings-applied
codex_status: dual-reviewer
audited_by: audit-review v1
---

# Audit: roadmap: task 119 -> blocked on muex#23/#24; record the discarded 0.8.3 campaign

**Original commit:** fb11b1b — `roadmap: task 119 -> blocked on muex#23/#24; record the discarded 0.8.3 campaign`
**Author:** E.FU
**Files touched:** 6
**LOC:** +95 / −15

No production-code paths (`.mutation/run.sh`, `mix.exs` comment + dep constraint, `ROADMAP.md`,
`roadmap/tasks.toml`, `roadmap/data.json`, `docs/verification-ledger.md`). Above the 100-LOC
fast-path threshold, so audited in full — as a documentation-integrity pass rather than a
code-correctness one. Direct commit on `main`; no PR review trail. Codex second opinion
dispatched (`task-mt7abwbe-93xj80`, dual-reviewer).

## Findings

| # | Pri | Category | File:Line | Description | Resolution |
|---|-----|----------|-----------|-------------|------------|
| 1 | 7 | doc-gap | mix.exs:208; docs/verification-ledger.md:301; roadmap/tasks.toml (task 119) | `equivalent` is claimed unaffected by #24; it is not — TCE runs on the *applied* mutant source | applied (codex-flagged at 9, confirmed by reading muex) |
| 2 | 5 | bug | .mutation/run.sh:52; .mutation/verify.sh:29 | Campaign exit status captured in `$rc` but never returned — a crashed run exits 0 | applied (codex) |
| 3 | 5 | doc-gap | .mutation/verify.sh:19 | Still `--concurrency 8`, which this commit's own reasoning declares invalid | applied (codex) |
| 4 | 5 | doc-gap | .mutation/run.sh:10 | "Exhaustive" overclaims: muex drops `line: 0` mutations unless `--keep-metadata-mutations` | applied — comment scoped to "every locatable mutation" (codex) |
| 5 | — | discuss | docs/verification-ledger.md:286 | Codex regenerated the mutation set and counts 355 #24 no-ops, not 383 | dropped, rationale below |
| 6 | 2 | doc-gap | roadmap/tasks.toml (task 119 title) | Title still says "once muex can report survivors" | dropped, rationale below |
| 7 | — | discuss | docs/verification-ledger.md:261–295 | Campaign numbers have no tracked artifact (`.mutation/results/` is gitignored) | dropped, rationale below |

## Finding 1 — the substantive one

Three places (the `mix.exs` dep comment, the ledger's new 0.8.3 section, and task 119's body
and `out_of_scope`) assert that `no_coverage` **and** `equivalent` are "decided before or
without running a test" and are therefore unaffected by all three muex defects, so task 114's
results for both classes stand.

That is true of `no_coverage` and false of `equivalent`. Traced in `deps/muex`:
`WorkerPool.run_mutation_worker/4` returns `:no_coverage` from `select_tests/2` *before* any
mutation is applied — that class really is untouched. But the `:equivalent` branch runs
`Compiler.compile_to_source/3` first — the line-keyed `transform/5` that #24 breaks — and
passes the resulting **source** to `Tce.equivalent_source?(file_entry.ast, mutated_source)`.
A mutation #24 turns into a no-op therefore yields source byte-identical to the original, TCE
reports an exact instruction-stream match, and the mutant is scored `equivalent` without ever
reaching a sandbox. `--no-optimize` does not disable this: `Config.resolve_tce/1` reads only
`--tce` / `--no-tce`, and the campaign passed neither.

So both recorded `equivalent` counts (task 114's 1,227 and this attempt's 1,256) are upper
bounds contaminated by unapplied mutations, and task 119's re-run has to re-derive that class
rather than inherit it. Corrected in all three places; `out_of_scope` no longer excuses the
re-run from re-deriving `equivalent`.

The `#20`-scoped claim in the task 114 section (ledger line ~145) is left as written — it is
true of #20, which is all it claimed.

## Auto-applied fixes

- `mix.exs`: dep comment splits `no_coverage` (stands) from `equivalent` (upper bound only).
- `docs/verification-ledger.md`: the "what this attempt does not change" paragraph replaced with the split, including the call chain and the `--no-optimize` / `--no-tce` distinction.
- `roadmap/tasks.toml` (+ rendered `roadmap/data.json`): task 119 body and `out_of_scope` corrected. `ROADMAP.md` unchanged — neither field renders into the table.
- `.mutation/run.sh`: `exit $rc`; "exhaustive" scoped to locatable mutations with the `maybe_drop_unlocatable/2` reference.
- `.mutation/verify.sh`: `--concurrency 1` with the #23 reasoning, and `exit $rc`.

## Dropped findings

- **355 vs 383 #24 no-ops** — Codex regenerated the locked-muex mutation set and reports 355,
  with 28 of the retained boolean mutations being operator/negation changes that do modify
  source. Not reproduced in this audit (regenerating the set is a campaign-scale run), and
  replacing a recorded measurement with an unreplicated second one would make the ledger less
  reliable, not more. Recorded here instead: **the 383 figure is a single unreplicated count
  and task 119's re-run should not treat it as established.**
- **Task 119 title** — "once muex can report survivors" reads correctly with #23/#24 folded in
  (they make muex report *false* survivors, which is a failure to report survivors). The
  `blocked_reason` and body carry the precise story; retitling a blocked task to restate what
  its own blocker field already says is churn.
- **Unverifiable ledger assertions** — `.mutation/results/` is deliberately gitignored (raw
  campaign JSON), and the ledger is a narrative verification record, not an artifact store.
  This tradeoff is already stated in the task 114 section. Not a defect introduced here.

## Reviewed clean

- Class arithmetic: 1,308 + 111 + 2,227 + 1,256 + 3 = 4,905 ✓.
- `roadmap/tasks.toml` ↔ `roadmap/data.json` ↔ `ROADMAP.md` consistent (`rmap validate` → valid; `rmap render` produced no `ROADMAP.md` delta).
- `mix.lock` carries muex 0.8.3, matching `mix.exs`.
- `.mutation/run.sh` and `verify.sh` parse under `zsh -n`.
- No CHANGELOG entry needed: muex is `only: [:dev, :test], runtime: false` and ships nothing to a consumer.

## Codex second-opinion

Status: dual-reviewer (`task-mt7abwbe-93xj80`)
Corroborated findings: 1 (independently confirmed against `deps/muex` source before applying)
Codex-only findings (verified, applied): 2, 3, 4
Codex-only findings (verified, dropped): 5, 6, 7
Claude-only findings: —
