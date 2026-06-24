# Onchain EVM Roadmap

**Vision:** EVM simulation, Solidity parsing, debug/trace APIs, and contract codegen for Elixir via Rust NIFs.

**Core dependency:** [onchain](../onchain) provides RPC, ABI, signing, address utilities.

**Sibling roadmaps:**
- [onchain/ROADMAP.md](../onchain/ROADMAP.md) — Core Ethereum primitives
- [onchain_aave/ROADMAP.md](../onchain_aave/ROADMAP.md) — Aave V3 protocol wrappers

---

<!-- FOCUS:BEGIN -->
**Focus phase:** 2 — Quality & Reliability Improvements (10 of 20 done · 0 in progress)

**Last shipped:** no recent shipments

**Up next:** Task 50 — Document `simulate_batch/2` partial-failure semantics in `@moduledoc` [D:1/B:3/U:4 → Eff:3.5] 🎯
<!-- FOCUS:END -->

---

## Status

All foundational tasks are complete. This package provides Solidity ABI parsing (Alloy NIF), contract codegen from `.sol` files, local EVM execution (revm NIF), and debug/trace APIs.

### Recently Completed (2026-04-19)
- **Task 30: RPC call timeouts** — `Onchain.EVM` now configures `reqwest::Client` with per-request timeout (default 30s, override via `:timeout_ms`); timeouts surface as `{:error, {:timeout, msg}}` instead of hanging the NIF

### Recently Completed (2026-04-10)
- **Task 37: `defbang` macro** — Replaced 11 bang-function definitions with `Onchain.BangHelper.defbang/1-2` macro calls across EVM, Trace, and Solidity modules
- **Bundle 1: EVM Input Validation** — Tasks 34, 35, 36 all complete. String block tags, rpc_url validation, and strict option validation.
- **Task 38: Error union types** — `{:error, term()}` replaced with named typed unions in `evm.ex` and `trace.ex` specs
- **Task 39: Generator typespecs** — Added `@spec` to `resolve_abi/1`, `resolve_contract_input/2`, `to_snake_case/1`, `disambiguate/1`
- **Struct name collision** — types in interfaces/contracts now get qualified canonical names (`IA.Data`, `IB.Data`)
- **Struct array from_raw** — `from_raw/1` now recursively converts arrays of structs
- **Enum runtime access** — enum constants are generated as callable functions, not compile-time-only attributes

---

## Phase 1 — Foundation

Contract Codegen and Local EVM Simulation. Drop a `.sol` file, get a typed Elixir module (Rustler NIF using Alloy to parse Solidity at compile time, Elixir macros to generate typed wrappers). Simulate contract execution locally without hitting the chain (revm NIF reusing the codegen infrastructure).

<!-- TASKS:BEGIN phase=1 -->
> 5 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-1-foundation).
<!-- TASKS:END -->

---

## Phase 2 — Quality & Reliability Improvements

Bundles identified via code review — grouped by shared code and common goals.

- **Bundle 1: EVM Input Validation** — string block tags, rpc_url validation, strict option validation.
- **Bundle 2: Rust Safety Hardening** — error handling, input size limits, NIF error taxonomy (hex-release blocker).
- **Bundle 3: Elixir Code Quality** — eliminate duplication, typed error unions, dead-code removal.
- **Bundle 4: Documentation & Specs** — typespecs, generator option docs, Rust module docs, batch partial-failure semantics.
- **Bundle 5: EVM Input Validation Round 2** — discovered 2026-04-22 during `onchain_aave` Task 41 (first real consumer integration). All four fit the "NIF catches what Elixir should" pattern — validation that happens after the NIF boundary with bare-string reasons, when it should happen at the Elixir layer with tagged error atoms. (The upstream address/data helper bugs live in the `onchain` core and are tracked there as Task 55.)

