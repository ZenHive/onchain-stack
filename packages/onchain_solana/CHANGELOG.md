# Changelog

## 0.1.0 (unreleased)

- Extract Solana support from cartouche under Onchain.Solana.*, including Onchain.Solana.Base58. No protocol behavior changes.
- Requires onchain `~> 0.16`; the shared HTTP, KMS and signer backends are the renamed `Onchain.*` modules (formerly `Cartouche.*`).
