# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## [Unreleased]

## [0.4.0] — 2026-08-01

No public API change.

**Minor, not patch.** This was drafted as 0.3.1 while every dependency edit was
dev/test-scoped. It now narrows a *runtime* requirement (`descripex`), and
narrowing a runtime bound can fail resolution for a consumer pinned below the
new floor. That failure is loud rather than silent, but it is still a
compatibility break and semver should say so.

### Changed — `{:onchain, "~> 0.11"}` → `{:onchain, "~> 0.12"}`

onchain 0.12.0 is the release that raises `zen_websocket` to `~> 0.6.0`, which
*requires* the gun version carrying the GHSA-w4f7-4cxr-rv3c fix rather than
merely permitting it. `~> 0.11` admits 0.12.0 but does not require it, so this
package's lock would have kept resolving onchain 0.11.0 → zen_websocket 0.4.2,
whose looser gun bound only happens to have landed on a fixed 2.5.0 — a lock
entry that still satisfies its bound is never re-resolved.

The lock now carries onchain 0.12.0 and zen_websocket 0.6.0. onchain 0.12.0 also
narrows `descripex` to `~> 0.12.0`, matching what this package now declares
directly (below). No code change was needed: onchain 0.12.0 makes no public API
change, and the suite is green against it.

### Changed — hieroglyph 1.6.0 in the lock, `elixir: "~> 1.17"` → `"~> 1.18"`

`mix.exs` gains no `hieroglyph` line — it arrives transitively through
onchain/cartouche, whose published bounds already admit it — but the lock now
carries 1.6.0, which restores `ABI.Event.decode_event/4`'s documented total
contract (unnamed event inputs no longer raise; an array length prefix that
cannot fit the remaining payload is rejected before the element list is
allocated) and makes `decode_structs: true` work on the event path.

The Elixir floor moves with it: hieroglyph 1.6.0's encode path uses
`Enum.sum_by/2` (1.18+), so declaring `~> 1.17` here would let this package
resolve on 1.17 and then fail compiling a dependency. Same reasoning as the
`descripex` narrowing below — a loud resolution failure, but still a
compatibility break.

### Changed — `{:descripex, "~> 0.11"}` → `{:descripex, "~> 0.12.0"}`

descripex 0.12.0 changed `short_name` in `describe/1` output from an atom to a
string — a consumer-visible contract change shipped at a *minor* bump, which the
old two-segment `~> 0.11` (`>= 0.11.0 and < 1.0.0`) would have absorbed on any
fresh resolution without a version bump here. The requirement is now
three-segment (`< 0.13.0`): a 0.x package that breaks on minor earns the tighter
form, and the cap gets raised deliberately after reading its release notes.

The `short_name` in `lib/onchain/contract/generator.ex` is an unrelated local
variable in the ABI enum-constant codegen, not descripex's field — nothing here
reads `describe/1` output. The suite (220 tests) is green against descripex
0.12.0 with no code change; the break is in the *bound*, not the behaviour.

### Fixed — 28 `length/1` comparisons, and one redundant guard

`credo --strict` reported 28 findings, all
`ExSlop.Check.Refactor.LengthComparison` — comparing `length/1` against a
literal where a pattern match answers the question without the O(n) walk. 26
were assertions in test files, rewritten to `match?([_, _, ...], list)`; the
pass/fail boundary is unchanged and no assertion became vacuous. Two were in
`lib/`: a `match?([_], ...)` in `solidity/resolver.ex`, and in
`contract/generator.ex` the clause guard `collisions when length(collisions) > 1`
became a bare `collisions ->`. That last one is behaviour-preserving because
`groups` is built by `Enum.group_by` over the same list the element comes from,
so the lookup is never empty and everything not matching `[_single]` has two or
more members.

### Changed — reach smell findings cleared

`.reach.exs` now carries `smells: [strict: true]` — the flag is the point, since
`reach.check --smells` raises only when `opts[:strict] || config.smells.strict`
and otherwise reports findings and exits 0. Cleared: `@doc false` on three
private functions in `solidity/resolver.ex`, a `case` reducible to `match?/2` in
`trace.ex`, a repeated-shape map in `contract/generator.ex` replaced by a
`ResolvedInput` struct, an `Enum.at/2`-in-loop replaced by tuple indexing, and a
string-concat accumulation replaced by iodata. Findings get fixed, never
ignore-listed — including the pre-existing `smells: [ignore: [paths: ...]]`
entries, which were removed after confirming what they had been hiding.

### Changed — the rest of the quality gates now actually gate

