# Solidity parser frontend spike

Date: 2026-08-22

**Status (2026-08-22):** implemented by Task 61 (`df9fd1a`). Source parsing now
uses `solar-parse` 0.2.0. The characterization test asserts the four sources
below parse; it no longer records `solang-parser` rejections.

## Decision

Migrate the Solidity-source path from `solang-parser` to `solar-parse`. Keep
`parse_abi_json` on `alloy-json-abi` and preserve the existing Elixir output
contract exactly.

This spike changed no parser dependency or production behavior. The only code
change at the time was a characterization test for the observed `solang-parser`
ceiling.

## Measured language gap

`solang-parser` 0.3.5 was published on 2025-06-22 and describes itself as
compatible with Solidity 0.8.22. The four sources below were compiled together
with `solc` 0.8.36 through Standard JSON; the compiler returned all four
contracts and no errors. The same strings were then passed directly to each
Rust parser.

The release chronology matters. High-level `transient` declarations were not a
Solidity 0.8.24 feature: 0.8.24 added the EIP-1153 `tload`/`tstore` assembly
builtins, 0.8.27 accepted the state-variable syntax, and 0.8.28 added code
generation for value types. Custom storage layout syntax shipped in 0.8.29,
before the 0.3.5 crate publication, but is still absent. The 0.8.31 and 0.8.35
rows are language extensions shipped after the crate publication.

### 1. Transient state variables — Solidity 0.8.27/0.8.28

```solidity
pragma solidity ^0.8.28;
contract C { uint256 transient lock; }
```

Observed from `solang-parser` 0.3.5:

```text
unrecognised token 'lock', expected "(", ";", "="
```

### 2. Literal custom storage layout — Solidity 0.8.29

```solidity
pragma solidity ^0.8.29;
contract C layout at 42 { uint256 value; }
```

Observed from `solang-parser` 0.3.5:

```text
unrecognised token 'layout', expected "is", "{"
```

### 3. Constant custom storage layout — Solidity 0.8.31

```solidity
pragma solidity ^0.8.31;
uint256 constant BASE = 42;
contract C layout at BASE { uint256 value; }
```

Observed from `solang-parser` 0.3.5:

```text
unrecognised token 'layout', expected "is", "{"
```

### 4. `erc7201` custom storage layout — Solidity 0.8.35

```solidity
pragma solidity ^0.8.35;
contract C layout at erc7201("example.storage.C") { uint256 value; }
```

Observed from `solang-parser` 0.3.5:

```text
unrecognised token 'layout', expected "is", "{"
```

Measured total: four failing source forms across two missing grammar families,
with two forms introduced after the last crate publication. These are parser
failures, not failures in this crate's AST adapter.

## Candidate results and cost

The probe used released crates and the same four exact source strings:

| Frontend | Version tested | Result | Maintenance evidence | Migration cost |
|---|---:|---:|---|---|
| `solar-parse` | 0.2.0 | 4/4 valid | Solar 0.2.0 was released 2026-07-07; parser fixes were still landing on 2026-08-21. | **D:6.** Replace `pt` matches with the typed Solar AST. Its contract, function, variable, type, storage-layout, source-span, and parsed NatSpec nodes map directly to the data collected here. It requires Rust 1.95 and its isolated dependency closure contained 115 packages versus 56 for `solang-parser`. The API is pre-1.0. |
| `slang_solidity` | 1.3.7 | 4/4 valid at `LanguageFacts::LATEST_VERSION` (0.8.36) | 1.3.7 was released 2026-07-13 specifically with 0.8.36 support; 1.3.8 followed on 2026-08-05. | **D:7.** Slang provides version-aware parsing, a lossless CST, queries, source ranges, comments, and optional binding graphs. Rebuilding this crate's typed extraction over cursor/query traversal is more work than adapting a typed AST. The 1.3.7 closure contained 66 packages and requires Rust 1.94. The latest 1.3.8 requires Rust 1.97.1, above the 1.96 toolchain used for this probe. |
| Stay on `solang-parser` | 0.3.5 | 0/4 valid | The crate's documented compatibility ceiling is Solidity 0.8.22. Its latest published version remains 0.3.5. | **D:1 immediate, recurring compatibility cost.** No migration work and no output risk, but every listed source remains a compile-time failure in `Onchain.Contract.Generator`. Supporting new syntax would make this project maintain a parser fork. |

The package counts are unique nodes reported by `cargo tree` from an isolated
probe manifest. They estimate dependency/build cost, not runtime cost.

