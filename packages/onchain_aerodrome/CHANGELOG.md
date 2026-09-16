# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-09-16

### Fixed

- Run the offline test suite in `mix check.dispatch`, so a failing test blocks harness review.

### Changed

- ABI function entries are resolved by **name and input types**, through one
  rule shared by `test/support/types_case.ex` and the Types drift test. The
  drift test already disambiguated overloads (`relay_sugar.json`
  `all(address)`); `TypesCase.abi_entry/2` matched on the name alone, so a
  re-capture that grew a second `all` would have graded `Types.Relay` against
  whichever overload sat first in the JSON array while the drift test stayed
  green. `assert_one_to_one/4,5` now takes `{file, function, input_types}`, an
  unresolvable lookup fails naming the file, the sought signature and the
  candidates it did find instead of raising on `nil`, and a bare-name lookup
  that matches more than one entry is rejected rather than guessed.

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

- Pinned, nonempty Position and Reward response fixtures at Base block
  51,348,944, with full ABI-field assertions and fixed liquidity/amount checks.
  The capture task's `--nonempty` mode requires explicit account, veNFT and
  pool selectors and rejects empty responses before writing its separate
  collection. Existing empty pagination fixtures remain as regression cases.

- `Types.VeNFT`, `Types.Vote`, `Types.Relay` (+ `Relay.AccountVeNFT`),
  `Types.LpEpoch` (+ `LpEpoch.TokenAmount`) and `Types.Reward` — the veAERO
  structs, positional `from_raw/1` over the `VeSugar.byId`,
  `RelaySugar.all(address)`, `RewardsSugar.epochsLatest` and
  `RewardsSugar.rewards` rows. **`Types.Vote` is defined once** — the `votes`
  nested components of `ve_sugar.json` `byId` and `relay_sugar.json`
  `all(address)` are byte-identical, and the drift test asserts that equality
  rather than assuming it, so a re-capture that diverges them fails instead of
  silently decoding one shape as the other. The two lookalike nested pairs stay
  separate on purpose: `LpEpoch.TokenAmount` (`{token, amount}`) is **not**
  `Types.Reward` (a flat six-field record), and `Relay.AccountVeNFT`
  (`{id, amount, earned}`) is neither a `VeNFT` nor a `Vote`; named tests
  assert each non-identity. Field names in the drift tests are read from
  `priv/abis/*.json` — including the nested `bribes`/`fees` components — never
  transcribed, because hand counts of `Relay`'s width have been wrong before.
  Amounts stay integers; addresses (and `Relay.managers`) are EIP-55
  checksummed, with the zero address kept as the checksummed zero address
  rather than rewritten to `nil`.

- `Onchain.Aerodrome.Bindings.LpSugar` — the deployed Base LpSugar read surface:
  `count/1`, `all/4`, `for_swaps/3`, `positions/4`, `positions_by_factory/5`,
  `positions_unstaked_concentrated/4`, `tokens/5` and `alm_estimate_amounts/4`,
  decoding positionally into `Types.Lp` / `.Swap` / `.Position` / `.Token`.
  **Enumeration is driven to `count/1`, never terminated on a short page** —
  every one of these reads walks a *scanned* index space (pool index or
  position-NFT index) whose rows are filtered, deduplicated or skipped upstream,
  so a page shorter than `limit` is normal mid-scan and stopping there silently
  drops pools. `paginate/3` is the public driver over a caller-supplied bound,
  and `all_pages/2` obtains the pool count itself; an out-of-range `:limit`
  fails with `{:error, {:invalid_limit, limit}}` before any RPC call. A named
  anti-regression test asserts the naive short-page loop *under-counts* against
  the committed fixtures, so the suite fails against the bug rather than merely
  passing against the fix. `all/4`'s `filter` is an opaque non-negative integer
  passthrough — its semantics are undocumented upstream, and fixture drift
  detection is the only available verification.

- `Types.Lp`, `Types.Position`, `Types.Swap` and `Types.Token` — positional
  `from_raw/1` constructors for the Sugar pool and token rows, with ABI
  field-order drift tests that read `priv/abis/*.json` directly.

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
