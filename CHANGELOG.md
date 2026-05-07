# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## [Unreleased]

### Added

- **Dependency bump:** `:onchain` narrowed from `~> 0.5` to `~> 0.5.3` (excludes 0.5.0–0.5.2). 0.5.3 renames the doc-private helper `Onchain.RPC.Helpers.to_signet_opts/1` → `to_rpc_opts/1`; `Onchain.Trace`'s 4 callsites updated accordingly.
- **Task 30: RPC call timeouts** — `Onchain.EVM` now configures the underlying `reqwest::Client` with an explicit per-request timeout (default 30s) and a hard-coded 5s TCP connect timeout. Callers can override the request timeout per call with the new `:timeout_ms` option (positive integer, validated). Timeouts surface as `{:error, {:timeout, msg}}` — a new variant on the `nif_error()` union — so callers can distinguish slow/unreachable endpoints from execution errors. Previously, a hung RPC endpoint would block the dirty-IO scheduler indefinitely. Implementation switches `build_fork_db` from `ProviderBuilder::on_http(url)` to `on_client(RpcClient::new(Http::with_client(reqwest_client, url), is_local))` so the explicit `reqwest::Client` (with timeouts) is threaded through. Error classification walks the display string for `"timed out"` / `"deadline"` markers since the underlying `reqwest::Error` is reformatted by intermediate alloy/revm layers. `:timeout_ms` caps each individual RPC request, not aggregate simulation time — a single `simulate_transaction` may issue many RPC reads.
- **Task 37: `defbang` macro** — Created `Onchain.BangHelper` with `defbang/1-2` macro that generates bang functions from non-bang ok/error functions. Replaced 11 hand-written bang functions across `Onchain.EVM` (3), `Onchain.Trace` (3), and `Onchain.Solidity` (5) with macro calls. Supports simple error messages (Pattern A) and tagged error clauses with fallback (Pattern B/C). Case AST constructed manually to prevent Styler from rewriting multi-clause case expressions into pattern match assignments.
- **Task 34: String block tags in EVM** — `Onchain.EVM` now accepts `block: "latest"`, `"finalized"`, `"safe"`, `"pending"`, `"earliest"`, and `"0x..."` hex strings in addition to integers. Tag strings are passed to the NIF and resolved natively by Alloy's provider. Updated Rust `build_fork_db` to accept `BlockId` directly via a new `resolve_block_id` helper. Hex block parsing extracted to `parse_hex_block/2` with defensive `Integer.parse` handling (bare `"0x"` no longer crashes).
- **Task 35: rpc_url validation** — `require_rpc_url/1` now rejects empty strings, whitespace-only strings, non-HTTP(S) URLs, and hostless URLs (e.g. `"http://"`) with `{:error, {:invalid_rpc_url, reason}}` tuples. Missing rpc_url now returns `{:error, {:invalid_rpc_url, :missing}}` (was `{:error, {:evm_error, ...}}`). Previously, empty or malformed URLs passed through to the NIF and produced cryptic connection errors.
- **Task 36: Strict option validation** — `maybe_put_value/2`, `maybe_put_gas_limit/2`, and `maybe_put_state_overrides/2` now return `{:error, {:invalid_*, input}}` instead of silently dropping invalid inputs. Also fixed `Trace.maybe_put_value/2` to validate that `:value` is a binary string. All three functions integrated into the `with` chain for fail-fast behavior.

- **Task 39: Generator typespecs** — Added `@spec` to public `Onchain.Contract.Generator` functions: `resolve_abi/1`, `resolve_contract_input/2`, `to_snake_case/1`, `disambiguate/1`. `resolve_contract_input/2` spec documents the returned map shape (`:abi`, `:is_sol`, `:external_files`).

- **Task 38: Specific error union types** — Replaced `{:error, term()}` with named error type unions in `Onchain.EVM` and `Onchain.Trace`. EVM module defines `evm_error()` (union of `validation_error()` and `nif_error()`), Trace module defines `trace_error()` (union of `validation_error()` and `rpc_error()`). Per-function narrowing on `trace_transaction/2` and `storage_at/3` where the error surface is small. Added `@spec` to all private helper functions in both modules. Updated Descripex `api()` `returns.type` strings to match narrowed specs. Dialyzer can now verify error propagation through `with` chains end-to-end.

### Changed

- **Task 40: Removed dead Application module** — Deleted `lib/onchain_evm/application.ex` (empty supervision tree, never wired up) and the commented `mod:` line in `mix.exs`.
- **Task 41: Documented Generator options** — Added Options section to `Onchain.Contract.Generator` moduledoc covering all 6 input options (`:abi_json`, `:abi_file`, `:sol`, `:sol_file`, `:remappings`, `:root_contract`). Post-review fix: corrected three doc/implementation mismatches — "exactly one source required" → documents precedence order, `:abi_file` no longer claims project-root resolution, `:remappings` now correctly documented as Foundry-style string list.
- **Cleaned `.sobelow-skips`** — Regenerated from current code, removing stale entries from prior line-number shifts (30 → 15 entries).
- **Fixed ROADMAP.md Eff scores** — Recalculated all efficiency scores using the correct formula `(B + U) / (2 × D)`. Previous values were miscalculated (0.1–0.5 instead of 1.38–2.25).

### Fixed

- **High: Struct name collision across interfaces** — `qualify_user_type` now namespaces types from all contract types (interface, contract, abstract), not just libraries. Previously, `IA.Data` and `IB.Data` collapsed to `Data` in the type registry, causing wrong ABI encodings. Added context-aware type resolution (`resolve_struct`/`resolve_enum`) that tries `Owner.TypeName` before falling back to the short name.
- **Medium: Struct arrays in `from_raw/1`** — `build_struct_field_value` now strips array suffixes before checking struct names and wraps conversion in `Enum.map` for array types (`Item[]`, `Item[2]`). Previously, arrays of structs passed through as raw tuples.
- **Low: Enum constants inaccessible at runtime** — Replaced `Module.put_attribute/3` (compile-time only, discarded after compilation) with generated public functions (`def status_pending, do: 0`). Enum constants are now callable at runtime with `@spec` and `@doc`.

---

## v0.1.0 — Initial Release (Split from onchain)

Extracted from [onchain](../onchain) v0.3.0 monolith as a standalone package.

**What's included:**

- **Onchain.Solidity** — Rustler NIF: Alloy-powered Solidity ABI parser
- **Onchain.Contract.Generator** — macro: `.sol` → typed Elixir module at compile time, with import/remapping resolution
- **Onchain.EVM** — Rustler NIF: revm local EVM execution (fork mainnet state, simulate transactions)
- **Onchain.Trace** — debug/trace APIs (trace_transaction, trace_call, storage_at)
- **Native crates** — `native/onchain_evm/` (revm, alloy) and `native/onchain_solidity/` (alloy-json-abi, solang-parser)

**Why:** Consumers who don't need Rust NIFs no longer compile Rustler + two native crates. The core `onchain` package is now pure Elixir.
