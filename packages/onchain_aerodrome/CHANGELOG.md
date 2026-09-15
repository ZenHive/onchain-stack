# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The `.reach.exs` layer contract now **enforces** what it documents. The 0.1.0
  entry below records that it did not: the gate forbade `bindings -> types`
  which the layer table requires, and nothing stopped an analytics or math
  module from calling the network. The allowlist is corrected, and
  `calls: [forbidden: ...]` bans `Onchain.RPC.*`, `Onchain.Contract.*`,
  `Onchain.Multicall.*`, `Req.*` and `:httpc.*` from analytics, types, base and
  math — layer edges alone cannot catch calls into modules that sit outside the
  graph. `Mix.Tasks.*` stays outside it deliberately: fixture generators must
  reach the network.

### Added

- Pinned-block Sugar `eth_call` fixtures under `test/fixtures/aerodrome/`, an
  offline loader (`Onchain.Aerodrome.Fixtures`), and
  `mix aerodrome.capture_fixtures --block N` to re-capture them. The Mix task
  is a dev workflow; `mix ci` decodes the committed hex with zero network.

- `test/reach_architecture_test.exs` — the layer contract is now asserted
  against Reach directly rather than trusted. Each test compiles a probe module
  and checks the violation Reach reports, and the permitted-edge tests assert
  Reach actually recorded the call (an empty violation list is also what a
  detector that saw nothing returns).

### Fixed

- Ship `docs/` in the Hex tarball: `docs/protocol-context.md` is declared as an
  ExDoc extra, but the explicit `files` list omitted it, so HexDocs built from
  the package could not find the extra.

## [0.1.0] - 2026-08-27

### Added

- Roadmap on the `rmap` substrate: 35 tasks across nine phases and two
  milestones, filed in the monorepo's root `roadmap/tasks.toml` (rendered to the
  root `ROADMAP.md` and `roadmap/data.json`; this package's ids are the 5xxx
  range). Records three findings that shape the build — the
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

### Changed

- **Package lives in the `onchain-stack` monorepo from its first release.**
  Source, issue tracker and release tags are at
  `github.com/ZenHive/onchain-stack`, under `packages/onchain_aerodrome/`;
  the tag scheme is `onchain_aerodrome-v<version>`. This package has never
  had a standalone repo.
