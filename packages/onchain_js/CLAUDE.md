# Onchain JS

@~/.claude/includes/verification-policy.md

JavaScript bridge for the onchain portfolio — run npm packages on the BEAM via QuickBEAM. No Node.js required.

<!-- Selective-load (Opus 4.8): eager floor = critical-rules + harness-workflow (this repo is
     harness-driven — the OTP dispatch→review→land loop is the active workflow). onchain-workspace
     is the harness workspace add-on (monorepo layout + sibling/3 + dependency shape), eager
     family-wide. Everything else previously imported here is skill-on-demand: the JS/Volt stack (elixir-volt, quickbeam, oxc,
     npm-ci-verify, npm-dep-analysis, npm-security-audit, reach) maps to elixir:* skills; the
     methodology/tooling set (across-instances, worktree, task-prioritization/writing,
     workflow-philosophy, web-command, elixir-setup, ex-unit-json, dialyzer-json, code-style,
     development-commands/philosophy, agent-economy) to elixir / task-driver / dev-lifecycle plugins.
     These are niche custom Hex packages — re-add a specific @-import (e.g. quickbeam/oxc) only if
     Opus visibly guesses its API wrong. See ~/.claude/setup-guide.md § "Elixir + JS/TS on the BEAM". -->
@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-guardrails.md
@~/.claude/includes/onchain-workspace.md

See the root `CLAUDE.md` for the family layout, the sibling/3 mechanism, and
the shared gate adjudications (reach #36 — resolved upstream in reach 2.8.3;
this package's `--arch`-only workaround is gone, see below — cowlib/gun,
sobelow). This file carries only what's specific to this package.

## Toolchain & check commands (read before judging a build)

Full post-merge QA: **`mix ci`** (= `mix precommit.full`), same shape as every
other package (root `CLAUDE.md` § Gates), with these package-specific notes:

- **Gate flag is `reach.check --dead-code --arch --smells`**, as in every
  package except onchain, whose dead-code pass times out (see root `CLAUDE.md`
  § Adjudicated findings). It spent 2026-08 to
  2026-09 on `--arch` only, because reach ≤ 2.8.2 crashed its whole smell pass
  on the JavaScript nodes the QuickBEAM plugin contributes (`source: nil`, and
  `plugins:` is not a `.reach.exs` key, so there was nothing to exclude).
  elixir-vibe/reach#36 was fixed in 2.8.3 and the workaround was removed on
  2026-09-16 under 2.8.4 — verified by running it, not by reading the
  CHANGELOG: Architecture Policy OK, Dead Code (none), no smell issues, exit 0.
  `.reach.exs` still sets `smells: [strict: true]`, which is what makes the
  pass actually gate rather than print-and-exit-0.
- Coverage floor is **25%** against a 27.78% measured baseline (2026-08-01) —
  this package's `lib/` surface is a thin 4-module QuickBEAM bridge; most
  behavior is only exercised by the (excluded-by-default) `:integration`
  tests, which need a live QuickBEAM runtime.
- **Cold compiles are slow: this package builds Zig NIFs (QuickBEAM).**
  Budget generous time for a fresh `mix deps.get && mix compile` or a
  cold-PLT `mix dialyzer` and do not kill it early.
- `deps.audit.gated` runs against `.mix_audit_ignore` (symlinked from the
  root file — see root `CLAUDE.md` § Adjudicated findings).

## Portfolio Context

This package is part of the family portfolio (root `CLAUDE.md` § Layout).
The dependency-relevant slice:

```
onchain (pure Elixir)
    ↑
onchain_js (Zig NIFs — QuickBEAM, npm)    onchain_aave (pure Elixir)
    ↑
onchain_evm (Rust NIFs — can use onchain_js for solc-js)
```

**Where does this feature go?**

1. Core Ethereum (RPC, ABI, signing, token reads/writes) → **onchain**
2. Aave V3 protocol operations → **onchain_aave**
3. EVM simulation, Solidity parsing, trace → **onchain_evm**
4. Run npm packages on the BEAM (solc-js, Uniswap SDK, DeFiSaver, merkletreejs) → **onchain_js** (this package)

## Architecture

- **QuickBEAM** — Zig NIF embedding QuickJS-NG. Each runtime is a GenServer with persistent JS context.
- **npm_ex** — Pure Elixir npm package management. Installs to `node_modules/`.
- **onchain** — Used for RPC/ABI when JS libraries need on-chain data (`sibling(:onchain, ...)`).
- **descripex** — Self-describing APIs via `api()` macro.
- Supervision tree manages JS runtime lifecycle.
- Standard error tuples: `{:ok, result} | {:error, {:tag, reason}}`

## Module Layout

```
lib/
  onchain_js.ex                   # Root module + Descripex.Discoverable (describe/0,1,2)
  onchain_js/
    application.ex                # Supervision tree
    runtime.ex                    # QuickBEAM runtime wrapper, Descripex-annotated
    runtime_supervisor.ex         # DynamicSupervisor for runtimes
    script.ex                     # Bundle entry script + npm imports, load into a runtime
package.json, npm.lock            # npm_ex manifest + lock (committed; test-only deps)
test/support/js/                  # Entry scripts used by script_test.exs
```

Every public function in an agent-facing module carries a `Descripex` `api()`
declaration, and the module is registered in `OnchainJs`'s `Discoverable` list
and in `@annotated` in `test/onchain_js/descripex_test.exs` — those contract
tests fail if a new public function lands without one.

## npm packages

- Install at build time only: `mix npm.install <pkg>@<range>` edits
  `package.json` and `npm.lock`; `mix npm.ci` reproduces `node_modules/`
  (gitignored) at the locked versions. npm_ex 0.7.6's frozen check compares
  package names only, not ranges: after editing a range in `package.json`,
  run `mix npm.update <pkg>` (plain `mix npm.install` says "Already up to
  date") and commit the lock. No public function may
  install at runtime.
- Entry scripts import from npm and assign callables to `globalThis`;
  `OnchainJs.Script.load/3` stubs browser globals, bundles, and evaluates.
  `Runtime.start_link(script:)` runs before stubs can be applied, so prefer
  `load/3` for browser bundles.
- Bare imports resolve only by Node-style ancestor walk from each importer.
  QuickBEAM 0.11.3's `:node_modules` bundler option changes labels, not
  resolution, so `OnchainJs.Script` rejects it; releases put entry scripts
  below the directory holding `node_modules/` (e.g. `priv/js/` + `priv/node_modules/`).
- Neither the manifest nor `node_modules/` ships to Hex; consumers supply
  their own (README "Loading npm packages").

## Testing

- Unit tests for pure functions
- Integration tests are **excluded by default** (`ExUnit.start(exclude: [:integration])` in test_helper.exs)
- `mix test.json --quiet` runs only unit tests
- Integration tests tagged `@tag :integration` require QuickBEAM runtime;
  `script_test.exs` also needs `mix npm.ci` first

### Quick Commands

```bash
mix test.json --quiet                          # Unit tests only
mix test.json --quiet --failed --first-failure # Iterate on failures
mix test.json --quiet --include integration    # Unit + integration tests
mix dialyzer.json --quiet                      # AI-friendly dialyzer output
mix credo --strict --format json               # Static analysis
```

## Related Packages

- **onchain** — Core Ethereum: `sibling(:onchain, ...)`
- **onchain_aave** — Aave V3 wrappers: `sibling(:onchain_aave, ...)`
- **onchain_evm** — Rust NIFs + codegen: `sibling(:onchain_evm, ...)`
