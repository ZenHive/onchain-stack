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

Every read in this library also runs inside a local EVM, forked from any RPC
endpoint, via [onchain_evm](https://hex.pm/packages/onchain_evm) (revm through a
Rustler NIF). Add it yourself — `onchain_aave` does not pull it in at runtime:

```elixir
{:onchain_evm, "~> 0.5"}
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

`simulate_batch/2` runs several calls on **one** fork, and state carries from one
call to the next — an approval made in call 1 is visible to call 2:

```elixir
{:ok, approve} = Onchain.ABI.encode_call("approve(address,uint256)", [pool_bin, amount])
{:ok, allowance} = Onchain.ABI.encode_call("allowance(address,address)", [user_bin, pool_bin])

{:ok, [_approve_result, allowance_result]} =
  Onchain.EVM.simulate_batch([{weth, approve}, {weth, allowance}],
    rpc_url: rpc_url, from: user)

# allowance_result.output == amount
```

`:state_overrides` seeds an account before execution, so a wallet holding nothing
can still originate a value-bearing transaction — the local equivalent of a
faucet:

```elixir
{:ok, result} =
  Onchain.EVM.simulate_transaction(weth, "0xd0e30db0",
    rpc_url: rpc_url,
    from: broke_address,
    value: "0xDE0B6B3A7640000",
    state_overrides: %{broke_address => %{"balance" => "0x8AC7230489E80000"}})

result.success   #=> true
result.gas_used  #=> 45038
result.logs      #=> [%{topics: ["0xe1fffcc4…" | _], …}]  WETH Deposit
```

### What this does not cover yet

`onchain_evm` 0.5 leaves the block environment at its defaults — `block.number`
is `0` and `block.timestamp` is `1`, whatever `:block` is passed. Reads that
ignore time are unaffected, which is why the examples above hold. Aave's write
paths are not: `supply`, `borrow`, `repay` and liquidation all run
`MathUtils.calculateLinearInterest`, which subtracts the reserve's
`lastUpdateTimestamp` from `block.timestamp` and reverts with `Panic(0x11)`
(arithmetic underflow) against a 1970 clock. Simulate reads today; simulate
write paths against a forked node (`anvil --fork-url`) until the block
environment is wired through.

A `"storage"` entry in `:state_overrides` replaces the whole account, dropping
its deployed code with it — an override of `%{token => %{"storage" => …}}` turns
that token into an EOA and every call to it returns `"0x"`. Override `"balance"`
and `"nonce"` freely; pair `"storage"` with `"code"`.

## Configuration

Requires an Ethereum JSON-RPC endpoint, configured via onchain/cartouche:

```elixir
config :cartouche, :ethereum_node, "https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
```

Or pass `:rpc_url` per-call to any function.