- **`mix_audit` added and wired.** `deps.audit.gated` proves the advisory
  database is current *before* auditing — `mix_audit` discards its own sync exit
  status (mirego/mix_audit#61), so a database that can no longer sync still
  prints "No vulnerabilities found" and exits 0.
- **`agents.check`** fails when `AGENTS.md` has drifted from `CLAUDE.md`.
- **CI invokes `mix ci`** instead of a hand-maintained check list.

## [0.3.0] — 2026-06-25

### Changed — `{:onchain, "~> 0.10"}` → `{:onchain, "~> 0.11"}`

onchain 0.11.0 is the release that carries `cartouche ~> 0.6`, which is what
lifts cartouche's transitive `req < 0.7` cap. The old two-segment `~> 0.10`
bound already *permitted* 0.11.0 but did not *require* it — a consumer holding a
lock on onchain 0.10.0 would have gone on resolving cartouche 0.5.x, and
therefore req 0.6.x, through any number of `mix deps.get` runs, because a
lockfile entry that still satisfies its bound is never re-resolved. Raising the
floor invalidates that entry so the upgrade happens on its own.

Resolves here to onchain 0.11.0, cartouche 0.6.0, descripex 0.11.0, req 0.7.1.

### Added

- **Vibe analyzer stack** — adopted the onchain-family analyzer toolchain: `ex_dna`, `ex_ast`, `ex_slop`, and `reach` (dev/test only). New `.credo.exs` (ExSlop plugin, `Readability.Specs` scoped to the library + test support) and `.reach.exs` (arch/smell policy; the compile-time contract generator is scoped out of the smell detector since its `String.to_atom` calls create the identifiers they emit). Added `precommit` (fast local loop), `precommit.full`/`ci` (the harness reviewer's `check_command`), and `integration` mix aliases.
- **`@spec` coverage** — added typespecs to all private helpers in `Onchain.Contract.Generator` and `Onchain.Solidity`, the NIF stubs in `Onchain.EVM`, and the `Onchain.BangHelper` macro helpers, satisfying the newly-enabled `Credo.Check.Readability.Specs`.
- **Solidity resolution unit tests** — temp-fixture tests for `resolve_sol_file/2` (relative/absolute/remapped imports, `remappings.txt`, `:root_contract` override, and the error paths) plus a `parse_sol_file/2` single-file fallback test.

### Changed

- **Dependencies — onchain 0.10 / cartouche 0.5 line.** Bumped `onchain` `~> 0.8` → `~> 0.10` and `descripex` `~> 0.9` → `~> 0.11`; `onchain 0.10` pulls `cartouche 0.5.0` (was 0.4.0) and `req 0.6.2`. No public onchain_evm API changes — full suite green (218 unit + 30 integration).
- **Native dependencies** — bumped `rustler` `0.37` → `0.38` (both crates, with the matching `mix.exs` constraint) and `alloy-json-abi` `0.8` → `1.6` in `native/onchain_solidity`; `ex_doc` `~> 0.39` → `~> 0.40` (older pin held `makeup_elixir < 1.0`, conflicting with `reach`).
- **`native/onchain_evm` revm/alloy major bump (Task 55)** — bumped `revm` `19` → `41` (now splitting the `alloydb` feature into the new `revm-database` crate) and the `alloy-*` stack `0.7`/`0.8` → `2.1`/`1.6` (`reqwest` `0.12` → `0.13`), clearing the low-severity `lru` advisory. Migration rewrites the fork-DB type alias to `WrapDatabaseAsync<AlloyDB<…>>`, replaces the `Evm::builder().modify_tx_env(…)` flow with the revm 41 `TxEnv::builder()` + `Context::mainnet().build_mainnet()` API, and threads per-call nonces through `simulate_batch` (revm 41 makes `TxEnv.nonce` a required `u64`). Adds Rust unit tests for `build_tx`.
- **Post-audit revm 41 fixes** — restored revm-19 behavior the major bump silently changed: (1) the read-only single-tx paths (`simulate_call` / `simulate_transaction`) now set `disable_nonce_check = true`, since revm 41 made `TxEnv.nonce` a required `u64` with default checking and these model `eth_call`/`eth_estimateGas`, which never validate nonce — simulating from any EOA with tx history regressed to `NonceTooLow` (added a high-nonce-EOA integration test; the prior golden tests only used nonce-0 senders); (2) `simulate_batch([])` returns `{:ok, []}` before opening the fork DB, eliminating a stray `eth_getTransactionCount` RPC read for an empty no-op batch. Also documented a known limitation: revm 41 defaults to the latest hardfork spec (OSAKA), so historical-block forks execute under newer rules — not derived from the block because these NIFs fork arbitrary (non-mainnet) chains.
- **Cover-able validation siblings** — extracted the pure-Elixir input validation and NIF-param assembly out of the two NIF-backed modules into `Onchain.EVM.Params` and `Onchain.Solidity.Resolver`, so the coverage gate can instrument them (the NIF `on_load` is incompatible with cover's beam recompilation). Behavior-preserving; the thin NIF shells stay `ignore_modules` in `test_coverage`.
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
