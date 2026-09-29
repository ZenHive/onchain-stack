# Native Tempo encoding verification — task 9033

The separate `native/onchain_tempo` crate uses `tempo-primitives = 1.11.0`
(crates.io, 2026-08-20), default features disabled, `std` + `serde` enabled.
The committed lock resolves commonware-cryptography 2026.9.0. The normal dependency
graph has no revm; core onchain's native manifest and lock are unchanged.

`Transaction.fields` now carries a named transaction map, sender signature, and
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

The existing Elixir source-mutation campaign is **not green**: three assertions
in `verification/mutation_test.exs` fail because its eleven replacement patterns
target the removed encoder internals. Porting that campaign to the native encoder
is the explicitly excluded mutation/canary work. No tests, flags or assertions
were disabled. This is a required follow-up, not evidence of a passing full suite.
Full `mix ci`, coverage of the entire package, and analyzers were not run.

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
