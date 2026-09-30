# Signer consolidation (Task 9040)

`Cartouche.Signer` is the survivor until the namespace rename in Task 9036.
Its existing carrier dispatch, message/typed-data signing, GenServer API,
low-s normalization, recovery verification, and EIP-155 packing remain intact.
The former `Onchain.Signer` transaction helpers now live on that module and
continue to pass `{Cartouche.Signer.Secp256k1, private_key}` to `sign_direct/4`.
There is no compatibility module at `Onchain.Signer`.

The two surfaces were complementary after Task 3089: the stateless transaction
API already used Cartouche's cryptographic implementation. Cartouche had the
broader tests (carrier/MFA parity, high-s backends, recovery, KMS, typed data,
and all supported transaction types), and its recorded critical signer
coverage was 96%. Keeping it preserves that implementation and merges the
transaction construction, gas estimation, error, bang-function, and live
broadcast tests under `test/signer/`.

## 0.16.0 breaking-change entry for the release changelog

Removed `Onchain.Signer`. Replace it with `Cartouche.Signer` for
`address_from_key/1`, `build_transaction/3`, `sign_transaction/3`,
`encode_transaction/1`, `send_transaction/3`, and their corresponding bang
variants (`address_from_key!/1`, `build_transaction!/3`, `sign_transaction!/3`,
`encode_transaction!/1`, `send_transaction!/3`). Descripex discovery now uses
the surviving `/ethereum/signer` namespace instead of `/signer`.

Return shapes are unchanged: `sign_transaction/3` retains the complete signed
`%Cartouche.Transaction.V2{}` inside `{:ok, signed_transaction}`; encoding
returns `{:ok, hex}`, broadcasting returns `{:ok, transaction_hash}`, and
existing tagged errors and bang behavior are preserved. The existing
Cartouche message-signing APIs continue to return packed signatures.

The same breaking entry is recorded under `Unreleased — v0.16.0` in
`packages/onchain/CHANGELOG.md`.

## Frozen byte evidence

Before changing production code, `bench/capture_signer_fixtures.exs` ran against
revision `186b9137b128598e2576c667de1d9ba7aaabfa40` with seed 9040. It traces
successful calls from the existing offline signer, transaction, typed-data,
recovery, key, and gas-estimation tests. The baseline passed 435 tests.

`test/support/fixtures/signers_before_consolidation.etf` stores 437 distinct
successful calls: 10 complete signed EIP-1559 transaction byte strings,
74 direct signatures, and 353 backend dispatch signatures (including the
prehashed transaction/typed-data path). Only public deterministic test keys
are used; integration tests are excluded. The capture script targets the old
revision and old test paths, and must not regenerate the oracle from the
consolidated implementation.

`test/signer/before_consolidation_test.exs` replays every record through the
survivor's public API and compares exact bytes. Existing ethers/viem,
pre-alloy transaction, KMS, low-s, cross-curve rejection, and recovery tests
remain in the focused run. The serialized fixtures retain the old module
atom solely as provenance, not as a callable implementation.

## Verification

From `packages/onchain`:

- `MIX_ENV=test mix run --no-start bench/signing_coverage.exs`: 452 passed,
  4 live tests excluded; all 437 frozen records matched. Critical signer
  coverage 97.84% (136/139), with `Cartouche.Signer` at 97.30% (108/111)
  and Backend, CloudKMS, and Secp256k1 at 100%.
- `mix check.dispatch`: passed.
- `mix test test/onchain/erc20_test.exs test/onchain/contract/generator_test.exs test/descripex_validation_test.exs test/onchain_test.exs`:
  62 passed.
- `mix test test/signer/transaction_integration_test.exs --include integration`:
  4 passed, including Sepolia receipt confirmation for explicit-gas and
  estimated-gas zero-value self-transfers.

Dependent checks (from each package directory):

- onchain_aave: `mix check.dispatch` passed;
  `mix test test/onchain/aave/{pool,faucet,debt_token,v4/position_manager}_test.exs`
  passed 120 tests.
- onchain_tempo: `mix check.dispatch` passed;
  `mix test test/onchain/tempo/faucet_test.exs test/onchain/tempo/transaction_test.exs test/onchain/tempo/transaction`
  passed 94 tests.
- onchain_solana:
  `mix test test/signer_boundary_test.exs test/solana/signer_test.exs test/solana/signer test/solana/transaction_test.exs`
  passed 94 tests.
- onchain_aerodrome: `mix test test/onchain/aerodrome/bindings` passed 27 tests.
  There are no signer callers or signing tests in this package to repoint;
  these tests exercise its core dependency boundary.

Solana already uses the retained backend contract. Neither its signing
internals nor Aerodrome code changed. Full QA remains post-merge work.
