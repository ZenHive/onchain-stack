# Onchain EVM Roadmap

**Vision:** EVM simulation, Solidity parsing, debug/trace APIs, and contract codegen for Elixir via Rust NIFs.

**Core dependency:** [onchain](../onchain) provides RPC, ABI, signing, address utilities.

**Sibling roadmaps:**
- [onchain/ROADMAP.md](../onchain/ROADMAP.md) — Core Ethereum primitives
- [onchain_aave/ROADMAP.md](../onchain_aave/ROADMAP.md) — Aave V3 protocol wrappers

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
| 30 | Add RPC call timeouts — configure `reqwest::Client` with timeout to prevent indefinite blocking | ✅ | 5 | 9 | 8 | 1.70 🚀 | `native/onchain_evm` |
| 31 | Replace `.expect()` with proper error handling — 6× in EVM encoder, 1× in Solidity `map_put` | ⬜ | 5 | 9 | 7 | 1.60 🚀 | Both native crates |
| 32 | Add input size limits — reject oversized Solidity source files | ⬜ | 4 | 7 | 6 | 1.63 🚀 | `native/onchain_solidity` |
| 49 | Restore `{:fork_error, _}` and `{:timeout, _}` Elixir error classes from the Rust NIF | ⬜ | 5 | 7 | 6 | 1.30 📋 | `native/onchain_evm` |

**Task 49 — NIF error taxonomy classification.** `:timeout` (added in Task 30) is currently classified by display-string match in `classify_transport_error` (`"timed out"` / `"deadline"` / `"operation timed out"`); these markers aren't guaranteed stable across alloy/revm version bumps because the underlying `reqwest::Error` is reformatted by intermediate layers. `:fork_error` still doesn't fire from transport-level connect failures — connect-refused, DNS-failure, and similar collapse to `{:evm_error, "database error: error sending request for url ..."}`, so callers can't distinguish transient infra failure (retry) from simulation bug (don't retry). Replace the string-match in `classify_transport_error` with `reqwest::Error::is_timeout()` / `is_connect()` once the underlying error type can be preserved through the alloy/revm layers (downcasting via `Error::source()` chains, or upstream PR to alloy). Discovered 2026-04-22 during `onchain_aave` Task 41; partially closed by Task 30.

### Bundle 3: Elixir Code Quality

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 37 | Eliminate bang-function duplication — introduce `defbang` macro to replace 11 copies of the same `case` pattern | ✅ | 4 | 6 | 7 | 1.63 🚀 | All Elixir modules |
| 38 | Add specific error union types — replace `{:error, term()}` with typed unions in `evm.ex` and `trace.ex` specs | ✅ | 4 | 7 | 7 | 1.75 🚀 | `Onchain.EVM`, `Onchain.Trace` |
| 40 | Remove dead Application module — delete `lib/onchain_evm/application.ex` and commented `mod:` in `mix.exs` | ✅ | 2 | 3 | 4 | 1.75 🚀 | `mix.exs`, `lib/onchain_evm/` |

### Bundle 4: Documentation & Specs

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 39 | Add `@spec` to public Generator functions — `resolve_abi/1`, `resolve_contract_input/2`, `to_snake_case/1`, `disambiguate/1` | ✅ | 3 | 5 | 5 | 1.67 🚀 | `Onchain.Contract.Generator` |
| 41 | Document Generator options — add `:abi_file`, `:remappings`, and `:root_contract` to moduledoc | ✅ | 2 | 4 | 5 | 2.25 🎯 | `Onchain.Contract.Generator` |
| 42 | Add module-level Rust documentation — doc comments on both native crate entry points | ⬜ | 3 | 5 | 5 | 1.67 🚀 | Both native crates |
| 50 | Document `simulate_batch/2` partial-failure semantics in `@moduledoc` | ⬜ | 1 | 3 | 4 | 3.50 🎯 | `Onchain.EVM` |

**Task 50 — Batch partial-failure docs.** Per-call reverts inside `simulate_batch` surface as `%{success: false, output: "0x"}` inside the outer `{:ok, results}`. That's the right design (batch resilience) but isn't called out in `@moduledoc`; a consumer seeing `{:ok, _}` may assume every call succeeded. Document explicitly that outer `{:ok, _}` only signals the fork itself succeeded — per-call outcomes must be checked against `:success`. Discovered 2026-04-22.

