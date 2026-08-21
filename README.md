# OnchainAave

Aave V3 protocol wrappers for Elixir -- pool reads/writes, oracle, math, and type structs. Built on [onchain](https://github.com/ZenHive/onchain).

## Installation

```elixir
def deps do
  [
    {:onchain_aave, "~> 0.3"}
  ]
end
```

`onchain` (`~> 0.12`) arrives transitively — declare it directly only if you
call it yourself, and then with a bound that admits `~> 0.12`.

## Modules

| Module | Purpose |
|--------|---------|
| `Onchain.Aave.Pool` | Pool read + write calls (getUserAccountData, supply, borrow, repay; `get_user_account_data_many` batches many users via Multicall3) |
| `Onchain.Aave.Oracle` | Asset price oracle + Chainlink |
| `Onchain.Aave.Math` | USD conversion, LTV, health factor, ray math |
| `Onchain.Aave.Math.V4` | Aave V4 ray/wad math (cross-validated against revm) |
| `Onchain.Aave.DebtToken` | Variable/stable debt-token credit delegation (approveDelegation, borrowAllowance) |
| `Onchain.Aave.Contracts` | Verified address registry (mainnet + multi-chain, V3 + V4) |
| `Onchain.Aave.UiPoolDataProvider` | Reserves and user reserves data |
| `Onchain.Aave.Faucet` | Testnet faucet interactions (mint test tokens) |
| `Onchain.Aave.V4.Hub` | V4 Hub reads across Core/Prime/Plus (member Spokes, credit-line inventory and caps, rate environment) |

## Discovery

All modules use [descripex](https://hex.pm/packages/descripex) for self-describing APIs:

```elixir
OnchainAave.describe()                    # Module overview
OnchainAave.describe(:pool)               # Function listings
OnchainAave.describe(:pool, :supply)      # Full function details
```

## Configuration

Requires an Ethereum JSON-RPC endpoint, configured via onchain/cartouche:

```elixir
config :cartouche, :ethereum_node, "https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
```

Or pass `:rpc_url` per-call to any function.
