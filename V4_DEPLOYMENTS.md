# Aave V4 Deployments — Landscape Snapshot

**Captured:** 2026-08-26
**Purpose:** dated map of *where V4 actually is*, for sessions that would otherwise treat `V4_SCOPING.md` (Ethereum addresses as of 2026-04-20) as the whole story. Address and ABI detail for the DAO deployments still lives in [V4_SCOPING.md](V4_SCOPING.md); Task 69 re-derives that file from the current address book.

This is not an address registry. Do not copy numbers from here into `Onchain.Aave.Contracts`. Authority for DAO deployments is `aave-dao/aave-address-book`. Authority for the ether.fi Cash instance is the live Optimism deployment plus the AIP that listed it.

---

## What is live

| Instance | Chain | Operator | In `safe.csv`? | Library coverage |
|----------|-------|----------|----------------|------------------|
| Ethereum DAO V4 (4 Hubs) | Ethereum (1) | Aave DAO | `AaveV4Ethereum` (304 entries) | Ethereum Core/Prime/Plus Hubs + Spokes wrapped; **Global Dollar Hub missing**; Hub type closed as `:core \| :prime \| :plus` |
| Avalanche DAO V4 | Avalanche (43114) | Aave DAO | `AaveV4Avalanche` (73 entries), deployed 2026-07-15 | **Missing** — Task 69 |
| ether.fi Cash | Optimism (10) | EtherFi (Aave-licensed whitelabel) | **No** `AaveV4Optimism` namespace | **Missing** — follow-on after 69 |
| Base V4 | Base (8453) | Aave DAO (announced) | **No** `AaveV4Base` namespace | Not deployed. Tokenized-stock *lending* is "soon" |

