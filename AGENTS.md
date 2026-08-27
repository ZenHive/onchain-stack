<!-- Auto-generated from CLAUDE.md by claude-marketplace/scripts/sync-agents-md.sh — do not edit manually -->

# Onchain Stack — Monorepo

Since **2026-08-27** the eight onchain library packages live in this one repo,
`packages/<name>/`, absorbed with full git history from their former standalone
checkouts. Each package is still its own Hex package with its own version,
`CHANGELOG.md`, and publish cycle — the repo boundary changed, the release unit
did not.

**Three packages stay standalone, deliberately**: `descripex` and `zen_websocket`
(`~/_DATA/code/descripex`, `~/_DATA/code/zen_websocket`) are first-party but
consumed *beyond* this family, so folding them in would mix an unrelated blast
radius into this repo's history; `mpp` (`~/_DATA/code/mpp`) is the top-level
Phoenix consumer app, structurally a leaf, not a library sibling. All three are
still coordinated from here for publish-ordering purposes (see the dependency
graph below) but are edited in their own checkouts.

**The old standalone checkouts of the eight absorbed packages are retired** —
GitHub repos archived, never deleted (`ZenHive/onchain_evm` still hosts NIF
release assets other tooling may reference). Do not work in
`~/_DATA/code/hieroglyph`, `~/_DATA/code/cartouche`, etc. — they are stale forks
of history now living here.

This document is self-contained on purpose: it must be readable by **any** agent
(Claude, Codex, Cursor, Grok). After editing it, regenerate `AGENTS.md`:

```bash
cd ~/_DATA/code/onchain-stack
~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh          # write AGENTS.md
~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh --check  # freshness gate
```

Per-package work also loads `packages/<name>/CLAUDE.md` (Claude Code reads
CLAUDE.md from cwd upward), which carries only what is specific to that
package — architecture, module layout, coverage threshold, native build notes,
gotchas. Everything family-wide lives here, once.

---

## Layout

| Package (`packages/…`) | Hex package | Role | Native |
|---|---|---|---|
| hieroglyph | `hieroglyph` | ABI encode/decode (`ABI.*`) | yecc/leex |
| cartouche | `cartouche` | Substrate: signing, tx encoding, raw RPC, crypto | — |
| onchain | `onchain` | Core primitives: RPC, ABI, ERC, signing | — |
| onchain_aave | `onchain_aave` | Aave V3 + V4 wrappers | — |
| onchain_aerodrome | `onchain_aerodrome` | Aerodrome Finance (Base) bindings, Sugar-backed reads + analytics | — |
| onchain_evm | `onchain_evm` | EVM sim, Solidity parse, trace, codegen | Rust (Rustler) |
| onchain_js | `onchain_js` | npm packages on the BEAM (QuickBEAM) | Zig NIFs |
| onchain_tempo | `onchain_tempo` | Tempo chain primitives (0x76 tx, TIP-20) | — |

**Standalone siblings** (not in `packages/`): `descripex`, `zen_websocket`
(shared upstreams), `mpp` (leaf app) — see above.

The monorepo root itself (`mix.exs` at the top level) is **not a Hex package
and ships no runtime code**. It exists to hold `mix onchain.bounds`
(`lib/mix/tasks/onchain_bounds.ex`) and the serial `ci` alias that drives all
eight packages.

---

## Toolchain — one pin for the whole repo

```
erlang 29.0.3
elixir 1.20.2-otp-29
```

Lives in exactly one file, `.tool-versions` at the repo root. The eight
packages' individual `.tool-versions` files were deleted on migration — there
is now nowhere else a version can drift to. (Before the monorepo, ten separate
repos each pinned their own copy, and alignment sweeps periodically found
copies missing or diverged; that failure class is gone by construction now
that there is exactly one file.)

Default branch is `main` (was uniformly `main` across all ten standalone repos
before the merge too — see the old per-repo history if you need the
org-settings story; it is anecdote now, not a live concern).

---

## The sibling/3 mechanism — dual-mode in-family dependencies

In-family deps are declared in each package's `mix.exs` as a call to a local
`sibling/2,3` helper, e.g. in `packages/cartouche/mix.exs`:

```elixir
sibling(:hieroglyph, "~> 1.6")
sibling(:onchain_evm, "~> 0.6", only: [:dev, :test])
```

`sibling/3` resolves to one of two shapes depending on context:

- **Path branch** (day-to-day dev, no Hex round-trips): when the marker file
  `.onchain-monorepo-root` is found walking up from the package — i.e. inside
  this checkout — it resolves to
  `{name, path: "../<name>", override: true, ...opts}`.
- **Hex branch** (a consumer's `deps/` layout, or `ONCHAIN_PUBLISH=1` set):
  resolves to `{name, req, opts}` — the literal Hex requirement string.

The predicate is the **root marker file**, never "does the sibling directory
exist" — in a consumer's unpacked `deps/`, every Hex package sits side by side,
so `../cartouche/mix.exs` exists there too, and an existence check would fire
exactly at the stranger it's meant to exclude.

**The publish trap, and why every publish sets `ONCHAIN_PUBLISH=1`:** Hex
≥2.5 does **not** abort `mix hex.build`/`mix hex.publish` on a path
dependency — it silently drops it from the tarball, printing only
"Dependencies excluded from the package" in the build output. A tarball built
without `ONCHAIN_PUBLISH=1` looks like it built fine and is missing a runtime
dependency. Every publish step:

1. Sets `ONCHAIN_PUBLISH=1` (forces the Hex branch for every `sibling/3` call).
2. Runs `mix deps.get` in that mode (re-resolves to the Hex requirement).
3. Greps `mix hex.build` output for the phrase `"excluded from the package"` —
   any hit means a sibling requirement is still resolving to a path dep, abort.
4. Restores the dev lock afterward: `git checkout -- mix.lock`.

`bin/publish-prep.sh` does steps 1–3 for you. This is the direct descendant of
a real incident: onchain_aave 0.3.0 shipped with
`{:onchain_evm, path: "../onchain_evm", only: [:dev, :test]}` and was
unbuildable for anyone without the sibling checkout — `only:` does not save
you, `mix hex.build` still packages the declaration as written. Fixed in 0.3.1
by moving to a real Hex dependency; the sibling/3 mechanism exists precisely so
that fix can never regress silently.

`mix onchain.bounds` (the root gate's first step) is the other half of this
contract: it AST-parses every `sibling(:name, "req")` literal across all eight
`mix.exs` files and checks the requirement still admits that sibling's
in-repo `@version`. Inside the monorepo the path branch always wins locally,
so a Hex requirement that has quietly rotted (a sibling moved to a new major,
say) is invisible until `mix hex.publish` or a consumer's `mix deps.get` — this
task catches it in seconds instead. Usage: `mix onchain.bounds` (all packages)
or `mix onchain.bounds <pkg>...` (scoped).

---

## Dependency graph

```
descripex ─┐                         (standalone, shared upstream)
           ↓
       hieroglyph ──→ cartouche ──→ onchain ──┬──→ onchain_aave
                                       ↑       ├──→ onchain_aerodrome
                 zen_websocket ────────┘       ├──→ onchain_evm
                 (standalone, shared upstream) ├──→ onchain_js
                                                └──→ onchain_tempo ──→ mpp
                                                                     (standalone, leaf)
```

Edges (verify in each `packages/<pkg>/mix.exs` — this is a hint, not ground
truth; sibling/3 calls are the source):

- hieroglyph → `descripex ~> 1.0`
- cartouche → `sibling(:hieroglyph, "~> 1.6")`, `descripex ~> 1.0`
- onchain → `sibling(:cartouche, ...)`, `descripex ~> ...`, `zen_websocket ~> 0.7.0`
- onchain_aerodrome → `sibling(:onchain, ...)`, `descripex ~> ...`, plus a
  dev/test-only `sibling(:onchain_evm, "~> 0.6", only: [:dev, :test])` — ABI
  parsing and codegen only, never simulation (revm rejects non-mainnet chain
  ids, so Base forks are impossible today)
- onchain_evm / onchain_js → `sibling(:onchain, ...)`, `descripex ~> ...`
- onchain_tempo → `sibling(:onchain, ...)`, `sibling(:cartouche, ...)`,
  `descripex ~> ...`
- onchain_aave → `sibling(:onchain, ...)`, `descripex ~> ...`, plus a
  dev/test-only `sibling(:onchain_evm, "~> 0.5", only: [:dev, :test])` — **a
  Hex dependency, not a raw path dep**, exactly because of the publish trap
  above
- mpp (standalone) → `onchain`, `cartouche`, `onchain_tempo`, `descripex` —
  three-segment caps here, see below

`descripex` and `zen_websocket` are roots — no first-party upstream of their
own — so a release there starts the whole cascade. Because they're consumed
beyond this family, bump them deliberately and note the wider blast radius
when you do.

---

## Release cascade rule

**Upstream-first, one published version at a time**, unchanged by the
monorepo move. A change at any node ripples *down* the graph. Publish the
upstream, `mix deps.update` the dependent's Hex-mode requirement (or just trust
the path dep in dev, but re-verify with `ONCHAIN_PUBLISH=1` before that
dependent's own publish), re-test, then publish the dependent.

Canonical order when the whole stack moves:

```
descripex ─┐
zen_websocket ─┴→ hieroglyph → cartouche → onchain → {onchain_aave, onchain_aerodrome, onchain_evm, onchain_js, onchain_tempo} → mpp
```

The five mid-tier siblings are mutually independent once `onchain` ships and
can publish in any order. `mpp` is always last.

**What the monorepo changed:** a cross-package edit (e.g. widening a bound in
five `mix.exs` files) is now a single commit instead of five repo-scoped
commits — but the **Hex publish order is still upstream-first, one package at
a time**. The path-dep branch of `sibling/3` means the working tree always
resolves fine regardless of publish order; only `mix hex.publish` still
enforces the graph.

**Tags** are cut after a successful publish, by hand, and are now
package-scoped within one repo: `<pkg>-v<ver>` (e.g. `cartouche-v0.7.1`), not
bare `v<ver>` — a bare tag would collide across packages sharing this repo.

---

## Durable release-engineering rules (carried forward from the standalone era)

These predate the monorepo and remain true; they are stated once here instead
of duplicated per package.

- **Diff the tarball, not the tag.** `mix hex.package fetch <pkg> <ver>
  --unpack` then `diff -rq <unpacked>/lib packages/<pkg>/lib` answers "is
  there unreleased code" definitively, in seconds. Tag distance does not — a
  tag is a lagging, hand-created record, not a boundary; a repo can carry
  100+ commits past its last tag while every one of them is already published.
- **Two-segment bounds (`~> 0.12`) for in-family and first-party deps by
  default; three-segment (`~> 0.12.0`) only where a 0.x package has actually
  broken consumers at a minor.** The reasoning: `mix.lock` is committed in
  every package, so an in-family upgrade can only land through a deliberate
  `mix deps.update` behind `mix ci` — there is no silent-upgrade path a
  three-segment cap would guard against. What a cap costs is real: raising a
  runtime bound is itself a minor version bump in the consumer (see below), so
  every one-segment-tighter cap turns each upstream minor into a forced
  release across every capped consumer. Widening a bound (`~> 0.12.0` →
  `~> 0.12`) is not a release — no version bump, no lock change — so it should
  ride along in a package's next release rather than force one.
  - **The near-miss to avoid:** `~> 0.13` is not the same as `~> 0.12` — the
    former *excludes* `0.12.x` and forces immediate adoption everywhere,
    recreating exactly the forced-cascade problem two-segment bounds exist to
    avoid. Two-segment means "accept the current major/minor line", never
    "require the newest minor."
  - **Where three-segment still earns its keep:** `zen_websocket` (0.5.0 and
    0.6.0 both narrowed runtime requirements at a minor — one consumer, one
    cheap bump if it breaks again), and native/0.x runtime deps whose minors
    change real behavior underneath a NIF (e.g. `quickbeam`). `mpp`, being a
    leaf nothing consumes, can afford either way — its caps are pure
    self-cost, not protection of a stranger, and are the next obvious
    widening candidates if left tight without a documented reason.
  - **A widened bound is inert while a *published* upstream still caps.**
    Resolution takes the intersection across the whole graph — widening
    onchain's own `descripex` bound changes nothing while cartouche and
    hieroglyph's *published* Hex versions still declare the old cap.
    `mix hex.outdated <dep>` names every capping source; run it before
    concluding a bound edit had any effect, and always derive publish order
    from the dependency graph, never from where the interesting code happens
    to sit.
  - **Narrowing a runtime requirement is itself a minor bump** in the
    consumer, even when nothing else in the package changed.
- **Third-party dev-tooling deps should not carry a three-segment self-cap**
  unless something upstream of *them* already caps tighter and you're
  documenting why (e.g. `ex_ast ~> 0.12.0` pinned by `reach`, not by any
  package here — a genuinely redundant self-cap would be pointless). A
  patch-line cap on an analyzer with no documented reason reads as
  forgotten drift, not a considered pin — it silently turns "update
  available" into "update not possible" and freezes the gate.
- **`mix.lock` is committed for every package, libraries included.** Mix only
  reads the top-level project's lock and Hex never ships one in a tarball, so
  a library's own lock never reaches a consumer either way — the only
  question is whether *this repo's own gate* resolves reproducibly, and there
  committing wins: `mix_audit` reads it (an uncommitted lock makes
  `deps.audit` grade whatever happened to resolve that run, with no diff to
  review), a transitive bump becomes a reviewable diff instead of a silent
  landing, and `git bisect` reproduces the exact dep set of a commit. The
  real cost: a committed lock means the gate only ever exercises **one**
  resolution, so a bound that has stopped holding can go unnoticed until a
  fresh consumer trips on it. Mitigate periodically with a scratch resolve
  (`mix deps.unlock --all && mix deps.get`, in a throwaway clone — never the
  working tree) and a test run against the newest versions the bounds admit.
  **Nothing automates this today** — see Open Items.

---

## Gates

### Root gate

```bash
cd ~/_DATA/code/onchain-stack && mix ci
```

runs, in order:

1. **`mix onchain.bounds`** — seconds of AST parsing; catches the one failure
   class the monorepo introduces (see sibling/3 above) before spending eight
   package gates discovering it downstream.
2. Each package's own `mix ci`, **strictly serial** — `packages_ci/1` in the
   root `mix.exs` shells into `packages/<name>` with `MIX_ENV`/`MIX_TARGET`
   cleared (so the package's own `def cli` env pins apply, not whatever the
   root process inherited) and raises on the first non-zero exit.

**Why serial, non-negotiable:** every package's `deps.audit.gated` step
touches **one shared external clone**,
`~/.local/share/elixir-security-advisories-mirego`, doing a `git pull --rebase`
in it via `bin/advisory-freshness.sh`. Two packages' gates running
concurrently interleave their fetches into one `FETCH_HEAD` and fail with

```
fatal: Cannot rebase onto multiple branches.
advisory-freshness: FAIL - 'git pull --rebase' failed in ~/.local/share/...
```

— a red on a package whose code is fine. The clone self-repairs on the next
serial run (no cleanup needed), but the failure is indistinguishable from a
real freshness problem until you've re-run it, so just never parallelize `mix
ci` across packages. (This constraint predates the monorepo — it was
"never run `mix ci` in more than one **repo** at a time" when these were ten
separate checkouts; the monorepo doesn't remove the hazard, it just moves it
one level down, from repos to packages sharing one working tree.) Parallelism
is safe for `deps.update`, `hex.audit`, and anything read-only.

### Per-package gate

Unchanged in shape from the standalone era — each package keeps its own
`.reach.exs`, `.doctor.exs`, sobelow config, and coverage threshold (see that
package's `CLAUDE.md`). `cd packages/<name> && mix ci` for focused work; that
alias is `precommit.full` under a different name in every package, still
gated on `MIX_ENV=test` via each package's `def cli`.

**Shared gate helpers** live once at `shared/mix_helpers.exs`
(`OnchainMonorepo.MixHelpers`, `agents_check/1` + `advisory_freshness/1` +
`host_script/3`) instead of being copy-pasted into all eight `mix.exs` files
(pre-monorepo, they drifted — only one package's copy carried an
executable-bit guard). Every package loads it behind `Code.ensure_loaded?/1` +
`File.exists?/1` — the file is **not** part of any published tarball (Hex
ships a package's own `mix.exs`, never the monorepo root), so a consumer
evaluating a package's `mix.exs` in isolation gets a loud skip, not a crash.
Never edit a package's copy of `agents_check`/`advisory_freshness` inline —
there shouldn't be one; if you find one, it's drift from before this file
existed and should be migrated to load `shared/mix_helpers.exs` instead.

**Consolidated config, root-owned:** `.tool-versions`, `.mix_audit_ignore`
(one shared entry, six per-package symlinks — see the adjudication below),
and the ExSlop/`.credo.exs` base policy now live once at the repo root instead
of eight near-identical copies. `cartouche` and `onchain` still carry their
own `.credo.exs` on top of the root policy — verify whether that's an
intentional per-package override or leftover drift before trusting it as
either.

### The gates are real — do not re-decorate them

Four properties are easy to silently undo; carried forward from the
standalone era because the failure modes are still live:

- **`smells: [strict: true]` in each package's `.reach.exs`.**
  `reach.check --smells` raises only when `opts[:strict] || config.smells.strict`
  — without it, the check prints findings and exits 0 anyway. Fix smell
  findings; never add an ignore entry to make one disappear.
- **`deps.audit.gated` runs `bin/advisory-freshness.sh` before `deps.audit`.**
  `mix_audit` discards its own sync exit status
  (mirego/mix_audit#61) — a database that can no longer sync still prints "No
  vulnerabilities found" and exits 0. The script asserts a clean tracked tree,
  proves the clone is at upstream tip, and falls back offline to the last
  *verified* sync. It deliberately does not gate on upstream commit age
  (observed gaps between mirego commits reach 96 days — a short age limit
  would red every consumer during normal quiet periods).
- **`agents.check`** fails when a package's `AGENTS.md` has drifted from its
  `CLAUDE.md`, diffing rendered output (so drift inside a transitive
  `@`-import is caught too). The root has no such gate wired into `mix ci` —
  regenerate and check `AGENTS.md` here by hand after any edit to this file
  (see the command block at the top).
- **Sobelow needs `--exit low`** (or the `.sobelow-conf` equivalent
  `exit: "Low"`); a bare `sobelow --skip` exits 0 while still printing
  findings. This flag being silently dropped let one package carry four
  findings straight through a green `mix ci` for weeks before it was caught —
  if you ever see a sobelow step *print* findings and the alias still pass,
  the flag has been dropped.

**Regenerate `.sobelow-skips` wholesale; never let it accumulate.** Each entry
pins `FindingType,file:line,HASH` — the line number is part of the identity,
so inserting a line *above* a suppressed finding invalidates it silently while
looking unchanged. `--mark-skip-all` only appends, so a reflex re-run leaves a
drifted entry behind forever, suppressing nothing while looking like it
suppresses something. The cadence: confirm every outstanding finding
(`mix sobelow --format compact`, **without** `--skip`) is a genuine false
positive, then `rm .sobelow-skips && mix sobelow --mark-skip-all`, verify zero
with `--skip`, commit. Never regenerate while an unconfirmed finding is
outstanding. Note Sobelow colourises `--format compact`, so a naive
`grep '^\[+\]'` matches nothing and silently reports a clean repo — strip ANSI
first. A drift-check that used to diff a fresh `--mark-skip-all` against the
committed file in CI has no replacement since the workflow removal below; see
Open Items.

**There is no CI runner.** All GitHub Actions workflows were removed from
every package (and the coordination repos) on 2026-08-22, before the monorepo
merge, and none has been added back — this is a standing operator decision,
not a gap to fill. `mix ci` was always what graded a package; the workflows
only invoked it. What changed is *who* triggers it: nobody, automatically.
Run `mix ci` in the affected package(s) — or the root `mix ci` for a
cross-cutting change — before pushing. Green locally is the only green there
is. Dependabot still opens bump PRs (it reads the dependency graph, not a
workflow run) but nothing grades them; treat one as a notification, run the
bump through `mix deps.update` + `mix ci` yourself, close the PR.

### Adjudicated findings — cite, don't re-derive

Two advisory findings recur on every fresh `deps.get`/`hex.audit` and have
been investigated repeatedly by different sessions. The verdicts below are
final; don't re-litigate them without a change to the trigger conditions
stated.

**cowlib / gun advisories are a mirror-grouping bug, not a real finding here.**
`GHSA-w4f7-4cxr-rv3c` (`EEF-CVE-2026-43966`) covers two Erlang packages with
different ranges — cowboy `< 2.16.0`, gun `< 2.4.0` — but the mirego mirror's
importer groups by `ghsaId` alone, so both collapse into one `gun` advisory
file carrying **cowboy's** range, and no `cowboy` file is written at all. This
repo resolves gun 2.5.0 (above gun's real fix) and cowlib 2.19.0, so the
finding is a false positive here. Filed upstream as
`mirego/elixir-security-advisories#8` (grouping fix) and `#9` (the one-line
`Dump.dump/1` patch), both open and unreviewed as of the last check. The
single ignore entry lives at the **root** `.mix_audit_ignore`, symlinked into
the six packages whose dep tree resolves `gun` (hieroglyph and cartouche audit
clean and carry no ignore file at all). Remove it once the importer fix lands
and the mirror splits the advisory — never add any *other* advisory id to
that file; every other finding it would report is real.

Separately: **cowlib 2.19.0 itself carries three EEF-CVE advisories with no
fix available** (`-43966`/`-43969`/`-43971`) — 2.19.0 is the newest release on
Hex, so this is unpatched upstream, not drift, arriving transitively through
`gun`. Nothing to do but know it's there.

**`mix deps.audit` (the gate) and `mix hex.audit` do not see the same
advisories — run both when asked about security, trust only the first for the
gate.** `hex.audit` has reported HIGH/MEDIUM `bandit` advisories that exist
nowhere in the mirego mirror `deps.audit` reads — so a `deps.audit` green
means "nothing the mirego mirror knows about," not "no advisories anywhere."
If a real `bandit` fix is ever available (check `hex.audit` output against
the bandit CHANGELOG), bump it — never suppress a bandit finding via
`.mix_audit_ignore`.

**`reach 2.8.2`'s `--smells` pass crashes on any non-Elixir AST node**
(`Reach.Evidence.NilParameter`/`ParameterShape` read `function.meta.module`
with dot access; a node with no `:module` — generated Erlang, or a
plugin-contributed JS node — raises and takes the **entire smell pass** down
before reporting a single finding). Filed as
[elixir-vibe/reach#36](https://github.com/elixir-vibe/reach/issues/36) with a
three-line fix; upstream is third-party, so the family works around it rather
than waiting:

- **hieroglyph** scopes `.reach.exs` to `source_paths: ["lib", "test/support"]`
  — the crash came from `src/` (yecc/leex-generated Erlang), which is the
  right scope regardless of the bug (a smell in generated code is unfixable
  by definition).
- **onchain_js** is the family's one package running `reach.check --arch`
  **only**, `smells: [strict: true]` left in the config so the gate re-engages
  the moment a fixed `reach` ships. The crash there comes from JavaScript
  nodes the QuickBEAM plugin contributes (`source: nil`), which have no path
  to exclude (`plugins:` is not a `.reach.exs` key).

**Never hand-patch `deps/reach` (or anything under any package's `deps/`) to
work around this.** A hand-edited unpacked tarball makes `mix ci` pass on your
machine with nothing left to disagree — no CI runner exists to catch the
divergence on a fresh clone or a consumer anymore (see "There is no CI
runner" above). To test a candidate fix: patch it, confirm, then
`mix deps.clean reach && mix deps.get` to restore pristine in the same
session, and carry any real fix in `.reach.exs`, the alias, or a `mix.exs`
override — never in `deps/`.

**`ex_ast`'s override is measured, not assumed.** `reach 2.8.2` declares
`ex_ast ~> 0.12.0`, which would hold a package at 0.12.10 unless it declares
`{:ex_ast, "~> 0.13", override: true, only: [:dev, :test], runtime: false}`.
All eight packages carry that override today. It was withheld for five of them
for a while on the theory that `ex_ast` 0.13's subset-pattern matching "could"
make `reach`'s smell checks report fewer findings; running
`mix reach.check --dead-code --arch --smells` under both 0.12.10 and 0.13.1 in
the same package produced byte-identical output. Two measurement traps worth
remembering if this is ever re-litigated: comparing finding *counts* across
packages proves nothing (every package gates on `strict: true`, so every
package sits at zero by construction — zero-vs-zero is what both a working and
a blind detector look like); and a seeded probe only tests anything if it
targets what `reach` actually checks (Elixir 1.20's own type checker already
catches an unused-function or a `nil`-into-`String.upcase/1` seed at compile
time, so a `reach` `(none)` on those seeds was never evidence of anything).
The override is `only: [:dev, :test], runtime: false` everywhere, so it never
reaches a published tarball or a consumer's graph regardless.

---

## Roadmap

One root rmap project, `roadmap/tasks.toml` (rendered to `ROADMAP.md` +
`roadmap/data.json`). The eight former per-package roadmaps were merged into
it; old per-package task IDs are offset to keep them unique and
recognizable in the merged numbering:

| Package | Offset |
|---|---|
| hieroglyph | +1000 |
| cartouche | +2000 |
| onchain | +3000 |
| onchain_aave | +4000 |
| onchain_aerodrome | +5000 |
| onchain_evm | +6000 |
| onchain_js | +7000 |
| onchain_tempo | +8000 |

Every task carries a `target_repo` field naming which package it belongs to,
and `touches` paths are `packages/<name>/…`-prefixed. Use the `tasks:rmap`
skill for picking/scoring/creating tasks; it operates on this one file
regardless of which package a task targets.

---

## Harness

One registered project, `onchain_stack`, source
`~/_DATA/code/onchain-stack` (server mirror
`/data/postgresql/code/onchain-stack`), `target_branch: main`, warm paths for
onchain_evm's Rust build artifacts
(`packages/onchain_evm/{native/*/target,priv/native}`) so a fresh dispatch
worktree doesn't pay a cold Rust build. The eight per-package harness
registrations from the standalone era are retired — write-set collisions that
used to require cross-repo coordination now happen naturally inside one repo,
and harness serializes overlapping waves on its own.

The dispatch-scale gate is **per package**: each package defines its own
`check.dispatch` (a lighter gate than `mix ci` — no `agents.check`, since
harness writes an ephemeral `AGENTS.md` preamble into the reviewer worktree
that would always read as drift; no `deps.audit.gated`, whose shared advisory
clone breaks under concurrent worktrees; no cold-PLT dialyzer or coverage
pass). The project's registered `check_command` says exactly that: run
`cd packages/<name> && mix check.dispatch` for each package the task touches.
The root `mix.exs` also defines `check.dispatch` — as a **loud failure** that
prints this instruction and exits nonzero, so a reviewer that runs it at the
root gets guidance instead of a silent "task not found" or a cheap green.

---

## Health & publish tooling

Both scripts are monorepo-aware (adapted 2026-08-27). They map the 8 packages
to `packages/<name>/` and the three external repos (descripex, zen_websocket,
mpp) to `~/_DATA/code/<name>`; root location overridable via
`ONCHAIN_STACK_DIR`.

- `fleet-health.sh` — one table: git state, toolchain pin, `mix hex.outdated`,
  `mix hex.audit`, `mix deps.audit`, open GitHub issues/PRs/Dependabot alerts.
  Read-only, no writes. The `onchain-stack` row owns git/fetch/toolchain/GitHub
  for the whole monorepo; the 8 indented package rows own the per-package
  hex/audit columns plus path-scoped dirty (their shared cells render `-`, not
  8 repeated numbers). It has no CI column (an absent gate must not read as a
  passing one) and never fails on outdated deps or a dirty tree — normal
  working state.
- `publish-prep.sh status` / `publish-prep.sh check <pkg> [--integration]` —
  local-vs-Hex version delta, and the deterministic pre-publish gauntlet
  (clean tree → version delta → deps.get → hex.audit → compile -Werror →
  tests → CHANGELOG → `hex.build` dry-run). For the 8 in-repo packages the
  whole gauntlet runs under `ONCHAIN_PUBLISH=1`, restores the package's
  `mix.lock` on exit, hard-fails on the Hex "excluded from the package"
  phrase, and positively checks that every declared `sibling/2` appears in
  `mix.lock` as a `{:hex, …}` entry. **Never publishes** — `mix hex.publish`
  (2FA) stays a human step, always.

**"Is everything up to date?" has two independent axes — answer both:**
release parity (local `@version` vs Hex, from `publish-prep.sh status`) and
dependency currency (`fleet-health.sh`'s OUTDATED column, `possible`/`blocked`).
A package can sit at perfect Hex parity while its own gate runs a year-old
analyzer; a green publish-parity report says nothing about that.

### Publish workflow (per package)

1. `cd packages/<name>` — work happens inside the package directory.
2. Confirm no one else is mid-edit in this package (see "Another session may
   be working in this repo" below) — the monorepo makes this collision
   *more* likely than the standalone era, not less, because everyone now
   shares one `.git`.
3. `git fetch && git status` — clean tree; note local-vs-Hex version delta.
4. Set `ONCHAIN_PUBLISH=1`, `mix deps.get` to pull the freshly published
   upstream (or confirm sibling/3 already resolves it in Hex mode).
5. Compile + full suite (incl. integration where the package has it). Green
   is the gate.
6. Bump `@version`/`version:` per semver against the **published** baseline,
   not the local tree.
7. Update `CHANGELOG.md` (and `README.md`/`SKILL.md` if surface changed).
8. Commit path-scoped to `packages/<name>/...`, push.
9. **Hand off to the human:** state the exact `mix hex.publish` command
   (run from inside `packages/<name>`) and that 2FA is required. Do **not**
   run it yourself.
10. After the human confirms, `mix hex.info <pkg>` should show the new
    version before starting the next downstream package.
11. Tag: `git tag -a <pkg>-v<ver> -m "<pkg> <ver>"`, pushed separately, by the
    human, after the publish. A missing tag says nothing about whether a
    version shipped — tags lag, they don't gate.

---

## After every task

Applies uniformly across all eight packages now that the roadmap is
root-owned — update all affected docs as part of the task, not as a
follow-up:

- **`roadmap/tasks.toml`** (root, via the `tasks:rmap` skill / `rmap`
  CLI) — mark status, not a hand-edit of the rendered `ROADMAP.md`.
- **`packages/<name>/CHANGELOG.md`** — add an entry under the latest
  `[Unreleased]`/version section for whichever package the task touched.
- **`packages/<name>/README.md`** — update if the task changed public
  modules or user-facing behavior.
- **This file or the touched package's `CLAUDE.md`** — update Module
  Layout if files were added/removed/renamed; update architecture notes if
  conventions changed.

Reviewers: reject a task as incomplete if these weren't touched where the
change warrants it.

## Operating rules

- **Verify live; the local tree can be ahead of Hex.** Read the package's own
  `mix.exs` *and* `mix hex.info <pkg>` / `mix hex.outdated` before any cascade
  decision — never trust a dated snapshot in this file or anywhere else.
- **Stage path-scoped.** Never `git add -A` / `git commit -a` — with one
  shared `.git` across all eight packages plus the root, this matters even
  more than it did in the standalone era. Stage explicit paths; verify
  `git diff --cached --name-only` before committing.
- **Another session may be working in the same package (or a different one)
  in this same repo — check before you stage.** `git add` of a path you
  edited also stages **anyone else's** uncommitted edits to that same path;
  "stage path-scoped" alone does not protect you if the paths collide.
  Before staging:
  ```bash
  git log --since='2 hours ago' --oneline   # commits you did not make
  git status --short                        # files you did not touch
  ```
  If either shows work that isn't yours, stop and leave it alone — do not
  commit, do not `reset --hard`, do not "tidy." Recovering a commit that
  swept up someone else's WIP is `git reset --soft HEAD~1 && git reset`,
  which restores their files unstaged and intact; anything harder risks
  their work.
- **No Co-Authored-By footers.** Title-only commit messages (`<scope>:
  <description>`).
- **Publish is human-gated (2FA), always.** Your terminal state is
  *publish-ready* — green suite, bumped version, updated CHANGELOG, committed,
  pushed. Never assume a package is on Hex because the local tree looks done.
- **Never edit anything under any package's `deps/`.** See the reach #36
  adjudication above for why this specifically matters here: a hand-patched
  dependency makes `mix ci` pass locally with nothing left in the world to
  disagree, now that there's no CI runner to catch the divergence on a fresh
  clone.
- **`mix.lock` is committed per package** — see the durable release rule
  above for why.
- **Local cross-package dev needs no path-dep juggling any more** — the
  sibling/3 mechanism's path branch *is* the local-dev story; there is no
  separate `only: [:dev, :test]` path-dep convention left to reach for. If you
  ever see a raw `{:dep, path: "../dep"}` in a package's `deps()` for an
  in-family sibling instead of a `sibling/2,3` call, that's drift from before
  the mechanism existed.

---

## Open items

- **The `.sobelow-skips` drift check has no replacement.** A workflow used to
  run `--mark-skip-all` into a scratch copy and diff it against the committed
  file, failing on stale fingerprints; it was removed with the other GitHub
  Actions workflows and never rebuilt as a `mix ci`/`precommit.full` step. The
  mechanism needs nothing but a scratch dir, `--mark-skip-all`, and a `diff`
  — no runner required. Owed to every package still carrying a skips file
  (hieroglyph, cartouche, onchain, onchain_evm).
- **No package or the root tests a fresh dependency resolution.** Nothing
  runs `deps.unlock --all` against a scratch clone, so a bound that has
  stopped holding is invisible until a consumer trips on it. This is a
  natural growth point for `fleet-health.sh` once it's updated for the
  monorepo layout (a scratch-clone write-ish mode, never the working tree).
- **`--summary-only` on `test.json --cover` hides both the failure identity
  and disqualifies the automatic flaky-retry** in whichever packages still
  carry that flag in their `precommit.full` — check each package's own
  `CLAUDE.md`/`mix.exs` for current status; it was being dropped
  package-by-package in the standalone era and that migration's completeness
  across all eight has not been re-verified since the merge.
