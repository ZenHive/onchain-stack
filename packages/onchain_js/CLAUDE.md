# Onchain JS

JavaScript bridge for the onchain portfolio — run npm packages on the BEAM via QuickBEAM. No Node.js required.

<!-- Selective-load (Opus 4.8): eager floor = critical-rules + harness-workflow (this repo is
     harness-driven — the OTP dispatch→review→land loop is the active workflow). onchain-workspace
     is the harness workspace add-on (7-repo roster + dependency shape), eager family-wide.
     Everything else previously imported here is skill-on-demand: the JS/Volt stack (elixir-volt, quickbeam, oxc,
     npm-ci-verify, npm-dep-analysis, npm-security-audit, reach) maps to elixir:* skills; the
     methodology/tooling set (across-instances, worktree, task-prioritization/writing,
     workflow-philosophy, web-command, elixir-setup, ex-unit-json, dialyzer-json, code-style,
     development-commands/philosophy, agent-economy) to elixir / task-driver / dev-lifecycle plugins.
     These are niche custom Hex packages — re-add a specific @-import (e.g. quickbeam/oxc) only if
     Opus visibly guesses its API wrong. See ~/.claude/setup-guide.md § "Elixir + JS/TS on the BEAM". -->
@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md
@~/.claude/includes/onchain-workspace.md

## Toolchain & check commands (read before judging a build)

Cross-family harness reviewers read **AGENTS.md** (auto-generated from this file), not the user's Claude skills. **`mix ci`** (= `mix precommit.full`) is the canonical gate — run it before judging a build green or red. It chains: `compile --warnings-as-errors`, `format --check-formatted`, `credo --strict`, `doctor --raise`, `ex_dna --max-clones 0`, `reach.check --arch --smells`, `sobelow --skip`, `deps.audit.gated`, `test.json --cover --cover-threshold 25 --exclude integration`, `dialyzer`, `agents.check`. `mix precommit` is the fast local loop (no dialyzer, no coverage).

- `mix reach.check --arch --smells` gates from `.reach.exs` (`smells: [strict: true]`). Smell findings must be **fixed, never added to an ignore list**.
- `deps.audit.gated` proves the local advisory mirror is fresh (`bin/advisory-freshness.sh` in the onchain-stack coordination home) before running `deps.audit --ignore-file .mix_audit_ignore` — `mix_audit` silently discards its own sync failure, so a stale mirror would otherwise report false-green.
- `agents.check` fails when `AGENTS.md` has drifted from this file (`sync-agents-md.sh --check`).
- **`mix test.json` (`ex_unit_json`) and `mix dialyzer.json` (`dialyzer_json`) emit JSON by design** — parse for real failures, never flag the JSON envelope itself as a build error. When `dialyzer.json`'s encoder can't serialize a warning shape, plain `mix dialyzer` is the authoritative check.
- Coverage floor is 25% against a 27.78% measured baseline (2026-08-01) — this repo's `lib/` surface is a thin 4-module QuickBEAM bridge; most behavior is only exercised by the (excluded-by-default) `:integration` tests, which need a live QuickBEAM runtime.
- Cold compiles are slow: this repo builds Zig NIFs (QuickBEAM). Budget generous time for a fresh `mix deps.get && mix compile` or a cold-PLT `mix dialyzer` and do not kill it early.

## Portfolio Context

This repo is part of a four-library portfolio. Each native runtime gets its own package.

- **onchain** — core Ethereum primitives, RPC, ABI, signing (pure Elixir, no native deps)
- **onchain_aave** — Aave V3 protocol wrappers (depends on onchain, pure Elixir)
- **onchain_evm** — Rust NIFs: revm simulation, Solidity parsing, debug/trace, codegen (depends on onchain + Rustler)
- **onchain_js** (this repo) — JS bridge: npm packages on the BEAM via QuickBEAM (depends on onchain + Zig NIFs)

**Dependency graph:**
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
4. Run npm packages on the BEAM (solc-js, Uniswap SDK, DeFiSaver, merkletreejs) → **onchain_js** (this repo)

## Architecture

- **QuickBEAM** — Zig NIF embedding QuickJS-NG. Each runtime is a GenServer with persistent JS context.
- **npm_ex** — Pure Elixir npm package management. Installs to `node_modules/`.
- **onchain** — Used for RPC/ABI when JS libraries need on-chain data.
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
```

Every public function in an agent-facing module carries a `Descripex` `api()`
declaration, and the module is registered in `OnchainJs`'s `Discoverable` list
and in `@annotated` in `test/onchain_js/descripex_test.exs` — those contract
tests fail if a new public function lands without one.

## After Every Task

Update **all affected `.md` files** after completing any roadmap task.

- **ROADMAP.md** — Mark status (⬜ → ✅), update Current Focus section
- **CHANGELOG.md** — Add entry under latest section with what was done
- **README.md** — Update if new modules, changed APIs, or user-facing functionality
- **CLAUDE.md** — Update Module Layout if files were added/removed/renamed

## Testing

- Unit tests for pure functions
- Integration tests are **excluded by default** (`ExUnit.start(exclude: [:integration])` in test_helper.exs)
- `mix test.json --quiet` runs only unit tests
- Integration tests tagged `@tag :integration` require QuickBEAM runtime

### Quick Commands

```bash
mix test.json --quiet                          # Unit tests only
mix test.json --quiet --failed --first-failure # Iterate on failures
mix test.json --quiet --include integration    # Unit + integration tests
mix dialyzer.json --quiet                      # AI-friendly dialyzer output
mix credo --strict --format json               # Static analysis
```

## Related Packages

- **onchain** — Core Ethereum: `{:onchain, path: "../onchain"}` (or `"~> 0.4"` from Hex)
- **onchain_aave** — Aave V3 wrappers: `{:onchain_aave, path: "../onchain_aave"}` (or `"~> 0.1"` from Hex)
- **onchain_evm** — Rust NIFs + codegen: `{:onchain_evm, path: "../onchain_evm"}` (or `"~> 0.1"` from Hex)
