# Onchain Stack — Monorepo

@~/.claude/includes/verification-policy.md

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
- onchain → `sibling(:cartouche, ...)`, `descripex ~> ...`, `zen_websocket ~> 0.9.0`
- onchain_aerodrome → `sibling(:onchain, ...)`, `descripex ~> ...`, plus a
  dev/test-only `sibling(:onchain_evm, "~> 0.6", only: [:dev, :test])` — ABI
  parsing, codegen and pinned Base fork simulation (with the Base hardfork
  schedule and fork chain identity preserved)
- onchain_evm / onchain_js → `sibling(:onchain, ...)`, `descripex ~> ...`
- onchain_tempo → `sibling(:onchain, ...)`, `sibling(:cartouche, ...)`,
  `descripex ~> ...`
- onchain_aave → `sibling(:onchain, ...)`, `descripex ~> ...`, plus a
  dev/test-only `sibling(:onchain_evm, "~> 0.6", only: [:dev, :test])` — **a
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
package's `CLAUDE.md`). `cd packages/<name> && mix ci` for full post-merge QA; that
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
of eight near-identical copies. There is no per-package override left: all
eight `packages/<name>/.credo.exs` are symlinks to the root `.credo.exs`, so
editing the root policy is the only way to change any package's credo rules.

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
Check scheduling follows the imported verification policy; the commands above
describe the available QA entry points. Dependabot still opens bump PRs (it
reads the dependency graph, not a workflow run), but nothing grades them
automatically.

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

**`reach`'s `--smells` crash on non-Elixir AST nodes (elixir-vibe/reach#36) is
fixed upstream in 2.8.3 — the onchain_js workaround is gone.** Up to `reach
2.8.2`, `Reach.Evidence.NilParameter`/`ParameterShape` read
`function.meta.module` with dot access, so a node with no `:module` — generated
Erlang, or a plugin-contributed JS node — raised and took the **entire smell
pass** down before reporting a single finding. 2.8.3's CHANGELOG records
"Smell evidence now handles functions without module metadata instead of
crashing during analysis"; both sites now use `function.meta[:module]`. What
remains:

- **hieroglyph** still scopes `.reach.exs` to
  `source_paths: ["lib", "test/support"]`. That is **not** a #36 workaround and
  should stay: a smell in yecc/leex-generated Erlang under `src/` is unfixable
  by definition, so the scope is right regardless of the bug.
- **onchain_js** ran `reach.check --arch` **only** for the same crash (JS nodes
  the QuickBEAM plugin contributes carry `source: nil`, and `plugins:` is not a
  `.reach.exs` key, so there was nothing to exclude). Restored 2026-09-16 under
  reach 2.8.4, verified green by running it.

**`--dead-code` is on in seven of eight packages; cartouche is the exception.**
The gate flag is `reach.check --dead-code --arch --smells` everywhere except
cartouche, which runs `--arch --smells`.

- **cartouche cannot run `--dead-code` at all.** At 67 files in scope
  (`lib, sol/src, src, test/support`) the pass dies with
  `** (exit) exited in: Task.Supervised.stream(30000) ** (EXIT) time out` from
  `Reach.CLI.Pipe.safely/1`, after Architecture Policy has already printed OK.
  It is a reach-side timeout on the largest package in the family, not a
  finding. Do not "fix" it by narrowing `.reach.exs` scope — that would hide
  real analysis to satisfy a tool limit. Re-test the flag after any reach
  upgrade.
- **The reach 2.8.4 bump turned three gates red before the flag was added, and
  they were repaired rather than suppressed.** 2.8.4 ships smell detectors
  2.8.2 did not ("Repeated map shapes", "bare rescue", "Suboptimal patterns",
  "trivial forwarder"), so `51bc9f5` red-lit onchain_aave, onchain_aerodrome
  and onchain_tempo on pre-existing `test/support/` code nobody had touched.
  Fixed 2026-09-16: the two 11×-repeated map shapes became real structs
  (`Onchain.Aave.MathMutator.Site`, `Onchain.Tempo.Verification.Campaign.Mutant`),
  the trivial `flatten/1` forwarder was deleted, `Enum.at/2`-in-a-loop became
  `Enum.zip/2`, `String.split/2 |> hd/1` gained `parts: 2`, and a `receive`
  result is bound so `flunk/1`'s value is used. **Nothing was added to any
  `.reach.exs` ignore list.**
