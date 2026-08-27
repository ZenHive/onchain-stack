# Aerodrome Finance (Base, chain id 8453) — captured ABIs

## Why Sourcify

There is no Basescan/Etherscan API key on this host. Sourcify v2 serves the
**deployed** ABI with **named tuple components** — required downstream because
`hieroglyph`'s `decode_structs: true` needs field names on tuple outputs (a
plain Etherscan-style flat ABI without component names would decode structs as
positional lists instead). Endpoint used for every capture:

```
curl -sS "https://sourcify.dev/server/v2/contract/8453/<ADDRESS>?fields=abi"
```

The response is a JSON envelope (`abi`, `match`, `creationMatch`,
`runtimeMatch`, `matchId`, `verifiedAt`, `address`, `chainId`); the ABI array
itself is extracted with `jq '.abi'` and written pretty-printed. Sourcify v2
rejects unknown field-selector names with HTTP 400 (`fields=abi,match` fails —
`match` is not a selectable field name, it's returned in the base envelope
regardless), so only `fields=abi` was passed.

**Re-capture after any Sugar redeploy.** These files pin the ABI shape for the
addresses below as of the fetch date. If any Sugar/helper contract is
redeployed to a new address (routine for the LP/rewards/ve/relay/token Sugar
family), re-run the same `curl` against the new address and overwrite the
corresponding file.

## Captured files

| file | contract | address | chain id | Sourcify match | fetch date | curl command |
|---|---|---|---|---|---|---|
| `lp_sugar.json` | LpSugar | `0x69dD9db6d8f8E7d83887A704f447b1a584b599A1` | 8453 | `match` (creationMatch=match, runtimeMatch=match) | 2026-08-26 | `curl -sS "https://sourcify.dev/server/v2/contract/8453/0x69dD9db6d8f8E7d83887A704f447b1a584b599A1?fields=abi"` |
| `rewards_sugar.json` | RewardsSugar | `0x1b121EfDaF4ABb8785a315C51D29BCE0552A7678` | 8453 | `match` (creationMatch=match, runtimeMatch=match) | 2026-08-26 | `curl -sS "https://sourcify.dev/server/v2/contract/8453/0x1b121EfDaF4ABb8785a315C51D29BCE0552A7678?fields=abi"` |
| `ve_sugar.json` | VeSugar | `0x4d6A741cEE6A8cC5632B2d948C050303F6246D24` | 8453 | `match` (creationMatch=match, runtimeMatch=match) | 2026-08-26 | `curl -sS "https://sourcify.dev/server/v2/contract/8453/0x4d6A741cEE6A8cC5632B2d948C050303F6246D24?fields=abi"` |
| `relay_sugar.json` | RelaySugar | `0x3dd0849D66DBd63D06f11442502e200601c50790` | 8453 | `match` (creationMatch=match, runtimeMatch=match) | 2026-08-26 | `curl -sS "https://sourcify.dev/server/v2/contract/8453/0x3dd0849D66DBd63D06f11442502e200601c50790?fields=abi"` |
| `token_sugar.json` | TokenSugar | `0x910CD56277994B4970F49AEDA52c96aD620aE81D` | 8453 | `match` (creationMatch=match, runtimeMatch=match) | 2026-08-26 | `curl -sS "https://sourcify.dev/server/v2/contract/8453/0x910CD56277994B4970F49AEDA52c96aD620aE81D?fields=abi"` |
| `voter.json` | Voter | `0x16613524e02ad97eDfeF371bC883F2F5d6C480A5` | 8453 | `match` (creationMatch=match, runtimeMatch=match) | 2026-08-26 | `curl -sS "https://sourcify.dev/server/v2/contract/8453/0x16613524e02ad97eDfeF371bC883F2F5d6C480A5?fields=abi"` |
| `pool_factory.json` | PoolFactory | `0x420DD381b31aEf6683db6B902084cB0FFECe40Da` | 8453 | `match` (creationMatch=match, runtimeMatch=match) | 2026-08-26 | `curl -sS "https://sourcify.dev/server/v2/contract/8453/0x420DD381b31aEf6683db6B902084cB0FFECe40Da?fields=abi"` |
| `cl_factory.json` | CLFactory | `0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A` | 8453 | `match` (creationMatch=match, runtimeMatch=match) | 2026-08-26 | `curl -sS "https://sourcify.dev/server/v2/contract/8453/0x5e7BB104d84c7CB9B682AaC2F3d509f5F406809A?fields=abi"` |
| `slipstream_helper.json` | SlipstreamHelper | `0x9c62ab10577fB3C20A22E231b7703Ed6D456CC7a` | 8453 | `exact_match` (creationMatch=exact_match, runtimeMatch=exact_match) | 2026-08-26 | `curl -sS "https://sourcify.dev/server/v2/contract/8453/0x9c62ab10577fB3C20A22E231b7703Ed6D456CC7a?fields=abi"` |

