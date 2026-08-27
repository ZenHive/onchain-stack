# Onchain

Shared Ethereum/blockchain library for the portfolio. Provides read (eth_call) and write (transaction signing) capabilities using `cartouche` as the sole Ethereum dependency.

<!-- Selective-load (Opus 4.8): eager floor = critical-rules. harness-workflow is eager
     because this repo is harness-driven (the OTP dispatch→review→land loop is the active
     workflow). Everything else previously imported here (worktree, task-prioritization/writing,
     workflow-philosophy, web-command, code-style, development-philosophy/commands, elixir-setup,
     ex-unit-json, dialyzer-json, agent-economy, reach) is skill-on-demand via the elixir /
     task-driver / dev-lifecycle plugins. Re-add an @-import per-surface only if Opus visibly
     degrades on it. See ~/.claude/setup-guide.md § "Skills vs Includes".
     NOTE: onchain-workspace.md is now the HARNESS workspace add-on (7-repo roster + dependency
     shape), eager family-wide. The retired Linear/cloud-delegation add-on is
     onchain-workspace-delegation.md (DORMANT). -->
@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md
@~/.claude/includes/onchain-workspace.md
@~/.claude/includes/ethereum-rpc.md
@~/.claude/includes/node-portability.md

<!-- Harness driver contract: onchain is registered with the harness OTP node
     (~/_DATA/code/harness, config/dev.local.exs). The harness MCP server
     (mcp__harness__dispatch__*, port 4018) is the primary surface for dispatching
     onchain roadmap tasks to headless agents gated by a cross-family reviewer AI;
     mcp__harness_eval__project_eval is the escape hatch. See .mcp.json.

     On-demand, NOT eager: the harness-driver SKILL.md is 55.8k chars (over the
     40k eager-import limit) — loading it every session is wasteful. Read it only
     when actually driving harness dispatch:
       Read ~/_DATA/code/harness/skills/harness-driver/SKILL.md -->


## Stack boundary — hieroglyph / cartouche / onchain

**Cut on what defines the bytes, not on who calls the node.** Canonical statement lives in
`cartouche/ROADMAP.md` § "Scope principle"; this is the binding summary.

| Layer | Owns |
|---|---|
| **hieroglyph** | The ABI codec. Pure functions over types and bytes. No I/O, no chain identity, no node. |
| **cartouche** | Everything defined by the **node's wire format**: the JSON-RPC transport, and one wrapper **plus one decoded struct** for every method in a **tagged release** of the `execution-apis` OpenRPC spec — plus transaction envelopes, signing, crypto, hex, and chain ids. |
| **onchain** (and `onchain_*` siblings) | Everything defined by a **contract, a standard, or an off-node protocol**: ERC-*, ENS, AA, MEV, DEX, Multicall, subscriptions, vendor/bundler/relay namespaces. It **re-presents** cartouche's structs; it never re-derives them. |

Routing, in one read:

- **New `eth_*` / `net_*` wrapper** → cartouche, iff the method is in a **tagged** OpenRPC
  release. Not in the spec → cartouche only with a `@doc` naming who serves it *and* a
  capability probe. Vendor/bundler/relay namespace (`eth_sendUserOperation`,
  `eth_sendBundle`, `eth_sendPrivateTransaction`) → onchain.
- **Response decoding** → cartouche, always, into a cartouche struct. onchain never
  re-derives a JSON shape the node emits.
- **ERC standard** → onchain, or a sibling when domain-heavy (`onchain_aave`).
- **Chain constants** → cartouche (`Cartouche.Chain`). A chain with a different tx envelope
  gets its own package (`onchain_tempo`).
- **Non-EVM chain** → its own package. Not cartouche, not onchain.

**Why the previous rule was reversed (2026-08-27).** The old rule sent "RPC method
wrappers" to onchain while leaving the transport and the response structs in cartouche.
That is not a separable cut — `send_rpc/3` takes a `:decode` function, so a wrapper is
*method string + param normalizer + pointer to a cartouche struct*, two of three parts
already cartouche's. onchain could not own the decode without owning the struct, so it
wrote its own. Measured cost: two mutually-incompatible `Block` representations
(`Cartouche.Block` → struct with raw binaries; `Onchain.RPC.Helpers.parse_block_response/1`
→ plain map with `0x` strings), ~500 LOC of duplicate decoders, twelve methods wrapped at
both layers, a `@dialyzer {:no_match, do_rpc: 3}` suppression as the receipt, and
`Onchain.HTTP` (34 LOC) existing only to escape cartouche's config key. No test can catch
that class, because no module consumes both. **The old rule did not prevent the
duplication — it caused it.**

