# Changelog

Completed roadmap tasks. For upcoming work, see [ROADMAP.md](ROADMAP.md).

---

## [Unreleased]

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
