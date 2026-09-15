# Post-merge audit: d0dd07b

## Scope

Reviewed `0d284d2^..d0dd07b` — eight commits covering two landed tasks plus their
roadmap transitions:

- **Task 4069** (`bd5c228`, onchain_aave) — the V4 address registry re-derived
  from `aave-dao/aave-address-book` `safe.csv` at `fdaecf26`, Ethereum + Avalanche
  (390 rows), `Onchain.Aave.V4.Hub` / `.TokenizationSpoke` opened from a closed
  `:core | :prime | :plus` map to registry-driven `:v4_<name>_hub` lookup, the
  `v4_safe.csv` fixture, three new test files, `V4_SCOPING.md` / `README.md` /
  `CLAUDE.md` / `AGENTS.md` updates.
- **Task 5008** (`33f4a63`, `b0f5810`, onchain_aerodrome) —
  `Onchain.Aerodrome.Bindings.LpSugar`: eight reads, the `count()`-driven
  pagination driver, 288 lines of tests, roster registration, module-layout doc
  sync.

Reviewed for dead code, stale or missing docs, CHANGELOG gaps, debug leftovers,
broken conventions and naming drift. Read every source and test file in the range
in full, plus the surrounding registry, doc and gate surfaces they claim to match.

## Findings

**3 findings, 3 fixed. All documentation; no code-behaviour defect found.**

### 1. `onchain_aave/CHANGELOG.md` still claimed V4 is Ethereum-mainnet-only — a named acceptance criterion of the task that landed (fixed)

Task 4069's acceptance criteria required, verbatim, that *"V4_SCOPING.md **and
CHANGELOG** no longer state that V4 is Ethereum-mainnet-only"*, and its body
(tasks.toml:5880) called the claim **load-bearing** — *"a task in the aave_sim
repo cites that claim as its reason to exclude V4 from multi-chain work."*
`V4_SCOPING.md` was corrected; `CHANGELOG.md` was not touched at all, and
line 105 of the v0.4.0 section still read:

```
V4 is Ethereum-mainnet only, so the write paths are pinned by encoded-calldata
unit tests rather than testnet sends.
```

This is the sharper half of the finding: not a convention slip but a stated
criterion that went unmet, on a factual claim about a money surface that another
repo's scoping decision depends on.

**Fixed** without rewriting released history: the v0.4.0 sentence now states the
fact *as of v0.4.0* and points forward to the `[Unreleased]` re-sync entry; the
calldata-pinning rationale it supports is unchanged and still holds.

### 2. Both packages' `CHANGELOG.md` had no entry for the landed work (fixed)

The root `CLAUDE.md` § "After every task" requires a `[Unreleased]` entry in
`packages/<name>/CHANGELOG.md` for whichever package a task touched, and adds
*"Reviewers: reject a task as incomplete if these weren't touched where the change
warrants it."* Neither delivery commit touched a CHANGELOG. This is not structural
— the three immediately preceding delivery commits (`b4c4fa3`, `38305e7`,
`d245a3f`) all carry per-package CHANGELOG edits, so the file is reachable from a
delivery commit in this project.

**Fixed.** `[Unreleased]` entries added to both:

- `onchain_aave` § Changed — the pinned-commit re-derivation and row counts, the
  two supported networks, `networks/0` now reporting V4-only networks, the fourth
  (Global Dollar) Hub and registry-driven Hub resolution, the moved config-engine
  address, and the retained e-Spoke / PT aliases.
- `onchain_aerodrome` § Added — the eight `LpSugar` reads, and specifically the
  invariant the task exists to protect: enumeration runs to `count/1` and never
  terminates on a short page, `paginate/3` / `all_pages/2`,
  `{:error, {:invalid_limit, _}}` before any RPC, the named anti-regression test,
  and the opaque-`filter` caveat.

### 3. Stale test name in `contracts_test.exs` (fixed)

`test "resolves representative spokes across all three hubs"` — Ethereum now has
four Hubs; the assertions inside cover three *representative* ones deliberately.
Renamed to "resolves representative spokes across hubs". Every other "three
Hubs" / "all three" reference in the range was already updated (`hub.ex`
moduledoc and function table, `tokenization_spoke.ex`, `hub_test.exs`,
`README.md`, `V4_SCOPING.md`); this was the one leftover.

## What was checked and found clean

- **No debug output, no `TODO`/`FIXME`, no `@tag :skip`, no `credo:disable`, no
  `sobelow_skip`** anywhere in the added lines. (The `TODO` strings in
  `packages/onchain_aave/AGENTS.md` are rendered content from a user-global
  include, not source markers.)
- **No dead code.** `@type hub :: atom()` in both V4 modules looks vacuous but is
  referenced by ~40 specs and carries the intent; `registered_hub_key/1` replaced
  the deleted `@hub_contracts` map with no orphan left behind.
- **`hub_address/2` network semantics are correct.** The key-name scan spans all
  registered networks, but the returned key is resolved through `Contracts.address/2`
  with the *caller's* `opts`, so a Hub that exists on the wrong network still
  surfaces `unknown_contract` / `unsupported_network` rather than a foreign
  address. The behaviour matches the comment above it and is pinned by
  `registry_test.exs`.
