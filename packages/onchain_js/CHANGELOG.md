# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## v0.3.1 — widened descripex bound (2026-08-22)

No public API or runtime behaviour changed.

### Changed

- Widened the `descripex` requirement from `~> 0.12.0` to `~> 0.12`. The
  three-segment cap turned every additive descripex minor into a forced
  nine-repo release cascade while protecting nothing in-family — `mix.lock` is
  committed, so a new descripex only ever lands through a deliberate
  `mix deps.update` behind `mix ci`.
- Resolved the refreshed family upstreams: onchain 0.13.0, descripex 0.13.0,
  cartouche 0.7.1, hieroglyph 1.6.2 and zen_websocket 0.7.1.
- Adopted `ex_ast` 0.13.1 via `override: true`, which reach 2.8.2 would
  otherwise cap at 0.12.10. Measured on onchain 2026-08-22: `mix reach.check
  --dead-code --arch --smells` produces identical output over identical scope
  under both versions.

---

## v0.3.0 — self-describing API, QuickBEAM 0.11 and dependency refresh (2026-08-18)

### Changed

- Raised the QuickBEAM requirement from `~> 0.10.4` to `~> 0.11.0`. The
  three-segment requirement deliberately caps this native 0.x dependency at
  the reviewed minor line. QuickBEAM 0.11 adds VM pinning support, Windows
  precompiled artifacts, safer native-addon initialization and promise deadline
  handling while retaining the APIs consumed by onchain_js.
- Refreshed the lock to the published family releases: onchain 0.12.1,
  cartouche 0.7.0, descripex 0.12.1, hieroglyph 1.6.1 and zen_websocket 0.6.1.
- Updated castore to 1.0.21, mint_web_socket to 1.0.6, Sobelow to 0.15.0 and
  Tidewave to 0.8.4. QuickBEAM now brings varint 1.6.0 transitively.

The dependency refresh itself carries no onchain_js public API change. All
installable dependencies are current; ex_ast remains on 0.12.x because reach
2.8.2 constrains that line.

### Added — the API is self-describing (`descripex`)

`{:descripex, "~> 0.12.0"}` was declared as a dependency and referenced nowhere
in `lib/`, while `CLAUDE.md` listed "self-describing APIs via the `api()` macro"
as part of the architecture. That gap is closed.

`OnchainJs.Runtime` now carries a `use Descripex, namespace: "/runtime"` and an
`api()` declaration for every public function (`start_link/1`, `eval/2,3`,
`call/3,4`, `stop/1`, `apply_browser_stubs/1`). The runtime handle is declared
`kind: :exchange_data` with `source: "start_link/1"` — an agent reading the
manifest can tell that the handle must be obtained before anything else is
callable, rather than guessing it is a value to supply.

`OnchainJs` gains `use Descripex.Discoverable`, so the three progressive
disclosure levels work:

    OnchainJs.describe()                  # modules and namespaces
    OnchainJs.describe(:runtime)          # function list
    OnchainJs.describe(:runtime, :eval)   # params, kinds, defaults, returns

`Descripex.Manifest.build/1` and `Descripex.MCP.tools/1` therefore cover this
package, matching how `onchain` and `onchain_tempo` already expose themselves.

### Added — contract tests so the hints cannot rot

`test/onchain_js/descripex_test.exs` asserts that every documented public
function of an annotated module has an `api()` declaration, that `:hints` reach
the BEAM doc chunk for *every* arity, that each param states a kind and a
description, that each `:exchange_data` param names its `source`, and that the
manifest/MCP surfaces build. A function added later without an `api()` fails the
suite instead of silently disappearing from `describe/2`.

Roadmap tasks 1–5 and 7 gained the same requirement as an acceptance criterion,
so each new module (`Solc`, `Uniswap`, `Merkle`, …) is annotated when it lands
rather than swept up afterwards.

Coverage moved 27.78% → 35.0% against the 25% floor.

---

## v0.2.1 — publishable tarball: 11 MB → ~40 KB, LICENSE added (2026-08-02)

No public API change and no requirement change. Both fixes are to what gets
packaged.

### Fixed — the published tarball was 11 MB of dialyzer PLT

`package/0` declared no `files`, so hex's default list shipped all of `priv/`.
`priv/` in this repo contains nothing *but* `priv/plts`, where `dialyzer/0`
pins `plt_local_path`/`plt_core_path`, and `mix hex.build` does not honour
`.gitignore`. onchain_js 0.2.0 therefore shipped eight PLT files spanning two
toolchain generations (OTP 27.3.4.11/Elixir 1.18.4 and OTP 29.0-rc3/Elixir
1.20.0-rc.4) — 11 MB of tarball wrapping ~40 KB of package.

`files` is now explicit and excludes `priv/` entirely. The Zig NIFs this
package relies on come from the `quickbeam` dependency, not from this repo, so
nothing under `priv/` belongs in the release.

Found by sweeping the stack after the same defect surfaced in onchain_aave
0.3.0 (fixed in 0.3.1). hieroglyph, onchain_tempo and cartouche were checked
and are unaffected — all three already carry an explicit `files` list.

### Fixed — README install block named an unpublishable bound

