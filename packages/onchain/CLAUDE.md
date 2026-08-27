# Onchain

Shared Ethereum/blockchain library for the portfolio. Provides read (eth_call) and write (transaction signing) capabilities using `cartouche` as the sole Ethereum dependency.

<!-- Selective-load (Opus 4.8): eager floor = critical-rules. harness-workflow is eager
     because this repo is harness-driven (the OTP dispatch→review→land loop is the active
     workflow). Everything else previously imported here (worktree, task-prioritization/writing,
     workflow-philosophy, web-command, code-style, development-philosophy/commands, elixir-setup,
     ex-unit-json, dialyzer-json, agent-economy, reach) is skill-on-demand via the elixir /
     task-driver / dev-lifecycle plugins. Re-add an @-import per-surface only if Opus visibly
     degrades on it. See ~/.claude/setup-guide.md § "Skills vs Includes".
     NOTE: onchain-workspace.md is the HARNESS workspace add-on (monorepo layout + sibling/3 +
     dependency shape), eager family-wide. The retired Linear/cloud-delegation add-on is
     onchain-workspace-delegation.md (DORMANT). -->
@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md
@~/.claude/includes/onchain-workspace.md
@~/.claude/includes/ethereum-rpc.md
@~/.claude/includes/node-portability.md

<!-- Harness driver contract: this package is dispatched through the single
     `onchain_stack` harness project registered against the monorepo root
     (~/_DATA/code/harness, config/dev.local.exs). The harness MCP server
     (mcp__harness__dispatch__*, port 4018) is the primary surface for dispatching
     roadmap tasks targeting this package to headless agents gated by a cross-family
     reviewer AI; mcp__harness_eval__project_eval is the escape hatch. See .mcp.json.

     On-demand, NOT eager: the harness-driver SKILL.md is 55.8k chars (over the
     40k eager-import limit) — loading it every session is wasteful. Read it only
     when actually driving harness dispatch:
       Read ~/_DATA/code/harness/skills/harness-driver/SKILL.md -->

See the root `CLAUDE.md` for the hieroglyph/cartouche/onchain stack-boundary
routing rule, the sibling/3 mechanism, and the shared gate adjudications. This
file carries only what's specific to this package.

## Portfolio Context

This package is part of a multi-library portfolio (root `CLAUDE.md` §
Layout). The boundary is **ephemeral vs durable**, not read vs write.

- **onchain** (this package) — core Ethereum primitives, RPC, ABI, signing (pure Elixir, no native deps)
- **onchain_aave** / **onchain_aerodrome** — protocol wrappers (depend on onchain, pure Elixir)
- **onchain_evm** — Rust NIFs: revm simulation, Solidity parsing, debug/trace, codegen
- **onchain_js** — JS bridge: npm packages on the BEAM via QuickBEAM
- **onchain_tempo** — Tempo blockchain primitives (0x76 transactions, TIP-20, depends on onchain)
- **onchain_agents** *(planned)* — EIP-8004 Trustless Agents: Identity / Reputation / Validation registries, plus a Descripex manifest bridge for trustless verification. Triggered when a consumer needs agent-economy registration; see `ROADMAP.md` "EIP Tracking" (task offset +3000)
- **rexex** *(separate, unabsorbed repo)* — chain indexing, durable facts (ExEx ingestion, Postgres, reorg-safe history)
- **hologram** *(separate, unabsorbed repo)* — JS runtimes, npm access, headless/edge execution

**Where does this feature go?**

1. Talks to Ethereum directly and returns an immediate result? → **onchain**
2. Talks to Tempo chain (0x76 txs, TIP-20 tokens)? → **onchain_tempo**
3. Runs npm packages on the BEAM (solc-js, Uniswap SDK, etc.)? → **onchain_js**
4. Persists or queries chain facts over time? → **rexex**
5. Runs Elixir in JS or reaches npm/edge runtimes? → **hologram**
6. Registers / queries / validates agents via EIP-8004 registries? → **onchain_agents** (when built)
7. Composes those capabilities into a user-facing workflow? → **separate consumer repo**