**Migrate lazily, never as a campaign.** When a task ports a method down into cartouche,
the same task converts onchain's copy into a facade. Do not open a migration project.

## Portfolio Context

This repo is part of a multi-library portfolio. The boundary is **ephemeral vs durable**, not read vs write. Each native runtime gets its own package.

- **onchain** (this repo) — core Ethereum primitives, RPC, ABI, signing (pure Elixir, no native deps)
- **onchain_aave** — Aave V3 protocol wrappers (depends on onchain, pure Elixir)
- **onchain_evm** — Rust NIFs: revm simulation, Solidity parsing, debug/trace, codegen (depends on onchain + Rustler)
- **onchain_js** — JS bridge: npm packages on the BEAM via QuickBEAM (depends on onchain + Zig NIFs)
- **onchain_tempo** — Tempo blockchain primitives: 0x76 transactions, TIP-20 encoding, RPC, TransferWithMemo parsing (depends on onchain, pure Elixir)
- **onchain_agents** *(planned)* — EIP-8004 Trustless Agents: Identity / Reputation / Validation registries, plus Descripex manifest bridge for trustless verification (depends on onchain, pure Elixir). Triggered when a consumer needs agent-economy registration; see `ROADMAP.md` "EIP Tracking"
- **rexex** — chain indexing, storing durable facts (ExEx ingestion, Postgres, reorg-safe history, dashboards)
- **hologram** — JS runtimes, npm access, headless/edge execution (Elixir interpreter in any JS runtime)

**Where does this feature go?**

1. Talks to Ethereum directly and returns an immediate result? → **onchain**
2. Talks to Tempo chain (0x76 txs, TIP-20 tokens)? → **onchain_tempo**
3. Runs npm packages on the BEAM (solc-js, Uniswap SDK, etc.)? → **onchain_js**
4. Persists or queries chain facts over time? → **rexex**
5. Runs Elixir in JS or reaches npm/edge runtimes? → **hologram**
6. Registers / queries / validates agents via EIP-8004 registries? → **onchain_agents** (when built)
7. Composes those capabilities into a user-facing workflow? → **separate consumer repo**

**Scope split with cartouche (substrate layer).** cartouche = Ethereum primitives (key management, signing, transaction encoding, raw RPC, hex/ABI/typed-data). onchain (and its siblings) = everything buildable on top of `Cartouche.*` from outside cartouche. **Rule:** if the feature requires cartouche internals (new tx type, signer extension, primitive encoding), it's a cartouche-PR candidate. Otherwise — including RPC method wrappers, ERC standards, protocol parsers, telemetry facades, retry/backoff, fee helpers, EIP-8004 registries — it lives in this portfolio. See `../signet/ROADMAP.md` "Scope principle" for the full classification and EIP triage rubric (the sibling design-discussion repo retains its historical name).

**Watch boundary:** onchain Phase 8 (eth_subscribe, Transfer parser) overlaps rexex territory. The distinction: onchain returns results to the caller (ephemeral); rexex writes facts to Postgres (durable). If a consumer needs historical queries over indexed data, that's rexex.

**Agent consumers:** AI agents are first-class consumers of this library. See [AGENT_WISHLIST.md](AGENT_WISHLIST.md) for use cases and scenarios. EIP-8004 registration / reputation / validation lives in `onchain_agents` — see `ROADMAP.md` "EIP Tracking".

## Architecture

- **Pure Elixir** — no native deps, no Rustler, no compilation of C/Rust
- **cartouche** is the primary Ethereum dep — RPC, ABI encoding, signing, crypto all in one (transitively pulls in `hieroglyph` for ABI)
- **zen_websocket** for WebSocket transport (eth_subscribe real-time subscriptions)
- Cartouche wraps **curvy** (pure Elixir secp256k1) internally for signing/key ops — never add curvy as a direct dep
- Consumers configure RPC URL via `config :cartouche` or pass URL per-call
- Standard error tuples: `{:ok, result} | {:error, {:tag, reason}}`
- Plain structs with `defstruct` + `@enforce_keys`, no private macro deps
- Path dependency in consumers: `{:onchain, path: "../onchain"}`

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

