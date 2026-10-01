# Onchain Solana

Solana RPC, legacy transactions, token programs, program-derived addresses, and Ed25519 signing for Elixir.

## Migration from cartouche

Add `{:onchain_solana, "~> 0.1"}` to your dependencies. Replace `Cartouche.Solana.*`
with `Onchain.Solana.*`, `Cartouche.Base58` with `Onchain.Solana.Base58`,
and Solana discovery calls to `Cartouche.describe` with `Onchain.Solana.describe`.
The existing `:solana_*` discovery aliases remain available.

Configuration retains its existing `:cartouche` application keys; rename module keys:

```elixir
config :cartouche, :solana_node, "https://api.mainnet-beta.solana.com"
config :cartouche, :solana_signer, default: {:ed25519, seed}
config :cartouche, Onchain.Solana.RPC, finch: MyFinch
```

Onchain.Solana.Application supervises configured signers. The KMS backend requires
the optional `:goth` dependency and uses the shared Onchain.CloudKMS client.
onchain (`~> 0.16`) remains a runtime dependency for shared transport and signing helpers.
