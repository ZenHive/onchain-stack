# Onchain Aerodrome

Aerodrome Finance (Base, chain id 8453) bindings, Sugar-backed reads, and pure analytics for Elixir. Depends on `onchain` core for RPC, ABI, multicall, signing, and address utilities.

<!-- Selective-load (Opus 4.8): eager floor = critical-rules + harness-workflow (this repo is
     harness-driven — the OTP dispatch→review→land loop is the active workflow). onchain-workspace
     is the harness workspace add-on (family roster + dependency shape), eager family-wide.
     ethereum-rpc stays eager (host-specific node access, no skill mirror). node-portability is the
     family law and this package is the interesting case, not the easy one — see below. Everything
     else (across-instances, worktree, task-prioritization/writing, workflow-philosophy, web-command,
     elixir-setup, ex-unit-json, dialyzer-json, code-style, development-commands/philosophy,
     agent-economy) is skill-on-demand via the elixir / task-driver / dev-lifecycle plugins.
     Re-add an @-import per-surface only if Opus visibly degrades on it. See ~/.claude/setup-guide.md. -->
@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md
@~/.claude/includes/onchain-workspace.md
@~/.claude/includes/ethereum-rpc.md
@~/.claude/includes/node-portability.md

## Toolchain & check commands (read before judging a build)

Cross-family harness reviewers read **AGENTS.md** (auto-generated from this file), not the user's Claude skills. **`mix ci`** (= `mix precommit.full`) is the canonical gate — run it before judging a build green or red. It chains: `compile --warnings-as-errors`, `format --check-formatted`, `credo --strict`, `doctor --raise`, `ex_dna --max-clones 0`, `reach.check --arch --smells`, `sobelow --skip`, `deps.audit.gated`, `test.json --cover --exclude integration`, `dialyzer`, `agents.check`. `mix precommit` is the fast local loop (no dialyzer, no coverage). `mix check.dispatch` is the per-dispatch reviewer gate (static checks only) and is what this repo registers as its harness `check_command`.

- `mix reach.check --arch --smells` gates from `.reach.exs` (`smells: [strict: true]`). Smell findings must be **fixed, never added to an ignore list**.
- `deps.audit.gated` proves the local advisory mirror is fresh (`bin/advisory-freshness.sh` in the onchain-stack coordination home) before running `deps.audit --ignore-file .mix_audit_ignore` — `mix_audit` silently discards its own sync failure, so a stale mirror would otherwise report false-green.
- `agents.check` fails when `AGENTS.md` has drifted from this file (`sync-agents-md.sh --check`).
- **The coverage floor lives in `mix.exs` (`--cover-threshold`) — read the current value there, never from prose; it was set from a measured baseline and roadmap task 22 replaces it with a tiered per-module gate.** Per `critical-rules.md` § coverage tiers, `Analytics.*` and `Math.*` are critical-path (95% target) because they are pure and there is no excuse; read/binding layers target 80%.
- `sobelow` is declared even though this package has **no Plug or web surface**. It is not there for security value — the `elixir` plugin's post-edit hook aborts its *entire* check stack (format, compile, credo, doctor, dialyzer) when sobelow is missing from `mix.exs`. Removing it silently disables per-edit checking. Leave it.

**The `.json` mix tasks emit JSON BY DESIGN — that is expected output, never an error or a broken setup:**

- **`mix test.json`** (`ex_unit_json` dep) — ExUnit results as JSON; identical run to `mix test`. Parse it for failures; the JSON envelope itself is never a failure signal. `--cover` can emit a large per-module blob — pipe to a file (`--output /tmp/cov.json`) and `jq` the summary, don't dump it to the transcript.
- **`mix dialyzer.json`** (`dialyzer_json` dep) — dialyzer warnings as JSON. Read the array for *real* warnings; do NOT flag the JSON output as a problem. If the encoder cannot serialize a warning shape, plain `mix dialyzer` is the authoritative check.

## 🚨 Base simulation is blocked — do not write revm fork tests

`onchain_evm`'s revm binding **hard-rejects any chain id other than 1**. `spec_id_for_fork` in `native/onchain_evm/src/lib.rs:98-101` returns an error because "the hardfork schedule is known only for Ethereum mainnet"; the Elixir side documents it at `lib/onchain/evm.ex:38-39`. Forking Base (8453) returns `{:error, {:fork_error, _}}`.

