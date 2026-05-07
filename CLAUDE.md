# Onchain Aave

Aave V3 protocol wrappers for Elixir. Depends on `onchain` core for RPC, ABI, signing, and address utilities.

@~/.claude/includes/across-instances.md
@~/.claude/includes/critical-rules.md

@~/.claude/includes/delegation.md
@~/.claude/includes/onchain-workspace.md
@~/.claude/includes/task-prioritization.md
@~/.claude/includes/task-writing.md
@~/.claude/includes/workflow-philosophy.md
@~/.claude/includes/web-command.md
@~/.claude/includes/elixir-setup.md
@~/.claude/includes/ex-unit-json.md
@~/.claude/includes/dialyzer-json.md
@~/.claude/includes/code-style.md
@~/.claude/includes/development-commands.md
@~/.claude/includes/development-philosophy.md
@~/.claude/includes/ethereum-rpc.md
@~/.claude/includes/agent-economy.md

## Architecture

- All modules use `Onchain.*` namespace (e.g., `Onchain.Aave.Pool`) — same as when they lived in the monolith
- Pure Elixir, no native deps
- Path dependency: `{:onchain, path: "../onchain"}`
- Standard error tuples: `{:ok, result} | {:error, {:tag, reason}}`

## Module Layout

```
lib/onchain/aave/
  contracts.ex                # address registry (mainnet + multi-chain)
  math.ex                     # to_usd, to_ltv, to_health_factor, to_ray
  pool.ex                     # read + write calls (getUserAccountData, supply, borrow, repay)
  oracle.ex                   # getAssetPrice + Chainlink
  ui_pool_data_provider.ex    # bulk reserve/user data
  faucet.ex                   # testnet faucet interactions
  types/
    user_account_data.ex
    aggregated_reserve_data.ex
    base_currency_info.ex
    user_reserve_data.ex
```

## Dependencies from onchain core

| Module | Used for |
|--------|----------|
| `Onchain.ABI` | ABI encoding/decoding |
| `Onchain.RPC` | eth_call |
| `Onchain.Signer` | Transaction signing (pool writes, faucet) |
| `Onchain.Address` | Validation, checksumming |
| `Onchain.Hex` | Hex encoding/decoding |
| `Onchain.Contract` | Generic contract call (oracle) |
| `Onchain.Decimal` | Decimal math (types) |

## Testing

```bash
mix test.json --quiet                          # Unit tests only
mix test.json --quiet --include integration    # Unit + integration (requires RPC)
mix test.json --quiet --only sepolia_send      # Sepolia write tests
```

Integration tests require `ETHEREUM_API_URL` or `ETH_RPC_URL` env var.
Sepolia write tests additionally require `ETH_SEPOLIA_PRIVATE_KEY` and `ETH_SEPOLIA_RPC_URL`.

## Contract Address Verification

When adding or updating addresses in `lib/onchain/aave/contracts.ex`, verify against the **Aave Address Book CSV**:

```bash
curl -s "https://raw.githubusercontent.com/bgd-labs/aave-address-book/main/safe.csv" | grep -i "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"
```

## Related Packages

- **onchain** — Core Ethereum primitives: `{:onchain, path: "../onchain"}`
- **onchain_evm** — Rust NIFs + codegen: `{:onchain_evm, path: "../onchain_evm"}`
