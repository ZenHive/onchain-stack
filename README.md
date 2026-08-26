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

### Which endpoint serves what

This package is **Tempo-specific by design** — it is not portable to an arbitrary
Ethereum provider, and that is the point rather than an oversight. Type-`0x76`
transactions, TIP-20 encoding, and the synchronous broadcast path are Tempo protocol
features; a generic Ethereum endpoint has no notion of them. What you can swap is *which
Tempo-compatible endpoint* you point at — your own node, or a provider serving the Tempo
chain — not the chain itself.

| Surface | Works against | Notes |
|---|---|---|
| `Onchain.Tempo.Transaction`, `.Builder`, `.TIP20`, `.Transfer` | **no node at all** | Pure encode/decode/sign — offline, no RPC |
| `Onchain.Tempo.RPC.broadcast_async/3`, `fetch_receipt/3` | any Tempo endpoint (mainnet or Moderato) | Standard `eth_sendRawTransaction` / `eth_getTransactionReceipt` shapes |
| `Onchain.Tempo.RPC.broadcast_sync/3` | any Tempo endpoint | Uses `eth_sendRawTransactionSync`, a **Tempo extension** — a generic Ethereum node answers `-32601 Method not found` |
| `Onchain.Tempo.Faucet` | **Moderato only** | Wraps `tempo_fundAddress`, which mainnet does not expose |

Every RPC function takes an `rpc_url` so you can target either network per call. The
faucet additionally reads a **`TEMPO_RPC_URL` environment variable** as its default,
falling back to `https://rpc.moderato.tempo.xyz` — set it to point the faucet at a
different Moderato endpoint without threading a URL through every call
(`Onchain.Tempo.Faucet.rpc_url/0` returns the resolved value).

## 0x76 verification

Signing and canonical encoding are checked against the provider-owned
[Tempo transaction spec](https://tempo.xyz/developers/docs/protocol/transactions/spec-tempo-transaction)
and the current `ox` TypeScript SDK (`TxEnvelopeTempo`), plus live Moderato
broadcast success and a relevant decode error. Evidence lives in
`priv/verification/0x76/` (ledger, ox vectors, live observation). Unit tests
under `test/onchain/tempo/verification/` rerun the properties, differential
checks and mutation campaign; live checks are the `:integration` suite.

## License

MIT
