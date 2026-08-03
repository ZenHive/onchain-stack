# Onchain Stack — Coordination Home

This folder is a **coordination cockpit** for the onchain package family, not a
container. The repos live where they always have — `~/_DATA/code/<repo>/` — and
under Hex dependencies their on-disk location is irrelevant. You operate from
*here* to drive **cross-repo updates and Hex publish-preparation**; each repo's
own `CLAUDE.md` still governs work *inside* that repo.

**Publishing is a manual human step (Hex 2FA).** Your job ends at *publish-ready*:
green suite, bumped version, updated CHANGELOG, committed, pushed. The human runs
`mix hex.publish` and enters the 2FA code. Never assume a package is on Hex
because the local tree looks done — **verify against Hex** (see Operating Rules).

This document is self-contained on purpose: it must be readable by **any** agent
(Claude, Codex, Cursor, Grok). After editing it, regenerate `AGENTS.md` with
`~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh` (run from this folder).

---

## The family (10 managed repos — all Hex packages)

Two tiers. The **shared upstreams** (descripex, zen_websocket) are first-party and
sit at the top of the cascade, but they're consumed *beyond* this family too — a
publish there has a wider blast radius than a family-internal one. Flag that when
you release them. The **onchain family** proper is the connected dependency cascade.

**Shared upstreams** (first-party, used beyond this family):

| Repo | Path | Hex package | Local ver | Role | Native |
|---|---|---|---|---|---|
| descripex | `~/_DATA/code/descripex` | `descripex` | 0.11.0 | Discovery/`describe` protocol — gates the whole stack via version bounds | — |
| zen_websocket | `~/_DATA/code/zen_websocket` | `zen_websocket` | 0.4.3 | WebSocket client substrate (feeds `onchain`) | — |

**Onchain family** (the connected cascade):

| Repo | Path | Hex package | Local ver | Role | Native |
|---|---|---|---|---|---|
| hieroglyph | `~/_DATA/code/hieroglyph` | `hieroglyph` | 1.5.0 | ABI encode/decode (`ABI.*`) | yecc/leex |
| cartouche | `~/_DATA/code/cartouche` | `cartouche` | 0.6.0 | Substrate: signing, tx encoding, raw RPC, crypto | — |
| onchain | `~/_DATA/code/onchain` | `onchain` | 0.11.0 | Core primitives: RPC, ABI, ERC, signing | — |
| onchain_aave | `~/_DATA/code/onchain_aave` | `onchain_aave` | 0.2.1 | Aave V3 wrappers | — |
| onchain_evm | `~/_DATA/code/onchain_evm` | `onchain_evm` | 0.3.0 | EVM sim, Solidity parse, trace, codegen | Rust (Rustler) |
| onchain_js | `~/_DATA/code/onchain_js` | `onchain_js` | 0.2.0 | npm packages on the BEAM (QuickBEAM) | Zig NIFs |
| onchain_tempo | `~/_DATA/code/onchain_tempo` | `onchain_tempo` | 0.8.0 | Tempo chain primitives (0x76 tx, TIP-20) | — |
| mpp | `~/_DATA/code/mpp` | `mpp` | 0.11.0 | Top-level consumer/app | Phoenix |

> Local versions are a **dated snapshot (2026-07-31)** — they drift. Treat them as
> a starting hint, never ground truth. Always re-read each repo's `mix.exs` and
> run `mix hex.info <pkg>` before acting (Operating Rules).
>
> **Scope note:** the home stays scoped to *this* dependency cascade. Don't fold in
> the rest of zenhive — the value here is one coherent dep graph with a defined
> publish order; unrelated packages have no cascade story and would turn this doc
> into a flat list. A generic all-packages publish dashboard, if ever wanted, is a
> separate (config-driven) tool, not this cascade-narrative home.

### Every repo's default branch is `main` (aligned 2026-08-02)

All ten, plus this coordination home. **Do not assume — but the answer is now
uniformly `main`, so stop re-deriving it.** Before 2026-08-02 the family was
split 7 `development` / 3 `main`, which is what made every agent guess wrong
about a third of the time.