It read `{:onchain_js, "~> 0.1"}`, but 0.2.0 is the *first* release on Hex —
v0.1.0 and v0.1.1 exist only as repository history. A consumer copying that
block got a resolution failure. It now reads `~> 0.2`.

### Added — `LICENSE`

The package declared `licenses: ["MIT"]` with no license text in the repo or
the tarball. The MIT text is now present and shipped, as in `onchain`,
`onchain_evm`, `onchain_tempo` and `cartouche`.

---

## v0.2.0 — first Hex release; descripex 0.12 / onchain 0.12 line

**This is the first release published to Hex.** v0.1.0 and v0.1.1 exist only as
repository history — `hex.pm/packages/onchain_js` had no release before this one.

Compiles clean under `--warnings-as-errors`, offline tests green against the new
dependency chain.

### Changed — `{:onchain, "~> 0.8"}` → `{:onchain, "~> 0.12"}`

onchain 0.12.0 is the release that raises `zen_websocket` to `~> 0.6.0`, which
*requires* the gun version carrying the GHSA-w4f7-4cxr-rv3c fix rather than
merely permitting it. `~> 0.11` admits 0.12.0 but does not require it, so this
package's lock would have kept resolving onchain 0.11.0 → zen_websocket 0.4.2,
whose looser gun bound only happens to have landed on a fixed 2.5.0 — a lock
entry that still satisfies its bound is never re-resolved.

The lock now carries onchain 0.12.0 and zen_websocket 0.6.0. onchain 0.12.0 also
narrows `descripex` to `~> 0.12.0`, matching what this package now declares
directly (below). No code change was needed: onchain 0.12.0 makes no public API
change, and the suite is green against it.

### Changed — hieroglyph 1.6.0 in the lock, `elixir: "~> 1.17"` → `"~> 1.18"`

`mix.exs` gains no `hieroglyph` line — it arrives transitively through
onchain/cartouche, whose published bounds already admit it — but the lock now
carries 1.6.0, which restores `ABI.Event.decode_event/4`'s documented total
contract (unnamed event inputs no longer raise; an array length prefix that
cannot fit the remaining payload is rejected before the element list is
allocated) and makes `decode_structs: true` work on the event path.

The Elixir floor moves with it: hieroglyph 1.6.0's encode path uses
`Enum.sum_by/2` (1.18+), so declaring `~> 1.17` here would let this package
resolve on 1.17 and then fail compiling a dependency.

### Fixed — a typespec referencing a module that never existed

`OnchainJs.Runtime` referred to `QuickBEAM.JS.Error.t/0`. The struct module is
`QuickBEAM.JSError` — `QuickBEAM.JS.Error` has never existed at any resolved
version, so this was a plain typo rather than a stale version bound, and it made
`mix dialyzer` fail with `Unknown type`. One reference, now correct; dialyzer
reports 0 errors.

### Changed — Tidewave port 4009 → 4028

4009 is registered to `onchain_evm`. This project was using it unregistered, so
running both Tidewave servers at once collided. 4028 is now recorded in the port
registry.

### Changed — the quality gates now actually gate

- **`reach` is finally wired.** The dep was declared but no alias ever called it, and
  `reach.check --smells` raises only when `opts[:strict] || config.smells.strict`
  — so even once called it would have reported findings and exited 0.
  `.reach.exs` now sets `smells: [strict: true]`.
- **`mix_audit` added and wired.** `deps.audit.gated` proves the advisory
  database is current *before* auditing — `mix_audit` discards its own sync exit
  status (mirego/mix_audit#61), so a database that can no longer sync still
  prints "No vulnerabilities found" and exits 0.
- **The CI coverage floor was fiction.** It asserted 85% against 27.78% actual,
  so it could never pass. Set to 25, below the measured value, and ratcheted
  upward as real coverage grows — a floor above actual coverage enforces nothing.
- **`agents.check`** fails when `AGENTS.md` has drifted from `CLAUDE.md`.
- **CI invokes `mix ci`** instead of a hand-maintained check list.
- **MCP config added for all four agent families** — this project had none at
  all, in any family.

### Changed — dependency floors state the real requirement

- `{:onchain, "~> 0.8"}` → `{:onchain, "~> 0.12"}` — see the dedicated section
  above for why the bound must *require* rather than merely permit it.
- `{:descripex, "~> 0.9"}` → `{:descripex, "~> 0.12.0"}`. Three-segment on
  purpose (`>= 0.12.0 and < 0.13.0`): descripex 0.12.0 changed `short_name` in
  `describe/1` output from an atom to a string — a consumer-visible contract
  change shipped at a *minor* bump — so a two-segment bound would absorb the
  next one silently. onchain_js does not read `short_name`; the suite is green
  against 0.12.0 with no code change.
- Dev/test bounds brought in line with what actually resolves:
  `reach ~> 2.2` → `~> 2.8`, `ex_ast ~> 0.5` → `~> 0.12`, `ex_dna ~> 1.3` → `~> 1.5`.

Resolves to onchain 0.12.0, cartouche 0.6.1, descripex 0.12.0, zen_websocket
0.6.0, req 0.7.2, quickbeam 0.10.20, npm 0.7.6, reach 2.8.2.

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