Consequences, all of them load-bearing:

- **Do not** write `Onchain.EVM` fork tests against a pinned Base block. They cannot run. An external spec for this package prescribed exactly that; it is wrong.
- **Do not** "fix" it by patching `deps/onchain_evm/`. Never edit anything under `deps/`.
- `onchain_evm` is still a legitimate dev/test dependency here — for `Onchain.Solidity` ABI parsing and `Onchain.Contract.Generator` codegen, **not** for simulation.
- **Determinism comes from golden fixtures plus a pinned block number**, not from a local EVM. Capture real `eth_call` return data once, commit it, and decode against it offline.

**Un-block condition:** an upstream `onchain_evm` change adding an OP-Stack/Base `spec_id` mapping, or a caller-supplied `:spec_id` option. A task for that is filed in the `onchain_evm` roadmap. When it lands, simulation-backed write tests become possible and this section should be rewritten, not deleted.

## 🚨 Sugar drift is the standing hazard

The **deployed ABI is the only authority.** Sugar's own `readme.md` in `velodrome-finance/sugar` documents `LpSugar.all(limit, offset)`; the deployed contract is **`all(uint256,uint256,uint256)`** — a third `_filter` argument — and the 2-argument form **reverts on-chain**. Documentation drift here is not hypothetical, it is the current state.

- ABIs live in `priv/abis/`, captured from **Sourcify v2** (`https://sourcify.dev/server/v2/contract/8453/<addr>?fields=abi`) because it serves the *deployed* ABI **with named tuple components** — required for `hieroglyph`'s `decode_structs: true`. `priv/abis/README.md` records address, match type, fetch date, and the exact `curl` per file.
- After any Sugar redeploy: re-capture from Sourcify, re-run the golden decode suite, and re-run the live probes in `priv/abis/README.md`. A decode that starts returning `nil` fields is drift, not a bug in the decoder.
- `decode_structs: true` uses `String.to_existing_atom/1` and **raises at runtime** on un-interned field atoms. Intern them (module attribute, `@type`, or an explicit list) before the first decode. It is also a **no-op on unnamed signatures** — the `"(uint256,bool)"` strings `Onchain.Solidity` produces carry no field names.

## 🚨 Pagination — never terminate on a short page

`LpSugar.all/3` applies `_filter` **after** fetching the page. With a non-zero filter a full page returns *fewer* than `limit` rows, and `_offset` still indexes the **unfiltered** space. The obvious "loop until a short page" termination is therefore a **silent data-loss bug**, not a crash — it stops early and reports success.

- **Drive `offset` to `count()`.** `LpSugar.count()` answered **35,156** on 2026-08-26 (it only grows). An external spec claimed "~2,500 pools"; that is off by 14× and every downstream sizing assumption built on it is wrong.
- Hard per-call caps compiled into the contracts: `MAX_LPS = 500`, `MAX_POSITIONS = 200`, `MAX_TOKENS = 2000`. `limit: 500` is verified working against the public Base RPC — so the real shape is ~71 sequential pages.
- **Multicall3 does not help the page loop.** One `all(500, …)` already returns ~1.1 MB and dominates the `eth_call` budget. `Onchain.Multicall.aggregate3/2` is for *per-pool enrichment*, not for parallelising pagination.
- **The trap generalizes beyond `all/3` — "no filter argument" does NOT imply short-page-safe.** `positions`/`positionsByFactory`/`positionsUnstakedConcentrated`, `forSwaps`, `TokenSugar.tokens`, `epochsLatest`, `rewards` and `VeSugar.all` offset over a *scanned* index space (pool index or token ids) that is not the returned-row space; upstream filtering, dedup, dead gauges and burned ids make short pages the normal mid-enumeration case. Only `epochsByAddress` (one row per epoch) is genuinely short-page-terminal. Verified against the Sugar Vyper sources, 2026-08-26.
- Batching, multicall and retries are **already provided by `onchain` core** — `Onchain.Multicall.aggregate3/2` and `call_many/2`, `Onchain.RPC.batch/2` (JSON-RPC array batch), a per-call `retry: [max_retries:, backoff_ms:]` option, and Req pool/retry config via `config :onchain, :req_options`. Do not reimplement them here.

