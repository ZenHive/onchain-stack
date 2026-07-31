# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## v0.2.0 — first Hex release; descripex 0.11 / onchain 0.11 line

**This is the first release published to Hex.** v0.1.0 and v0.1.1 exist only as
repository history — `hex.pm/packages/onchain_js` had no release before this one.

No onchain_js code changes. Compiles clean under `--warnings-as-errors`, offline
tests green against the new dependency chain.

### Changed — dependency floors state the real requirement

- `{:onchain, "~> 0.8"}` → `{:onchain, "~> 0.11"}`. onchain 0.11.0 is the
  release that carries `cartouche ~> 0.6`, which lifts cartouche's transitive
  `req < 0.7` cap. A lower bound would merely *permit* 0.11.0 rather than
  *require* it, and a consumer holding an existing lock on an older onchain
  would keep resolving cartouche 0.5.x — and therefore req 0.6.x — indefinitely,
  because a lock entry that still satisfies its bound is never re-resolved.
- `{:descripex, "~> 0.9"}` → `{:descripex, "~> 0.11"}`, matching what cartouche
  0.6 already forces.
- Dev/test bounds brought in line with what actually resolves:
  `reach ~> 2.2` → `~> 2.8`, `ex_ast ~> 0.5` → `~> 0.12`, `ex_dna ~> 1.3` → `~> 1.5`.

Resolves to onchain 0.11.0, cartouche 0.6.0, descripex 0.11.0, req 0.7.1,
quickbeam 0.10.20, npm 0.7.6, reach 2.8.2.

> An earlier draft of this entry claimed descripex 0.11.0 was "held back,
> capped at 0.9.1 by transitive `cartouche ~> 0.9.1`". That hold does not apply
> to this dependency chain — cartouche 0.6.0 declares `descripex ~> 0.11`. The
> claim is removed rather than corrected in place, since nothing was ever
> published under it.

### Added — `.reach.exs` architecture policy

`reach` was a declared dev/test dependency with no policy file, so
`mix reach.check --arch` aborted with "No .reach.exs architecture policy found".
Added a permissive policy; `--arch` now passes.

`mix reach.check --smells` still fails here, but on an upstream defect rather
than a finding: the QuickBEAM plugin auto-activates (quickbeam is a dependency)
and splices JavaScript nodes into the graph, and reach 2.8.2's
`Reach.Evidence.NilParameter.function_id/1` assumes every node carries a
`:module` key, raising `KeyError` on `language: :javascript` nodes. Reported
upstream; `--arch` is unaffected.

### Dependency refresh (carried over from the v0.1.1 holds)

- `npm` 0.6.1 → 0.7.6 (mix.exs `~> 0.6.0` → `~> 0.7`), `quickbeam` 0.10.9 → 0.10.20,
  `oxc` 0.12.1 → 0.15.1 — quickbeam requires `npm ~> 0.7` / `oxc ~> 0.15`, so all
  three move together.
- `tidewave` 0.5.6 → 0.6.0 (mix.exs `~> 0.5.0` → `~> 0.6`), `bandit` 1.11.0 → 1.12.0,
  `thousand_island` 1.4.3 → 1.5.0, `plug` 1.19.1 → 1.19.2.
- `reach` 2.2.0 → 2.8.2, `ex_ast` 0.11.0 → 0.12.10, `ex_dna` 1.5.1 → 1.5.4,
  `ex_unit_json` 0.4.3 → 0.6.0, `credo` 1.7.18 → 1.7.19, `dialyzer_json` 0.2.0 → 0.2.1,
  `ex_doc` 0.40.1 → 0.40.3.

Note: `reach` / `ex_dna` / `dialyzer_json` advertise `~> 1.19` Elixir; they
compile and run on 1.18.4 with a dependency-requirement warning (dev/test-only
tooling).

## v0.1.1 — Dependency updates

Refreshed dependencies within constraints. Notable bumps:
- `onchain` 0.5.3 → 0.5.4 (core upstream; pulls `cartouche ~> 0.2.0`)
- `reach` 2.2.0 → 2.7.1, `ex_ast` 0.11.0 → 0.12.0, `ex_unit_json` 0.4.3 → 0.5.0
- `req` 0.5.17 → 0.6.1, `finch` 0.21.0 → 0.22.0, `mint` 1.7.1 → 1.9.0
- `bandit` 1.11.0 → 1.12.0, `thousand_island` 1.4.3 → 1.5.0, `gun` 2.2.0 → 2.4.0
- `credo` 1.7.18 → 1.7.19, `ex_dna` 1.5.1 → 1.5.2, `ex_doc` 0.40.1 → 0.40.3, `dialyzer_json` 0.2.0 → 0.2.1, `oxc` 0.12.0 → 0.12.1

Held back: `descripex` 0.7.0 (capped at 0.6.0 by `onchain 0.5.4`'s `descripex ~> 0.6.0`); `npm` 0.7.4 and `quickbeam` 0.10.15 (require an `npm ~> 0.7.4` / `oxc ~> 0.15.0` coordinated bump).

---

## v0.1.0 — Project Setup

Initial project creation. Extracted JS bridge tasks from [onchain](https://github.com/ZenHive/onchain) Phase 9 into a dedicated library.

**Why:** QuickBEAM (Zig NIF) violates onchain's "pure Elixir, no native deps" principle. Following the portfolio pattern where each native runtime gets its own package (onchain_evm for Rust, onchain_js for Zig).

**What's included:**
- Project scaffold with supervision tree
- Dependencies: onchain (path), quickbeam, npm, descripex
- Dev tooling: ex_unit_json, dialyzer_json, styler, credo, dialyxir, doctor, sobelow, ex_doc
- Project documentation: CLAUDE.md, README.md, ROADMAP.md, CHANGELOG.md
- Roadmap with 7 tasks across 3 phases (migrated from onchain Phase 9)
