# OnchainEvm

Rust NIFs for Elixir: local EVM simulation via [revm](https://github.com/bluealloy/revm), Solidity ABI parsing via [Alloy](https://github.com/alloy-rs/alloy) and [solar-parse](https://github.com/paradigmxyz/solar), debug/trace APIs, and contract codegen. Built on [onchain](https://github.com/ZenHive/onchain).

## Installation

Requires no Rust toolchain on hosts with a matching precompiled artifact (macOS and Linux; see below). Windows, unmatched targets, and `RUSTLER_PRECOMPILED_FORCE_BUILD_ALL=1` still compile from source and need Rust 1.95+.

```elixir
def deps do
  [
    {:onchain, "~> 0.12"},
    {:onchain_evm, "~> 0.5"}
  ]
end
```

Matching hosts download a NIF from the GitHub Release for this version and verify it against `checksum-Elixir.Onchain.EVM.exs` / `checksum-Elixir.Onchain.Solidity.exs`. A missing or tampered checksum fails the load; it does not fall back to a silent source build.

To force a source build on any host:

```bash
RUSTLER_PRECOMPILED_FORCE_BUILD_ALL=1 mix compile
```

That env var is rustler_precompiled's own (`"1"` or `"true"`). The package-specific equivalent is `ONCHAIN_EVM_BUILD=1`, or `config :rustler_precompiled, :force_build, onchain_evm: true`. Source builds need `{:rustler, "~> 0.38"}` in the consumer's deps — it is an optional dependency of this package.

Windows is not a shipped target. Those consumers source-build.

## Precompiled release runbook

Order matters: the checksum step *downloads* what was uploaded, so artifacts must be live first. There is no CI. Cross-compilation is a local `cargo-zigbuild` ritual on an Apple Silicon Mac.

1. Tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`
2. Cross-build every shipped target for both crates: `scripts/build-precompiled.sh`
3. Publish the tarballs: `gh release create vX.Y.Z artifacts/precompiled/vX.Y.Z/*.tar.gz` (or `gh release upload` onto an existing tag)
4. Fetch them back and write checksums:
   `mix rustler_precompiled.download Onchain.EVM --all --print`
   `mix rustler_precompiled.download Onchain.Solidity --all --print`
5. Commit `checksum-Elixir.Onchain.EVM.exs` and `checksum-Elixir.Onchain.Solidity.exs` (both are in the Hex `files:` glob; omitting them drops checksum verification for every consumer)
6. `mix hex.publish`

Shipped targets, all reachable with `cargo-zigbuild` from one Mac: `aarch64-apple-darwin`, `x86_64-apple-darwin`, `x86_64-unknown-linux-gnu`, `aarch64-unknown-linux-gnu`, `x86_64-unknown-linux-musl`. Linux GNU builds pin glibc 2.28 via a Zig target suffix (`x86_64-unknown-linux-gnu.2.28`); the script asserts the artifact's GLIBC requirement rather than trusting the suffix. Adding riscv64 / armv7 is a one-line append to `TARGETS` in the script — they are not shipped.

The release is a manual local ritual with no build provenance or attestation, and it is reproducible only on a machine with the Zig toolchain installed. That is the accepted cost of not running CI.

## Modules

| Module | Purpose |
|--------|---------|
| `Onchain.EVM` | Local EVM execution — fork mainnet state, simulate calls/transactions/batches |
| `Onchain.Solidity` | Alloy-powered Solidity ABI parser (JSON ABI, `.sol` source, import resolution) |
| `Onchain.Trace` | Debug/trace APIs — `trace_transaction`, `trace_call`, `storage_at` |
| `Onchain.Contract.Generator` | `.sol` file → typed Elixir module at compile time |

## EVM Simulation

EVM simulation forks state from an RPC endpoint passed per-call via `:rpc_url`:

```elixir
# Simulate a read (eth_call semantics)
Onchain.EVM.simulate_call(usdc_address, calldata, rpc_url: "https://eth-mainnet.example.com")

# Full execution result (gas_used, success, return data)
Onchain.EVM.simulate_transaction(address, calldata, rpc_url: url)

# Batch many calls against one shared fork
Onchain.EVM.simulate_batch(calls, rpc_url: url)
```

**Options:**

| Option | Meaning |
|--------|---------|
| `:rpc_url` | RPC endpoint to fork from (required; empty/non-HTTP(S)/hostless rejected) |
| `:block` | Block to fork at — integer, `"0x…"` hex, or a tag (`"latest"`, `"finalized"`, `"safe"`, `"pending"`, `"earliest"`). Also selects the EVM revision that was active at that block on Ethereum mainnet; other chain ids are rejected |
| `:from` | Sender address (0x hex or 20-byte binary) |
| `:timeout_ms` | Per-RPC-request timeout (positive integer; default 30s, 5s connect). Surfaces as `{:error, {:timeout, msg}}` |
| `:value` | 0x-prefixed U256 hex quantity |
| `:gas_limit` | Positive integer ≤ u64 |
| `:state_overrides` | `%{address => %{balance/nonce/code/storage}}` applied on top of the forked account |

Malformed options fail at the Elixir boundary with a tagged `{:error, {atom, term}}`; they never reach the NIF.

Every public function has a bang (`!`) variant that raises on error.

## Contract Codegen

Generate a typed module from a `.sol` file or JSON ABI at compile time:

```elixir
defmodule USDC do
  use Onchain.Contract.Generator, abi_file: "priv/abis/erc20.json"
end

USDC.balance_of(contract, holder, rpc_url: url)   # => {:ok, [balance]}
```

Generator inputs (in precedence order): `:abi_json`, `:abi_file`, `:sol`, `:sol_file`. Solidity sources support `:remappings` (Foundry-style) and `:root_contract` for import resolution. Each generated module also emits a nested `Multicall` with typed call builders and result decoders for `Onchain.Multicall.aggregate3/2`.

## Discovery

All modules use [descripex](https://hex.pm/packages/descripex) for self-describing APIs:

```elixir
OnchainEvm.describe()                     # Module overview
OnchainEvm.describe(:evm)                 # Function listings
OnchainEvm.describe(:evm, :simulate_call) # Full function details
```

## Testing

```bash
mix test.json --quiet                        # Offline unit tests
mix test.json --quiet --include integration  # + integration (requires an RPC node)
```

Integration tests read `ETHEREUM_API_URL` (or `ETH_RPC_URL`).

## License

MIT
