# Onchain

@~/.claude/includes/verification-policy.md

Shared Ethereum/blockchain library for the portfolio. Provides read (eth_call) and write (transaction signing) capabilities including the former hieroglyph and cartouche code, renamed to `Onchain.*` (`Onchain.ABI.*` for the codec) in 0.16.0.

<!-- Selective-load (Opus 4.8): eager floor = critical-rules. harness-workflow is eager
     because this repo is harness-driven (the OTP dispatch→review→land loop is the active
     workflow). Everything else previously imported here (worktree, task-prioritization/writing,
     workflow-philosophy, web-command, code-style, development-philosophy/commands, elixir-setup,
     ex-unit-json, dialyzer-json, agent-economy, reach) is skill-on-demand via the elixir /
     task-driver / dev-lifecycle plugins. Re-add an @-import per-surface only if Opus visibly
     degrades on it. See ~/.claude/setup-guide.md § "Skills vs Includes".
     Workspace layout and release ordering are maintained in ../../CLAUDE.md. -->
@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-guardrails.md
<!-- Consolidated workspace layout and release ordering: see ../../CLAUDE.md. -->
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

See the root `CLAUDE.md` for the consolidated layout, the sibling/3 mechanism, and the shared gate adjudications. This
file carries only what's specific to this package.

## Portfolio Context

This package is part of a multi-library portfolio (root `CLAUDE.md` §
Layout). The boundary is **ephemeral vs durable**, not read vs write.

- **onchain** (this package) — core Ethereum primitives, RPC, ABI, signing (includes crypto NIF dependencies)
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

- **ABI codecs use an alloy Rust NIF**, shipped as checksum-verified precompiled artifacts. Supported consumers do not need Cargo.
- **Former hieroglyph and cartouche code** ships inside this package under `Onchain.*` since 0.16.0 (full map in `CHANGELOG.md`); `:cartouche` config keys are unchanged.
- **zen_websocket** for WebSocket transport (eth_subscribe real-time subscriptions) — a standalone (unabsorbed) dep, plain Hex requirement, no sibling/3 involved
- Signing wraps **ex_secp256k1** (precompiled RustCrypto k256 NIF) internally for signing/key ops via `Onchain.Signer.Secp256k1` — never add a secp256k1 library as a direct dep
- Consumers configure RPC URL via `config :cartouche` or pass URL per-call
- Standard error tuples: `{:ok, result} | {:error, {:tag, reason}}`
- Plain structs with `defstruct` + `@enforce_keys`, no private macro deps

## Node Portability

The family-wide law is `node-portability.md` (`@`-imported above): our archive node is a
privileged environment, not the reference one, and this is an open-source package whose
users run Alchemy, Infura, or a pruned Geth. What is specific to this repo:

- **`Onchain.RPC.base_fee/1` is the worked example.** It reads the final
  `baseFeePerGas` from `eth_feeHistory(1, "latest", [])`. `eth_baseFee` is on
  execution-apis `main` since 2026-06-15 and in no tagged release; Alchemy and
  Infura mainnet refuse it. `Onchain.RPC.base_fee/1` (the pending-header read)
  is removed. Verbatim refusals and the same-batch equality check are in
  `docs/base-fee-portability.md`. A non-obvious portability decision still gets
  a `NOTE (portability):` comment naming the method, who serves it, and the
  consumer-visible error.
- **Node-capability refusals are classified in `Onchain.RPC` (`send_rpc/3` and
  `send_batch/2`).** `Onchain.RPC.Helpers.do_rpc/3` and `Onchain.RPC.batch/2` both call that transport. A method the node does not implement is `{:error, {:method_not_found, map}}`,
  a plan-disabled namespace is `{:error, {:namespace_unavailable, map}}`, and a
  request the node cannot complete (including historical `eth_feeHistory` on Alchemy)
  is `{:error, {:unavailable, map}}`. Unrecognized codes stay `{:rpc_error, map}`.
  Patterns are pinned from live Alchemy + reth responses; `-32001` is not uniquely
  pruned history. See the module's "Node-capability refusals" section.
- **`defrpc`'s compile-time guard does NOT enforce this.**
  `Onchain.RPC.Codegen.ensure_known_method!/1` calls `Specs.lookup/1`, which reads the
  **merged** OpenRPC + `erigon-methods.json` map — a `trace_*` Erigon method passes
  exactly as `eth_getBalance` does. The OpenRPC file is
  `priv/specs/openrpc-v1.0.0-beta.7.json`, built from the execution-apis tag
  v1.0.0-beta.7 (`5aebdfdd45cadeb723be4bd45b4611b71c8b1c85`). `eth_baseFee`,
  `net_listening`, `net_peerCount`, and `web3_clientVersion` are absent from that
  file. Standard-vs-extension is a judgment call at review time, not a gate.