**Watch boundary:** onchain Phase 8 (eth_subscribe, Transfer parser) overlaps rexex territory. The distinction: onchain returns results to the caller (ephemeral); rexex writes facts to Postgres (durable). If a consumer needs historical queries over indexed data, that's rexex.

**Agent consumers:** AI agents are first-class consumers of this library. See [AGENT_WISHLIST.md](AGENT_WISHLIST.md) for use cases and scenarios. EIP-8004 registration / reputation / validation lives in `onchain_agents` — see `ROADMAP.md` "EIP Tracking".

## Architecture

- **Pure Elixir** — no native deps, no Rustler, no compilation of C/Rust
- **cartouche** is the primary Ethereum dep — RPC, ABI encoding, signing, crypto all in one (transitively pulls in `hieroglyph` for ABI), resolved via `sibling(:cartouche, ...)`
- **zen_websocket** for WebSocket transport (eth_subscribe real-time subscriptions) — a standalone (unabsorbed) dep, plain Hex requirement, no sibling/3 involved
- Cartouche wraps **curvy** (pure Elixir secp256k1) internally for signing/key ops — never add curvy as a direct dep
- Consumers configure RPC URL via `config :cartouche` or pass URL per-call
- Standard error tuples: `{:ok, result} | {:error, {:tag, reason}}`
- Plain structs with `defstruct` + `@enforce_keys`, no private macro deps

## Node Portability

The family-wide law is `node-portability.md` (`@`-imported above): our archive node is a
privileged environment, not the reference one, and this is an open-source package whose
users run Alchemy, Infura, or a pruned Geth. What is specific to this repo:

- **`Onchain.RPC.base_fee/1` is the worked example.** Read the `NOTE (portability):`
  comment above it in `lib/onchain/rpc.ex` — it records why the wrapper reads
  `baseFeePerGas` from the **pending** block header instead of calling cartouche's
  `eth_baseFee` (an Erigon extension Alchemy rejects with `-32600`), and the batch request
  that proved the two equivalent on reth v2.5.1. That comment tag is the convention:
  a non-obvious portability decision gets a `NOTE (portability):` comment naming the
  method, who serves it, and the consumer-visible error.
- **Node-capability refusals are classified on `Onchain.RPC`'s shared `do_rpc/3`
  path and on `batch/2`'s decode path.** A method the node does not implement is `{:error, {:method_not_found, map}}`,
  a plan-disabled namespace is `{:error, {:namespace_unavailable, map}}`, and a
  request the node cannot complete (including historical `eth_feeHistory` on Alchemy)
  is `{:error, {:unavailable, map}}`. Unrecognized codes stay `{:rpc_error, map}`.
  Patterns are pinned from live Alchemy + reth responses; `-32001` is not uniquely
  pruned history. See the module's "Node-capability refusals" section.
- **`defrpc`'s compile-time guard does NOT enforce this.**
  `Onchain.RPC.Codegen.ensure_known_method!/1` calls `Specs.lookup/1`, which reads the
  **merged** OpenRPC + `erigon-methods.json` map — a `trace_*` Erigon method passes
  exactly as `eth_getBalance` does. `eth_baseFee` was rejected only because it is in
  *neither* file. Standard-vs-extension is a judgment call at review time, not a gate.
- **Limited-endpoint tests use `Onchain.RPCCase.limited_rpc_url!/0`**
  (`ETHEREUM_LIMITED_RPC_URL` or `ETHEREUM_ALCHEMY_URL`) and flunk with setup
  instructions when unset. Success-path dual-endpoint verification still has no
  automatic seam — `rpc_url!/0` returns a single string — so a portability claim
  on a *successful* read still means you ran it against a hosted endpoint by hand.
- **Two surfaces legitimately need more than a default endpoint** and are documented as
  such in `README.md` § "Node compatibility": historical reads need an archive node,
  and `Onchain.Subscription` needs a WebSocket URL. Adding a third means adding a row.

## Toolchain & check commands

Canonical gate: **`mix ci`** (= `precommit.full`), same shape as every other
package (root `CLAUDE.md` § Gates). Coverage floor here is **70%**. `mix
precommit` is the fast local loop (no dialyzer/coverage).

- **`reach.check --arch --smells` is scanned across `roots=dev, lib, src`** —
  do not narrow that scope.