## 🚨 APR denominators — fee and emission APRs are never summed

This is the part of the domain most likely to be silently wrong, because a wrong number still looks like a number.

- **Emit `fee_apr` and `emission_apr` separately, each tagged with its explicit denominator.** Never add them into a single "total APR". They are denominated over different capital bases and summing them is not an approximation, it is a category error.
- **Emission APR is denominated in staked, in-range liquidity** — not in total TVL. `Lp.emissions` is **per second**; the weekly figure is `emissions × 604_800`.
- **Weekly, not daily, epochs.** Cross-check that held: `12337.58 × 52 / 8_515_374 = 7.53%` against a displayed 8.76%.
- **The fee/emission dichotomy is NOT binary on Slipstream.** An unstaked concentrated-liquidity position pays a rake to the gauge: `CLFactory.defaultUnstakedFee()` = `100_000` pips (1e-6 units) = **10%**, per-pool overridable and surfaced as `Lp.unstaked_fee`. So an unstaked CL LP keeps `1 - unstaked_fee` of trading fees, not all of them. Modelling it as a clean either/or understates voter revenue and overstates unstaked-CL yield.
- **`Lp.emissions_cap` is not a token-amount bound — never `min()` it against the weekly rate.** Where the gauge factories expose a cap at all it is a *relative share* in basis points (`defaultCap()` / `MAX_BPS()`); several gauge factories revert on the cap selectors (Sugar's `_safe_emissions_cap` then yields 0), and `Lp.emissions` is the *post-notification* rate the cap has already shaped, so re-applying any cap double-counts. Probed live 2026-08-26.
- **Do not try to reproduce the frontend's headline number.** If ours disagrees with aerodrome.finance, the correct response is to state which denominator each uses — not to tune a constant until they match.
- Money is **integers**; ratios are **`Decimal`**. No floats on any money path.

## Domain facts worth not re-deriving

- **Epoch = 1 week, flipping Thursday 00:00 UTC.** `floor(ts / 604_800) * 604_800` lands on Thursday midnight because Unix epoch 0 was a Thursday.
- **`Lp.type` is the pool-type discriminator**: `-1` = v2 stable, `0` = v2 volatile, `> 0` = CL tick spacing. The whole quoting/analytics split hinges on this field.
- **`CLFactory.tickSpacings()`** returns `[1, 50, 100, 200, 2000, 10]` (that raw order, verified live).
- **There are three CL factories on Base**, not one — `base.env`'s `CL_FACTORIES_8453`. `Contracts.cl_factories/1` returns all three. Which are in scope for a given enumeration is an explicit decision, never an assumption.
- **`RewardsSugar.rewardsByAddress(uint256 _venft_id, address _pool)`** is a **veNFT-scoped** lookup, not an account lookup. `epochsByAddress` is `(limit, offset, address)`.
- **Sugar is the canonical read path** — Aerodrome has no REST API, and the `Lp` struct carries exactly the raw inputs APR needs (`emissions`, `emissions_token`, `gauge_liquidity`, `staked0`/`staked1`, `token0_fees`/`token1_fees`, `pool_fee`, `unstaked_fee`).

## Layer contract

`.reach.exs` turns "each layer is usable on its own" from prose into a gate:

| Layer | Namespace | Depends on |
|-------|-----------|------------|
| `types` | `Onchain.Aerodrome.Types.*` | nothing |
| `base` | `Onchain.Aerodrome.Contracts`, `.Epoch`, `.Math`, `.Math.*` | nothing |
| `bindings` | `Onchain.Aerodrome.Bindings.*` | `types`, `base` |
| `analytics` | `Onchain.Aerodrome.Analytics.*` | `types`, `base` |
| `read` | `Onchain.Aerodrome.Sugar.*` | everything below |
| `write` | `Onchain.Aerodrome.Write.*` | everything below |

**`analytics` sits below `read` deliberately.** APR, tick math and valuation take structs, not RPC options — so the entire L3 suite is testable with zero network, and the "never sum the APRs" invariant is checkable statically. If an analytics module needs to make a call, the design is wrong: pass it the data.

Layer order in `.reach.exs` matters — reach's `*` crosses name segments, so specific layers must precede a broad catch-all.

## Architecture

- All modules use the `Onchain.Aerodrome.*` namespace; the root discovery module is `OnchainAerodrome`.
- Pure Elixir, no native deps in the runtime dependency set.
- All dependencies resolve from hex.pm — no path or git deps, so the package is publishable as-is.
- Standard error tuples: `{:ok, result} | {:error, {:tag, reason}}`.
- **Writes return calldata by default.** Signing is opt-in and requires an explicit signer; no module reads a private key from the environment on its own.

## Node Portability

The family-wide law is `node-portability.md` (`@`-imported above). This package's specifics:

- **Everything is `eth_call` against a deployed contract**, routed through `Onchain.RPC` / `Onchain.Contract` / `Onchain.Multicall`. No `debug_*`/`trace_*`, no client extensions, no WebSocket.
- **`eth_call` weight, not archive depth, is the portability question here.** `LpSugar.all(500, offset, 0)` is heavy (~1.1 MB response), but verified 2026-08-26 on **both** the public `https://mainnet.base.org` and an Alchemy Base endpoint — identical results, so `limit: 500` is not a privileged-endpoint assumption. An endpoint with a tighter per-call gas or response cap can still refuse it; document that requirement rather than silently lowering `limit`.
- **Archive is needed only for historical/epoch queries** — anything taking a block parameter. Say so in that function's `@doc`. An integration test that only ever runs against our archive node is not evidence of portability.
- **Base only.** Contract addresses here are Base-specific; the Velodrome sibling on Optimism has different addresses and is out of scope.

## Module Layout

```
lib/onchain_aerodrome.ex        # Descripex.Discoverable roster
lib/onchain/aerodrome/
  contracts.ex                  # address registry + verified constants (base layer)
priv/abis/                      # Sourcify-captured deployed ABIs + provenance README
```

The remaining layers (`types/`, `bindings/`, `analytics/`, `sugar/`, `write/`) are scoped in `roadmap/tasks.toml` and not yet implemented. `.reach.exs` already declares them, so the gate is in place before the first module lands.

## Dependencies from onchain core

| Module | Used for |
|--------|----------|
| `Onchain.ABI` | ABI encoding/decoding |
| `Onchain.RPC` | `eth_call`, `batch/2`, per-call retry |
| `Onchain.Multicall` | `aggregate3/2`, `call_many/2` — per-pool enrichment |
| `Onchain.Contract` | Generic contract call; `Contract.Generator` for bindings |
| `Onchain.Solidity` | `parse_abi_file/1` over `priv/abis/` |
| `Onchain.Signer` | Transaction signing (opt-in write path only) |
| `Onchain.Address` | Validation, checksumming |
| `Onchain.Hex` | Hex encoding/decoding |
| `Onchain.Decimal` | Decimal math (ratios) |

## Testing

```bash
mix test.json --quiet                          # Unit tests only
mix test.json --quiet --include integration    # Unit + integration (requires a Base RPC)
```

Integration tests require a Base endpoint (`BASE_RPC_URL`, falling back to `https://mainnet.base.org`). Golden-fixture decode tests need no network at all and are the primary defence against Sugar redeploy drift.

## Contract Address Verification

Addresses in `lib/onchain/aerodrome/contracts.ex` carry a provenance comment each. Re-verify against two independent sources — never a BaseScan label alone:

```bash
# 1. The Sugar team's own deployment manifest
gh api repos/velodrome-finance/sugar/contents/deployments/base.env --jq '.content' | base64 -d

# 2. A live probe that the contract answers as expected
cast call 0x69dD9db6d8f8E7d83887A704f447b1a584b599A1 "count()(uint256)" --rpc-url https://mainnet.base.org
cast call 0x69dD9db6d8f8E7d83887A704f447b1a584b599A1 "token_sugar()(address)" --rpc-url https://mainnet.base.org
```

There is no Basescan/Etherscan API key on this host — Sourcify v2 is the ABI source. See `priv/abis/README.md`.

## Related Packages

- **onchain** — Core Ethereum primitives: `{:onchain, "~> 0.13"}`
- **onchain_aave** — The sibling protocol wrapper this package's shape is modelled on
- **onchain_evm** — Rust NIFs + codegen: `{:onchain_evm, "~> 0.6", only: [:dev, :test]}` (ABI parsing and codegen only — **simulation against Base is blocked**, see above)
- **descripex** — Runtime API discovery (`OnchainAerodrome.describe/0..2`)
