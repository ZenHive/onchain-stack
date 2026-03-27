# Onchain JS

JavaScript bridge for the onchain portfolio — run npm packages on the BEAM via QuickBEAM. No Node.js required.

@~/.claude/includes/across-instances.md
@~/.claude/includes/critical-rules.md
@~/.claude/includes/skills-awareness.md
@~/.claude/includes/task-prioritization.md
@~/.claude/includes/task-writing.md
@~/.claude/includes/web-command.md
@~/.claude/includes/code-style.md
@~/.claude/includes/development-philosophy.md
@~/.claude/includes/documentation-guidelines.md
@~/.claude/includes/ai-coder-docs.md
@~/.claude/includes/workflow-philosophy.md
@~/.claude/includes/agent-economy.md
@~/.claude/includes/elixir-patterns.md
@~/.claude/includes/elixir-setup.md
@~/.claude/includes/development-commands.md
@~/.claude/includes/ex-unit-json.md
@~/.claude/includes/dialyzer-json.md
@~/.claude/includes/library-design.md
@~/.claude/includes/elixir-volt.md
@~/.claude/includes/quickbeam.md

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
  onchain_js.ex                   # Root module
  onchain_js/
    application.ex                # Supervision tree
```

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
