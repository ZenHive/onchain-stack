# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Roadmap on the `rmap` substrate: `roadmap/tasks.toml` as canonical source with
  35 tasks across nine phases and two milestones, rendering `ROADMAP.md` and
  `roadmap/data.json`. Records three findings that shape the build — the
  `.reach.exs` layer gate does not yet enforce what it documents (and forbids
  `bindings -> types`, which the layer table requires); `decode_structs: true` is
  unreachable through hex `onchain` 0.13.0's 2-arity wrappers, so decoding is
  positional with per-struct field-order drift tests; and although Base EVM
  simulation is blocked, `SlipstreamHelper`'s `pure` functions serve as a
  deployed differential oracle for the tick and liquidity math.

- Dated protocol-context snapshot in `docs/protocol-context.md`: official
  Python Sugar SDK as unsigned-calldata sibling, Coinbase tokenized stocks
  live on Aerodrome as ordinary B20/ERC-20 pool tokens, and the B20
  multiplier plus 24/5 Chainlink TRV feeds as a denominator trap for the
  price layer.

- Initial scaffold: contract address registry (`Onchain.Aerodrome.Contracts`)
  with Base addresses verified against `velodrome-finance/sugar` deployments
  and live `eth_call`, captured Sugar/factory ABIs in `priv/abis/`, and the
  `.reach.exs` layer contract.