The split was never a convention anyone chose. **`development` spread because an
earlier automated session changed the ZenHive org's `default_repository_branch`
to `development`** — a settings change nobody asked for, which then silently
stamped itself on every repo created server-side while it stood. The local
`~/.gitconfig` carried `init.defaultBranch = development` alongside it, so
`git init`-and-push repos landed the same way (the first branch pushed becomes
GitHub's default). Two defaults, both wrong, from the same cause class.

Both are corrected: the org setting was fixed by the operator, and
`init.defaultBranch` is now `main`. Verified 2026-08-03 —
`ZenHive.default_repository_branch = main`, `inetpeople.default_repository_branch
= main`, `git config --global init.defaultBranch = main`. New repos land on
`main` whichever way they are created. GitHub's platform default has been `main`
since 2020-10-01, and Git's own builtin follows in 3.0; `development` was never
a platform default and never a decision here.

The residue is not fully reconstructible per repo — which trunk a given repo got
depended on whether it was born before or after the org flip, and hieroglyph is
a **fork** of `exthereum/abi` that simply inherited upstream's `main`. Don't
spend effort re-deriving the timeline; the answer everywhere is now `main`.

**The lesson worth keeping: an agent editing org-level or global git settings
has a blast radius measured in repos-not-yet-created.** Nothing failed at the
time it happened; the cost arrived months later as ~19 repos on the wrong trunk,
a harness registry pointing at branches that were about to be deleted, and a
fleet-wide rename. Treat `gh api -X PATCH orgs/...` and
`git config --global` as changes that need the operator's explicit go-ahead.

Renaming was cheap because **no repo has both branches** — each has exactly one
trunk. There is no `main`-is-released / `development`-is-integration model here,
and the rename did not create one. If you ever want that two-branch model, it is
a deliberate change, not a thing to reintroduce by naming a branch `development`.

The rename went through the GitHub rename API, which retargets open PRs and
leaves redirects, so old clone URLs and links keep resolving. Workflow branch
filters (`on: push/pull_request: branches:`) were updated in the same pass —
if you add a workflow, target `main`.

**The redirects do not cover everything that names a branch.** `git push` does
not follow them, so a push to the old name silently *recreates* it. The live
example was harness: its project registry still carried
`target_branch: "development"` for seven of these repos (cartouche, mpp,
onchain, onchain_aave, onchain_evm, onchain_js, onchain_tempo), all on
`landing_policy: :auto` — so the next autonomous land would have pushed
`origin/development` back into existence in each. Corrected in
`harness_dev.projects` on 2026-08-03. When renaming a branch, sweep the
consumers that *write*: orchestrator registrations, deploy configs, dashboard
links, anything holding a branch name as data rather than as a URL.

**And check whether the consumer has a second layer.** Patching
`harness_dev.projects` looked like it had failed — six of seven repos still
reported `development` after the restart — because harness keeps a *runtime
override* in `harness_settings` under the key `landing`, which
`Harness.Landing.Settings.overlay/1` applies **on top of** the registration and
wins. Only cartouche, which had no override row, showed the patched value. The
registration is the default; the override is the truth. (`SettingsStore` holds
no in-memory cache, so a write there takes effect without a restart — the
restart was never the variable.) Same shape as `.tool-versions` vs an inline
workflow pin: fixing the layer that loses changes nothing observable.

### One toolchain for all ten (aligned 2026-08-03)

```
erlang 29.0.3
elixir 1.20.2-otp-29
```

Every repo pins exactly that in its own `.tool-versions`, and every
`erlef/setup-beam` step reads **that file** via `version-file:` rather than
naming a version itself. One source of truth per repo, and the same pair in all
ten. `fleet-health.sh` declares the canonical pair in `CANON_ERLANG` /
`CANON_ELIXIR` and reds the sweep on any divergence — bumping the family means
editing those two lines *and* ten `.tool-versions` files, and the TOOLCHAIN
column is what makes a forgotten repo visible instead of silent.

**`version-file` requires `version-type: strict` beside it** — setup-beam
hard-errors with `you have to set version-type=strict if you're using
version-file` and never installs a toolchain. Both keys are needed together in
every step; the five repos converted on 2026-08-03 got `version-file` alone and
took *both* their workflows red instantly, while the five that already used the
mechanism carried `strict` and stayed green. The failure is loud, but it fires
at step two, so nothing downstream in the job ever runs and the logs look
unrelated to the toolchain.

What this replaced is worth recording, because each variant looked fine on its
own and only the cross-repo view exposed them:

- **Four repos had no `.tool-versions` at all** (descripex, zen_websocket,
  hieroglyph, onchain_aave) and inline-pinned `otp-version: "27"` /
  `elixir-version: "1.18"` in CI, while local development resolved the global
  1.20.2-otp-29. So CI graded every PR on a runtime nobody actually developed
  on. All four carried a comment proposing exactly this fix as a "recommended
  follow-up" — written, never done.
- **cartouche ran a one-entry `strategy.matrix`** pinning Elixir `1.20.1` with
  OTP `27.3`. A matrix implies multi-version coverage; with one entry it bought
  none, and the pair was one that exists nowhere else in the family. Dissolved
  to `version-file`; the job is now plain `Harness` (no branch protection
  referenced the old interpolated name).
- **onchain_js and onchain_tempo pinned 1.18.4-otp-27 deliberately**, on the
  assumption that onchain_js's NIFs needed OTP 27. They do not:
  `quickbeam` arrives as a `zigler_precompiled` artifact and `oxc` as a
  `rustler_precompiled` one, both keyed by target triple / NIF ABI 2.15 rather
  than by OTP version — nothing Zig or Rust compiles locally at all. Both NIFs
  load and execute under OTP 29, verified by running onchain_js's integration
  tests, not merely by loading them.
- **The three already-`version-file` repos still drifted** among themselves
  (onchain on 1.20.1 / erlang 29.0.2, the other two on 29.0.2). Having the
  mechanism right does not keep the values aligned; only the sweep does.

---

## Dependency graph

```
descripex ─┐                         (shared upstream)
           ↓
       hieroglyph ──→ cartouche ──→ onchain ──┬──→ onchain_aave
                                       ↑       ├──→ onchain_evm
                       zen_websocket ──┘       ├──→ onchain_js
                          (shared upstream)    └──→ onchain_tempo ──→ mpp
```

Edges as of the snapshot (verify in each `mix.exs`):

- hieroglyph → `descripex ~> 0.6`
- cartouche → `hieroglyph ~> 1.5`, `descripex ~> 0.11`
- onchain → `cartouche ~> 0.5`, `descripex ~> 0.9`, `zen_websocket ~> 0.4.2`
- onchain_evm → `onchain ~> 0.10`, `descripex ~> 0.11`
- onchain_tempo → `onchain ~> 0.10`, `descripex ~> 0.9`
- onchain_aave / onchain_js → `onchain ~> 0.8`, `descripex ~> 0.9` (the `~> 0.8` bound
  still admits 0.10, so both resolve to onchain 0.10.0 — the declared floor is just
  stale, not blocking)
- mpp → `onchain ~> 0.10`, `onchain_tempo ~> 0.7`, `descripex ~> 0.9`
- onchain_aave → `{:onchain_evm, path: "../onchain_evm", only: [:dev, :test]}` (sibling path dep — **another reason repos must not move**)

`descripex` and `zen_websocket` are roots — no first-party upstream of their own —
so a release there starts the whole cascade. Because they're consumed beyond this
family, bump them deliberately and note the wider blast radius.

---

## Release cascade rule

**Upstream-first, one published version at a time.** A change at any node ripples
*down* the graph. Publish the upstream, then `mix deps.update` and re-test each
dependent before publishing it. Never publish a dependent against an unpublished
upstream version.

Canonical order when the whole stack moves:

```
descripex ─┐
zen_websocket ─┴→ hieroglyph → cartouche → onchain → {onchain_aave, onchain_evm, onchain_js, onchain_tempo} → mpp
```

(`zen_websocket` feeds `onchain` directly, not hieroglyph — it just shares the
"publish the upstream before the dependent" rule.) The four mid-tier siblings
(aave/evm/js/tempo) are mutually independent — once `onchain` ships they can publish
in any order. `mpp` is always last (it consumes the tier above).

---

## Current cascade state (2026-08-02)

Verify before acting — this is a snapshot (`./bin/publish-prep.sh status`).

**The descripex 0.12 cascade is complete.** All ten packages are on Hex at their
local version — descripex 0.12.0, zen_websocket 0.6.0, hieroglyph 1.6.0,
cartouche 0.6.1, onchain 0.12.0, onchain_aave 0.3.0, onchain_evm 0.4.0,
onchain_js 0.2.0, onchain_tempo 0.9.0, mpp 0.12.0. Nothing awaits
`mix hex.publish`, and nothing is blocked on a first-party bound.

**Three-segment bounds for first-party 0.x deps are deliberate — but they are
scoped, not universal.** descripex 0.12.0 (`short_name` atom → string) and
zen_websocket 0.5.0/0.6.0 (narrowed runtime requirements) each shipped a
consumer-visible break at a *minor*, and a two-segment `~> 0.11` absorbs that
silently on the next resolution. So the cap-at-next-minor rule applies where the
protection is worth its cost:

- **Shared upstreams** (descripex, zen_websocket) — three-segment everywhere.
  This is where the breaks actually happened. True in all ten repos **as of
  2026-08-02**: an earlier revision of this file asserted it was already
  universal, and it was not — cartouche still declared `descripex "~> 0.12"`,
  the one two-segment bound on the very package whose 0.12.0 broke consumers.
  Now `~> 0.12.0`. A claim like this is worth re-deriving from the ten
  `mix.exs` files rather than trusting the prose.
- **mpp**, the leaf app — three-segment (`onchain ~> 0.12.0`,
  `onchain_tempo ~> 0.9.0`). Nothing consumes mpp, so the cap costs no one.
- **Intra-family libs as deps** (cartouche, onchain, onchain_tempo) —
  two-segment (`~> 0.12`, `~> 0.6`). None of the three has broken on a minor so
  far. The tradeoff either way: an over-tight bound in a published library
  propagates into strangers' dependency graphs and can cause diamond conflicts
  there, while a loose one absorbs a break silently.

Do not read this as licence to loosen a bound that is already three-segment.
And note the converse case for **third-party** deps: onchain's `ex_ast ~> 0.12`
records why three segments there were "a redundant self-cap" — reach already
caps it. Cap what can surprise you; don't cap what someone else already pinned.

Consequence of the rule where it applies: narrowing a **runtime** requirement is
itself a minor bump in the consumer — onchain 0.11.1 → 0.12.0, onchain_aave
0.2.2 → 0.3.0, onchain_evm 0.3.1 → 0.4.0, onchain_tempo 0.8.0 → 0.9.0 all moved
for exactly that reason.

**The `ex_ast` cap is a choice, not a wall.** `reach 2.8.2` declares
`ex_ast ~> 0.12.0`, so nine repos resolve 0.12.10 — but **cartouche reaches
0.13.1 via `{:ex_ast, "~> 0.13", override: true}`**, which overrides the
transitive requirement. An earlier revision of this file called 0.13.1
"unreachable in all ten repos"; that was wrong. The open question is not
*whether* the override works but whether reach still grades honestly under it:
ex_ast 0.13.0 changed pattern-matching semantics (map patterns became subset
matching) and reach's smell checks are built on those patterns. **Unmeasured
so far** — the comparison to run is the same smell corpus under 0.12.10 and
0.13.1, checking whether the finding count drops. Until that is measured, the
nine repos stay on 0.12.x and hieroglyph 1.6.0's three-segment `~> 0.12.0` pin
(with its reason recorded in-repo) is the family's documented default.

**`mix.lock` is committed in all ten repos, libraries included.** It was
gitignored in onchain, onchain_aave, onchain_evm and onchain_tempo under the
banner "consumers generate their own" — true but beside the point: Mix reads
only the *top-level* project's lock, and Hex does not ship one in the tarball,
so a library's lock never reaches a consumer either way. The entire question is
your own CI, and there committing wins:

- `mix_audit` reads `mix.lock`. Without a committed lock, `deps.audit` grades
  whatever was resolved that minute — unreproducible, and with no diff to
  review. The whole `advisory-freshness.sh` gate points at that file.
- A transitive bump shows up in a PR diff instead of landing silently.
- `git bisect` reproduces the dep set of the commit rather than today's Hex.

The cost is real and worth naming: a committed lock means CI only ever exercises
**one** resolution, so a bound that no longer holds goes unnoticed — which is
exactly how mpp sat on `onchain ~> 0.11` after 0.12.0 shipped. The mitigation is
a second CI job that resolves fresh (`mix deps.unlock --all && mix deps.get`)
and tests the newest versions the bounds admit. **Not yet added anywhere** — see
the open item below.

### The gates are real now — do not re-decorate them

Every repo gates on `mix ci` → `precommit.full`, and every repo's CI workflow
invokes that alias instead of a hand-kept checklist. Four properties are easy to
silently undo, so they are stated here:

- **`smells: [strict: true]` in `.reach.exs`.** `reach.check --smells` raises only
  when `opts[:strict] || config.smells.strict`; without it the check prints
  findings and still exits 0. Fix smell findings — never add an ignore entry.
- **`deps.audit.gated` runs `bin/advisory-freshness.sh` before `deps.audit`.**
  `mix_audit` discards its own sync exit status (mirego/mix_audit#61), so a
  database that can no longer sync still prints "No vulnerabilities found" and
  exits 0. The script asserts a clean tracked tree, proves the clone is at
  upstream tip, and falls back offline to the last *verified* sync. It
  deliberately does not gate on upstream's commit age: observed gaps between
  mirego commits reach 96 days, so a short age limit reds every consumer during
  normal quiet periods.
- **`agents.check`** fails when `AGENTS.md` has drifted from `CLAUDE.md`. It
  diffs rendered output, so drift inside a transitive `@`-import is caught too.
- **Sobelow needs `--exit low`; a bare `sobelow --skip` exits 0 with findings.**
  Same shape as the two above: the check prints, CI stays green. This was live
  in eight repos until 2026-08-02 — onchain_evm carried four findings through
  `mix ci` and out to GitHub code scanning while its alias reported success.
  Every repo now runs `sobelow --skip --exit low` (cartouche sets the equivalent
  `exit: "Low"` in `.sobelow-conf`). If you ever see a sobelow step *print*
  findings and the alias still pass, the flag has been dropped.

**Regenerate `.sobelow-skips` wholesale; never let it accumulate.** Each entry
pins `FindingType,file:line,HASH` — the line number is part of the identity, so
inserting lines *above* a suppressed finding re-reds it even though the flagged
code never changed. `--mark-skip-all` only appends, so the reflex re-run leaves
the drifted entry behind forever. The cadence: confirm every outstanding finding
(`mix sobelow --format compact`, **without** `--skip`) is a genuine false
positive, then `rm .sobelow-skips && mix sobelow --mark-skip-all`, verify zero
with `--skip`, commit. Never regenerate while an unconfirmed finding is
outstanding — that buries it. Note that Sobelow colourises `--format compact`,
so a naive `grep '^\[+\]'` matches nothing and silently reports a clean repo;
strip ANSI first.

**`.mix_audit_ignore` holds exactly one entry**, GHSA-w4f7-4cxr-rv3c, a verified
false positive for gun: the advisory covers cowboy (`< 2.16.0`) and gun
(`< 2.4.0`), but the mirror's importer groups by `ghsaId` alone, so both collapse
into one gun file carrying cowboy's range — and no cowboy file is written at all
(mirego/elixir-security-advisories#8). Any other finding is real; do not add it.
Repos that audit clean carry no ignore file and use a bare `deps.audit`.

### Propagate cartouche's `.sobelow-skips` drift check

cartouche's `harness.yml` carries a step the rest of the family lacks: it runs
`mix sobelow --mark-skip-all` into a scratch copy and diffs it against the
committed `.sobelow-skips`, failing with the diff inline when fingerprints have
gone stale. That is precisely the failure that let onchain_evm ship four
findings to GitHub code scanning while its own gate reported success. Repos
carrying a skips file — zen_websocket, onchain, onchain_evm, hieroglyph,
cartouche — should all have it. Note hieroglyph's and cartouche's skips files
currently suppress nothing at all (both are at zero findings even without
`--skip`), which is harmless but means the files are vestigial.

### reach 2.8.2 aborts `--smells` on non-Elixir nodes — never hand-patch `deps/`

`Reach.Evidence.NilParameter` and `Reach.Evidence.ParameterShape` read
`function.meta.module` with dot access at three sites. Function nodes that are
not Elixir module functions carry no `:module`, so the read raises and takes the
**entire smell pass** down before a single finding is reported — the gate fails
loudly, but what it is really doing is delivering zero smell coverage. Filed as
[elixir-vibe/reach#36](https://github.com/elixir-vibe/reach/issues/36) with the
three-line bracket-access fix; upstream is a third-party org, so the family
works around it rather than waiting:

- **hieroglyph** — the crash came from `src/`, the yecc/leex output, because
  reach analyzes `:erlc_paths` alongside `:elixirc_paths` by default.
  `.reach.exs` now sets `checks: [source_paths: ["lib", "test/support"]]`. This
  is the right scope regardless of the bug: a smell in generated Erlang is
  unfixable by definition.
- **onchain_js** — the crash comes from JavaScript nodes the QuickBEAM plugin
  contributes (`source: nil`), so there is no path to exclude, and `plugins:`
  is not a `.reach.exs` key. `mix ci` runs `reach.check --arch` **only** here,
  with `smells: [strict: true]` left in place so the gate returns the moment
  `--smells` goes back into the alias. This is the family's one repo without
  smell gating; restore it when a fixed reach ships.

**The trap this hid behind:** both repos had a *hand-edited `deps/reach`* — the
bracket fix applied directly to the unpacked hex tarball. Local `mix ci` was
therefore green while CI, which unpacks pristine, was red, and the divergence
read as "not reproducible locally." Two copies, two different patch generations,
neither visible to git. **Never edit anything under `deps/`.** To test a
candidate fix, patch it, confirm, then `mix deps.clean <dep> && mix deps.get` to
restore pristine *in the same session* — and carry the fix in `.reach.exs`, the
alias, or an override in `mix.exs`, where CI can see it.

### Open items

- **No repo tests a fresh dependency resolution.** No workflow runs
  `deps.unlock --all`, deletes `mix.lock`, or matrixes over dep versions, so a
  bound that has stopped holding is invisible until a consumer trips on it. Add
  one job per repo; see the `mix.lock` rationale above.
- **`--summary-only` hides both the failure identity and the retry.** Every
  repo's `precommit.full` runs `test.json --cover ... --summary-only`, and the
  emitted JSON then carries counts and coverage but **no failure entries** — so
  onchain_aave's run 30742057271 reports `"failed": 2` and nothing whatsoever
  about *which* two, and the only way back to the identity is to edit the alias
  and push again. Worse, the flag also disqualifies ex_unit_json's automatic
  flaky-retry (`retry_disqualified_opts?/1`,
  `deps/ex_unit_json/lib/mix/tasks/test_json.ex:654`), so a load-sensitive test
  that would have passed on its second attempt reds the gate instead. **Dropped
  in zen_websocket and onchain_aave** (the fast `precommit` alias keeps it,
  where the hooks already print detail); the remaining eight still carry it.
- **All four originally-red `Harness` gates are fixed (2026-08-03); onchain_aave
  needed a second pass.** hieroglyph and onchain_js were the reach #36 crashes
  (see below). The other two were called "flaky, not broken" — half right:
  zen_websocket's really was a race, onchain_aave's was never flaky at all:
  - **zen_websocket** — `ZenWebsocket.DebugTest` asserted `log == ""` around a
    `capture_log/1` call while running `async: true`. `capture_log` intercepts
    the **global** `:logger`, not the calling process, so under enough
    concurrency an unrelated async test's warning lands inside the capture and
    fails the assertion — reproduced at `--max-cases 32 --seed 203` with a
    `Batch subscribe failed for req_3: :not_connected` line from
    `BatchSubscriptionManagerTest`. Fixed by making that module `async: false`
    (ExUnit runs sync tests after all async ones, closing the window). Note
    this was **not** the `PoolRouter` `{:exit, _}` defect fixed in the same
    pass: that one needs a caller that traps exits, which no test here does, so
    it was unreachable from this suite — a genuine latent bug for consumers,
    but not the cause of the CI red.
  - **onchain_aave** — not a flake: `debt_token_integration_test.exs` was the
    one file of nine `*_integration_test.exs` missing `@moduletag :integration`,
    so its two Sepolia tests ran on every credential-less CI run and failed
    deterministically on `sepolia_rpc_url!/0`. It read as a flake only because
    `--summary-only` had reported `"failed": 2` with no identity for weeks.
    Dropping that flag named the file, the lines and the messages on the very
    next run — **and** re-enabled the retry, which reported
    `retried: 2, confirmed: 2, flaky: 0`, i.e. proved they were not flaky. Both
    halves of the `--summary-only` argument paid off in one run, which is the
    case for dropping it in the remaining eight repos.

    Fixing the tests then exposed a **second, older** failure that had been
    hiding behind them: `mix ci` never reached its dialyzer step while the suite
    was red, and dialyzer immediately reported five `unknown_function` errors on
    `ExUnit.Assertions.flunk/1`. The PLT simply had no `:ex_unit` —
    `plt_add_apps: [:mix]`, while `elixirc_paths(:test)` compiles `test/support`,
    so the case modules were analyzed against a PLT that did not contain the
    assertion library. cartouche, onchain and onchain_evm all carry `:ex_unit`;
    onchain_aave and onchain_tempo did not (onchain_tempo's `test/support` uses
    no ExUnit functions, so it never tripped). Fixed in `5d5be9d` — and the same
    commit deleted `.dialyzer_ignore.exs`, all 17 of whose entries reported as
    unnecessary skips, including a `~r/Function Onchain\./` catch-all that would
    have swallowed any genuine unknown_function on an Onchain call. **This is
    the general shape: a gate that fails early reports one defect and conceals
    every later step's.** Do not read "the red is fixed" as "the gate is green"
    until a full run says so.
- **mpp carries a test that has never matched its own code.**
  `test/mpp/methods/tempo_test.exs:1847` asserts
  `~r/atomic store implementing update\/3/`, but the message has read
  `check_and_mark/2 — atomic single-use is required` since `ee5ba91`
  (2026-07-08), and `update/3` is no longer in the API at all. The test arrived
  on 2026-08-01 in `ddc4686`, a harness agent delivery, and landed anyway. A
  one-line fix, but worth noting *why* it got through: this is exactly the
  failure `--summary-only` renders invisible.
- **The `ex_ast` 0.13.1 measurement** described above is still unrun.

---

## Health sweep (all repos at once)

`./bin/fleet-health.sh` answers "is anything wrong anywhere" in one table:
git state (ahead/behind/dirty), toolchain pin, `mix hex.outdated`,
`mix hex.audit` (retired), `mix deps.audit` (vulnerabilities), open GitHub
issues/PRs, and open GitHub security alerts (Dependabot + code scanning). ~20s
for all ten, four repos in parallel. `--json` for machine consumption;
`--no-fetch` / `--no-gh` / `--no-hex` / `--no-audit` to cut scope;
`./bin/fleet-health.sh <repo>...` to narrow.

TOOLCHAIN reports the *worse* of two independent divergences, because fixing
one without the other fixes nothing: `drift` / `none` means the repo's
`.tool-versions` disagrees with the canonical pair or is missing, while
`inline` means a workflow hardcodes a version — and there, correcting the pin
would never reach CI at all. A matrix-driven pin (`${{ matrix.* }}`) is
deliberate multi-version testing and is not counted as `inline`.

It is **read-only** — no `deps.get`, no writes into any repo. That is what makes
its own "dirty tree" column trustworthy.

Three things it deliberately does *not* treat as equivalent:

- **The advisory gate runs once, not per repo.** All ten audit against one
  shared mix_audit clone. If `advisory-freshness.sh` cannot prove that clone
  current, every VULN cell reads `?` and the sweep exits 1 — because a stale
  database prints "No vulnerabilities found" and exits 0 (mirego/mix_audit#61),
  so an unverified green is not a green.
- **A failed GitHub call reads `?`, never `0`.** Zero is what all-clear looks
  like; a silent 404 or rate-limit must not forge it. `0*` is a third state:
  code scanning was never enabled on that repo (currently onchain_aave), so
  ALERTS counts Dependabot only.
- **Dependabot alerts are hard; code-scanning `warning`s are not.** This org
  uploads Sobelow output to code scanning, so only high/critical (or an
  `error`-level rule) fails the sweep. onchain_evm's four SBLW warnings are
  reported in the details block and leave the exit code at 0.

Outdated deps, open issues/PRs and a dirty tree never fail the sweep — they are
normal working state. OUTDATED reads `possible/blocked`; **blocked** means
another dep caps the version (the `ex_ast ~> 0.12.0` case above), which is a
decision to make, not a bump to run.

Health is not release readiness — for local-vs-Hex deltas use `publish-prep.sh`.

## Publish workflow (per repo)

**Tooling:** `./bin/publish-prep.sh status` shows every repo's local-vs-Hex
version delta; `./bin/publish-prep.sh check <repo> [--integration]` runs the
deterministic gauntlet (clean tree → version delta → deps.get → hex.audit →
compile -Werror → tests → CHANGELOG → `hex.build` dry-run) and prints the exact
publish command. The script **never publishes** — `mix hex.publish` (2FA) is yours.

You prepare; the **human runs `mix hex.publish`** (2FA). For each repo being released:

1. `cd ~/_DATA/code/<repo>` — work happens in the repo; this home only coordinates.
2. `git fetch && git status` — clean tree; note local-vs-Hex version delta.
3. `mix deps.update <changed-upstreams>` — pull the freshly published upstream.
4. Compile + full suite (incl. integration where the repo has it). Green is the gate.
5. Bump `@version` / `version:` per semver against the **published** baseline.
6. Update `CHANGELOG.md` (and README/SKILL.md if surface changed).
7. Commit path-scoped, push.
8. **Hand off to the human:** state the exact `mix hex.publish` command and that
   2FA is required. Do **not** run it yourself.

After the human confirms the publish, `mix hex.info <pkg>` should show the new
version before you start the next downstream repo.

---

## Operating rules

- **Verify live; the local tree can be ahead of Hex.** cartouche is the proof:
  local `mix.exs` deps ≠ published deps at the same version number. Before any
  cascade decision, read the repo's `mix.exs` *and* `mix hex.info <pkg>` /
  `mix hex.outdated` — never trust the snapshot table above.
- **Repos do not move.** Location is irrelevant under Hex, and `onchain_aave`'s
  `../onchain_evm` path dep would break. This home references them by absolute path.
- **Per-repo CLAUDE.md wins inside its repo.** Those carry the toolchain, test
  commands (`mix test.json`), coverage tiers, and hook rules. This home governs
  only cross-repo ordering and publish-prep.
- **Stage path-scoped.** Never `git add -A` / `git commit -a` — the family repos
  may have parallel WIP. Stage explicit paths; verify `git diff --cached --name-only`.
- **No Co-Authored-By footers.** Title-only commit messages (`<scope>: <desc>`).
- **Publish is human-gated (2FA).** Always. Your terminal state is *publish-ready*.
- **Local cross-stack dev without Hex round-trips:** for active multi-repo work,
  a dev/test-only path dep (`{:dep, path: "../dep", only: [:dev, :test]}`, as
  onchain_aave already uses for onchain_evm) lets you build against local
  checkouts. Release/CI still resolves the pinned Hex version. Use it to avoid
  publishing just to test a downstream — but the *published* `mix.exs` must pin
  the Hex version, never a path.

---

## AGENTS.md

`AGENTS.md` (for Codex/Cursor/Grok, which don't read Claude includes/hooks) is
generated from this file. This `CLAUDE.md` is self-contained (no `@`-imports), so
the render is effectively 1:1. Regenerate after every edit:

```bash
cd ~/_DATA/code/onchain-stack
~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh          # write AGENTS.md
~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh --check  # CI freshness gate
```