- **`deps.audit.gated`** runs against `.mix_audit_ignore` (symlinked from the
  root file — see root `CLAUDE.md` § Adjudicated findings for the gun/cowlib
  false-positive rationale). Do not add any other advisory id to it.

## Module Layout

```
lib/onchain/
  hex.ex            # hex<->binary, hex<->integer, 0x prefix
  http.ex           # req_options/3 — onchain's Req transport-override seam (:onchain app config) for batch + CCIP gateway
  address.ex        # validate, checksum (EIP-55), normalize
  abi.ex            # encode_call/2, decode_response/2, decode_types/2, decode_call/3, decode_error/2
  decimal.ex        # to_decimal/2, to_basis_points/1, div_pow10/2
  fees.ex           # suggest_fees/2 — EIP-1559 fee recommendation over Cartouche.FeeHistory.t()
  rpc.ex            # eth_call, eth_estimateGas, eth_getLogs, eth_getBalance, receipts, nonces, syncing, fee_history, base_fee (portable, via the block header), blob_base_fee, get_proof, generic call/3 passthrough; do_rpc + batch classify node refusals (:method_not_found / :namespace_unavailable / :unavailable)
  rpc/codegen.ex    # defrpc/defrpc_bang macros — NimbleOptions-backed codegen for uniform RPC wrapper bodies
  rpc/helpers.ex    # shared RPC helpers; parse_block_response/1, parse_transaction_map/1; do_rpc enriches revert maps with :data hex for decode_error/2
  signer.ex         # key management, transaction signing
  erc20.ex          # reads + writes: balanceOf, allowance, decimals, symbol, totalSupply, approve, transfer
  erc721.ex         # ERC-721 NFT reads: ownerOf, tokenURI, balanceOf
  erc1155.ex        # ERC-1155 multi-token reads: balanceOf, balanceOfBatch, uri
  erc7730.ex        # ERC-7730 clear-signing: load/1, format/2, format!/2
  erc7730/
    descriptor.ex   # parse + structurally validate descriptor JSON → struct
    binding.ex      # resolve which display format applies (calldata / EIP-712 / UserOp)
    formatter.ex    # display-rule engine: path resolution + field formatters
  block.ex          # block queries
  contract.ex       # generic call/4 (encode → eth_call → decode)
  log.ex            # event log queries
  wallet.ex         # classify (EOA/contract), native ETH balance
  multicall.ex      # batched calls via Multicall3
  sleuth.ex         # Compound-style deploy-as-call: ship bytecode in eth_call, decode returned bytes
  ens.ex            # ENS resolution: namehash, resolve, reverse, records; address/3 multi-coin (ENSIP-9/10 wildcard + EIP-3668 CCIP-Read); normalize/1, dns_encode/1, evm_coin_type/1
  ens/
    normalize.ex    # UTS-46/ENSIP-15 name normalization (deterministic subset: case-fold + NFC + ignored/disallowed code points)
    ccip.ex         # EIP-3668 CCIP-Read pure helpers + injectable gateway round-trip loop
  transfer.ex       # ERC-20 Transfer event parsing
  mev.ex            # private tx submission via Flashbots-style relays (eth_sendPrivateTransaction / eth_sendBundle)
  subscription.ex   # real-time eth_subscribe (newHeads, pendingTx, logs)
  subscription/
    parser.ex       # pure parsing for subscription notification payloads
  dex/
    router.ex       # DEX swap routing — optimal path across Uniswap v2/v3 pools (pure-Elixir v2 math + on-chain QuoterV2 for v3); Onchain.DEX.Router + Pool/Route structs
  aa.ex             # ERC-4337: UserOperation hashing/signing + bundler RPC (v0.6 + v0.7 EntryPoint)
  aa/
    user_operation.ex # ERC-4337 UserOperation struct (unpacked, version-agnostic)
```

**Lives in onchain_aave:** `aave/` (math, contracts, pool, oracle, faucet, ui_pool_data_provider, types/)
**Lives in onchain_evm:** `evm.ex`, `solidity.ex`, `trace.ex`, `contract/generator.ex`, `native/`

## Testing

- **A green integration run against `localhost:8545` is not a portability claim** — see
  `## Node Portability` above before asserting a method works for consumers.