Verified 2026-08-26 against [aave-dao/aave-address-book `safe.csv`](https://github.com/aave-dao/aave-address-book/blob/main/safe.csv): the only `AaveV4*` chain IDs are `1` and `43114`.

---

## Ethereum DAO V4

Live since 2026-03-30. `V4_SCOPING.md` enumerated three Hubs (Core, Prime, Plus) from address-book commit `10c4e9d` (2026-04-16). The book has since grown to four:

| Hub | Address-book key | Role |
|-----|------------------|------|
| Core | `HUBS CORE_HUB` `0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9` | Primary liquidity. Wrapped. |
| Plus | `HUBS PLUS_HUB` `0x06002e9c4412CB7814a791eA3666D905871E536A` | Ethena / strategy stables. Wrapped. |
| Prime | `HUBS PRIME_HUB` `0x943827DCA022D0F354a8a8c332dA1e5Eb9f9F931` | Non-borrowable collateral. Wrapped. |
| Global Dollar | `HUBS GLOBAL_DOLLAR_HUB` `0x62d63197660c080236193CA60b70E49A08E90368` | Fourth Hub. **Not in this library.** `Onchain.Aave.V4.Hub` cannot name it. |

Do not confuse Ethereum's **EtherFi Spoke** (`v4_etherfi_spoke`, weETH collateral → WETH borrow, e-Mode on Core Hub) with the Optimism Cash instance. They share a partner name and nothing else.

The two Spokes added since `V4_SCOPING.md` (Task 69 already sweeps them via "every AaveV4Ethereum entry") are partner markets on USDG, not new chains:

| Address-book key | Address | Partner |
|------------------|---------|---------|
| `SPOKES USDG_PENDLE_SPOKE` | `0x956d8e0A89cfa3744428C4641b5a53B56167a7f9` | Pendle |
| `SPOKES USDG_MAPLE_ESPOKE` | `0x774b9655413c34809c1f1b16b654465A89EBE989` | Maple |

Neither is in `Onchain.Aave.Contracts` today.

Protocol-wide figures circulating in the same week (not independently re-measured here):

- Ethereum V4 deposits $500M ATH ([@aave 2026-08-25](https://x.com/aave/status/2092317333192892829); Stani the day before)
- Independent on-chain read the same day ([@binji_x](https://x.com/binji_x/status/2092355088341987329)): ~$525–530M supplied, $188M borrowed, **36% utilisation**, linear/opt-in growth (not a V2/V3 incentive migration), ~65% depositor retention (5,050 wallets supplied / ~3,270 still holding), **~28% of TVL in partner spokes** (ether.fi, Maple, Pendle, Lido)
- Protocol-wide deposits ~$750M, +$300M in a week ([@aave 2026-08-21](https://x.com/aave/status/2090850756022657062))
- Active loans $200M ATH ([@aave 2026-08-25](https://x.com/aave/status/2092300554676453838); Stani confirmation)
- Ethereum Core Hub (Token Logic, 2026-08-26): $375M deposits, $152M loans, ~40% weighted utilisation ([@MahoneDeFi](https://x.com/MahoneDeFi/status/2092485976744714646))

Stani, quoting [@alphaleaked](https://x.com/alphaleaked/status/2091927578986660171)'s three-item list: "What to expect next" — Coinbase stocks, Avalanche RWA Hub, Arc launch ([@StaniKulechov](https://x.com/StaniKulechov/status/2091981960251937248)). The bullets are alphaleaked's; Stani's post is the endorsement.

---

## Avalanche DAO V4

First V4 deployment beyond Ethereum. Address book: 73 `AaveV4Avalanche` entries — one Core Hub (`0xd07369fAE4A5BB13c9Ce446B052c7867B1AbDf6e`), Main / Forex / AVAX-Correlated Spokes with oracles, seven Tokenization Spokes, full Position Manager set, Treasury Spoke. Contract-kind labels match Ethereum, so the registry shape does not need a new axis — only a new network key and an open Hub type.

Task 69 already owns this. Out of scope here.

---

## ether.fi Cash — Optimism whitelabel (the gap Task 69 must not swallow)

Aave licensed the V4 codebase to EtherFi for a **ring-fenced instance on OP Mainnet** that powers EtherFi Cash (Visa card). Aave is not the operator; EtherFi runs configuration, risk, liquidity and growth; Nonce Capital is independent risk admin. Borrowing is whitelisted to Cash users. Aave DAO takes a 20% revenue share.

This is V4's first **externally managed** deployment ([@StaniKulechov 2026-08-20](https://x.com/StaniKulechov/status/2090465169813958850)).

Architecture from the ARFC (not from the address book — it is not there):

- **Hub:** EtherFi Cash Hub (sole liquidity hub)
- **Spoke:** Cash Spoke at launch, listing the then-current Cash collateral set
- Isolated from Aave's shared liquidity and from every other Aave market

Collateral named at launch by Aave ([@aave 2026-08-14](https://x.com/aave/status/2088265181230969095)): PAXG (Paxos), SPYx (xStocks), WBTC, ETH, ETHFI. weETH looping showed up on the same market within two weeks ([@DeFiSaver 2026-08-24](https://x.com/DeFiSaver/status/2091920583797989791)).

Growth (operator and third-party figures, not re-measured):

| Date | Claim | Source |
|------|-------|--------|
| 2026-08-14 | Live; >100k cardholders migrating off in-house Debt Manager | [@aave](https://x.com/aave/status/2088265181230969095), [Optimism blog](https://optimism.io/blog/etherfi-upgrades-to-aave-v4-on-op-mainnet) |
| 2026-08-20 | $100M deposits in first week | [@aave](https://x.com/aave/status/2090445306986946733) |
| 2026-08-26 | ~$249M deposits, ~$20M borrows; #2 V4 market by deposits; ~8% hub utilisation, USDC ~40% | [@DeFi_Andree](https://x.com/DeFi_Andree/status/2092449601903309300) |

**Why a separate task, not an extra AC on 69:** Task 69's authority is `AaveV4Ethereum` + `AaveV4Avalanche` in the address book. Cash is a licensed instance whose addresses are not in `safe.csv`. Mixing those sources in one session would either skip Cash (silent) or invent addresses (worse). The Hub type must already be open (`:core \| :prime \| :plus` is exactly the trap for a fifth name like `:cash`) — that is 69's job, then this instance is additive.

---

## Base — tokenized stocks live, V4 lending not

2026-08-24: Coinbase Tokenized Stocks launched on Base for eligible non-US users (B20, 1:1 underlying at Alpaca, Chainlink oracles). Initial names circulating: NVDAc, METAc, AAPLc, GOOGLc; some reports list a longer set.

Aave's own wording is "soon", not "live":

- [@aave 2026-08-24](https://x.com/aave/status/2091919166458540455): "Soon, Aave V4 will be the first credit market to support them."
- [@aave 2026-08-24](https://x.com/aave/status/2091964984494350369): "Once V4 is deployed on Base, it will power stock-backed loans."

Independent reporting the next day matches that: trading is open (1inch / Aerodrome), Aave lending is still in governance/risk configuration ([FinanceFeeds 2026-08-25](https://financefeeds.com/coinbase-uses-chainlink-to-price-four-stock-tokens-as-aave-lending-waits-for-v4/)).

No `AaveV4Base` namespace. No Hub addresses. **Do not file a Base V4 registry task until the address book (or an AIP) lists them.** After Task 69 the Hub type is open, so a Base deployment is additive data.

---

## Aerodrome

Two different events, often collapsed:

1. **2025-02-05** — Aave **V3** listed on Base; AAVE/WETH on Aerodrome ([@AerodromeFi](https://x.com/AerodromeFi/status/1887199535015096500)). Already in this library as V3 `network: :base` (Task 21).
2. **2026-08-24** — Aerodrome is the spot-liquidity venue for Coinbase Tokenized Stocks on Base. Lending, if/when V4 deploys, is Aave's job; the DEX is not.

Nothing here to wrap in `onchain_aave`. DEX surface belongs in `onchain_aerodrome` if it belongs anywhere.

---

## Mapping onto this roadmap

| Task | Owns | Does not own |
|------|------|----------------|
| **69** (next) | Re-sync `AaveV4Ethereum` (incl. Global Dollar Hub) + `AaveV4Avalanche`; stop hardcoding three Hub atoms; fix `networks/0`; rewrite `V4_SCOPING.md` | Optimism Cash, Base, Aerodrome, Chainlink feed addresses |
| 66 | Tokenization Spoke ERC-4626 writes on *already registered* spokes | New networks |
| 67 | Position-manager authorization + Taker fork evidence | New networks |
| 68 | V4 event decode (depends on 63) | New networks |
| **follow-on** (filed 2026-08-26) | Register the ether.fi Cash instance from live Optimism state + AIP, after 69 | Writes through the Cash borrow-whitelist, GHO GSM, the card product |

v0.5 stays pinned to 69/66/67 plus the V3 write-gap tasks. The Cash instance tests a *further* hypothesis — that the open Hub model carries a non-DAO deployment — so it is not a v0.5 pin.

---

## Sources

**Address book (DAO deployments)**

- https://github.com/aave-dao/aave-address-book (`safe.csv`; org moved off `bgd-labs`)
- Local check 2026-08-26: `AaveV4Ethereum` 304 rows, `AaveV4Avalanche` 73 rows, no other `AaveV4*` namespace

**Governance / operator docs (Cash)**

- TEMP CHECK: https://governance.aave.com/t/temp-check-deploy-a-dedicated-aave-v4-whitelabel-instance-fully-managed-by-etherfi-on-op-mainnet-to-power-ether-fi-cash/25267
- ARFC: https://governance.aave.com/t/arfc-deploy-a-dedicated-aave-v4-whitelabel-instance-fully-managed-by-etherfi-on-op-mainnet-to-power-ether-fi-cash/25314
- Optimism blog (2026-08-13): https://optimism.io/blog/etherfi-upgrades-to-aave-v4-on-op-mainnet

**X (primary, 2026-08-13 → 2026-08-26)**

- https://x.com/aave/status/2088265181230969095 — Cash backend live on Optimism
- https://x.com/aave/status/2090445306986946733 — $100M Cash deposits, week one
- https://x.com/StaniKulechov/status/2090465169813958850 — first externally managed V4
- https://x.com/DeFi_Andree/status/2092449601903309300 — $249M / $20M, #2 V4 market
- https://x.com/aave/status/2092317333192892829 — $500M deposits on Ethereum
- https://x.com/binji_x/status/2092355088341987329 — on-chain breakdown: 36% util, 65% retention, 28% TVL in ether.fi/Maple/Pendle/Lido spokes
- https://x.com/aave/status/2091919166458540455 — Coinbase stocks live; V4 on Base "soon"
- https://x.com/aave/status/2091964984494350369 — stock-backed loans once V4 deploys on Base (reply in the 2091964981675704495 thread)
- https://x.com/StaniKulechov/status/2091981960251937248 — "What to expect next", quoting alphaleaked's Coinbase-stocks / Avalanche-RWA / Arc list
- https://x.com/StaniKulechov/status/2092265564672545174 — stocks as securities-finance thesis
- https://x.com/StaniKulechov/status/2092302228392407481 — $200M V4 borrows ATH
- https://x.com/MahoneDeFi/status/2092485976744714646 — Ethereum Core Hub utilisation
- https://x.com/AerodromeFi/status/1887199535015096500 — V3-on-Base / Aerodrome (2025, not V4)

**Independent reporting (Base stocks)**

- https://financefeeds.com/coinbase-uses-chainlink-to-price-four-stock-tokens-as-aave-lending-waits-for-v4/
- https://www.blockhead.co/2026/08/25/coinbase-debuts-tokenized-stocks-on-base-network/
- https://blog.base.org/tokenized-stocks
