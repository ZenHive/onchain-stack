# Aerodrome protocol context

Dated snapshot, fetched 2026-08-26. This is **not** load-bearing law —
`CLAUDE.md` / `roadmap/tasks.toml` remain the contract. Re-fetch before treating
any address, feed, or SDK version as current.

**What this file is for:** later sessions should not rediscover these facts from
X or training data. The package's types, pagination, APR split and write-shape
are already decided. The items below are the protocol facts the roadmap did not
yet carry.

## Sources

| What | Where | Fetched |
|---|---|---|
| Official agent SDK | https://github.com/velodrome-finance/sugar-sdk (v0.4.x; install docs pin `v0.4.2`) | 2026-08-26 |
| Agent landing page | https://aerodrome-finance.github.io/agents/ | 2026-08-26 |
| Sugar SDK never-signs release | https://github.com/velodrome-finance/sugar-sdk/releases/tag/v0.4.0 (2026-05-24) | 2026-08-26 |
| Tokenized-stocks launch | https://aero.xyz/articles/coinbase-tokenized-stocks-launch-on-aerodrome/ (2026-08-24) | 2026-08-26 |
| B20 / stocks integrator guide | https://docs.base.org/base-chain/asset-issuance/tokenized-stocks-on-base | 2026-08-26 |
| Chainlink tokenized-equity feeds | https://docs.chain.link/data-feeds/tokenized-equity-feeds/coinbase | 2026-08-26 |
| X `@AerodromeFi` | posts cited inline | 2026-08-26 |

X is marketing. Provider docs and deployed contracts remain the authority.

---

## 1. Official Sugar SDK — sibling, not a competitor

Aerodrome's official agent path is a **Python** SDK plus CLI plus a Claude Code
skill, not an Elixir library.

- Repo: `velodrome-finance/sugar-sdk`. Chains: OP `10`, Base `8453`, Unichain
  `130`, Lisk `1135`.
- Install is git-pinned, not hex/pypi-stable: `pip install git+https://github.com/velodrome-finance/sugar-sdk.git@v0.4.2`.
- Skill lives at `.claude/skills/sugar/` in that repo.
- Consumed by Base MCP's Aerodrome plugin and by Bankr's stock-LP skill.

**v0.4.0 breaking change (2026-05-24):** the SDK **never signs and never
broadcasts**. Writes return unsigned `{from, to, data, value}` dicts (approvals
first, then the call). `SUGAR_PK` is refused. That is the same contract this
package already chose for `Write.*`.