### Bundle 5: EVM Input Validation Round 2

Discovered 2026-04-22 during `onchain_aave` Task 41 (first real consumer integration). All four fit the "NIF catches what Elixir should" pattern — validation that happens after the NIF boundary with bare-string reasons, when it should happen at the Elixir layer with tagged error atoms. (The upstream address/data helper bugs live in the `onchain` core and are tracked there as Task 55.)

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 45 | `simulate_batch/2` input shape validation — reject non-list `calls` and non-2-tuple elements before `validate_calls/1` | ⬜ | 2 | 6 | 5 | 2.75 🎯 | `Onchain.EVM` |
| 46 | Validate `:value` option as 0x-prefixed even-length hex U256, not any binary | ⬜ | 2 | 5 | 4 | 2.25 🎯 | `Onchain.EVM` |
| 47 | Validate `:state_overrides` nested keys/values are strings, per `@type state_overrides` | ⬜ | 2 | 5 | 4 | 2.25 🎯 | `Onchain.EVM` |
| 48 | Bound-check `:block` hex values against u64 max in `parse_hex_block/2` | ⬜ | 2 | 4 | 3 | 1.75 🚀 | `Onchain.EVM` |

**Task 45 — Batch input shape.** `simulate_batch(%{}, opts)` currently returns `{:ok, []}` silently because `Enum.reduce_while/3` iterates any `Enumerable`; `simulate_batch([{addr, data, :extra}], opts)` raises `FunctionClauseError` from the anon fn inside `validate_calls/1`, escaping the `{:ok, _} | {:error, _}` contract. Add a pre-guard requiring `is_list(calls)` and pattern-match 2-tuples explicitly, returning `{:error, {:invalid_calls, _}}` in both cases.

**Task 46 — Value hex validation.** `maybe_put_value/2` currently only checks `is_binary/1`. `value: ""` and `value: "not-a-hex"` pass Elixir, fail in Rust as `{:evm_error, "invalid U256 hex: digit ... is out of range"}`. Validate 0x-prefixed, even-length, hex-only at the Elixir boundary → `{:error, {:invalid_value, _}}`.

**Task 47 — state_overrides nested validation.** `@type state_overrides` doc is explicit that all keys/values in nested maps must be strings. Currently atom keys (`%{addr => %{code: "0x..."}}`) and int values (`%{"balance" => 123}`) produce `{:evm_error, "invalid state_overrides format"}` from Rust. Validate recursively in `maybe_put_state_overrides/2`.

**Task 48 — Block u64 bound.** `parse_hex_block/2` calls `Integer.parse/2` with no upper bound; `block: "0x" <> String.duplicate("f", 20)` lands as `{:evm_error, "invalid param type: block_number"}` from the NIF. Reject > u64 max at the Elixir layer → `{:error, {:invalid_block, _}}`.

---

### Standalone Tasks

| # | Task | Status | D | B | U | Eff | Module |
|---|------|--------|---|---|---|-----|--------|
| 28 | Rust unit tests for `onchain_evm` crate — `CallParams` parsing, `EvmError` encoding, hex helpers, fork DB setup | ⬜ | 6 | 10 | 9 | 1.58 🚀 | `native/onchain_evm` |
| 29 | Rust unit tests for `onchain_solidity` crate — ABI JSON parsing, type canonicalization, NatSpec extraction, import resolution | ⬜ | 6 | 10 | 9 | 1.58 🚀 | `native/onchain_solidity` |
| 33 | Reuse tokio runtime — lazy-init a single `current_thread` runtime instead of creating one per EVM call | ⬜ | 5 | 8 | 7 | 1.50 📋 | `native/onchain_evm` |
| 43 | Add `cargo clippy` to CI — `#![warn(clippy::all)]` on both crates | ⬜ | 3 | 5 | 4 | 1.50 📋 | Both native crates |
| 44 | Fix `format!("{:?}", expr)` fallbacks — proper error types for unhandled Solidity expression types | ⬜ | 4 | 6 | 5 | 1.38 📋 | `native/onchain_solidity` |
| 51 | Mine `defi-skills:intent-to-transaction` action surface for `onchain_evm` simulation coverage | ⬜ | 3 | 8 | 7 | 2.50 🎯 | (cross-cutting research) |
| 52 | Codegen-emit per-contract Multicall helper modules | ⬜ | 5 | 7 | 6 | 1.30 📋 | `Onchain.Contract.Generator` |
| 53 | Adopt `rustler_precompiled` for both native crates — prebuilt artifacts via GitHub Releases | ⬜ | 5 | 8 | 8 | 1.60 🚀 | Both native crates |

