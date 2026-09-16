# OnchainAerodrome

[![Hex.pm](https://img.shields.io/hexpm/v/onchain_aerodrome.svg)](https://hex.pm/packages/onchain_aerodrome)

Aerodrome Finance bindings, Sugar-backed reads, and pure analytics for Elixir.
Base only (chain id 8453). Built on the
[`onchain`](https://hex.pm/packages/onchain) core library.

Aerodrome is a ve(3,3) exchange combining Solidly-style v2 pools (volatile and
stable) with Slipstream concentrated-liquidity pools. Emissions are directed
weekly by veAERO voters; an epoch is one week and flips **Thursday 00:00 UTC**.

> **Status.** The address registry, weekly epoch arithmetic, captured ABIs,
> pool/token structs (`Types.Lp`, `.Position`, `.Swap`, `.Token`), veAERO
> structs (`Types.VeNFT`, `.Vote`, `.Relay`, `.LpEpoch`, `.Reward`), and the
> LpSugar read binding (`Bindings.LpSugar`) are in place. Remaining Sugar
> bindings, the ergonomic `Sugar.*` read API, analytics, and writes are scoped
> in [the monorepo `ROADMAP.md`](https://github.com/ZenHive/onchain-stack/blob/main/ROADMAP.md)
> (canonical source `roadmap/tasks.toml` at the repo root, tasks offset +5000).
> Dated protocol notes (official Sugar SDK sibling, tokenized stocks, B20
> multiplier) live in [`docs/protocol-context.md`](docs/protocol-context.md).

## Installation

```elixir
def deps do
  [
    {:onchain_aerodrome, "~> 0.2"}
  ]
end
```

## Layers

Each layer is usable on its own and depends only on the ones below it. This is
enforced by `.reach.exs` (`mix reach.check --arch`), not merely documented.

| Layer | Namespace | Needs |
|-------|-----------|-------|
| Registry / math | `Onchain.Aerodrome.Contracts`, `.Epoch`, `.Math` | nothing |
| Types | `Onchain.Aerodrome.Types.*` | nothing |
| Bindings | `Onchain.Aerodrome.Bindings.*` | an RPC endpoint |
| Analytics | `Onchain.Aerodrome.Analytics.*` | structs only — **no network** |
| Read API | `Onchain.Aerodrome.Sugar.*` | an RPC endpoint |
| Writes | `Onchain.Aerodrome.Write.*` | calldata by default; a signer only if you opt in |

Analytics sits *below* the read API on purpose: APR, tick math and valuation
take structs, not RPC options, so the whole analytics suite is testable with
zero network access.

## Quick start

```elixir
iex> Onchain.Aerodrome.Contracts.address(:lp_sugar)
{:ok, "0x69dD9db6d8f8E7d83887A704f447b1a584b599A1"}

iex> Onchain.Aerodrome.Contracts.chain_id()
{:ok, 8453}

iex> Onchain.Aerodrome.Contracts.constants().max_lps
500

iex> Onchain.Aerodrome.Epoch.start(1_704_326_401)
1_704_326_400

iex> Onchain.Aerodrome.Epoch.epochs_per_year()
52
```

Runtime API discovery is provided by
[`descripex`](https://hex.pm/packages/descripex):

```elixir
OnchainAerodrome.describe()                       # module overview
OnchainAerodrome.describe(Onchain.Aerodrome.Bindings.LpSugar)
```

## RPC requirements

Reads go through Sugar, a set of on-chain view contracts that batch protocol
state into large structs. That makes the **`eth_call` gas limit**, not archive
depth, the binding constraint.

- **A generous per-call gas limit is required.** `LpSugar.all(500, offset, 0)`
  is a heavy call. `limit: 500` is verified working against the public endpoint
  `https://mainnet.base.org`; endpoints with a tight per-call cap will fail it
  while appearing otherwise healthy. Lower the limit only as a deliberate,
  documented fallback.
- **There were 35,156 pools on 2026-08-26** (`LpSugar.count()`), so a full
  enumeration is roughly 71 sequential pages at `limit: 500`. Plan for that
  shape; it is not a small dataset.
- **An archive node is needed only for historical or epoch-indexed queries** —
  anything passing a block parameter. Current-state reads work against a pruned
  node.
- Batching, multicall and retry are supplied by `onchain` core
  (`Onchain.Multicall.aggregate3/2`, `Onchain.RPC.batch/2`, per-call
  `retry: [max_retries:, backoff_ms:]`). Multicall helps with *per-pool
  enrichment*, not with the page loop — one `all(500, …)` is already near the
  gas cap.

### Pagination has a trap

`LpSugar.all/3` applies its `_filter` argument **after** fetching the page. With
a non-zero filter, a full page returns *fewer* than `limit` rows while `_offset`
still indexes the unfiltered space. Terminating the loop on a short page is a
**silent data-loss bug** — it stops early and reports success. Drive `offset` to
`count()` instead.

Hard per-call caps compiled into the contracts: `MAX_LPS = 500`,
`MAX_POSITIONS = 200`, `MAX_TOKENS = 2000`.

## APR denominator semantics

**This library does not reproduce the numbers on aerodrome.finance, and that is
deliberate.** A single "APR" figure requires choosing one denominator and
hiding it. This library reports the components with their denominators attached
so the caller can decide.

- **`fee_apr` and `emission_apr` are separate and are never summed.** They are
  denominated over different capital bases; adding them is a category error, not
  a rounding shortcut.
- **Emission APR is denominated in staked, in-range liquidity**, not total TVL.
  `Lp.emissions` is a **per-second** rate; the weekly figure is
  `emissions × 604_800`.
- **Epochs are weekly.** Annualising from a daily rate overstates by ~7×. The
  cross-check that validated this: `12337.58 × 52 / 8_515_374 = 7.53%` against a
  displayed 8.76% — the gap is the denominator, not an error.
- **The fee/emission split is not binary on Slipstream.** An unstaked
  concentrated-liquidity position still pays a rake to the gauge:
  `CLFactory.defaultUnstakedFee()` is `100_000` pips (units of 1e-6) = **10%**,
  overridable per pool and surfaced as `Lp.unstaked_fee`. An unstaked CL LP
  keeps `1 - unstaked_fee` of trading fees, not all of them.
- **Money is integers; ratios are `Decimal`.** No floats appear on any money
  path.

If a figure here disagrees with the frontend, the answer is to state which
denominator each uses — not to tune a constant until they match.

## Address verification

Addresses live in `lib/onchain/aerodrome/contracts.ex`, each with a provenance
comment. They are verified against **two independent sources**; a BaseScan label
alone is never sufficient.

```bash
# 1. The Sugar team's own deployment manifest
gh api repos/velodrome-finance/sugar/contents/deployments/base.env --jq '.content' | base64 -d

# 2. A live probe confirming the contract answers as expected
cast call 0x69dD9db6d8f8E7d83887A704f447b1a584b599A1 "count()(uint256)" \
  --rpc-url https://mainnet.base.org
cast call 0x69dD9db6d8f8E7d83887A704f447b1a584b599A1 "token_sugar()(address)" \
  --rpc-url https://mainnet.base.org
```

Note that there are **three** Slipstream CL factories on Base, not one.
`Contracts.cl_factories/1` returns all of them; which are in scope for a given
enumeration is an explicit decision.

### ABIs

`priv/abis/` holds ABIs captured from **Sourcify v2**, which serves the
*deployed* ABI with named tuple components for field-count and field-order
drift tests. Decode positionally with `Onchain.RPC.eth_call/3`,
`Onchain.ABI.decode_response/2`, and hand-written `from_raw/1` constructors.
`Bindings.Abi` derives signatures from these captures. Avoid
`decode_structs: true`, which raises on un-interned field atoms.
`priv/abis/README.md` records the address, Sourcify match type, fetch date and
exact `curl` for every file.

**Sugar documentation drifts from the deployed contracts.** Sugar's own
`readme.md` documents `LpSugar.all(limit, offset)`; the deployed contract is
`all(uint256,uint256,uint256)` and the two-argument form reverts. The deployed
ABI is the only authority. Re-capture and re-run the golden decode suite after
any Sugar redeploy.

## Development

```bash
mix deps.get
mix precommit        # fast local loop
mix ci               # full gate (= mix precommit.full)
mix test.json --quiet
mix test.json --quiet --include integration   # requires Base RPC + BASE_SECONDARY_RPC_URL
mix aerodrome.capture_fixtures --block N      # live Base RPC; not part of mix ci
```

`BASE_RPC_URL` is used when `--rpc-url` is omitted, falling back to
`https://mainnet.base.org`. Portability integration tests also require
`BASE_SECONDARY_RPC_URL` (Alchemy/Infura-class Base URL; no fallback).
`--block` is required: a capture at `latest` is not a fixture. Re-running at
the same block is byte-identical (`captured_at` is the block timestamp).
For positive Position/Reward decode evidence, capture the separate `nonempty/`
collection with explicit selectors; either empty response fails before writing:

```bash
mix aerodrome.capture_fixtures --nonempty --block 51348944 \
  --rpc-url https://mainnet.base.org \
  --position-account 0x50f0249b824033cf0af0c8b9fe1c67c2842a34d5 \
  --reward-venft-id 10 --reward-pool 0x42d4a22CaD0F5a49681a5715cE994Af73A43B76b
```

The original empty pagination fixtures remain in the main collection.

Golden-fixture decode tests require no network and are the primary defence
against Sugar redeploy drift.

Calldata tests require Foundry `cast` on PATH (missing cast flunks). Install:

```bash
curl -L https://getfoundry.sh/install | bash
source ~/.bashrc  # or source ~/.zshrc
foundryup
```

`Onchain.Aerodrome.CalldataFixture.assert_calldata/3` compares library output
against an independent `cast calldata` invocation; pass cast arguments as CLI
strings. `eth_call_as_sugar_owner/4` discovers a sender via VeSugar.byId and
preserves simulated return bytes or RPC revert data. Its Voter.reset integration
test requires both endpoints to serve historical block 51,348,944 and asserts
the exact `NotApprovedOrOwner()` revert bytes for a non-owner, then decodes the
simulated void return for the actual owner. See the helper's `@doc` for the
limits of this evidence model.

## Related packages

- [`onchain`](https://hex.pm/packages/onchain) — core Ethereum primitives
- [`onchain_aave`](https://hex.pm/packages/onchain_aave) — the sibling protocol wrapper this package is modelled on
- [`descripex`](https://hex.pm/packages/descripex) — runtime API discovery

## License

MIT — see [LICENSE](https://github.com/ZenHive/onchain-stack/blob/main/packages/onchain_aerodrome/LICENSE).
