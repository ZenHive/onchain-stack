# OnchainEvm

Rust NIFs for Elixir: local EVM simulation via [revm](https://github.com/bluealloy/revm), Solidity ABI parsing via [Alloy](https://github.com/alloy-rs/alloy), debug/trace APIs, and contract codegen. Built on [onchain](https://github.com/ZenHive/onchain).

## Installation

Requires Rust toolchain for NIF compilation.

```elixir
def deps do
  [
    {:onchain, "~> 0.4"},
    {:onchain_evm, "~> 0.1"}
  ]
end
```

## Modules

| Module | Purpose |
|--------|---------|
| `Onchain.EVM` | Local EVM execution (fork mainnet, simulate transactions) |
| `Onchain.Solidity` | Alloy-powered Solidity ABI parser |
| `Onchain.Trace` | Debug/trace APIs (trace_transaction, trace_call, storage_at) |
| `Onchain.Contract.Generator` | `.sol` file -> typed Elixir module at compile time |

## Discovery

All modules use [descripex](https://hex.pm/packages/descripex) for self-describing APIs:

```elixir
OnchainEvm.describe()                     # Module overview
OnchainEvm.describe(:evm)                 # Function listings
OnchainEvm.describe(:evm, :simulate_call) # Full function details
```

## Configuration

EVM simulation requires an RPC URL passed per-call:

```elixir
Onchain.EVM.simulate_call(address, calldata, rpc_url: "https://eth-mainnet.example.com")
```