**Task 52 — Codegen-emit per-contract Multicall helper modules.** [D:5/B:7/U:6 → Eff:1.30 📋]

Extend `Onchain.Contract.Generator` so each generated contract emits typed Multicall helpers — callers using both codegen and `Onchain.Multicall` (in the core `onchain` library) shouldn't have to hand-pack call tuples and lose the type safety the generator otherwise provides. Include unit and integration tests.

---

**Task 53 — Adopt `rustler_precompiled` for both native crates.** [D:5/B:8/U:8 → Eff:1.60 🚀]

Hex-release blocker (see "Path to hex.pm Release"). Without prebuilt artifacts, every consumer of `onchain_evm` needs a working Rust toolchain plus several minutes to compile `revm` + `alloy` + `solang-parser` from source.

**Scope:**
- Wrap both `native/onchain_evm` (revm, alloy) and `native/onchain_solidity` (alloy-json-abi, solang-parser) with `RustlerPrecompiled.use/1` instead of plain `Rustler`.
- GitHub Actions cross-compile matrix per release: Linux x86_64-gnu, x86_64-musl, aarch64-gnu; macOS x86_64, aarch64; Windows x86_64-msvc.
- Attach `.so`/`.dylib`/`.dll` artifacts + `checksum-Elixir.RustlerPrecompiled-*.exs` to each GitHub Release.
- Document `RUSTLER_PRECOMPILATION_*_BUILD=1` force-from-source fallback in README.
- CI job to validate the checksum file is regenerated on every release.

**Trade-offs:** 2× build matrix per release (two crates), more release ceremony (tag → wait for CI → publish), force-from-source fallback as support surface. Worth it once a real external consumer installs from hex.

---

**Task 51 — Mine `defi-skills:intent-to-transaction` action surface for `onchain_evm` simulation coverage.** [D:3/B:8/U:7 → Eff:2.50 🎯]

Planted 2026-04-30 from a cartouche session that surveyed cross-repo applicability of the `defi-skills` skill. Self-contained discovery exercise — execute it from a fresh `onchain_evm` Claude Code session so this repo's CLAUDE.md, hooks, and revm fixtures are loaded.

**Prompt for the executing session:**

> Invoke `/defi-skills:intent-to-transaction` to load the skill, then run `defi-skills actions --json` to enumerate the supported action surface (~50 actions across Aave, Uniswap, Lido, Compound, Balancer, Pendle, EigenLayer, Curve, MakerDAO, Rocket Pool, Fibrous, WETH).
>
> Map relevant actions to **`onchain_evm`'s scope: simulation harness coverage** — can `revm` + Alloy ABI parsing simulate the unsigned transactions defi-skills builds end-to-end (the approval transaction *and* the action transaction in sequence), surface revert reasons cleanly, and produce useful state-diff output? Propose a differential-test pattern: build with defi-skills → simulate with `Onchain.EVM.simulate_batch/2` → assert state changes (token balance deltas, approval allowance, log emissions). Identify any defi-skills action shape that the current `simulate_batch` API can't represent (e.g. unusual fork-DB requirements, value-bearing calls, multi-tx sequencing limits).
>
> For each gap or coverage opportunity, propose a ROADMAP entry with D/B/U scoring per `~/.claude/includes/task-prioritization.md`. Output: a "Proposed additions from defi-skills mining" section the user reviews before merging into the appropriate bundle or `Standalone Tasks`.
>
> Read-only exercise — discovery + scoring only, no `Onchain.EVM` / Rust code edits in this task itself. The skill is already installed (`pip install defi-skills`); no new deps. Companion tasks were planted in `hieroglyph`, `onchain`, and `onchain_aave` ROADMAPs the same day.

**Acceptance:** a "Proposed additions from defi-skills mining" section lands in this ROADMAP listing each candidate task with D/B/U scores and which `defi-skills` action(s) motivated it. The user merges accepted entries into `Standalone Tasks` or a new bundle.

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