X, 2026-07-23, [@AerodromeFi](https://x.com/AerodromeFi/status/2080389513826935260):

> With Aerodrome, agents can build ready-to-sign transactions to swap, manage
> liquidity, claim LP rewards, and more. All without ever touching your keys.

**Implications for this package**

- This repo is the Elixir library over deployed Sugar contracts. It does not
  wrap, vendor, or reimplement the Python CLI.
- Task 26's independent encoder stays Foundry `cast`. sugar-sdk is a second
  language implementing routing *and* encoding; using it as the oracle would
  grade us against their router, not against the ABI spec. File a new task if a
  consumer later wants a sugar-sdk compatibility suite.
- sugar-sdk 0.2.0 notes "pagination fixed for pools, tokens and prices". That is
  their client loop. It does **not** retire this package's contract-level trap:
  `LpSugar.all(uint256,uint256,uint256)` filters after fetch; a short page is
  not terminal. Drive `offset` to `count()`.

---

## 2. Coinbase tokenized stocks, live on Aerodrome

Day-one liquidity on Aerodrome, 2026-08-24. Tokens are **B20** (ERC-20
superset, Base precompile), not a new Aerodrome pool type.

X, 2026-08-25, [@AerodromeFi](https://x.com/AerodromeFi/status/2092299728981836277):

> LP tokenized stocks on Aerodrome. Nvidia, Meta, Apple, and Google now live.

Frontend: https://aerodrome.finance/liquidity/stocks — a *Stocks* filter, not a
new factory. Bankr shipped an "Aerodrome Stock LP" skill the same week
([@bankrbot](https://x.com/bankrbot/status/2091997727311733066)).

Eligibility is an **interface** geo-block (USA, UK, Canada, Australia,
Singapore named in the aero.xyz FAQ). The pools themselves are ordinary Sugar
`Lp` rows. This library talks to contracts, not the frontend, and does not
enforce that block.

**Identify tokens by address, never by ticker.** B20 `name` / `symbol` are
mutable onchain. Addresses start `0xB200…`. Registry:
`0x3f3E8cf41cdd3b1D118c16471aB0113DfDDd5CaD`.

Addresses below are copied from Base docs on 2026-08-26. Re-verify before use.

| Ticker | Token |
|---|---|
| AAPLc | `0xb200000000000000000000C2e324d24d7eEcd1fb` |
| AMZNc | `0xb200000000000000000000d9192b6B456483C2E8` |
| COINc | `0xb200000000000000000000c85a31389D71F3ecfb` |
| CRCLc | `0xB20000000000000000000019f6E7C675b73C2e4D` |
| GOOGLc | `0xb2000000000000000000002D0BA3164cc74f58B7` |
| INTCc | `0xB2000000000000000000004AFF16039bA04bdFBc` |
| METAc | `0xb2000000000000000000008bC8786B856E61707C` |
| MSFTc | `0xB200000000000000000000Ab99cFa739E253872B` |
| MSTRc | `0xb2000000000000000000004884b426556b92883d` |
| NVDAc | `0xb20000000000000000000078ee7ce2fE4908108C` |
| SNDKc | `0xb200000000000000000000397293Cb8cda9a10c5` |
| SPCXc | `0xb2000000000000000000007b9fcbd005511aCBd5` |
| TSLAc | `0xb2000000000000000000001e800a7f5189430cD0` |

**Implications for this package**

- No new `Lp.type`. No Stocks factory. Pagination `count()` only grows.
- Do not special-case these tokens in Types or Bindings. They are ERC-20
  balances inside existing v2 / CL pools.
- Do not add a B20 helper module in v0.1. File `rmap new` when a consumer
  actually needs share-equivalent conversion.

---

## 3. B20 multiplier — the other denominator trap

`balanceOf` is the **raw** ERC-20 balance. One B20 token is **not** permanently
one share. Corporate actions (dividends converted to shares, splits) update a
WAD-scaled (`1e18`) multiplier; raw balances stay put so DeFi positions do not
break.

```
share_equivalent = raw * multiplier / WAD
```

Helpers on the token: `multiplier()`, `scaledBalanceOf(account)`,
`toScaledBalance(raw)`, `toRawBalance(scaled)`. Scheduled updates use
`updateUIMultiplier(new, effectiveAt)` (ERC-8056).

Pool TVL, swap quoting and `Lp` reserves are **raw**. That is what the pool
holds. Applying the multiplier to reserves double-counts against a Chainlink
tokenized-equity feed, because those feeds already report **Total Return Value**
= underlying equity price × multiplier.

Same class of bug as summing `fee_apr` and `emission_apr`: both numbers look
like money, they are not the same quantity.

B20 extras that can bite a write path later (not v0.1): transfer policies
(`approve` is **not** policy-gated), per-function pause, reverse-split halt via
`PausableFeature.TRANSFER`. Secondary-market holding is permissionless; mint /
redeem of the underlying is AP-only.

---

## 4. Chainlink equity feeds are 24/5, not 24/7

Coinbase tokenized-equity feeds on Base:

- Standard AggregatorV3, 8 decimals, `latestRoundData()` through the proxy.
- Report **TRV**, not the raw equity print. DEX spot of the B20 does **not**
  feed the oracle.
- Publish 24/5. Off hours (nights, weekends, holidays, corporate-action pause)
  they **stop updating and hold the last value**. `updatedAt` freezes; the
  contract stays callable.
- Heartbeat during market hours: 0.5% deviation or 24h. Staleness checks that
  treat "callable + old `updatedAt`" as a dead crypto feed will false-red every
  weekend. Checks that ignore `updatedAt` will settle against a Friday close.

Aerodrome pools for the same tokens trade 24/7. Off-hours, pool-route spot and
the Chainlink TRV feed are allowed to disagree; that is not a routing bug.

Feeds from Base docs, 2026-08-26:

| Feed | Aggregator proxy |
|---|---|
| Coinbase AAPL | `0x787f13dEa48Db0897CbCDD985de77809D837F988` |
| Coinbase AMZN | `0x06A8E4b3aBB3B7543d8396FB2B763d22820cB295` |
| Coinbase COIN | `0x408e44f504A7371a345F03a73dDC96A4b48e8aa7` |
| Coinbase CRCL | `0x0231cF2635D1E17bB5c2462cc7504Ba1fBd61f33` |
| Coinbase GOOGL | `0x5bF49E0ffA937CE2FfF033c739aD7C634c4D34F2` |
| Coinbase INTC | `0xAB657C39bac0D5886250D70849e2E3E008F2EECB` |
| Coinbase META | `0x6526aE6797A76123638b863AeE4dD27Ba4E4b27D` |
| Coinbase MSFT | `0xeB10A6c9aa7E537aEd766C08c35Dae35B321b18c` |
| Coinbase MSTR | `0xB3cE282CD188b35DA0E38D8Bc7d58e33173D202a` |
| Coinbase NVDA | `0x04689a41629776563E6822F76f2e57D148d28513` |
| Coinbase SNDK | `0x388b0dC46C0Fb05A74BeE0994fa5b02c6Fcca2eA` |
| Coinbase SPCX | `0x6A634B235903C4ad6376892180d6fF8612e3Fa68` |
| Coinbase TSLA | `0xFaf869185383a24F8cb00e27BdA6b63B9905DCb4` |

**Implications for Task 18 (Sugar.Prices / Bindings.Chainlink)**

- v0.1 default anchors stay crypto (ETH, USDC, maybe AERO). Equity feeds are
  opt-in.
- If an equity feed is added, its market-hours policy is **data on the Price**
  (heartbeat, session calendar, TRV vs raw), not a silent exception to
  `max_staleness_s`.
- Two different tagged errors: heartbeat missed *during expected publishing
  hours*, versus *session closed / feed frozen by design*. One `stale` bucket
  collapses them.
- A stale or weekend-frozen equity anchor is never silently replaced by a
  24/7 pool-route price without `Price.source` saying so.
- Do not treat disagreement between a Friday-close TRV feed and Sunday DEX
  spot as a reconciliation failure.

---

## 5. Aero merge (future, already scoped)

aero.xyz, 2026-08-24: "In 2026, Aerodrome will merge with Velodrome to become
Aero: the unified liquidity layer for all of Ethereum."

ROADMAP.md already lists Velodrome-on-Optimism as a future direction (same
Sugar family, different addresses). No new task. When addresses unify, recapture
`priv/abis/` and re-verify `Contracts` — the existing Sugar-drift procedure.

---

## 6. Roadmap findings this snapshot exists alongside

Recorded 2026-08-26 against `rmap validate` / `rmap ready` / `rmap critical-path`.
Not a substitute for `rmap show`.

- 35 pending tasks, 0 done. Focus phase 1. Next: Task 2 (Epoch). Ready: 1, 2, 5,
  and Task 25 (v0.2 ABI capture, no deps).
- Critical path is 12 tasks, gated on 1 → 3 → 4.
- `CLAUDE.md` still tells implementers to intern atoms for `decode_structs:
  true`. Task 3 (positional decode) is the decision; CLAUDE.md / `priv/abis/README.md`
  must follow it. Folded into Task 3.
- CHANGELOG said "34 tasks"; there are 35.
- `rmap doctor`'s nine "degenerate bundles" (bundle == phase) are cosmetic.

### Open decisions already derivable (fold before dispatch, do not re-ask)

| Task | Decision |
|---|---|
| 1a | `types` must not reach `base` — Types are pure structs |
| 1b | `Contracts` and `Math.*` stay one `base` layer |
| 2 | `Epoch.index/1` is absolute since Unix epoch |
| 3a | no unreleased `onchain` — `mix.exs` is hex-only |
| 3b | type-string builder covers the nine captured ABIs, not a Solidity grammar |

---

## Explicitly not following from this snapshot

- No Agent CLI, no Python dep, no wrapping sugar-sdk.
- No B20 module, no share-equivalent helper, no stocks factory binding in v0.1.
- No geo-eligibility checks in the library.
- No new rmap tasks. File one when a consumer needs B20 conversion or a
  sugar-sdk compatibility suite.
- Addresses and feed lists above are a copy of provider docs on one day. Live
  `description()` / Sourcify / `cast` remain the verification path.