Canonical gate: **`mix ci`** (= `precommit.full`) — compile `--warnings-as-errors`,
`format --check-formatted`, `credo --strict`, `doctor --raise`, `ex_dna --max-clones 0`,
`reach.check --arch --smells`, `sobelow --skip`, `deps.audit.gated`, `test.json --cover
--cover-threshold 70`, `dialyzer`, `agents.check`. `mix precommit` is the fast local loop
(no dialyzer/coverage). A clean `mix ci` is the merge bar.

- **`mix test.json` / `mix dialyzer.json` emit JSON by design** — parse for real failures,
  never flag the envelope itself as a problem. When the JSON encoder can't serialize a
  warning shape, plain `mix dialyzer` (MIX_ENV=dev) is authoritative.
- **`mix reach.check --arch --smells` gates from `.reach.exs`** (`smells: [strict: true]`),
  scanned across `roots=dev, lib, src` — do not narrow that scope. Smell findings must be
  fixed, never added to an ignore list.
- **`deps.audit.gated`** runs `bin/advisory-freshness.sh` (in `onchain-stack`) before
  `mix deps.audit --ignore-file .mix_audit_ignore` — `mix_audit` discards its own sync exit
  status, so a frozen advisory DB would otherwise still report green. The one ignore entry
  (`GHSA-w4f7-4cxr-rv3c`) is a verified false positive for `gun` — see `.mix_audit_ignore`
  for the full rationale. Do not add any other advisory id to that file.

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

**Moved to onchain_aave:** `aave/` (math, contracts, pool, oracle, faucet, ui_pool_data_provider, types/)
**Moved to onchain_evm:** `evm.ex`, `solidity.ex`, `trace.ex`, `contract/generator.ex`, `native/`

## Git Workflow (current)

- **Harness-driven.** As of 2026-06 this repo's active workflow is the harness OTP loop (`@~/.claude/includes/harness-workflow.md`): rmap task → implementer AI in a `harness/<run-id>` worktree → cross-family reviewer (THE GATE) → ff-merge/land to `development`. The retired Linear-as-queue + Codex/Cursor delegation flow (`onchain-workspace`) no longer applies.
- **No PRs for routine work.** Completed work commits and merges **directly to `development`** (the default branch). Don't open `gh pr create` — harness lands via ff-merge; manual work commits/merges to `development` directly. (Overrides the global PR-based / GH-native-auto-merge flow for this repo.)
- **Manual worktrees: ask first.** Harness manages its own per-run worktrees automatically. For *hand-build* sessions outside harness, the global worktree-workflow auto-allows a worktree when a tracking ID exists; in this repo, **ask first** — don't auto-create one.

## After Every Task

Update **all affected `.md` files** after completing any roadmap task. This is part of every task, not a separate step.

- **ROADMAP.md** — Mark status (⬜ → ✅), update Current Focus section
- **CHANGELOG.md** — Add entry under latest section with what was done
- **README.md** — Update if new modules, changed APIs, or user-facing functionality
- **CLAUDE.md** — Update Module Layout if files were added/removed/renamed, update Architecture if conventions changed

**Code reviewers**: Verify all four files were checked. Reject reviews where task completion didn't include doc updates.

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

**This is now the only way the differential suite ever runs.** It used to also run nightly and non-gating via `.github/workflows/differential.yml`, removed with every other workflow on 2026-08-22 — so archive-node drift no longer surfaces on its own. Run `ocdiff` deliberately when touching RPC decoding or block/receipt shapes.

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

- **onchain_aave** — Aave V3 wrappers: `{:onchain_aave, path: "../onchain_aave"}`
- **onchain_evm** — Rust NIFs + codegen: `{:onchain_evm, path: "../onchain_evm"}`
- **onchain_js** — JS bridge (QuickBEAM): `{:onchain_js, path: "../onchain_js"}`
- **onchain_tempo** — Tempo chain primitives: `{:onchain_tempo, path: "../onchain_tempo"}`