- **Limited-endpoint tests use `Onchain.RPCCase.limited_rpc_url!/0`**
  (`ETHEREUM_LIMITED_RPC_URL` or `ETHEREUM_ALCHEMY_URL`) and flunk with setup
  instructions when unset. Success-path dual-endpoint verification still has no
  automatic seam — `rpc_url!/0` returns a single string — so a portability claim
  on a *successful* read still means you ran it against a hosted endpoint by hand.
- **Endpoint requirements belong in `README.md` § "Node compatibility".**
  It covers historical reads, WebSocket subscriptions, tracing namespaces and
  methods a provider does not implement. Document any additional requirement
  there; the portable next-block base-fee read needs no special endpoint.

## Toolchain & check commands

Full post-merge QA: **`mix ci`** (= `precommit.full`), same shape as every other
package (root `CLAUDE.md` § Gates). Coverage floors are per library (`mix onchain.coverage`, see below). `mix
precommit` is the fast local loop (no dialyzer/coverage).

- **`reach.check --arch --smells` is scanned across `lib, dev, sol/src, test/support`** —
  do not narrow that scope (`--dead-code` times out; see Gate configuration below).
- **`deps.audit.gated`** runs against `.mix_audit_ignore` (symlinked from the
  root file — see root `CLAUDE.md` § Adjudicated findings for the gun/cowlib
  false-positive rationale). Do not add any other advisory id to it.

## Module Layout

