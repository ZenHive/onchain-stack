# OnchainAave

Aave V3 protocol wrappers for Elixir -- pool reads/writes, oracle, math, and type structs. Built on [onchain](https://github.com/ZenHive/onchain).

## Installation

```elixir
def deps do
  [
    {:onchain, "~> 0.5"},
    {:onchain_aave, "~> 0.1"}
  ]
end
```

## Modules

| Module | Purpose |
|--------|---------|
| `Onchain.Aave.Pool` | Pool read + write calls (getUserAccountData, supply, borrow, repay) |
| `Onchain.Aave.Oracle` | Asset price oracle + Chainlink |
| `Onchain.Aave.Math` | USD conversion, LTV, health factor, ray math |
| `Onchain.Aave.Contracts` | Verified address registry (mainnet + multi-chain) |
| `Onchain.Aave.UiPoolDataProvider` | Reserves and user reserves data |
| `Onchain.Aave.Faucet` | Testnet faucet interactions (mint test tokens) |

## Discovery

All modules use [descripex](https://hex.pm/packages/descripex) for self-describing APIs:

```elixir
OnchainAave.describe()                    # Module overview
OnchainAave.describe(:pool)               # Function listings
OnchainAave.describe(:pool, :supply)      # Full function details
```

## Configuration

Requires an Ethereum RPC URL configured for `signet` (via onchain):

```elixir
config :signet, :rpc_url, "https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
```

Or pass `:rpc_url` per-call to any function.
