# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## [Unreleased]

## [0.3.0] — 2026-06-25

### Added

- **Vibe analyzer stack** — adopted the onchain-family analyzer toolchain: `ex_dna`, `ex_ast`, `ex_slop`, and `reach` (dev/test only). New `.credo.exs` (ExSlop plugin, `Readability.Specs` scoped to the library + test support) and `.reach.exs` (arch/smell policy; the compile-time contract generator is scoped out of the smell detector since its `String.to_atom` calls create the identifiers they emit). Added `precommit` (fast local loop), `precommit.full`/`ci` (the harness reviewer's `check_command`), and `integration` mix aliases.
- **`@spec` coverage** — added typespecs to all private helpers in `Onchain.Contract.Generator` and `Onchain.Solidity`, the NIF stubs in `Onchain.EVM`, and the `Onchain.BangHelper` macro helpers, satisfying the newly-enabled `Credo.Check.Readability.Specs`.
- **Solidity resolution unit tests** — temp-fixture tests for `resolve_sol_file/2` (relative/absolute/remapped imports, `remappings.txt`, `:root_contract` override, and the error paths) plus a `parse_sol_file/2` single-file fallback test.

### Changed

- **Dependencies — onchain 0.10 / cartouche 0.5 line.** Bumped `onchain` `~> 0.8` → `~> 0.10` and `descripex` `~> 0.9` → `~> 0.11`; `onchain 0.10` pulls `cartouche 0.5.0` (was 0.4.0) and `req 0.6.2`. No public onchain_evm API changes — full suite green (218 unit + 30 integration).
- **Native dependencies** — bumped `rustler` `0.37` → `0.38` (both crates, with the matching `mix.exs` constraint) and `alloy-json-abi` `0.8` → `1.6` in `native/onchain_solidity`; `ex_doc` `~> 0.39` → `~> 0.40` (older pin held `makeup_elixir < 1.0`, conflicting with `reach`).
- **`Onchain.BangHelper`** — `defbang` now resolves the base name with `String.to_existing_atom/1` (the wrapped function's atom always exists by macro-expansion time), avoiding atom-table growth and turning a typo'd base name into a compile error.
- **`Onchain.Contract.Generator`** — extracted the shared bang-wrapper body (`build_bang_body/2`) used by generated read/write functions, removing the duplicated `case` template.
- **Sobelow false-positive suppression** — the generator's compile-time codegen creates the identifier atoms it emits (function names, struct field keys, param vars), so its 11 `String.to_atom` sites are now routed through a single documented `to_identifier_atom/1` helper, collapsing the `DOS.StringToAtom` finding to one skip-anchored line. The `code-scanning.yml` Sobelow step now runs `--skip` so the SARIF upload honors `.sobelow-skips` (matching `precommit.full`), and `.sobelow-skips` was regenerated against current line numbers — clearing the stale Code Scanning alerts while still surfacing any new finding.

## [0.2.0] — 2026-06-12

Hardening release on top of the v0.1.0 split: stricter input validation, named
error types, RPC timeouts, and three codegen correctness fixes — plus the upgrade
to the `onchain 0.8` / `descripex 0.9` / `cartouche 0.3` dependency line.

### Added

- **Task 30: RPC call timeouts** — `Onchain.EVM` now configures the underlying `reqwest::Client` with an explicit per-request timeout (default 30s) and a hard-coded 5s TCP connect timeout. Callers can override the request timeout per call with the new `:timeout_ms` option (positive integer, validated). Timeouts surface as `{:error, {:timeout, msg}}` — a new variant on the `nif_error()` union — so callers can distinguish slow/unreachable endpoints from execution errors. Previously, a hung RPC endpoint would block the dirty-IO scheduler indefinitely. Implementation switches `build_fork_db` from `ProviderBuilder::on_http(url)` to `on_client(RpcClient::new(Http::with_client(reqwest_client, url), is_local))` so the explicit `reqwest::Client` (with timeouts) is threaded through. Error classification walks the display string for `"timed out"` / `"deadline"` markers since the underlying `reqwest::Error` is reformatted by intermediate alloy/revm layers. `:timeout_ms` caps each individual RPC request, not aggregate simulation time — a single `simulate_transaction` may issue many RPC reads.
- **Task 34: String block tags in EVM** — `Onchain.EVM` now accepts `block: "latest"`, `"finalized"`, `"safe"`, `"pending"`, `"earliest"`, and `"0x..."` hex strings in addition to integers. Tag strings are passed to the NIF and resolved natively by Alloy's provider. Updated Rust `build_fork_db` to accept `BlockId` directly via a new `resolve_block_id` helper. Hex block parsing extracted to `parse_hex_block/2` with defensive `Integer.parse` handling (bare `"0x"` no longer crashes).
- **Task 35: rpc_url validation** — `require_rpc_url/1` now rejects empty strings, whitespace-only strings, non-HTTP(S) URLs, and hostless URLs (e.g. `"http://"`) with `{:error, {:invalid_rpc_url, reason}}` tuples. Missing rpc_url now returns `{:error, {:invalid_rpc_url, :missing}}` (was `{:error, {:evm_error, ...}}`). Previously, empty or malformed URLs passed through to the NIF and produced cryptic connection errors.
- **Task 36: Strict option validation** — `maybe_put_value/2`, `maybe_put_gas_limit/2`, and `maybe_put_state_overrides/2` now return `{:error, {:invalid_*, input}}` instead of silently dropping invalid inputs. Also fixed `Trace.maybe_put_value/2` to validate that `:value` is a binary string. All three functions integrated into the `with` chain for fail-fast behavior.
- **Task 37: `defbang` macro** — Created `Onchain.BangHelper` with `defbang/1-2` macro that generates bang functions from non-bang ok/error functions. Replaced 11 hand-written bang functions across `Onchain.EVM` (3), `Onchain.Trace` (3), and `Onchain.Solidity` (5) with macro calls. Supports simple error messages (Pattern A) and tagged error clauses with fallback (Pattern B/C). Case AST constructed manually to prevent Styler from rewriting multi-clause case expressions into pattern match assignments.
- **Task 38: Specific error union types** — Replaced `{:error, term()}` with named error type unions in `Onchain.EVM` and `Onchain.Trace`. EVM module defines `evm_error()` (union of `validation_error()` and `nif_error()`), Trace module defines `trace_error()` (union of `validation_error()` and `rpc_error()`). Per-function narrowing on `trace_transaction/2` and `storage_at/3` where the error surface is small. Added `@spec` to all private helper functions in both modules. Updated Descripex `api()` `returns.type` strings to match narrowed specs. Dialyzer can now verify error propagation through `with` chains end-to-end.
- **Task 39: Generator typespecs** — Added `@spec` to public `Onchain.Contract.Generator` functions: `resolve_abi/1`, `resolve_contract_input/2`, `to_snake_case/1`, `disambiguate/1`. `resolve_contract_input/2` spec documents the returned map shape (`:abi`, `:is_sol`, `:external_files`).
- **Task 49: Robust transport-error classification** — `classify_transport_error` (Rust NIF) now walks the `std::error::Error` source chain to recover the underlying `reqwest::Error` and classifies via `is_timeout()` / `is_connect()` instead of matching alloy/revm's reformatted display string. This makes `{:error, {:timeout, _}}` reliable (the Task 30 string-match missed reqwest timeouts that surfaced as `"database error: error sending request for url ..."`) and **restores `{:error, {:fork_error, _}}`** for connect failures (refused / DNS / unreachable), so callers can again distinguish transient infra failure (retry) from a simulation bug (don't retry). The chain is reached through revm's `EVMError::Database`, alloy's `#[error(transparent)]` `RpcError::Transport`, and `TransportErrorKind::Custom`'s `#[source]` box; display-string heuristics remain only as a fallback. Error messages now include the full source chain (e.g. `"... operation timed out"`). Covered by black-hole-timeout and connect-refused integration tests.

### Changed

- **Dependencies — onchain 0.8 / descripex 0.9 / cartouche 0.3 line.** Bumped `onchain` `~> 0.5` → `~> 0.8` and `descripex` `~> 0.6` → `~> 0.9` (onchain 0.8.0 relaxes its descripex floor; descripex 0.9.1's `safe_convert` fix keeps manifest/`describe` from crashing on unconvertible spec types). `onchain 0.8` pulls `cartouche 0.3.0`. Also bumped `rustler` `~> 0.37` → `~> 0.38`, `doctor` `~> 0.22` → `~> 0.23`, `ex_unit_json` → 0.5.0, and transitive HTTP-stack deps (`req`, `finch`, `mint`, `gun`, `decimal`). The onchain 0.5.3→0.8 path renamed the doc-private helper `Onchain.RPC.Helpers.to_signet_opts/1` → `to_rpc_opts/1`; `Onchain.Trace`'s 4 callsites were updated accordingly. No public onchain_evm API changes from the upgrade — compile clean under `--warnings-as-errors`, offline suite green.
- **Task 40: Removed dead Application module** — Deleted `lib/onchain_evm/application.ex` (empty supervision tree, never wired up) and the commented `mod:` line in `mix.exs`.
- **Task 41: Documented Generator options** — Added Options section to `Onchain.Contract.Generator` moduledoc covering all 6 input options (`:abi_json`, `:abi_file`, `:sol`, `:sol_file`, `:remappings`, `:root_contract`). Post-review fix: corrected three doc/implementation mismatches — "exactly one source required" → documents precedence order, `:abi_file` no longer claims project-root resolution, `:remappings` now correctly documented as Foundry-style string list.
- **Cleaned `.sobelow-skips`** — Regenerated from current code, removing stale entries from prior line-number shifts (30 → 15 entries).
- **Fixed ROADMAP.md Eff scores** — Recalculated all efficiency scores using the correct formula `(B + U) / (2 × D)`. Previous values were miscalculated (0.1–0.5 instead of 1.38–2.25).

### Fixed

- **High: Struct name collision across interfaces** — `qualify_user_type` now namespaces types from all contract types (interface, contract, abstract), not just libraries. Previously, `IA.Data` and `IB.Data` collapsed to `Data` in the type registry, causing wrong ABI encodings. Added context-aware type resolution (`resolve_struct`/`resolve_enum`) that tries `Owner.TypeName` before falling back to the short name.
- **Medium: Struct arrays in `from_raw/1`** — `build_struct_field_value` now strips array suffixes before checking struct names and wraps conversion in `Enum.map` for array types (`Item[]`, `Item[2]`). Previously, arrays of structs passed through as raw tuples.
- **Low: Enum constants inaccessible at runtime** — Replaced `Module.put_attribute/3` (compile-time only, discarded after compilation) with generated public functions (`def status_pending, do: 0`). Enum constants are now callable at runtime with `@spec` and `@doc`.

---

## [0.1.0] — Initial Release (Split from onchain)

Extracted from [onchain](../onchain) v0.3.0 monolith as a standalone package.

**What's included:**

- **Onchain.Solidity** — Rustler NIF: Alloy-powered Solidity ABI parser
- **Onchain.Contract.Generator** — macro: `.sol` → typed Elixir module at compile time, with import/remapping resolution
- **Onchain.EVM** — Rustler NIF: revm local EVM execution (fork mainnet state, simulate transactions)
- **Onchain.Trace** — debug/trace APIs (trace_transaction, trace_call, storage_at)
- **Native crates** — `native/onchain_evm/` (revm, alloy) and `native/onchain_solidity/` (alloy-json-abi, solang-parser)

**Why:** Consumers who don't need Rust NIFs no longer compile Rustler + two native crates. The core `onchain` package is now pure Elixir.