- Unit tests for all pure functions (hex, address, decimal, math)
- Integration tests are **excluded by default** (`ExUnit.start(exclude: [:integration])` in test_helper.exs)
- `mix test.json --quiet` runs only unit tests — no flags needed to skip integration
- Integration tests for RPC reads require `ETHEREUM_API_URL` or `ETH_RPC_URL` env var
- Integration tests for Sepolia writes (`@tag :sepolia_send`) additionally require `SIGNER_PRIVATE_KEY`
- Use `Onchain.RPCCase.rpc_url!/0` from `test/support/rpc_case.ex` to resolve RPC URL
- Use `flunk/1` with setup instructions for missing credentials, never silent skip

#### Credentialed integration suites

`BUNDLER_RPC_URL` and `MEV_RELAY_URL` are persisted in `~/.secrets` (sourced by `.zprofile`). `ETHEREUM_API_URL` defaults to the `localhost:8545` archive-node tunnel — bring it up (`ssh -L 8545:127.0.0.1:8545 blockwatch-one`) or override inline with `$ETHEREUM_ALCHEMY_URL` (mainnet, also serves ERC-4337 methods).

| Suite (tag) | Env vars | Notes |
|---|---|---|
| Differential RPC (`:differential`) | `ONCHAIN_DIFFERENTIAL_TESTS=1` + mainnet `ETHEREUM_API_URL` | Compares `Onchain.RPC` vs `Cartouche.RPC` against one mainnet URL. Reads historical block `20_000_000` → needs archive. |
| AA bundler (`aa_integration_test.exs`) | `BUNDLER_RPC_URL` | Read-only ERC-4337 calls. Alchemy serves these on its standard node URL. |
| MEV relay (`mev_integration_test.exs`) | `MEV_RELAY_URL` (`https://rpc.flashbots.net`) | No `MEV_AUTH_HEADER` — Flashbots' `signature required` reply is itself the valid JSON-RPC round-trip the test asserts. |
| Node-capability refusals (`rpc/node_refusal_integration_test.exs`) | `ETHEREUM_API_URL` (archive `-32601`) plus `ETHEREUM_LIMITED_RPC_URL` or `ETHEREUM_ALCHEMY_URL` (hosted `-32600` / `-32001`) | Flunks with the exact export commands when the limited URL is unset. |

Run differential + AA + MEV (do **not** point `ETHEREUM_API_URL` at Alchemy
when running the node-refusal suite — that suite pins archive `-32601` on
`rpc_url!/0` and hosted refusals on `limited_rpc_url!/0`):

```bash
ONCHAIN_DIFFERENTIAL_TESTS=1 ETHEREUM_API_URL="$ETHEREUM_ALCHEMY_URL" \
mix test.json --quiet --include integration --include differential
```

**Differential only — `ocdiff` shell helper** (in `~/.zshrc`): runs the differential suite against the Alchemy archive (no SSH tunnel needed); pass a URL to override (`ocdiff http://localhost:8545`).

**This is now the only way the differential suite ever runs** — there is no
scheduled/nightly run any more (removed with every workflow, family-wide,
2026-08-22), so archive-node drift no longer surfaces on its own. Run
`ocdiff` deliberately when touching RPC decoding or block/receipt shapes.

### Quick Commands

```bash
mix test.json --quiet                          # Unit tests only (integration excluded by default)
mix test.json --quiet --failed --first-failure # Iterate on failures
mix test.json --quiet --include integration    # Unit + all integration tests
mix test.json --quiet --only integration       # Integration tests only
mix test.json --quiet --only sepolia_send      # Sepolia write tests only (sends transactions)
mix dialyzer.json --quiet                      # AI-friendly dialyzer output
mix credo --strict --format json               # Static analysis (JSON output)
```

## Related Packages

- **onchain_aave** — Aave V3 wrappers: `sibling(:onchain, ...)` consumer
- **onchain_evm** — Rust NIFs + codegen: `sibling(:onchain, ...)` consumer
- **onchain_js** — JS bridge (QuickBEAM): `sibling(:onchain, ...)` consumer
- **onchain_tempo** — Tempo chain primitives: `sibling(:onchain, ...)` consumer