Solar is the preferred tradeoff. Slang has the stronger multi-version grammar
model and the smaller dependency closure, but exact version validation is not a
feature of `parse_sol` today. Solar's typed AST makes preservation of the
existing adapter substantially easier, and `solar-parse` is separable from the
unfinished Solar code generator.

## Public output compatibility

The frontend is private. A migration must not expose Solar AST values or alter
the terms returned by `parse_sol`, `__parse_sol_root__`, or
`__extract_sol_imports__`.

### Selectors and topics

Keep computing selectors and event topics inside this crate with Keccak-256 of
the canonical signature. Parser-provided semantic data must not replace the
existing `tiny-keccak` boundary without separate compatibility evidence.
Function and error selectors remain `0x` plus four bytes; event topics remain
`0x` plus 32 bytes.

### Canonical type strings

Preserve the existing normalization before hashing or encoding terms:

- payable addresses and contract references become `address`;
- enum references become `uint8`;
- struct references become recursively expanded tuple signatures and `tuple`
  parameter maps with `:components`;
- array suffixes remain attached to the normalized base type;
- `:return_type` remains a parenthesized comma-separated tuple string accepted
  by `Onchain.ABI.decode_response/2`.

The migration test must compare `parse_sol` and `parse_abi_json` selectors for
the same ABI, including nested structs and arrays. A parser accepting the source
is insufficient if it changes a canonical string.

### NatSpec attachment

Solar attaches parsed `DocComments` and `NatSpecItem` values to AST items. The
public result must still expose only the existing function-level map:

```text
%{notice: String.t(), params: %{String.t() => String.t()}, returns: %{String.t() => String.t()}}
```

Preserve the present attachment behavior during the parser migration, either
by retaining `extract_doc_comments` or by proving byte-for-byte parity before
using Solar's attachment. Expanding support to more NatSpec tags is a separate
public behavior change.

### Other invariants

Preserve source order, root-contract filtering, import extraction, structs,
enums, constants, constructor shape, mutability strings, and the
`{:error, {:parse_error, reason}}` boundary. `parse_abi_json` is unaffected.

## Follow-up task

### Migrate Solidity source parsing to Solar `[D:6/B:8/U:7]`

Replace the source parser with the released `solar-parse` frontend so
`Onchain.Contract.Generator` accepts Solidity through 0.8.36. Preserve every
existing `Onchain.Solidity.parsed_sol()` field and error tuple, and leave the
Alloy JSON-ABI path unchanged.

Success criteria (met by Task 61):

- [x] The four sources in this spike parse successfully through
      `Onchain.Solidity.parse_sol/1`.
- [x] Existing source-parser and Generator tests pass without output-shape
      changes.
- [x] Tests compare source and JSON-ABI signatures, selectors, topics,
      canonical nested types, and NatSpec attachment.
- [x] Import extraction and root-contract selection retain their existing
      behavior.
- [x] The dependency lock and the supported Rust version are updated and the
      full project gate passes.

## Reproduction and sources

Observed commands:

```text
npx --yes solc@0.8.36 --standard-json
cargo run --manifest-path native/onchain_solidity/target/parser-spike/Cargo.toml
cargo tree --manifest-path native/onchain_solidity/target/parser-spike/Cargo.toml -p <crate>
```

The isolated parser probe was scratch data and is not part of the deliverable.
The Rust characterization test now asserts those four sources parse through
`solar-parse`.

- [`solang-parser` 0.3.5 documentation and publication date](https://docs.rs/crate/solang-parser/0.3.5)
- [Solidity 0.8.27 transient syntax announcement](https://www.soliditylang.org/blog/2024/09/04/solidity-0.8.27-release-announcement/)
- [Solidity 0.8.28 transient code-generation announcement](https://www.soliditylang.org/blog/2024/10/09/solidity-0.8.28-release-announcement/)
- [Solidity 0.8.29 custom layout announcement](https://www.soliditylang.org/blog/2025/03/12/solidity-0.8.29-release-announcement/)
- [Solidity 0.8.31 constant layout announcement](https://www.soliditylang.org/blog/2025/12/03/solidity-0.8.31-release-announcement/)
- [Solidity 0.8.35 `erc7201` announcement](https://www.soliditylang.org/blog/2026/04/29/solidity-0.8.35-release-announcement/)
- [Solar 0.2.0 release](https://github.com/paradigmxyz/solar/releases/tag/v0.2.0)
- [Solar AST API](https://docs.rs/solar-ast/0.2.0/solar_ast/)
- [Slang 1.3.7 release](https://github.com/NomicFoundation/slang/releases/tag/v1.3.7)
- [Slang Rust API](https://docs.rs/slang_solidity/1.3.7/slang_solidity/)
