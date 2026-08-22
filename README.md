# OnchainEvm

Rust NIFs for Elixir: local EVM simulation via [revm](https://github.com/bluealloy/revm), Solidity ABI parsing via [Alloy](https://github.com/alloy-rs/alloy), debug/trace APIs, and contract codegen. Built on [onchain](https://github.com/ZenHive/onchain).

## Installation

Requires a Rust toolchain for NIF compilation.

```elixir
def deps do
  [
    {:onchain, "~> 0.12"},
    {:onchain_evm, "~> 0.5"}
  ]
end
```

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
| `:block` | Block to fork at — integer, `"0x…"` hex, or a tag (`"latest"`, `"finalized"`, `"safe"`, `"pending"`, `"earliest"`) |
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
