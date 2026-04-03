# Onchain EVM Roadmap

**Vision:** EVM simulation, Solidity parsing, debug/trace APIs, and contract codegen for Elixir via Rust NIFs.

**Core dependency:** [onchain](../onchain) provides RPC, ABI, signing, address utilities.

**Sibling roadmaps:**
- [onchain/ROADMAP.md](../onchain/ROADMAP.md) — Core Ethereum primitives
- [onchain_aave/ROADMAP.md](../onchain_aave/ROADMAP.md) — Aave V3 protocol wrappers

---

## Status

All foundational tasks are complete. This package provides Solidity ABI parsing (Alloy NIF), contract codegen from `.sol` files, local EVM execution (revm NIF), and debug/trace APIs.

### Recently Completed (2026-04-03)
- **Bundle 1: EVM Input Validation** — Tasks 34, 35, 36 all complete. String block tags, rpc_url validation, and strict option validation.
- **Struct name collision** — types in interfaces/contracts now get qualified canonical names (`IA.Data`, `IB.Data`)
- **Struct array from_raw** — `from_raw/1` now recursively converts arrays of structs
- **Enum runtime access** — enum constants are generated as callable functions, not compile-time-only attributes

---

## Contract Codegen ✅

Drop a `.sol` file, get a typed Elixir module. Rustler NIF using Alloy to parse Solidity at compile time, Elixir macros to generate typed wrappers.

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 24 | Rustler NIF: Solidity ABI parser via Alloy | ✅ | 5 | 9 | 9 | 1.80 🚀 | `Onchain.Solidity` (native) |
| 25 | Contract codegen macro (`use Onchain.Contract.Generator, sol: "..."`) | ✅ | 6 | 10 | 9 | 1.58 🚀 | `Onchain.Contract.Generator` |
| 25b | Solidity import/remapping resolution for multi-file codegen | ✅ | 5 | 9 | 8 | 1.80 🚀 | `Onchain.Contract.Generator` |

---

## Local EVM Simulation ✅

Simulate contract execution locally without hitting the chain. Reuses the Rustler NIF infrastructure from codegen.

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 26 | Rustler NIF: revm local EVM execution | ✅ | 6 | 10 | 9 | 1.58 🚀 | `Onchain.EVM` (native) |
| 27 | Debug/trace API module (trace transaction, trace call, storage reads) | ✅ | 4 | 7 | 6 | 1.63 🚀 | `Onchain.Trace` |

---

## Quality & Reliability Improvements

Bundles identified via code review — grouped by shared code and common goals.

### Bundle 1: EVM Input Validation

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 34 | Support string block tags (`"latest"`, `"finalized"`) in EVM — consistent with `Onchain.Trace` | ✅ | 4 | 7 | 8 | 1.88 🚀 | `Onchain.EVM` |
| 35 | Validate `rpc_url` input — reject empty/invalid strings before reaching NIF | ✅ | 4 | 8 | 8 | 2.00 🎯 | `Onchain.EVM` |
| 36 | Fix silent value dropping — error on invalid `value`, `gas_limit`, `state_overrides` instead of silently ignoring | ✅ | 5 | 8 | 7 | 1.50 📋 | `Onchain.EVM`, `Onchain.Trace` |

### Bundle 2: Rust Safety Hardening

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 30 | Add RPC call timeouts — configure `reqwest::Client` with timeout to prevent indefinite blocking | ⬜ | 5 | 9 | 8 | 1.70 🚀 | `native/onchain_evm` |
| 31 | Replace `.expect()` with proper error handling — 6× in EVM encoder, 1× in Solidity `map_put` | ⬜ | 5 | 9 | 7 | 1.60 🚀 | Both native crates |
| 32 | Add input size limits — reject oversized Solidity source files | ⬜ | 4 | 7 | 6 | 1.63 🚀 | `native/onchain_solidity` |

### Bundle 3: Elixir Code Quality

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 37 | Eliminate bang-function duplication — introduce `defbang` macro to replace 9 copies of the same `case` pattern | ⬜ | 4 | 6 | 7 | 1.63 🚀 | All Elixir modules |
| 38 | Add specific error union types — replace `{:error, term()}` with typed unions in `evm.ex` and `trace.ex` specs | ⬜ | 4 | 7 | 7 | 1.75 🚀 | `Onchain.EVM`, `Onchain.Trace` |
| 40 | Remove dead Application module — delete `lib/onchain_evm/application.ex` and commented `mod:` in `mix.exs` | ✅ | 2 | 3 | 4 | 1.75 🚀 | `mix.exs`, `lib/onchain_evm/` |

