# Contract codegen in core (0.16 migration)

ABI JSON codegen now needs only `onchain`:

```elixir
defmodule MyApp.Token do
  use Onchain.Contract.Generator, abi_file: "priv/abis/token.json"
end
```

`Onchain.Contract.ABI.parse_abi_json/1` and `parse_abi_file/1` expose the
alloy-json-abi parser. Bang forms raise on errors. The generator also accepts
`:abi_json`. ABI files are registered as external resources for recompilation.

Solidity `:sol` / `:sol_file` inputs still require `onchain_evm` at development
time. Its `Onchain.Solidity` frontend resolves imports and parses source, then
supplies the core generator with enriched ABI metadata. Its existing ABI JSON
API delegates to core. solar-parse remains exclusively in onchain_evm; the core
NIF has no compiler frontend dependency.

## Release note

The breaking changes are recorded in `CHANGELOG.md` under v0.16.0.

## Native size measurement

On x86_64 Linux, the same release build command on the task's starting revision
and after adding ABI JSON parsing:

```sh
cargo build --release --manifest-path packages/onchain/native/onchain_abi/Cargo.toml
stat -c %s packages/onchain/native/onchain_abi/target/release/libonchain_abi.so
```

| Artifact | Before | After | Increase |
|---|---:|---:|---:|
| `libonchain_abi.so` | 1,863,376 bytes | 2,075,584 bytes | 212,208 bytes (11.39%) |

These are uncompressed host release artifacts, not every precompiled target.
alloy-json-abi was already a core dependency. onchain_solidity retains it only
as a test dependency for comparing source signatures to compiled ABI fixtures.

## Focused verification

Run in `packages/onchain`:

```sh
mix check.dispatch
mix test test/onchain/contract test/sleuth_test.exs test/abi_regression_test.exs \
  test/contract/ierc20_test.exs test/abi/native_boundary_test.exs
mix test test/cartouche/sleuth_integration_test.exs \
  test/onchain/contract/generator_integration_test.exs --include integration
```

The live tests require `ETHEREUM_API_URL` or `ETH_RPC_URL`.

Run in `packages/onchain_evm` to cover both ABI JSON and Solidity codegen:

```sh
ONCHAIN_EVM_BUILD=1 mix check.dispatch
ONCHAIN_EVM_BUILD=1 mix test test/onchain/solidity_test.exs test/onchain/contract/generator_test.exs
ONCHAIN_EVM_BUILD=1 MIX_ENV=test mix run --no-start ../onchain/scripts/codegen-coverage.exs
cargo test --manifest-path native/onchain_solidity/Cargo.toml
```

The scoped coverage script enforces 80% for `Onchain.Contract.Generator`;
measured coverage is 92.67% (253/273 executable lines). It includes constructors,
events, errors, tuple arguments and overloaded functions through the ABI tests,
and source structs, enums, NatSpec and import resolution through the EVM tests.

The current Aave and Aerodrome sources contain no direct generator invocations.
Their relevant consumer checks are `mix check.dispatch` plus Aave's
`test/onchain/aave/{pool,oracle}_test.exs` and Aerodrome's
`test/onchain/aerodrome/bindings` and `calldata_fixture_test.exs`.
Full QA is reserved for the separate post-merge audit.

Verification for this change: core dispatch passed; the focused core run passed
108 tests/properties, followed by 6 passing ABI tests after adding input-limit
coverage. EVM dispatch and 121 parser/generator tests passed with source-built
NIFs; the combined coverage run passed 82 tests. Native Solidity tests passed
7/7, and live integration tests passed 11/11. Aave dispatch and 85 tests passed;
Aerodrome dispatch and 37 tests passed. Aerodrome required
`PATH="/home/harness/.foundry/bin:$PATH"` for its existing cast reference tests.
Its first process exited with signal 135 during dependency compilation; the
serial rerun exposed the missing PATH entry, and the corrected run passed.
