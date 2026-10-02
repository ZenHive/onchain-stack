# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-10-02

Moved into the onchain-stack monorepo (`packages/faucet_ex`) with its history;
the standalone `ZenHive/faucet_ex` repository is archived.

### Changed

- The optional `onchain` dependency now requires `~> 0.16`. onchain 0.16.0
  folded `cartouche` into `Onchain.*`, so `Faucet.ForkOverride` hashes with
  `Onchain.Hash.keccak/1` (0.1.0 called `Cartouche.Hash.keccak/1`, which no
  longer exists) and `Faucet.Source.ERC20Mint` encodes calldata with
  `Onchain.ABI.encode_hex_call/2`.
- Docs and package links point at the monorepo; source tags are
  `faucet_ex-v<version>`.

## [0.1.0] - 2026-09-23

Initial extraction. Consolidates the faucet helpers that had grown separately
in `onchain_tempo` (`Onchain.Tempo.Faucet`), `onchain_aave`
(`Onchain.Aave.Faucet` plus the `faucet_mint_if_needed` test helper), `mpp`
(Solana airdrop and XRPL test helpers) and `aave_sim`
(`AaveSim.TestnetFaucet`, the CDP client with the top-up loop).

### Added

- `Faucet.ensure_min_balance/4` and `/4!`: the read → fund → wait → verify
  loop with request budget, per-address `:global.trans/2` lock, and
  `Faucet.Error` carrying the provider's reason.
- `Faucet.Source` behaviour (`balance/2`, `fund/2`, `unit/0`, optional
  `wait_confirmed/3`); the loop passes `:deficit` to `fund/2`.
- Sources: `Faucet.Source.CDP` (Coinbase Developer Platform, EdDSA JWT),
  `Faucet.Source.Tempo` (`tempo_fundAddress`), `Faucet.Source.Solana`
  (`requestAirdrop`), `Faucet.Source.XRPL` (altnet faucet HTTP API),
  `Faucet.Source.ERC20Mint` (Aave-style `mint(token,to,amount)` contract,
  needs `onchain`).
- `Faucet.EVM`: native / ERC-20 balance reads, receipt polling,
  `fresh_wallet/0` and `fresh_funded_wallet/3` (need `onchain`).
- `Faucet.ForkOverride`: `state_overrides` builder for `Onchain.EVM` fork
  simulation, including Solidity mapping-slot derivation (needs `onchain`).
- `Faucet.JSONRPC` and `Faucet.Wait` as the shared HTTP and polling primitives.
- Descripex `api()` hints on every public function; `Faucet.describe/0..2`.