```
lib/onchain/
  abi.ex, abi/      # Onchain.ABI codec (alloy NIF); hex conveniences are encode_hex_call/decode_hex_call/decode_hex_error
  configuration.ex  # Onchain.Configuration: former Cartouche root (config + descripex discovery)
  hex.ex            # hex codec, sigils, and the former Onchain.Hex convenience names
  http.ex           # Req options; Onchain.ENS reads :onchain, other owners read :cartouche
  block.ex          # full block decode plus get_by_number/find_by_timestamp
  address.ex        # validate, checksum (EIP-55), normalize, from_public_key/1
  decimal.ex        # to_decimal/2, to_basis_points/1, div_pow10/2
  fees.ex           # suggest_fees/2 — EIP-1559 fee recommendation over Onchain.FeeHistory.t()
  rpc.ex            # Onchain.RPC: the one RPC module (formerly Cartouche.RPC; the 0.15 Onchain.RPC aliases are gone). Next-block base fee is base_fee/1 via eth_feeHistory. Node refusals are classified on send_rpc/3 (:method_not_found / :namespace_unavailable / :unavailable). eth_getStorageAt and EIP-1186 eth_getProof are eth_get_storage_at/3 and eth_get_proof/3
  rpc/proof.ex, rpc/trace.ex  # eth_getProof and trace_* result structs (Onchain.RPC.Trace, not onchain_evm's Onchain.Trace)
  rpc/codegen.ex    # the one defrpc/2 macro, checked against Onchain.RPC.Specs, plus defrpc_bang/2
  rpc/helpers.ex    # shared RPC helpers; parse_block_response/1, parse_transaction_map/1; do_rpc enriches revert maps with :data hex for decode_error/2. parse_log/1 is removed; receipt and subscription logs decode through Onchain.Filter.Log
  erc20.ex          # reads + writes, plus ERC20.Call and ERC20.CallData
  erc721.ex         # ERC-721 NFT reads: ownerOf, tokenURI, balanceOf
  erc1155.ex        # ERC-1155 multi-token reads: balanceOf, balanceOfBatch, uri
  erc7730.ex        # ERC-7730 clear-signing: load/1, format/2, format!/2
  erc7730/
    descriptor.ex   # parse + structurally validate descriptor JSON → struct
    binding.ex      # resolve which display format applies (calldata / EIP-712 / UserOp)
    formatter.ex    # display-rule engine: path resolution + field formatters
  contract.ex       # generic call/4 (encode → eth_call → decode)
  contract/
    abi.ex          # alloy-json-abi JSON parser (core NIF)
    generator.ex    # compile-time ABI JSON codegen; .sol inputs delegate to onchain_evm
  wallet.ex         # classify (EOA/contract), native ETH balance
  multicall.ex      # batched calls via Multicall3
  ens.ex            # ENS resolution: namehash, resolve, reverse, records; address/3 multi-coin (ENSIP-9/10 wildcard + EIP-3668 CCIP-Read); normalize/1, dns_encode/1, evm_coin_type/1
  ens/
    normalize.ex    # UTS-46/ENSIP-15 name normalization (deterministic subset: case-fold + NFC + ignored/disallowed code points)
    ccip.ex         # EIP-3668 CCIP-Read pure helpers + injectable gateway round-trip loop
  transfer.ex       # ERC-20/721/1155 Transfer parsing via Onchain.ABI.decode_event/3
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
**Lives in onchain_evm:** `evm.ex`, `solidity.ex`, `trace.ex`, `native/`

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
| Differential RPC (`:differential`) | `ONCHAIN_DIFFERENTIAL_TESTS=1` + mainnet `ETHEREUM_API_URL` | Compares `Onchain.RPC` wrappers with independently decoded wire results on one mainnet URL. Reads historical block `20_000_000` → needs archive. |
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

## Consolidated ABI and Cartouche sources

hieroglyph's `ABI.*` and cartouche's `Cartouche.*` sources moved into this
package and were renamed to `Onchain.*` in 0.16.0; they now live under
`lib/onchain/` (`abi.ex` and `abi/` for the codec, `configuration.ex` for the
former `Cartouche` root). The former yecc/leex grammar is removed; type parsing
uses alloy. `priv/*.json`, `sol/`, the original test suites, fixtures and
support modules move with them. `Onchain.Application` is onchain's application
callback; existing `:cartouche` configuration keys and supervisor names remain
compatible. Mix warns that the `:cartouche` application is absent when loading
that config; the keys are still read. The pre-0.16 `.etf` oracle fixtures keep
their recorded `ABI.*`/`Cartouche.*` atoms; `Onchain.Test.LegacyModuleNames`
translates them on replay.

Full QA runs `mix onchain.coverage`: the former ABI modules (`Onchain.ABI*`) retain 95%,
the former cartouche modules (listed by new name in the task) retain 85%, the
signer modules retain a separate 95% floor, and the rest of Onchain retains 70%.
`.doctor-hieroglyph.exs` and `.doctor-cartouche.exs` select the same former
sources by their new paths.
`Onchain.Contract.IConsole` and its coverage exclusion are gone; `Onchain.Contract.Sleuth` is a thin `use` of `Onchain.Contract.Generator`.
The original strict Doctor policies are retained in `.doctor-hieroglyph.exs`
and `.doctor-cartouche.exs`. The ABI manifest check remains in full QA.

Reach includes all hand-written `lib`, `dev`, `sol/src`, and `test/support` sources.
The old generated Erlang parser under `src` was removed by the alloy migration. The merged 109-file scope reproduces cartouche's `--dead-code` timeout:
`Task.Supervised.stream(30000)` exits from `Reach.CLI.Pipe.safely/1` under reach
2.8.4 after Architecture Policy reports OK. Full QA therefore runs
`reach.check --arch --smells`, just as cartouche did. Re-test dead-code after a
reach upgrade. No hand-written source scope was narrowed.

Default tests combine the former exclusions: integration, differential,
debug_namespace and dev_node. Cartouche's test config supplies its offline
RPC stubs and default test signer. Live tests require the original credentials
and node capabilities described by their test support modules.

ABI verification notes live in `docs/abi-verification-ledger.md`; Cartouche's
ledger is `docs/verification-ledger.md`. Original licenses and package history
are preserved in `docs/hieroglyph/` and `docs/cartouche/`.


## Core ABI native build and release verification

`Onchain.ABI.Native` is the generic Rustler boundary in `native/onchain_abi`. It accepts
operations, type strings or compiled schema resources, and BEAM values. Its one
recursive converter handles values without JSON serialization. `Onchain.ABI.TypeEncoder`
and `Onchain.ABI.TypeDecoder` remain compatibility facades with no handwritten value
codec. `Onchain.ABI.Validation` normalizes the historically ignored tuple offsets before
alloy follows them and passes payloads through unchanged when their offsets
already name those tails. Zero-width aggregate shape and packed-array padding
need explicit compatibility adaptation around alloy. `Onchain.Filter` groups
logs by topic, calls `Onchain.ABI.Event.decode_events/3`, then restores the original log
order.

The boundary's rules are in `docs/specs/onchain-native.md` (repo root):

- NIF-1: panics are caught, and malformed input returns an error tuple.
- NIF-2: input limits on type strings, payloads, nodes and batch size.
- NIF-3: normal-scheduler vs dirty-CPU split.
- NIF-4: output parity with the pre-alloy oracle fixture.
- NIF-5: `strict: true` semantics.
- NIF-6: `fixed`/`ufixed` are rejected (exthereum/abi#54). Solidity cannot yet
  assign to or from fixed-point types, so a codec would support nothing usable
  (rationale from `docs/hieroglyph/README.md`).
- NIF-7: bounded, separate schema and signature caches. Inserts are serialized
  per cache (`:global.trans`), so concurrent misses cannot drop each other's
  entry; misses beyond the 1,024-entry cap compile without retention.

Payload preflight bounds alloy allocation before decoding, including
repeated/overlapping offsets. Compiled schema resources hold only immutable parsed
types and event topic0, with no VM environment or process-owned terms. The
facades keep their doctests.

`Onchain.Precompiled` and `scripts/build-precompiled.sh` live here;
`onchain_evm` consumes the module and delegates its build script here. The
distribution rules (DIST-1..8) are in `docs/specs/onchain-distribution.md`. In
short: this checkout source-builds core and needs Rust/Cargo (DIST-4), while
`ONCHAIN_PUBLISH=1` and Hex installs download verified artifacts and fail on a
bad checksum (DIST-2, DIST-3). `ONCHAIN_BUILD` / `ONCHAIN_EVM_BUILD` are scoped
per crate (DIST-7), and unsupported hosts are rejected (DIST-6).

Publish-time commands (run from this package; artifacts must be built from the
exact release revision):

```sh
# Requires Rust targets, Zig and cargo-zigbuild on the release builder only.
# Use an empty OUT_DIR; the script rejects stale artifact directories.
OUT_DIR="$PWD/artifacts/precompiled/release" scripts/build-precompiled.sh
# Produces aarch64/x86_64 Darwin, aarch64/x86_64 GNU/Linux, x86_64 musl.
# After the operator publishes the package-scoped GitHub release assets:
mix rustler_precompiled.download Onchain.ABI.Native --all --print
# Commit checksum-Elixir.Onchain.ABI.Native.exs, then verify packaging:
ONCHAIN_PUBLISH=1 mix deps.get
ONCHAIN_PUBLISH=1 mix hex.build | tee artifacts/hex-build.log
! grep -q 'excluded from the package' artifacts/hex-build.log
# Inspect metadata/files and ensure checksum-Elixir.Onchain.ABI.Native.exs is included.
# Restore the development lock after publish preparation.
git restore mix.lock
```

Verify a fresh consumer of the built tarball with Cargo absent from PATH and
all force-build environment variables unset. After `mix deps.get`, run
`mix compile` and `mix run -e 'IO.inspect(Onchain.ABI.encode("f(uint256)", [1]))'`.
Use an empty build directory; ensure `System.find_executable("cargo") == nil`.
An offline smoke check can seed `RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH` with the
locally built tarballs. That verifies checksum/loading/compilation but **does not
verify a GitHub release download**; repeat with an empty cache after asset upload.
Never publish onchain before its checksummed assets are downloadable. EVM's own
assets and version remain independent of the core package release.

Performance is reporting only. `bench/abi.exs` compares the production facades
with the preserved pre-migration codecs under `bench/legacy`; `bench/results.json`
and `bench/README.md` record ips, BEAM allocation and compilation/phase costs.
`bench/teardown_test.exs` is the shared consumer shutdown probe: run it together
with focused package tests and record the OS exit status after the VM halts.


Full QA (`mix ci`) also runs `cargo audit`, `cargo test` and
`cargo clippy --all-targets -- -D warnings` for `native/onchain_abi` through
the root's shared development helper. Production denies `unwrap_used`; tests
are exempt and `expect_used` is allowed. Missing Cargo/clippy skips visibly;
missing cargo-audit fails with `cargo install cargo-audit --locked`.
Vulnerabilities and offline advisory-fetch failures fail the gate;
unmaintained/yanked warnings pass. Any ignore must be a commented per-advisory
entry in the crate's `.cargo/audit.toml`. See root Gates for the shared policy.
The deep-input boundary test uses 1,000 tuple/array levels under 4,096 bytes:
the existing 64 nesting-marker limit rejects them before alloy allocation.
