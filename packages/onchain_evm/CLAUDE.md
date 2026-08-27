# Onchain EVM

EVM simulation, Solidity parsing, debug/trace APIs, and contract codegen for Elixir via Rust NIFs. Depends on `onchain` core for RPC, ABI, signing, and address utilities.

<!-- Selective-load (Opus 4.8): eager floor = critical-rules + harness-workflow (this repo is
     harness-driven — the OTP dispatch→review→land loop is the active workflow). onchain-workspace
     is the harness workspace add-on (monorepo layout + sibling/3 + dependency shape), eager
     family-wide. ethereum-rpc stays eager (host-specific node access, no skill mirror). Everything
     else previously imported here (across-instances, worktree, task-prioritization/writing,
     workflow-philosophy, web-command, elixir-setup, ex-unit-json, dialyzer-json, code-style,
     development-commands/philosophy, agent-economy) is skill-on-demand via the elixir / task-driver
     / dev-lifecycle plugins. Re-add an @-import per-surface only if Opus visibly degrades on it.
     See ~/.claude/setup-guide.md. -->
@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md
@~/.claude/includes/onchain-workspace.md
@~/.claude/includes/ethereum-rpc.md
@~/.claude/includes/node-portability.md

See the root `CLAUDE.md` for the family layout, the sibling/3 mechanism, and
the shared gate adjudications (reach #36, cowlib/gun, sobelow). This file
carries only what's specific to this package — the one with native Rust
builds in the family, which is the source of most of what follows.

## Toolchain & check commands

Canonical gate: **`mix ci`** (= `mix precommit.full`), same shape as every
other package (root `CLAUDE.md` § Gates) **plus a native Rust step**:
`cargo test` and `cargo clippy --all-targets -- -D warnings` over both
native crates (`clippy::unwrap_used` denied in production; `expect_used` not
denied; if `cargo`/clippy is absent, the step skips with a message rather
than failing the gate). Coverage floor is **85%**.

- **Do not add the cargo steps to `mix check.dispatch`** — a harness worktree
  has no `target/`, so a cold Rust build would be paid on every dispatch.
- **`reach.check --arch --smells`'s `smells.ignore.paths` entry is scoped to
  one metaprogramming-inherent finding** (see the comment in `.reach.exs`) —
  never add to that list to make a new finding disappear.
- **Rustler NIF + `cover` incompatibility (read before touching coverage).**
  `cover` recompiles each instrumented module's `.beam`, which re-fires a
  Rustler NIF's `on_load` as an unsupported "upgrade" — so the two NIF-backed
  modules (`Onchain.EVM`, `Onchain.Solidity`) cannot be cover-instrumented
  (it fails non-deterministically by load order). Their pure-Elixir logic
  lives in cover-able sibling modules — `Onchain.EVM.Params` (validation +
  NIF-param assembly) and `Onchain.Solidity.Resolver` (import/remapping
  resolution) — and only the thin NIF shells are excluded via
  `test_coverage: [ignore_modules: …]` in `mix.exs`. A residual cosmetic
  "coverage data may be incomplete" warning about those two modules can
  surface inside the full pipeline; it does not affect the threshold (the
  report set is the 6 non-NIF modules, deterministically).
- **Sobelow baseline (`.sobelow-skips`, tracked, 5 lines).** The skip set is
  the codegen's `String.to_atom` calls in `lib/onchain/contract/generator.ex`
  (it creates not-yet-defined identifiers — `to_existing_atom` is impossible)
  plus operator-supplied `File.read` paths in `solidity.ex` /
  `solidity/resolver.ex` (caller-derived `.sol` paths, not web input).
  Regenerate from live state with `mix sobelow --mark-skip-all` after fixing
  a finding or when line shifts invalidate the hashes; never hand-edit.
- `deps.audit.gated` runs against `.mix_audit_ignore` (symlinked from the
  root file — see root `CLAUDE.md` § Adjudicated findings).

## Architecture

- All modules use `Onchain.*` namespace (e.g., `Onchain.EVM`) — same as when it lived in the monolith
- Rust NIFs via Rustler: `otp_app: :onchain_evm` (not `:onchain`)
- Two native crates: `native/onchain_evm/` (revm) and `native/onchain_solidity/` (Alloy + solar-parse)
- `sibling(:onchain, "~> 0.12")`
- Standard error tuples: `{:ok, result} | {:error, {:tag, reason}}`

## Node Portability

The family-wide law is `node-portability.md` (`@`-imported above). This repo owns the
family's **best existing example of rule 3** — reuse it rather than inventing a new
pattern:

- **`Onchain.Trace.available?/1` is the capability probe.** One cheap `debug_traceCall`
  against the zero address, returning a boolean, so a consumer can branch instead of
  failing deep in a pipeline. Any new surface that depends on a namespace a hosted plan
  may gate gets a probe of the same shape — not a bare call that explodes at runtime.
- **`Onchain.Trace`'s moduledoc is the wording to copy:** it names the clients that serve
  `debug_*` (reth, geth, Erigon, Nethermind — any full node with debug APIs enabled) and
  states plainly that the module is *not* a core dependency. Name the clients and the
  consumer-visible error; don't write "requires a compatible node."
- **The integration tests already flunk with setup instructions** naming the Alchemy
  Growth plan (`test/onchain/trace_integration_test.exs`) — that is the house pattern for
  a credentialed suite: a real result or its real refusal, never a skip.
- **Forked simulation has a *different* requirement from tracing.** A fork pulls state via
  standard `eth_getStorageAt`/`eth_getCode`/`eth_getBalance`, so it needs no `debug_*` —
  but forking a historical block needs an **archive** node. Don't collapse the two into
  one "needs a good node" caveat; they fail differently and on different endpoints.

## Module Layout

```
lib/onchain/
  bang_helper.ex              # defbang macro: generates bang (!) wrappers for ok/error functions
  cargo.ex                    # mix ci gate: cargo test + clippy over both native crates
  evm.ex                      # Rustler NIF: revm local EVM execution
  evm/
    params.ex                 # cover-able sibling: pure-Elixir input validation + NIF-param assembly
  solidity.ex                 # Rustler NIF: Alloy-powered Solidity ABI parser
  solidity/
    resolver.ex               # cover-able sibling: import/remapping resolution
  trace.ex                    # debug/trace APIs (trace_transaction, trace_call, storage_at)
  contract/
    generator.ex              # macro: .sol → typed Elixir module at compile time
native/
  onchain_evm/                # Rust crate (revm, alloy)
  onchain_solidity/            # Rust crate (alloy-json-abi, solar-parse)
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

Warm the harness dispatch worktree's Rust build via
`packages/onchain_evm/{native/*/target,priv/native}` (registered as a harness
warm path against the `onchain_stack` project — see root `CLAUDE.md` §
Harness) so a fresh dispatch doesn't pay a cold `cargo build`.

## Related Packages

- **onchain** — Core Ethereum primitives: `sibling(:onchain, "~> 0.12")`
- **onchain_aave** — Aave V3 wrappers: `sibling(:onchain_aave, "~> 0.1")` consumer, dev/test-only
