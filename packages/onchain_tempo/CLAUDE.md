<!-- Selective-load (Opus 4.8): eager floor = critical-rules + harness-workflow (this repo is
     harness-driven — the OTP dispatch→review→land loop is the active workflow). onchain-workspace
     is the harness workspace add-on (monorepo layout + sibling/3 + dependency shape), eager
     family-wide. Everything else previously imported here (across-instances, worktree, task-prioritization/writing, rmap,
     workflow-philosophy, web-command, elixir-setup, ex-unit-json, dialyzer-json, code-style,
     development-commands/philosophy, agent-economy) is skill-on-demand via the elixir / task-driver
     / dev-lifecycle plugins. The Linear-as-queue + Codex/Cursor delegation flow (delegation +
     onchain-workspace) is retired — harness replaced it. Re-add an @-import per-surface only if
     Opus visibly degrades on it. See ~/.claude/setup-guide.md § "Skills vs Includes". -->
@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md
@~/.claude/includes/onchain-workspace.md
@~/.claude/includes/node-portability.md

# OnchainTempo

Tempo blockchain primitives for Elixir. Extracted from MPP (Machine Payments Protocol) to provide standalone 0x76 transaction handling, TIP-20 encoding, RPC, and event parsing.

See the root `CLAUDE.md` for the family layout, the sibling/3 mechanism, and
the shared gate adjudications (reach #36, cowlib/gun, sobelow). This file
carries only what's specific to this package.

## Toolchain & check commands

Canonical gate: **`mix ci`** (= `mix precommit.full`), same shape as every
other package (root `CLAUDE.md` § Gates). Coverage floor here is **90%**
(`test.json --cover --cover-threshold 90 --exclude integration`, run under
`MIX_ENV=test` since `preferred_envs` in `def cli` is ignored inside alias
steps). `mix precommit` is the fast local loop.

- `.reach.exs` carries no `smells.ignore` entries — this package's smell pass
  is clean without any workaround.
- `deps.audit.gated` runs against `.mix_audit_ignore` (symlinked from the
  root file — see root `CLAUDE.md` § Adjudicated findings).

## Commands

```bash
mix test.json --quiet              # Unit tests (AI-friendly JSON)
mix test.json --quiet --failed     # Re-run failures
mix test.json --quiet --include integration  # + integration tests
mix dialyzer.json --quiet          # Type checking
mix credo --strict --format json   # Static analysis
mix sobelow                        # Security scanner
mix doctor                         # Docs/specs coverage
mix format                         # Auto-format (Styler)
```

## Architecture

This is a **library** (not a Phoenix app). It provides Tempo-specific blockchain primitives that any Elixir project can use.

### Module Map

```
OnchainTempo                       — Root module, Discoverable entry point
Onchain.Tempo.TIP20                — TIP-20 selectors, calldata encoders, DEX address
Onchain.Tempo.Transaction          — 0x76 struct, deserialize, payment matching, fee payer co-signing
Onchain.Tempo.Transaction.Builder  — Build + sign 0x76 transactions from scratch
Onchain.Tempo.RPC                  — broadcast_async/sync, fetch_receipt, parse_receipt, simulate (pre-broadcast eth_simulateV1)
Onchain.Tempo.Transfer             — TransferWithMemo event log parsing
Onchain.Tempo.Faucet               — Moderato testnet faucet (tempo_fundAddress) wrapper
```

### Node Portability (constrained, not portable)

The family-wide law is `node-portability.md` (`@`-imported above): our own node is a
privileged environment and consumers run something else. **This repo is the deliberate
exception to its rule 2** — and the exception has to be stated, not assumed:

- **Tempo-specific methods are the product here, not a portability bug.**
  `eth_sendRawTransactionSync` (`lib/onchain/tempo/rpc.ex`) and `tempo_fundAddress`
  (`lib/onchain/tempo/faucet.ex`) are Tempo protocol extensions; a generic Ethereum
  endpoint answers `-32601`. Wrapping them is correct. What rule 2 still demands is that
  you don't reach for an extension where a standard method would do — check first.
- **What varies for the consumer is *which Tempo endpoint*, not which chain.** Mainnet
  (4217, `https://rpc.tempo.xyz`) and Moderato (42431,
  `https://rpc.moderato.tempo.xyz`) do not serve the same surface: **the faucet is
  Moderato-only**. A new function must say which networks serve it, in its `@doc`.
- **`TEMPO_RPC_URL` is a real, consumer-visible override** read by
  `Onchain.Tempo.Faucet.rpc_url/0`. It was undocumented outside the source until
  2026-08-25; keep it in `README.md` § "Tempo Networks" if its behaviour changes.
- **The offline surface is the majority of the package** — `Transaction`, `Builder`,
  `TIP20`, `Transfer` need no node at all. Prefer growing that side; a new function that
  needs a live endpoint should justify why the work can't be done offline.

### Key Design Decisions

- **Signing uses Curvy directly** — Tempo 0x76 is non-standard; `Onchain.Signer` handles EIP-1559 only. Direct `Cartouche.Signer.Curvy` + `Cartouche.Recover.find_recid/3` is correct.
- **TIP20 owns all selectors** — Single source of truth, eliminates duplication.
- **RPC uses plain errors** — `{:error, "message"}` not wrapped error structs.
- **ExRLP is transitive** — Available via onchain → cartouche. `@dialyzer` suppressions needed.

### Dependencies

- `onchain` — Core Ethereum utilities (RPC, ABI, signing, logs), via `sibling(:onchain, ...)`
- `req` — HTTP client for RPC calls
- `jason` — JSON encoding for RPC payloads
- `descripex` — Self-describing APIs
- `plug` — Required for Req.Test stubs (dev/test only)

### Tempo Network Chain IDs

| Network | Chain ID | RPC URL |
|---------|----------|---------|
| Mainnet | `4217` | `https://rpc.tempo.xyz` |
| Moderato (testnet) | `42431` | `https://rpc.moderato.tempo.xyz` |

### Dialyzer Notes

`.dialyzer_ignore.exs` carries exactly one entry: `~r/Function ExRLP\./`. ExRLP is transitive (onchain → cartouche → ex_rlp), used only from `test/support`, and transitive deps are not in the `:apps_direct` PLT — a false positive. Everything else (Jason/Req/Cartouche/Onchain/Descripex) resolves via the sibling/3 path branch since the monorepo; the standalone-era suppressions for those were pruned 2026-08-27. If a new unknown-function warning appears, regenerate the file wholesale rather than appending.

### Conventions

- Styler is the formatter plugin (runs automatically via `mix format`)
- `test/support/` is compiled in test env
- Integration tests live under `test/onchain/tempo/integration/`, tagged `:integration`, excluded by default. They self-fund fresh wallets via the Moderato `tempo_fundAddress` faucet RPC — no env var required. Override the endpoint with `TEMPO_RPC_URL`.
- All calldata functions accept raw binaries (20-byte addresses, 32-byte memos), not hex strings
- Error format: `{:ok, result} | {:error, String.t()}`