- **Both bare rescues became `catch kind, reason`, which is a fix and not a
  rename.** Both sites run deliberately-broken code — a mutated arithmetic
  expression, a recompiled mutated module — where every failure mode is a
  result to record. `rescue` catches only raises, so a mutant that exits or
  throws would have escaped and aborted the campaign; `catch` records it. If
  you ever see a bare `rescue` reintroduced there, it is a regression in
  behaviour, not just in style.


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

<<<<<<< Updated upstream
The alias inventory is **per package**: every package's `check.dispatch`
runs `format --check-formatted` and `compile --warnings-as-errors` only.
Invoke it with `cd packages/<name> && mix check.dispatch` for each touched
package; test and risk-check selection follows the imported verification policy.
Each package's `ci` → `precommit.full` retains its complete QA graph,
independent of `check.dispatch`. The root full-QA command is `mix ci`;
it checks bounds and runs every package's QA serially.

Aerodrome's full-QA test command prepends `$HOME/.foundry/bin` to PATH for
the independent calldata tests. Focused tests that use Foundry `cast` also
need that directory on PATH; missing cast fails with installation instructions.

The alias regression check is `elixir test/alias_separation_test.exs`
(no package dependency bootstrap). Its baseline fixture records the pre-change
alias graph; it checks the expanded full-QA graph and the root dispatch guard.

||||||| Stash base
The dispatch-scale gate is **per package**: every package's `check.dispatch`
runs its offline test suite as well as static checks. Aerodrome requires
Foundry `cast` for independent calldata tests; its dispatch test command prepends
`$HOME/.foundry/bin` to PATH (the standard Foundry installation directory).
Verified on `blockwatch-harness`: `~/.foundry/bin/cast` version 1.8.3 is installed;
the service PATH alone does not include it. Missing cast fails with installation
instructions. Each package defines its own
`check.dispatch` (a lighter gate than `mix ci` — no `agents.check`, since
harness writes an ephemeral `AGENTS.md` preamble into the reviewer worktree
that would always read as drift; no `deps.audit.gated`, whose shared advisory
clone breaks under concurrent worktrees; no cold-PLT dialyzer or coverage
pass). The project's registered `check_command` says exactly that: run
`cd packages/<name> && mix check.dispatch` for each package the task touches.
=======
The existing alias inventory is **per package**: every package's `check.dispatch`
runs its offline test suite as well as static checks. Aerodrome requires
Foundry `cast` for independent calldata tests; its dispatch test command prepends
`$HOME/.foundry/bin` to PATH (the standard Foundry installation directory).
Verified on `blockwatch-harness`: `~/.foundry/bin/cast` version 1.8.3 is installed;
the service PATH alone does not include it. Missing cast fails with installation
instructions. Each package defines its own
`check.dispatch` (a lighter gate than `mix ci` — no `agents.check`, since
harness writes an ephemeral `AGENTS.md` preamble into the reviewer worktree
that would always read as drift; no `deps.audit.gated`, whose shared advisory
clone breaks under concurrent worktrees; no cold-PLT dialyzer or coverage
pass). The registered `check_command` names
`cd packages/<name> && mix check.dispatch`. Because it includes the complete
package suite, select explicit format/compile/focused-test commands during
implementation and review under `verification-policy.md`.
>>>>>>> Stashed changes
The root `mix.exs` also defines `check.dispatch` — as a **loud failure** that
prints this instruction and exits nonzero, so a reviewer that runs it at the
root gets guidance instead of a silent "task not found" or a cheap green.

### MCP config — two tidewave ports, and they mean different things

The root `.mcp.json` carries **two** tidewave entries:

- **`tidewave` → `localhost:4013` is cartouche's dev server, nothing broader.**
  Commit f9d6102 consolidated eight per-package `.mcp.json` files into that one
  root file; eight tidewave entries could not survive the merge (they point at
  eight different ports, one per package) and cartouche's was the copy that
  carried over. It has meant "cartouche" ever since, despite sitting at the root.
- **`tidewave_all` → `localhost:4037` is the monorepo-root aggregate**, added
  2026-09-16 (`0fb58a6`). The root `mix.exs` declares all eight packages as
  `only: :dev, override: true` path deps and runs a standalone Bandit serving
  `Tidewave` on 4037, so one `project_eval` sees all eight applications in a
  single node and can cross package boundaries in one expression.

**The eight per-package ports stay as they are — that is a decision, not an
oversight.** Each package's `mix.exs` still declares its own `tidewave` alias
(hieroglyph 4006, onchain 4007, onchain_evm 4009, onchain_tempo 4010,
onchain_aave 4012, cartouche 4013, onchain_js 4028, onchain_aerodrome 4035),
and distinct ports are the feature: eight package dev servers can run in
parallel. Converging them on one port was considered and **rejected** — the fix
for "only cartouche is reachable" is the *additive* root aggregate above, not
a reassignment. Do not "tidy" these ports into one; a 2026-09-16 session tried
exactly that and it was reverted.

What this leaves true: reaching one *specific* package's own dev server (say
onchain_evm on 4009) still means pointing `.mcp.json` at that port first. The
aggregate covers the common case — evaluating across the family — not that one.

Two residual facts, deliberately left alone rather than "tidied":

- `~/.claude/tidewave-ports.md` was reconciled with this repo on 2026-09-16:
  the seven package ports are un-retired, 4013 names cartouche rather than "all
  8 packages", and a note records that the convergence was rejected. It also
  flags one latent collision worth knowing: **4007 (onchain) is `live_debugger`'s
  default port** — harmless while onchain is a library with no Phoenix dev
  server, but any Phoenix app running alongside must pin `live_debugger` to the
  registry's `41xx` band instead of taking the default.
- Seven packages still carry `.cursor/mcp.json`, `.codex/config.toml` and
  `.grok/config.toml` (21 tracked files) pointing at their pre-merge port, and
  some at the pre-rename `harness_tidewave` server name. f9d6102 consolidated
  only the Claude Code config. The repo root did gain its own `.cursor/`,
  `.codex/` and `.grok/` in `0fb58a6`, all pointing at the 4037 aggregate — the
  21 per-package mirrors were left untouched.

Both are folded into task 9005, which owns this whole surface. Do not resolve
either by changing ports or deleting those files as a side effect of unrelated
work.

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
4. **Dep currency, before anything else ships:** `mix hex.outdated --all`
   must show no "Update possible" row (`--all` matters — a plain
   `hex.outdated` hides transitive deps). Bump, re-test, commit first if it
   does; "Update not possible" rows mean a bound caps the dep — widen it
   deliberately or document why it stays. `bin/publish-prep.sh check` hard-
   fails on this since 2026-08-27, but run the sweep at the *start* of a
   cascade, across all packages at once — not as a surprise mid-gauntlet.
5. Set `ONCHAIN_PUBLISH=1`, `mix deps.get` to pull the freshly published
   upstream (or confirm sibling/3 already resolves it in Hex mode).
6. Compile + full suite (incl. integration where the package has it). Green
   is the gate.
7. Bump `@version`/`version:` per semver against the **published** baseline,
   not the local tree.
8. Update `CHANGELOG.md` (and `README.md`/`SKILL.md` if surface changed).
9. Commit path-scoped to `packages/<name>/...`, push.
10. **Hand off to the human:** state the exact `mix hex.publish` command
   (run from inside `packages/<name>`) and that 2FA is required. Do **not**
   run it yourself.
11. After the human confirms, `mix hex.info <pkg>` should show the new
    version before starting the next downstream package.
12. Tag: `git tag -a <pkg>-v<ver> -m "<pkg> <ver>"`, pushed separately, by the
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