<!-- TASKS:BEGIN phase=2 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 34 | ✅ | 🎁 **bundle1_evm_input_validation** · *Onchain.EVM* · Support string block tags (`"latest"`, `"finalized"`) in EVM — consistent with `Onchain.Trace` [D:4/B:7/U:8 → Eff:1.88?] 🚀 |
| Task 35 | ✅ | 🎁 **bundle1_evm_input_validation** · *Onchain.EVM* · Validate `rpc_url` input — reject empty/invalid strings before reaching NIF [D:4/B:8/U:8 → Eff:2.0?] 🎯 |
| Task 36 | ✅ | 🎁 **bundle1_evm_input_validation** · *Onchain.EVM, Onchain.Trace* · Fix silent value dropping — error on invalid `value`, `gas_limit`, `state_overrides` instead of silently ignoring [D:5/B:8/U:7 → Eff:1.5?] 🚀 |
| Task 30 | ✅ | 🎁 **bundle2_rust_safety_hardening** · *native/onchain_evm* · Add RPC call timeouts — configure `reqwest::Client` with timeout to prevent indefinite blocking [D:5/B:9/U:8 → Eff:1.7?] 🚀 |
| Task 31 | ⬜ | 🎁 **bundle2_rust_safety_hardening** · *Both native crates* · Replace `.expect()` with proper error handling — 6× in EVM encoder, 1× in Solidity `map_put` [D:5/B:9/U:7 → Eff:1.6?] 🚀 |
| Task 32 | ⬜ | 🎁 **bundle2_rust_safety_hardening** · *native/onchain_solidity* · Add input size limits — reject oversized Solidity source files [D:4/B:7/U:6 → Eff:1.62?] 🚀 |
| Task 49 | ✅ | 🎁 **bundle2_rust_safety_hardening** · *native/onchain_evm* · Restore `{:fork_error, _}` and `{:timeout, _}` Elixir error classes from the Rust NIF [D:5/B:7/U:6 → Eff:1.3?] 📋 |
| Task 37 | ✅ | 🎁 **bundle3_elixir_code_quality** · *All Elixir modules* · Eliminate bang-function duplication — introduce `defbang` macro to replace 11 copies of the same `case` pattern [D:4/B:6/U:7 → Eff:1.62?] 🚀 |
| Task 38 | ✅ | 🎁 **bundle3_elixir_code_quality** · *Onchain.EVM, Onchain.Trace* · Add specific error union types — replace `{:error, term()}` with typed unions in `evm.ex` and `trace.ex` specs [D:4/B:7/U:7 → Eff:1.75?] 🚀 |
| Task 40 | ✅ | 🎁 **bundle3_elixir_code_quality** · *mix.exs, lib/onchain_evm/* · Remove dead Application module — delete `lib/onchain_evm/application.ex` and commented `mod:` in `mix.exs` [D:2/B:3/U:4 → Eff:1.75?] 🚀 |
| Task 39 | ✅ | 🎁 **bundle4_documentation_specs** · *Onchain.Contract.Generator* · Add `@spec` to public Generator functions — `resolve_abi/1`, `resolve_contract_input/2`, `to_snake_case/1`, `disambiguate/1` [D:3/B:5/U:5 → Eff:1.67?] 🚀 |
| Task 41 | ✅ | 🎁 **bundle4_documentation_specs** · *Onchain.Contract.Generator* · Document Generator options — add `:abi_file`, `:remappings`, and `:root_contract` to moduledoc [D:2/B:4/U:5 → Eff:2.25?] 🎯 |
| Task 42 | ⬜ | 🎁 **bundle4_documentation_specs** · *Both native crates* · Add module-level Rust documentation — doc comments on both native crate entry points [D:3/B:5/U:5 → Eff:1.67?] 🚀 |
| Task 50 | ⬜ | 🎁 **bundle4_documentation_specs** · *Onchain.EVM* · Document `simulate_batch/2` partial-failure semantics in `@moduledoc` [D:1/B:3/U:4 → Eff:3.5?] 🎯 |
| Task 45 | ⬜ | 🎁 **bundle5_evm_input_validation_round2** · *Onchain.EVM* · `simulate_batch/2` input shape validation — reject non-list `calls` and non-2-tuple elements before `validate_calls/1` [D:2/B:6/U:5 → Eff:2.75?] 🎯 |
| Task 46 | ⬜ | 🎁 **bundle5_evm_input_validation_round2** · *Onchain.EVM* · Validate `:value` option as 0x-prefixed even-length hex U256, not any binary [D:2/B:5/U:4 → Eff:2.25?] 🎯 |
| Task 47 | ⬜ | 🎁 **bundle5_evm_input_validation_round2** · *Onchain.EVM* · Validate `:state_overrides` nested keys/values are strings, per `@type state_overrides` [D:2/B:5/U:4 → Eff:2.25?] 🎯 |
| Task 48 | ⬜ | 🎁 **bundle5_evm_input_validation_round2** · *Onchain.EVM* · Bound-check `:block` hex values against u64 max in `parse_hex_block/2` [D:2/B:4/U:3 → Eff:1.75?] 🚀 |
| Task 54 | ⬜ | 🎁 **bundle2_rust_safety_hardening** · *Onchain.EVM* · Behavioral golden tests for EVM fork+execute — safety net before the revm/alloy major bump [D:4/B:7/U:6 → Eff:1.62] 🚀 |
| Task 55 | ⬜ | 🎁 **bundle2_rust_safety_hardening** · *native/onchain_evm* · Bump revm 19→41 + alloy 0.7→2.1 in native/onchain_evm — clears lru low-severity advisory [D:9/B:6/U:7 → Eff:0.72] ⚠️ |
<!-- TASKS:END -->

---

## Phase 3 — Standalone & Release

Standalone tasks: Rust unit tests, tokio runtime reuse, clippy CI, codegen extensions, and hex-release prep.

<!-- TASKS:BEGIN phase=3 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 28 | ⬜ | 🎁 **standalone** · *native/onchain_evm* · Rust unit tests for `onchain_evm` crate — `CallParams` parsing, `EvmError` encoding, hex helpers, fork DB setup [D:6/B:10/U:9 → Eff:1.58?] 🚀 |
| Task 29 | ⬜ | 🎁 **standalone** · *native/onchain_solidity* · Rust unit tests for `onchain_solidity` crate — ABI JSON parsing, type canonicalization, NatSpec extraction, import resolution [D:6/B:10/U:9 → Eff:1.58?] 🚀 |
| Task 33 | ⬜ | 🎁 **standalone** · *native/onchain_evm* · Reuse tokio runtime — lazy-init a single `current_thread` runtime instead of creating one per EVM call [D:5/B:8/U:7 → Eff:1.5?] 🚀 |
| Task 43 | ⬜ | 🎁 **standalone** · *Both native crates* · Add `cargo clippy` to CI — `#![warn(clippy::all)]` on both crates [D:3/B:5/U:4 → Eff:1.5?] 🚀 |
| Task 44 | ⬜ | 🎁 **standalone** · *native/onchain_solidity* · Fix `format!("{:?}", expr)` fallbacks — proper error types for unhandled Solidity expression types [D:4/B:6/U:5 → Eff:1.38?] 📋 |
| Task 51 | ⬜ | 🎁 **standalone** · *(cross-cutting research)* · Mine `defi-skills:intent-to-transaction` action surface for `onchain_evm` simulation coverage [D:3/B:8/U:7 → Eff:2.5?] 🎯 |
| Task 52 | ⬜ | 🎁 **standalone** · *Onchain.Contract.Generator* · Codegen-emit per-contract Multicall helper modules [D:5/B:7/U:6 → Eff:1.3?] 📋 |
| Task 53 | ⬜ | 🎁 **standalone** · *Both native crates* · Adopt `rustler_precompiled` for both native crates — prebuilt artifacts via GitHub Releases [D:5/B:8/U:8 → Eff:1.6?] 🚀 |
<!-- TASKS:END -->

---

## Path to hex.pm Release (`0.1.0`)

Release when these are true:

**Blockers (must close before `mix hex.publish`):**
- [x] Credo on hex — swapped git dep for `~> 1.7` (1.7.18 shipped 2026-04-10)
- [ ] Bundle 2 closed — Tasks 30 (RPC timeouts), 31 (`.expect()` → errors), 32 (input size limits). Public API contracts around reliability are hard to change post-release.
- [ ] Task 53 — `rustler_precompiled` wrapping both native crates, with prebuilt artifacts published via GitHub Releases. Without this, every install requires a full Rust toolchain.

**Should do (but not blockers):**
- Task 28/29 — Rust unit tests for both crates (confidence in the NIFs users are compiling against)
- Task 42 — module-level Rust doc comments (shows up in crate docs)
- Task 43 — `cargo clippy` in CI

**Version strategy:** release as `0.1.0` to signal API-may-still-shift. Bump to `0.2.0` for any breaking change in Elixir signatures or NIF ABI. Reserve `1.0.0` for when the debug/trace + codegen surfaces feel stable across a few real downstream users (`onchain_aave`, etc.).

---

## Future Directions

Potential expansions — not yet scoped or scored:

- **Bytecode analysis** — disassemble EVM bytecode, detect proxy patterns, extract storage layout
- **Deployment pipeline** — compile (via `OnchainJs.Solc.compile/2` — see [onchain_js](../onchain_js/ROADMAP.md) Task 2) → deploy → verify on Etherscan
- **Enhanced trace APIs** — `debug_traceBlockByNumber`, `trace_filter`, `trace_block` for block-level analysis
- **State diff extraction** — compare pre/post state from revm execution for "what changed?" queries
- **Gas estimation** — accurate gas estimation via local revm execution before broadcast
- **Batch simulation** — simulate multiple transactions in sequence (recipe preview, strategy testing)

**Related sibling tasks:**
- [onchain_js](../onchain_js/ROADMAP.md) Task 2 (solc-js compilation via QuickBEAM) closes the codegen → compile → deploy loop and feeds onchain Sleuth (Task 62)

---

## Key Design Decisions

1. **`Onchain.*` namespace** — modules keep the same namespace as when they lived in the monolith
2. **Rustler `otp_app: :onchain_evm`** — NIFs must reference `:onchain_evm`, not `:onchain`
3. **Two native crates** — `native/onchain_evm/` (revm, alloy) and `native/onchain_solidity/` (alloy-json-abi, solang-parser)
4. **Hex dependency** — `{:onchain, "~> 0.5"}` (was a path dep during the monolith split)
5. **`priv_dir` references** — tests use `:code.priv_dir(:onchain_evm)` (not `:onchain`)
6. **Standard error tuples** — `{:ok, result} | {:error, {:tag, reason}}`

## Module Structure

```
lib/onchain/
  bang_helper.ex                  # defbang macro: generates bang (!) wrappers for ok/error functions
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
