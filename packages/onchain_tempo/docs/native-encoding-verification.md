# Native Tempo encoding verification

## Task 9052 — 0.13.0

The public transaction is now a named typed struct. Signature unions cover
Secp256k1, P-256, WebAuthn and keychain V1/V2; key authorizations, spending limits,
call scopes, access lists and Tempo authorizations use typed atom-key maps.
Only `Codec`, the internal NIF boundary, translates JSON. The builders also use
the struct and accept named call maps. `fields` is removed without a shim.
See the README migration table for every old RLP index and serde key.

`all_signatures.json` contains 15 independent ox 1.8.5 cases. They cover all
primitive types, both keychain versions with every primitive inner signature,
all three access-key types, P-256 with and without prehash, nested authorizations,
spending limits/scopes/witnesses, access lists, validity windows and CREATE.
Each checks exact bytes, signing/transaction hashes, sender recovery and
fee-payer cosigned bytes. Removing key authorization changes both signing
hashes. Tampered P-256/WebAuthn inner signatures fail recovery and cosigning;
truncated envelopes, unknown tags and incorrect signature lengths return errors.

The generator and npm lock are committed in `priv/verification/0x76/oracle`.
Regeneration is deterministic (SHA-256 of `all_signatures.json`:
`487efe54610a523d54f4524ce6c63095dd5c1c6e17db9a1c0fd41d0f65874e33`).
`all_signatures_live_evidence.json` records the successful Moderato P-256
receipt, expected/recovered sender and malformed-envelope RPC rejection.
The integration test signs with ox and a fresh random P-256 key; no production
P-256 signing API or private-key recording was added.

Verification from `packages/onchain_tempo`, with `ONCHAIN_BUILD=1` and
`ONCHAIN_TEMPO_BUILD=1` for Mix commands:

| Command | Result |
|---|---|
| `npm ci --prefix priv/verification/0x76/oracle --ignore-scripts` then `npm run generate --prefix priv/verification/0x76/oracle` | ox pinned to 1.8.5; 15 vectors; deterministic regeneration verified |
| `MIX_ENV=test mix run scripts/check-transaction-coverage.exs` | 101 tests/properties passed; Transaction coverage 98.21% (110/112 lines), floor 95% |
| `mix test test/onchain/tempo/integration/native_encoding_test.exs --include integration` | 2 passed; fresh P-256 transaction accepted and recovered; relevant RPC error recorded |
| `mix check.dispatch` | Passed: formatting and compilation with warnings as errors |
| `cargo test --locked --manifest-path native/onchain_tempo/Cargo.toml` | 4 passed, including every independent signature vector |
| `cargo clippy --locked --manifest-path native/onchain_tempo/Cargo.toml --all-targets -- -D warnings` | Passed |
| `scripts/build-precompiled.sh` | Passed for all five targets; artifacts in `artifacts/precompiled/v0.13.0/`; no checksum generated |
| AGENTS generation and `sync-agents-md.sh --check` | Passed; regenerated from package CLAUDE and host imports |

The release build used Rust 1.98.0, Zig 0.16.0 and cargo-zigbuild 0.23.3,
with NIF 2.15 and the script's glibc 2.28 floor. Install that cargo-zigbuild
version (`cargo install cargo-zigbuild --version 0.23.3 --locked`) and put
Zig 0.16.0 on PATH before invoking the script. cargo-zigbuild 0.23.4 failed:
its generic `-Wl,<file>` rewrite turns the exported-symbols-list argument into
a positional file; Zig 0.16 reports `unable to read exported symbols list
'-dead_strip'`. Zig 0.14/0.15 also crashed in the Darwin linker during earlier
attempts. The successful run used the unmodified project build script and
produced aarch64/x86_64 Darwin, aarch64/x86_64 GNU Linux, and x86_64 musl Linux
artifacts. This is cross-build evidence, not execution on each platform.

Existing mutation patterns were migrated to the typed API and checked against
the source. The full mutation campaign and full post-merge QA were not run;
the focused run above is the implementation evidence, not reviewer approval.

TEMPO-4 now distinguishes our Secp256k1 signing from all-type reading, hashing,
cosigning and recovery. TEMPO-5 and TEMPO-6 are added and tagged in tests.
CHANGELOG 0.13.0 records the named-field migration, and the 0.12.0 entry notes
the undocumented `fields` shape change and the Secp256k1-only signature
regression. No Hex publish, release upload or checksum change is part of this work.

## Task 9033 — 0.12 historical evidence

The separate `native/onchain_tempo` crate uses `tempo-primitives = 1.11.0`
(crates.io, 2026-08-20), default features disabled, `std` + `serde` enabled.
The committed lock resolves commonware-cryptography 2026.9.0. The normal dependency
graph has no revm; core onchain's native manifest and lock are unchanged.

In 0.12, `Transaction.fields` carried a named transaction map, sender signature, and
fee-payer-placeholder flag. Existing builder, deserialize, sender, co-sign,
payment matching and simulation functions retain tagged return contracts.
Production Elixir contains no 0x76/0x78 RLP encoder. Rust delegates encoding to
TempoTransaction and AASigned. A small decoding adapter replaces the fee-payer
service marker with RLP null before upstream decoding, then restores its meaning;
1.11.0's standard decoder cannot consume its own fee-payer-service marker.

## Oracles and byte parity

- `priv/verification/0x76/legacy_capture.json` was captured from the original
  encoder before replacing it; it records the original revision and all five
  ox fixture cases' unsigned bytes, signing hashes, transaction hashes, signed
  bytes and co-signed bytes. The new path matches every recorded value.
