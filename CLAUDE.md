# Onchain EVM

EVM simulation, Solidity parsing, debug/trace APIs, and contract codegen for Elixir via Rust NIFs. Depends on `onchain` core for RPC, ABI, signing, and address utilities.

<!-- Selective-load (Opus 4.8): eager floor = critical-rules + harness-workflow (this repo is
     harness-driven — the OTP dispatch→review→land loop is the active workflow). onchain-workspace
     is the harness workspace add-on (7-repo roster + dependency shape), eager family-wide.
     ethereum-rpc stays eager (host-specific node access, no skill mirror). Everything else previously imported
     here (across-instances, worktree, task-prioritization/writing, workflow-philosophy, web-command,
     elixir-setup, ex-unit-json, dialyzer-json, code-style, development-commands/philosophy,
     agent-economy) is skill-on-demand via the elixir / task-driver / dev-lifecycle plugins.
     Re-add an @-import per-surface only if Opus visibly degrades on it. See ~/.claude/setup-guide.md. -->
@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md
@~/.claude/includes/onchain-workspace.md
@~/.claude/includes/ethereum-rpc.md

## Delegation roster

Portfolio default — carried by `harness-workflow.md` § "Delegation roster — opus last" (`@`-imported above): assign dispatchable tasks **cursor / codex / grok first, opus only if needed** (opus tokens are precious). onchain_evm takes the family default; no project override.

## Toolchain & check commands

Self-contained so it survives into `AGENTS.md` on regen — cross-family reviewers (codex / cursor / grok) read `AGENTS.md`, not the Claude skill set.

- **Canonical gate:** `mix precommit.full` (alias `mix ci`) — the comprehensive pass the harness reviewer's `check_command` runs. Fast local loop: `mix precommit` (skips the cold-PLT dialyzer + full coverage). Both are defined in `mix.exs` aliases and pinned to `MIX_ENV=test` via `def cli`.
- `mix precommit.full` runs, in order: `compile --warnings-as-errors`, `format --check-formatted`, `credo --strict` (ignoring TODO/FIXME tags; ExSlop plugin enabled in `.credo.exs`), `doctor --raise`, `ex_dna --max-clones 0` (zero-clone budget), `reach.check --arch --smells` (policy in `.reach.exs`), `sobelow --skip`, `test.json --cover --cover-threshold 85 --exclude integration`, `dialyzer`. GitHub CI (`.github/workflows/harness.yml`) mirrors these as separate PR steps (its own coverage floor is a conservative 70%; raise as coverage climbs).
- **`mix test.json` (`ex_unit_json`) and `mix dialyzer.json` (`dialyzer_json`) emit JSON by design — this is NOT a build failure.** Parse the JSON for real failures; never flag the envelope itself. Plain `mix dialyzer` is the authoritative dialyzer check when the JSON encoder can't serialize a warning shape (it's what the gate and CI run).
- **The gate's dialyzer runs under `MIX_ENV=test`, so it compiles and analyzes `test/support/` and `:ex_unit`.** Reproduce the gate's view with `MIX_ENV=test mix dialyzer`; a clean dev-env dialyzer does not imply a clean `mix ci`.
- **Rustler NIF + `cover` incompatibility (read before touching coverage).** `cover` recompiles each instrumented module's `.beam`, which re-fires a Rustler NIF's `on_load` as an unsupported "upgrade" — so the two NIF-backed modules (`Onchain.EVM`, `Onchain.Solidity`) cannot be cover-instrumented (it fails non-deterministically by load order). Their pure-Elixir logic lives in cover-able sibling modules — `Onchain.EVM.Params` (validation + NIF-param assembly) and `Onchain.Solidity.Resolver` (import/remapping resolution) — and only the thin NIF shells are excluded via `test_coverage: [ignore_modules: …]` in `mix.exs`. A residual cosmetic "coverage data may be incomplete" warning about those two modules can surface inside the full pipeline; it does not affect the threshold (the report set is the 6 non-NIF modules, deterministically).
- **Sobelow baseline (`.sobelow-skips`, tracked).** The hook honors `mix sobelow --skip`, not inline comments. The skip set is the codegen's `String.to_atom` calls in `lib/onchain/contract/generator.ex` (it creates not-yet-defined identifiers — `to_existing_atom` is impossible) plus operator-supplied `File.read` paths in `solidity.ex` / `solidity/resolver.ex` (caller-derived `.sol` paths, not web input). Regenerate from live state with `mix sobelow --mark-skip-all` after fixing a finding or when line shifts invalidate the hashes; never hand-edit.

## Architecture

- All modules use `Onchain.*` namespace (e.g., `Onchain.EVM`) — same as when they lived in the monolith
- Rust NIFs via Rustler: `otp_app: :onchain_evm` (not `:onchain`)
- Two native crates: `native/onchain_evm/` (revm) and `native/onchain_solidity/` (Alloy + solang-parser)
- Hex dependency: `{:onchain, "~> 0.5"}`
- Standard error tuples: `{:ok, result} | {:error, {:tag, reason}}`

## Module Layout

```
lib/onchain/
  bang_helper.ex              # defbang macro: generates bang (!) wrappers for ok/error functions
  evm.ex                      # Rustler NIF: revm local EVM execution
  solidity.ex                 # Rustler NIF: Alloy-powered Solidity ABI parser
  trace.ex                    # debug/trace APIs (trace_transaction, trace_call, storage_at)
  contract/
    generator.ex              # macro: .sol → typed Elixir module at compile time
native/
  onchain_evm/                # Rust crate (revm, alloy)
  onchain_solidity/           # Rust crate (alloy-json-abi, solang-parser)
priv/
  abis/
    chainlink_aggregator.json
    aave_pool.json            # test fixture for parser tests
  contracts/
    test_interface.sol        # test fixture
    real/                     # vendored upstream Solidity for import resolution tests
```

## Dependencies from onchain core

| Module | Used for |
|--------|----------|
| `Onchain.Address` | Validation |
| `Onchain.Hex` | Hex encoding/decoding |
| `Onchain.RPC.Helpers` | Shared RPC helpers (Trace + EVM: `ensure_hex_address`, `ensure_hex_data`, `normalize_block`) |
| `Onchain.Contract` | Generic contract call (Generator runtime) |
| `Onchain.ABI` | ABI encoding (Generator runtime) |
| `Onchain.Signer` | Transaction signing (Generator runtime) |

## Testing

```bash
mix test.json --quiet                          # Unit tests only
mix test.json --quiet --include integration    # Unit + integration (requires RPC)
```

Integration tests require `ETHEREUM_API_URL` or `ETH_RPC_URL` env var.

**Note:** `priv_dir` references in tests use `:onchain_evm` (not `:onchain`).

## Related Packages

- **onchain** — Core Ethereum primitives: `{:onchain, "~> 0.5"}`
- **onchain_aave** — Aave V3 wrappers: `{:onchain_aave, "~> 0.1"}`
