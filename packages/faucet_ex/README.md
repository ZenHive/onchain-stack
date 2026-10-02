# FaucetEx

Programmatic testnet funding for integration tests, as one library instead of
a helper copied into every repo.

One loop — read the balance, request funding, wait for it to land, read again,
bounded by a request budget and serialized per address — over pluggable
sources. The loop never knows which provider it is driving.

| Source | Provider | Asset |
|---|---|---|
| `Faucet.Source.CDP` | Coinbase Developer Platform faucet API | ETH / USDC / EURC / cbBTC on Base Sepolia, Ethereum Sepolia |
| `Faucet.Source.Tempo` | Tempo Moderato `tempo_fundAddress` RPC | pathUSD fee token + native gas |
| `Faucet.Source.Solana` | `requestAirdrop` RPC | SOL on devnet / testnet |
| `Faucet.Source.XRPL` | XRPL testnet faucet HTTP API | XRP on altnet |
| `Faucet.Source.ERC20Mint` | An Aave-style `mint(token, to, amount)` faucet contract | Any mintable test ERC-20 |
| `Faucet.ForkOverride` | None — builds `state_overrides` for `Onchain.EVM` fork simulation | ETH and ERC-20 balances |

## Installation

```elixir
def deps do
  [
    {:faucet_ex, "~> 0.2", only: :test},
    # Optional. Needed for ERC20Mint (signing), fresh keypairs and ForkOverride (keccak).
    {:onchain, "~> 0.16", only: :test}
  ]
end
```

## Usage

```elixir
# Top up an address to at least 0.001 ETH on Base Sepolia. Existing balance is
# reused; nothing is requested when it already suffices.
{:ok, wei} =
  Faucet.ensure_min_balance(Faucet.Source.CDP, address, 1_000_000_000_000_000, network: "base-sepolia")

# Fresh keypair funded with pathUSD on Tempo Moderato.
{:ok, %{private_key: key, address_hex: hex}} =
  Faucet.EVM.fresh_funded_wallet(Faucet.Source.Tempo, 1_000_000)

# Aave testUSDC on Base Sepolia, minted by the faucet contract from a gas-funded key.
{:ok, units} =
  Faucet.ensure_min_balance(Faucet.Source.ERC20Mint, address, 25_000_000,
    faucet: "0xd9145b5f45ad4519c7accd6e0a4a82e83bb8a6dc",
    token: "0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f",
    rpc_url: "https://sepolia.base.org",
    chain_id: 84_532,
    private_key: key
  )

# In ExUnit setup: fail loudly with the provider's reason instead of skipping.
Faucet.ensure_min_balance!(Faucet.Source.Solana, pubkey, 100_000_000)

# Fork simulation: no provider, just the override map Onchain.EVM accepts.
overrides =
  Faucet.ForkOverride.new()
  |> Faucet.ForkOverride.native(user, 10 ** 18)
  |> Faucet.ForkOverride.erc20(weth, user, 3, 5 * 10 ** 18)
```

Loop options: `:max_requests` (default 10), `:timeout_ms` (60_000),
`:poll_interval_ms` (1_000), `:lock` (`true`, serializes callers per address
via `:global.trans/2`). Everything else is passed to the source; each source
documents its keys.

## Writing a source

Implement `Faucet.Source`: `balance/2`, `fund/2`, `unit/0`, and optionally
`wait_confirmed/3`. Without the last, the loop polls `balance/2` until it rises
above the pre-request reading. `fund/2` receives `:deficit` in `opts` so a
source that can mint an exact amount does not have to guess.

## Credentials

Only `Faucet.Source.CDP` needs any: `CDP_API_KEY_ID` and `CDP_API_KEY_SECRET`
(Ed25519 key from https://portal.cdp.coinbase.com/access/api), or the
`:api_key_id` / `:api_key_secret` options. Missing credentials return
`{:error, {:missing_credential, name, hint}}` before any request is made.

## Discoverability

Public modules carry [Descripex](https://hex.pm/packages/descripex) hints:
`Faucet.describe()`, `Faucet.describe(:evm)`, `Faucet.describe(:evm, :wait_receipt)`.

## License

MIT