- `ox_vectors.json` remains unchanged (ox 1.7.2).
- `tempo_primitives_key_authorization.json` records the pinned native oracle's
  unsigned/signed/co-signed bytes, sender signing hash, fee-payer preimage/hash,
  and recovered identities. The original Elixir module, loaded under a temporary
  module name directly from HEAD, also matched its unsigned bytes, signing hash
  and co-signed bytes. Key authorization was already included in both domains;
  this migration does not claim to fix an omission.
- The [Tempo transaction spec](https://docs.tempo.xyz/protocol/transactions/spec-tempo-transaction)
  was retrieved 2026-09-29. Its content SHA-256 is recorded in the key vector.
  The full transaction field layout includes the AA authorization list before
  optional key authorization; the abbreviated fee-payer pseudocode omits the AA
  list. Verification uses the complete layout and pinned upstream implementation.
- Rust tests directly check canonical round trips and both signing hashes.
  Elixir independently reconstructs the spec preimage in test code and proves
  dropping key authorization changes the fee-payer hash.

The upstream decoder rejects malformed signature lengths, incomplete call tuples
and invalid validity windows which the old partial parser accepted. Tests now
assert those errors. Numeric limits follow the upstream u64/u128/U256 types.

## Live Moderato

`native_live_evidence.json` records a successful self-paid transfer without key
authorization, a successful sponsored transfer with key authorization, recovered
sender/payer identities, and rejection of `0x76ff`. Both receipts had status 1.
The integration test creates and funds fresh wallets; no private keys are stored.
`eth_sendRawTransactionSync` returned HTTP 502 on two attempts. The successful
run used `eth_sendRawTransaction` followed by `eth_getTransactionReceipt`.

Run explicitly:

```sh
ONCHAIN_BUILD=1 mix test test/onchain/tempo/integration/native_encoding_test.exs --include integration
```

`TEMPO_RPC_URL` must point to Moderato (42431), support `tempo_fundAddress`,
`eth_call`, `eth_getTransactionCount`, `eth_sendRawTransaction`, and
`eth_getTransactionReceipt`. Setup failure raises an assertion with these
requirements; the test never silently skips unavailable network access.

## Checks and remaining work

The focused Rust and Elixir checks pass. Transaction line coverage is measured
with the project's `ExUnitJSON.Coverage` calculation (excluding generated line 0)
and enforced at 95% by `scripts/check-transaction-coverage.exs`:

```sh
ONCHAIN_BUILD=1 MIX_ENV=test mix run scripts/check-transaction-coverage.exs
```

The source-mutation campaign in `verification/mutation_test.exs` targets the
native encoder glue (`native/onchain_tempo`), `Codec`, `Transaction`, and
`Builder`. Run it with:

```sh
ONCHAIN_BUILD=1 MIX_ENV=test mix test.json test/onchain/tempo/verification/mutation_test.exs
```

Evidence and per-mutant disposition live in `priv/verification/0x76/ledger.json`.

Core's ABI release URL currently returns 404, so local verification uses
`ONCHAIN_BUILD=1`. Tempo precompiled artifacts and checksums must be released
before Hex publication. Native build notes are in CLAUDE.md. Changelogs and the
roadmap are left to harness, as required by its operational rules.

## Measured build and dispatch results

On this x86_64 Linux worktree (Rust 1.98.0, OTP 29.1, Elixir 1.20.4), a locked
release build into an empty target directory took **24.86 seconds** with registry
sources already downloaded. The unstripped shared library was **3,777,440 bytes**.
This is a host build; the five release cross-targets were dry-run validated,
not built or published.

- `cargo test --locked --manifest-path native/onchain_tempo/Cargo.toml`: 3 passed.
- `cargo clippy --locked --manifest-path native/onchain_tempo/Cargo.toml -- -D warnings`: passed.
- `ONCHAIN_BUILD=1 MIX_ENV=test mix run scripts/check-transaction-coverage.exs`:
  97 passed, Transaction **99.1%** (110/111 source lines).
- Core `mix test test/precompiled_options_test.exs`: 2 passed.
- Explicit native Moderato integration: 1 passed, exercising both successes and
  the live error above.

The Tempo version moves to 0.12.0 because its core requirement now starts at
0.15, which introduced the shared precompiled infrastructure. The core helper
change must be published before the Tempo release; release preparation must
verify that the published core version contains Tempo crate dispatch.

The standard AGENTS generator cannot resolve the host's missing
`~/.claude/includes/harness-guardrails.md`; two other host imports are older
than the committed generated instructions. AGENTS.md was regenerated with a
worktree-local copy of the generator resolving those three imports to their
committed AGENTS.md snapshots, then checked with that same generator. The
unmodified host freshness command remains blocked on its missing import.

- `ONCHAIN_BUILD=1 mix check.dispatch` in core and
  `ONCHAIN_BUILD=1 MIX_ENV=test mix check.dispatch` in Tempo: both passed.
- `scripts/build-precompiled.sh --dry-run`: all five expected Tempo artifact
  names generated; no release upload was performed.

`MIX_ENV=test mix onchain.bounds onchain_tempo` passes: `~> 0.15` admits the
in-tree core 0.15.0. The task module is `lib/mix/tasks/onchain.bounds.ex`.
Published Hex onchain 0.15.0 does not yet contain the Tempo crate-dispatch
clauses added here, so that core change has to be published before
onchain_tempo 0.12.0. No full root `mix ci` is claimed.