### Bundle 4: Documentation & Specs

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 39 | Add `@spec` to public Generator functions — `resolve_abi/1`, `to_snake_case/1`, `disambiguate/1` | ⬜ | 3 | 5 | 5 | 1.67 🚀 | `Onchain.Contract.Generator` |
| 41 | Document Generator options — add `:abi_file`, `:remappings`, and `:root_contract` to moduledoc | ✅ | 2 | 4 | 5 | 2.25 🎯 | `Onchain.Contract.Generator` |
| 42 | Add module-level Rust documentation — doc comments on both native crate entry points | ⬜ | 3 | 5 | 5 | 1.67 🚀 | Both native crates |

### Standalone Tasks

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 28 | Rust unit tests for `onchain_evm` crate — `CallParams` parsing, `EvmError` encoding, hex helpers, fork DB setup | ⬜ | 6 | 10 | 9 | 1.58 🚀 | `native/onchain_evm` |
| 29 | Rust unit tests for `onchain_solidity` crate — ABI JSON parsing, type canonicalization, NatSpec extraction, import resolution | ⬜ | 6 | 10 | 9 | 1.58 🚀 | `native/onchain_solidity` |
| 33 | Reuse tokio runtime — lazy-init a single `current_thread` runtime instead of creating one per EVM call | ⬜ | 5 | 8 | 7 | 1.50 📋 | `native/onchain_evm` |
| 43 | Add `cargo clippy` to CI — `#![warn(clippy::all)]` on both crates | ⬜ | 3 | 5 | 4 | 1.50 📋 | Both native crates |
| 44 | Fix `format!("{:?}", expr)` fallbacks — proper error types for unhandled Solidity expression types | ⬜ | 4 | 6 | 5 | 1.38 📋 | `native/onchain_solidity` |

---

## Future Directions

Potential expansions — not yet scoped or scored:

- **Bytecode analysis** — disassemble EVM bytecode, detect proxy patterns, extract storage layout
- **Deployment pipeline** — compile (via solc-js in onchain core Phase 9) → deploy → verify on Etherscan
- **Enhanced trace APIs** — `debug_traceBlockByNumber`, `trace_filter`, `trace_block` for block-level analysis
- **State diff extraction** — compare pre/post state from revm execution for "what changed?" queries
- **Gas estimation** — accurate gas estimation via local revm execution before broadcast
- **Batch simulation** — simulate multiple transactions in sequence (recipe preview, strategy testing)

**Related onchain core tasks:**
- Task 38 (solc-js compilation via QuickBEAM) closes the codegen → compile → deploy loop

---

## Key Design Decisions

1. **`Onchain.*` namespace** — modules keep the same namespace as when they lived in the monolith
2. **Rustler `otp_app: :onchain_evm`** — NIFs must reference `:onchain_evm`, not `:onchain`
3. **Two native crates** — `native/onchain_evm/` (revm, alloy) and `native/onchain_solidity/` (alloy-json-abi, solang-parser)
4. **Path dependency** — `{:onchain, path: "../onchain"}`
5. **`priv_dir` references** — tests use `:code.priv_dir(:onchain_evm)` (not `:onchain`)
6. **Standard error tuples** — `{:ok, result} | {:error, {:tag, reason}}`

## Module Structure

```
lib/onchain/
  evm.ex                          # Rustler NIF: revm local EVM execution
  solidity.ex                     # Rustler NIF: Alloy-powered Solidity ABI parser
  trace.ex                        # debug/trace APIs (trace_transaction, trace_call, storage_at)
  contract/
    generator.ex                  # macro: .sol → typed Elixir module at compile time
native/
  onchain_evm/                    # Rust crate (revm, alloy)
  onchain_solidity/               # Rust crate (alloy-json-abi, solang-parser)
priv/
  abis/
    chainlink_aggregator.json
    aave_pool.json                # test fixture for parser tests
  contracts/
    test_interface.sol            # test fixture
    real/                         # vendored upstream Solidity for import resolution tests
```
