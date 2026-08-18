# OnchainTempo

[![Hex.pm](https://img.shields.io/hexpm/v/onchain_tempo.svg)](https://hex.pm/packages/onchain_tempo)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/onchain_tempo)

Tempo blockchain primitives for Elixir — 0x76 transaction handling, TIP-20 token encoding, RPC broadcasting, and TransferWithMemo event parsing.

Built on [onchain](https://hex.pm/packages/onchain).

## Installation

```elixir
def deps do
  [
    {:onchain_tempo, "~> 0.9"}
  ]
end
```

Documentation: [hexdocs.pm/onchain_tempo](https://hexdocs.pm/onchain_tempo).

## Modules

| Module | Purpose |
|--------|---------|
| `Onchain.Tempo.TIP20` | TIP-20 function selectors, calldata encoders, Tempo constants |
| `Onchain.Tempo.Transaction` | 0x76 transaction struct, deserialize, payment matching, fee payer co-signing |
| `Onchain.Tempo.Transaction.Builder` | Build and sign 0x76 transactions from scratch |
| `Onchain.Tempo.RPC` | Tempo JSON-RPC operations (broadcast async/sync, fetch receipt, pre-broadcast `eth_simulateV1`) |
| `Onchain.Tempo.Transfer` | TransferWithMemo event log parsing |
| `Onchain.Tempo.Faucet` | Moderato testnet faucet — `tempo_fundAddress` wrapper (testing only) |

## Quick Start

### Deserialize a Tempo transaction

```elixir
{:ok, tx} = Onchain.Tempo.Transaction.deserialize("0x76...")
tx.chain_id  #=> 42431
tx.calls     #=> [%{to: <<...>>, value: 0, input: <<...>>}]
```

### Find a payment call

```elixir
{:ok, match} = Onchain.Tempo.Transaction.find_payment_call(tx, token_address,
  amount: "1000000",
  recipient: "0x70997970..."
)
match.amount  #=> 1000000
```

### Build and sign a transfer

```elixir
{:ok, tx_hex} = Onchain.Tempo.Transaction.Builder.build_signed_transfer(
  private_key: "0xac09...",
  token: "0x20c0...",
  recipient: "0x7099...",
  amount: 1_000_000,
  chain_id: 42_431,
  rpc_url: "https://rpc.moderato.tempo.xyz"
)
```

### Broadcast

```elixir
# Async (returns tx hash immediately)
{:ok, tx_hash} = Onchain.Tempo.RPC.broadcast_async(tx_hex, rpc_url)

# Sync (waits for block inclusion, returns receipt)
{:ok, tx_hash, receipt} = Onchain.Tempo.RPC.broadcast_sync(tx_hex, rpc_url)
```

### Fund a Moderato testnet wallet

For integration tests against Moderato (testnet `42_431`), `Onchain.Tempo.Faucet`
wraps the non-standard `tempo_fundAddress` JSON-RPC:

```elixir
# Fund an existing address.
{:ok, [tx_hash | _]} = Onchain.Tempo.Faucet.fund_address("0xabc...")

# Generate + fund a fresh keypair (polls for confirmation before returning).
{:ok, %{private_key: priv, address_hex: hex, address_bin: bin}} =
  Onchain.Tempo.Faucet.fresh_funded_wallet()
```

Defaults to `https://rpc.moderato.tempo.xyz`; overridable via `TEMPO_RPC_URL`
or by passing `rpc_url:` in the opts (e.g. `fund_address("0xabc...", rpc_url:
"https://my-mirror")`). Mainnet does not support `tempo_fundAddress`.

## Discovery

All modules use [descripex](https://hex.pm/packages/descripex):

```elixir
OnchainTempo.describe()                          # Module overview
OnchainTempo.describe(:transaction)              # Function list
OnchainTempo.describe(:transaction, :deserialize) # Full details
```

## Tempo Networks

| Network | Chain ID | RPC URL |
|---------|----------|---------|
| Mainnet | `4217` | `https://rpc.tempo.xyz` |
| Moderato (testnet) | `42431` | `https://rpc.moderato.tempo.xyz` |

## License

MIT
