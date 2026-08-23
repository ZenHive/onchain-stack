# OnchainAave

Aave V3 and V4 protocol wrappers for Elixir -- V3 pool reads/writes, V4 Hub-and-Spoke reads and Position Manager writes, oracle, math, and type structs. Built on [onchain](https://github.com/ZenHive/onchain).

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
| `Onchain.Aave.Math` | USD conversion, LTV, health factor, V3 WadRayMath / MathUtils (revm- and mutation-checked) |
| `Onchain.Aave.Math.V4` | Aave V4 ray/wad math (pinned-bytecode revm and mutation-checked) |
| `Onchain.Aave.DebtToken` | Variable/stable debt-token credit delegation (approveDelegation, borrowAllowance) |
| `Onchain.Aave.Contracts` | Verified address registry (mainnet + multi-chain, V3 + V4) |
| `Onchain.Aave.UiPoolDataProvider` | Reserves and user reserves data |
| `Onchain.Aave.Faucet` | Testnet faucet interactions (mint test tokens) |
| `Onchain.Aave.V4.Hub` | V4 Hub reads across Core/Prime/Plus (member Spokes, credit-line inventory and caps, rate environment, share/asset previews, bound constants) |
| `Onchain.Aave.V4.Oracle` | V4 Spoke-scoped IAaveOracle reads (reserve prices, sources, decimals) plus Chainlink feeds |
| `Onchain.Aave.V4.PositionManager` | V4 Giver/Taker writes (supply/repay/borrow/withdraw on-behalf-of) plus Taker allowances |
| `Onchain.Aave.V4.Spoke` | V4 Spoke reads (reserve/user data, position-manager checks) |
| `Onchain.Aave.V4.TokenizationSpoke` | V4 ERC-4626 Tokenization Spoke reads (`lookup(hub, asset)`, share accounting, Hub/asset metadata) |

## Discovery

All modules use [descripex](https://hex.pm/packages/descripex) for self-describing APIs:

```elixir
OnchainAave.describe()                    # Module overview
OnchainAave.describe(:pool)               # Function listings
OnchainAave.describe(:pool, :supply)      # Full function details
```

## Local simulation against forked state

Every call in this library — reads *and* writes — also runs inside a local EVM
forked from any RPC endpoint, via
[onchain_evm](https://hex.pm/packages/onchain_evm) (revm through a Rustler NIF).
Add it yourself; `onchain_aave` does not pull it in at runtime:

```elixir
{:onchain_evm, "~> 0.6"}
```

Read Aave state at fork state, with no transaction and no gas:

```elixir
pool = "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"
{:ok, data} = Onchain.ABI.encode_call("getUserAccountData(address)", [user_bin])
{:ok, out} = Onchain.EVM.simulate_call(pool, data, rpc_url: rpc_url)

{:ok, raw} = Onchain.ABI.decode_types("(uint256,uint256,uint256,uint256,uint256,uint256)", out)
Onchain.Aave.Types.UserAccountData.from_raw(raw)
#=> %UserAccountData{total_collateral_base: #Decimal<…>, health_factor: #Decimal<…>, …}
```

`simulate_batch/2` runs several calls on **one** fork and carries state between
them, and `:state_overrides` seeds accounts beforehand — so a wallet holding
nothing can approve, supply, and be scored, entirely locally. `"balance"`,
`"nonce"` and `"code"` are hex strings; `"storage"` is a JSON string of a
slot→value map:

```elixir
# WETH's balanceOf mapping lives at storage slot 3
slot = Cartouche.Hash.keccak(<<0::96>> <> user_bin <> <<3::256>>) |> Onchain.Hex.encode()

{:ok, approve} = Onchain.ABI.encode_call("approve(address,uint256)", [pool_bin, amount])
{:ok, supply} = Onchain.ABI.encode_call("supply(address,uint256,address,uint16)", [weth_bin, amount, user_bin, 0])
{:ok, query} = Onchain.ABI.encode_call("getUserAccountData(address)", [user_bin])

{:ok, [_approve, supply_result, account]} =
  Onchain.EVM.simulate_batch(
    [{weth, approve}, {pool, supply}, {pool, query}],
    rpc_url: rpc_url,
    from: user,
    state_overrides: %{
      user => %{"balance" => "0x8AC7230489E80000"},
      weth => %{"storage" => JSON.encode!(%{slot => "0x8AC7230489E80000"})}
    }
  )

supply_result.success   #=> true
supply_result.gas_used  #=> 184324
supply_result.logs      #=> ReserveDataUpdated, aWETH Transfer/Mint, Supply

{:ok, raw} = Onchain.ABI.decode_types("(uint256,uint256,uint256,uint256,uint256,uint256)", account.output)
Onchain.Aave.Types.UserAccountData.from_raw(raw)
#=> %UserAccountData{total_collateral_base: #Decimal<24262.09170529>,
#=>                  ltv: #Decimal<0.805>, current_liquidation_threshold: #Decimal<0.83>, …}
```

The fork's block environment comes from the forked block header — number,
timestamp, basefee, gas limit, coinbase and prevrandao — so interest accrual,
oracle staleness checks and anything else reading `block.timestamp` behave as
they do on chain. `:state_overrides` are applied on top of the fetched account
rather than replacing it, so the `"storage"` patch above leaves WETH's deployed
code intact.

`test/onchain/aave/v4/deployed_integration_test.exs` runs the same path against
V4: it supplies, borrows and repays through the PositionManager against mainnet
state at a pinned block.

## Configuration

Requires an Ethereum JSON-RPC endpoint, configured via onchain/cartouche:

```elixir
config :cartouche, :ethereum_node, "https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
```

Or pass `:rpc_url` per-call to any function.