- **Doc sync is thorough**, not perfunctory: `AGENTS.md` regenerated alongside
  `CLAUDE.md` in both packages, aerodrome's module layout and "remaining work"
  paragraph narrowed from "the rest of `bindings/`" to the four named remaining
  Sugar bindings, README status line de-scaffolded, the `describe/1` example
  repointed at the new module, and `portability_test.exs`'s comment updated from
  "LpSugar is a later task" to why it still encodes the call directly.
- **`LpSugar`'s test quality is above the bar.** The anti-regression test
  (`naive stop-when-length(page)-is-less-than-limit UNDER-COUNTS…`) asserts the
  *bug* fails, which is what the acceptance criteria asked for and what a
  same-direction golden test would have missed. Error paths (RPC error mid-scan,
  malformed response, unsupported network, five bad-address arities), zero count,
  exact multiples and page ordering are all covered.
- **`Descripex` roster consistency.** `Bindings.LpSugar` is registered without
  `use Descripex`, matching its sibling `Bindings.Abi`; the `api(...)` convention
  is used by the registry/types layer only. Not drift.
- **`git diff --check`**: clean, no whitespace errors.

## Reviewer feedback loop

No reviewer rejections are recorded for this project, so there is no false
rejection to assess. One observation in the other direction: finding 1 is an
explicitly enumerated acceptance criterion, quoted in the task body as
load-bearing for another repo, that the reviewer approved unmet. The gate held on
everything mechanical; it missed a criterion that required reading the task's own
criteria list against a file the diff never touched.

## Follow-ups filed

**Task 9009** — *Detect V4 address-book drift against upstream instead of only
against the committed snapshot* (onchain_aave, phase 4005, D4/B7/U6, codex /
gpt-6-astra).

`registry_test.exs` asserts all 390 rows of `test/fixtures/v4_safe.csv` resolve
correctly, which is real work — but the fixture *is* the snapshot the registry was
generated from, so the test cannot notice that upstream has moved. The rot rate is
measured, not hypothetical: the `AaveV4Ethereum` namespace went 150 → 304 → 317
entries in five months, and this very task found `CONFIG_ENGINE` re-pointed from
`0xe8096f93…` to `0xa1673fbD…` in that window. Nothing in the repo noticed; a
human re-derivation prompted by a roadmap task did. Serving a stale address is the
money-losing direction — `address/2` returns `{:ok, addr}` and callers sign
against it, so a re-pointed Hub or configurator is a wrong-contract call, not a
missing-key error.

Not filed, deliberately:

- **`registered_hub_key/1` rescans the registry on every Hub read** (~390
  atom-to-string comparisons per call, freshly allocated per network). Every call
  site is immediately followed by a network round-trip, so the cost is invisible;
  a compile-time hub→key map would be tidier but is not worth a task.
- **`mix check.dispatch` runs no tests in any of the eight packages.** Worth
  knowing (the 476 aave and 134 aerodrome tests in this range were never executed
  by the gate that approved them), but the project has adjudicated this surface
  repeatedly — task 6043's `out_of_scope` states "the dispatch hint stays
  static-only and the reviewer runs focused tests", and tasks in the 8866/9007
  range discuss what `check.dispatch` deliberately omits. Filing it would
  re-litigate a documented decision, not surface a gap.

## Validation

All commands run in this intentionally un-warmed worktree (no copied `deps`,
`_build` or PLTs).

| Command | Result |
|---|---|
| `packages/onchain_aave` → `mix deps.get` | ok, no lock change |
| `packages/onchain_aave` → `mix check.dispatch` | **passed** (cold witness) |
| `packages/onchain_aave` → `mix check.dispatch` (after audit fix) | **passed** |
| `packages/onchain_aave` → `MIX_ENV=test mix test.json --exclude integration` | **passed**, 396 passed / 0 failed / 80 excluded |
| `packages/onchain_aerodrome` → `mix deps.get` | ok, no lock change |
| `packages/onchain_aerodrome` → `mix check.dispatch` | **passed** (cold witness) |
| `packages/onchain_aerodrome` → `MIX_ENV=test mix test.json --exclude integration` | 129 passed, **3 failed** — see below |

**The three aerodrome failures are host tooling, not the landed range.** All three
are in `test/onchain/aerodrome/calldata_fixture_test.exs` (last touched in
`fe6faa0`, outside this range) and all three report *"Foundry cast is required on
PATH; never a skip"*. `command -v cast` confirms Foundry is absent on this node.
That hard-flunk-instead-of-skip is the file's deliberate anti-evasion stance, so
the fix is installing Foundry on the node, not a code change — noted here rather
than filed. `mix check.dispatch`, the registered dispatch gate, does not run tests
and is unaffected.

**One methodology note for future audits:** running `MIX_ENV=test mix
check.dispatch` fails both packages on `mix doctor --raise`, because the test env
adds `test/support` to `elixirc_paths` and those modules carry no `@doc`s.
`check.dispatch` is not env-pinned (only `test.json` and `dialyzer.json` are, via
`def cli`), so it must be run in the default `:dev` env — which is how the gate
actually runs it. The root `CLAUDE.md`'s claim that the per-package gate is
"gated on `MIX_ENV=test` via each package's `def cli`" is true of `mix ci`'s test
step, not of `check.dispatch`.