Note: Sourcify's `match` field distinguishes `exact_match` (bytecode
byte-for-byte identical, including metadata hash) from `match` (a "partial"
match — functionally identical, metadata/comments differ). All nine addresses
resolved with `creationMatch` and `runtimeMatch` both non-null (no partial/no
`null` matches), so every ABI here reflects the actual deployed bytecode.

## Live verification (2026-08-26, `cast` 1.5.1, RPC `https://mainnet.base.org`)

| check | contract | call | result | expected | status |
|---|---|---|---|---|---|
| 1 | lp_sugar | `count()(uint256)` | `35156` | ~35,155 | OK |
| 2 | cl_factory | `tickSpacings()(int24[])` | `[1, 50, 100, 200, 2000, 10]` | `[1, 50, 100, 200, 2000, 10]` | OK |
| 3 | cl_factory | `defaultUnstakedFee()(uint24)` | `100000` | `100000` | OK |
| 4 | lp_sugar | `token_sugar()(address)` | `0x910CD56277994B4970F49AEDA52c96aD620aE81D` | matches `token_sugar.json` address | OK |
| 5 | ve_sugar | `voter()(address)` | `0x16613524e02ad97eDfeF371bC883F2F5d6C480A5` | matches `voter.json` address | OK |
| 6 | rewards_sugar | `WEEK()(uint256)` | `604800` | 7 days in seconds | OK |
| 7 | relay_sugar | `voter()(address)` | `0x16613524e02ad97eDfeF371bC883F2F5d6C480A5` | matches `voter.json` address | OK |
| 8 | token_sugar | `MAX_TOKENS()(uint256)` | `2000` | sane cap | OK |
| 9 | voter | `length()(uint256)` | `1877` | sane pool count | OK |
| 10 | pool_factory | `allPoolsLength()(uint256)` | `28653` | sane pool count | OK |
| 11 | slipstream_helper | `getSqrtRatioAtTick(int24)(uint160)` with `0` | `79228162514264337593543950336` | `2^96` (pure-math identity, tick 0 → sqrtPriceX96 = 1.0) | OK |

Checks 5 and 7 (`ve_sugar.voter()` and `relay_sugar.voter()` both returning the
`voter.json` address) are an incidental cross-check that all three contracts
agree on the same Voter deployment.

`slipstream_helper` exposes no zero-argument view function, so check 11 uses
its `pure` `getSqrtRatioAtTick` — a deterministic Uniswap-v3-style tick-math
identity (tick 0 must map to sqrtPriceX96 = 2^96) — as the cheapest possible
sanity check against the deployed bytecode.

## `lp_sugar.all()` signature — cross-check against known ground truth

Captured ABI shows:

```
all(uint256,uint256,uint256) -> (tuple[])   // (_limit, _offset, _filter)
```

This is the **3-arg** form. It matches the ground truth in the task brief
(the deployed `all` takes `_limit, _offset, _filter`) and does **not** match
the stale 2-arg form documented in `velodrome-finance/sugar`'s own README.

## Named-function presence check (per task brief)

`lp_sugar.json`:

| function | present | signature |
|---|---|---|
| `forSwaps` | yes | `forSwaps(uint256,uint256) -> (tuple[])` |
| `positionsByFactory` | yes | `positionsByFactory(uint256,uint256,address,address) -> (tuple[])` |
| `positionsUnstakedConcentrated` | yes | `positionsUnstakedConcentrated(uint256,uint256,address) -> (tuple[])` |
| `almEstimateAmounts` | yes | `almEstimateAmounts(address,uint256,uint256) -> (uint256[3])` |
| `tokens` | yes | `tokens(uint256,uint256,address,address[]) -> (tuple[])` |

`rewards_sugar.json`:

| function | present | signature |
|---|---|---|
| `rewardsByAddress` | yes | `rewardsByAddress(uint256,address) -> (tuple[])` |
| `epochsByAddress` | yes | `epochsByAddress(uint256,uint256,address) -> (tuple[])` |
| `epochsLatest` | yes | `epochsLatest(uint256,uint256) -> (tuple[])` |
| `forRoot` | yes | `forRoot(address) -> (address[3])` |

All nine named functions are present in the captured ABIs.
