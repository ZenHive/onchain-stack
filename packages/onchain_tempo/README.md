# OnchainTempo

[![Hex.pm](https://img.shields.io/hexpm/v/onchain_tempo.svg)](https://hex.pm/packages/onchain_tempo)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/onchain_tempo)

Tempo blockchain primitives for Elixir — 0x76 transaction handling, TIP-20 token encoding, RPC broadcasting, and TransferWithMemo event parsing.

Built on [onchain](https://hex.pm/packages/onchain).

## Installation

```elixir
def deps do
  [
    {:onchain_tempo, "~> 0.13"}
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

Version 0.13 removes `tx.fields`. Read and update named struct fields, then call
`Transaction.serialize/1`. `raw` retains the original broadcast hex;
`serialize/1` returns hex for the current fields. `signing_hash/1`, `hash/1`, and `sender/1` return `{:ok, binary}`.
Decode, serialization, hashing, fee-payer cosigning and recovery support
Secp256k1, P-256, WebAuthn, and keychain V1/V2. Our builders sign with
Secp256k1 keys. Keychain recovery verifies the inner signature, but callers
must separately check access-key authorization on-chain.

Signatures are `{:secp256k1, %{r: integer, s: integer, y_parity: 0 | 1}}`,
`{:p256, %{r: binary, s: binary, pub_key_x: binary, pub_key_y: binary, pre_hash: boolean}}`,
`{:webauthn, %{r: binary, s: binary, pub_key_x: binary, pub_key_y: binary, webauthn_data: binary}}`,
or `{:keychain, 1 | 2, user_address_binary, primitive_signature}`.
Key authorizations are typed maps with atom keys; see `t:Onchain.Tempo.Transaction.key_authorization/0`.
Multicall builders accept `%{to: address_binary, value: integer, input: binary}` calls.

### Migration from 0.11 and 0.12

0.12 changed `fields` from positional RLP to an internal serde map without
documenting the break, and restricted signatures to Secp256k1. 0.13 replaces
both representations with named fields and restores all supported signatures.
The 0.12 keys below lived under `fields["transaction"]` unless stated otherwise.
Addresses/data now use binaries, quantities use integers, and absent optionals
use `nil`. A fee-payer placeholder is `:placeholder`.

| 0.11 RLP index (zero-based) | 0.12 serde key | 0.13 field |
|---|---|---|
| 0 | `chainId` | `chain_id` |
| 1 | `maxPriorityFeePerGas` | `max_priority_fee_per_gas` |
| 2 | `maxFeePerGas` | `max_fee_per_gas` |
| 3 | `gas` | `gas_limit` |
| 4 | `calls` | `calls` |
| 5 | `accessList` | `access_list` |
| 6 | `nonceKey` | `nonce_key` |
| 7 | `nonce` | `nonce` |
| 8 | `validBefore` | `valid_before` |
| 9 | `validAfter` | `valid_after` |
| 10 | `feeToken` | `fee_token` |
| 11 | `feePayerSignature` / `fields["placeholder"]` | `fee_payer_signature` |
| 12 | `aaAuthorizationList` | `tempo_authorization_list` |
| 13 when present, before signature | `keyAuthorization` | `key_authorization` |
| Last | `fields["signature"]` | `signature` |
| Original envelope | `raw` | `raw` |

`Transaction.sender/1` normalizes high-s Secp256k1 signatures to low-s before recovery,
so equivalent complement-s encodings recover the same sender. It preserves
the original envelope; successful recovery does not imply broadcast acceptance.

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
