<!-- Selective-load (Opus 4.8): eager floor = critical-rules + harness-workflow (this repo is
     harness-driven — the OTP dispatch→review→land loop is the active workflow). onchain-workspace
     is the harness workspace add-on (7-repo roster + dependency shape), eager family-wide.
     Everything else previously imported here (across-instances, worktree, task-prioritization/writing, rmap,
     workflow-philosophy, web-command, elixir-setup, ex-unit-json, dialyzer-json, code-style,
     development-commands/philosophy, agent-economy) is skill-on-demand via the elixir / task-driver
     / dev-lifecycle plugins. The Linear-as-queue + Codex/Cursor delegation flow (delegation +
     onchain-workspace) is retired — harness replaced it. Re-add an @-import per-surface only if
     Opus visibly degrades on it. See ~/.claude/setup-guide.md § "Skills vs Includes". -->
@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md
@~/.claude/includes/onchain-workspace.md

# OnchainTempo

Tempo blockchain primitives for Elixir. Extracted from MPP (Machine Payments Protocol) to provide standalone 0x76 transaction handling, TIP-20 encoding, RPC, and event parsing.

**Repo:** [ZenHive/onchain_tempo](https://github.com/ZenHive/onchain_tempo) | **Org:** ZenHive

## Toolchain & check commands

Self-contained so it survives into `AGENTS.md` on regen — cross-family reviewers (codex / cursor / grok) read `AGENTS.md`, not the Claude skill set.

- **Canonical gate:** `mix precommit.full` (alias `mix ci`) — the comprehensive pass the harness reviewer's `check_command` runs, and the *only* thing that grades this repo: the GitHub Actions workflows were removed family-wide on 2026-08-22, so nothing runs on push. Run it before pushing. Fast local loop: `mix precommit` (skips the cold-PLT dialyzer + full coverage). Both are defined in `mix.exs` aliases.
- `mix precommit.full` runs, in order: `compile --warnings-as-errors`, `format --check-formatted`, `credo --strict` (ignoring TODO/FIXME tags), `doctor --raise`, `ex_dna --max-clones 0` (zero-clone budget), `reach.check --arch --smells` (policy in `.reach.exs`), `sobelow --skip`, `deps.audit.gated`, `test.json --cover --cover-threshold 90 --exclude integration` (under `MIX_ENV=test`, since `preferred_envs` in `def cli` is ignored inside alias steps), `dialyzer`, `agents.check`.
- **`mix test.json` (`ex_unit_json`) and `mix dialyzer.json` (`dialyzer_json`) emit JSON by design — this is NOT a build failure.** Parse the JSON for real failures; never flag the envelope itself. Plain `mix dialyzer` is the authoritative dialyzer check when the JSON encoder can't serialize a warning shape.
- **`reach.check --arch --smells` gates from `.reach.exs`** (`smells: [strict: true]`). Smell findings must be fixed for real, never added to an ignore list — onchain_tempo's `.reach.exs` carries no `smells.ignore` entries.
- **`deps.audit.gated` proves the local mix_audit advisory mirror is fresh (`bin/advisory-freshness.sh` in `onchain-stack`) before running `mix deps.audit --ignore-file .mix_audit_ignore`** — `mix_audit` discards its own sync exit status (`mirego/mix_audit#61`), so a frozen mirror would otherwise report a false "No vulnerabilities found." `.mix_audit_ignore` carries exactly one verified false positive (GHSA-w4f7-4cxr-rv3c on `gun`); do not add other advisory ids there — a real finding gets reported, never suppressed.

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

### Key Design Decisions

- **Signing uses Curvy directly** — Tempo 0x76 is non-standard; `Onchain.Signer` handles EIP-1559 only. Direct `Cartouche.Signer.Curvy` + `Cartouche.Recover.find_recid/3` is correct.
- **TIP20 owns all selectors** — Single source of truth, eliminates duplication.
- **RPC uses plain errors** — `{:error, "message"}` not wrapped error structs.
- **ExRLP is transitive** — Available via onchain → cartouche. `@dialyzer` suppressions needed.

### Dependencies

- `onchain` — Core Ethereum utilities (RPC, ABI, signing, logs)
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

Dialyzer shows `unknown_function` warnings for transitive deps when using onchain as a path dep. This is a known issue shared with onchain_aave — the path dep's transitive deps aren't fully resolved in the PLT. These are false positives.

### Conventions

- Styler is the formatter plugin (runs automatically via `mix format`)
- `test/support/` is compiled in test env
- Integration tests live under `test/onchain/tempo/integration/`, tagged `:integration`, excluded by default. They self-fund fresh wallets via the Moderato `tempo_fundAddress` faucet RPC — no env var required. Override the endpoint with `TEMPO_RPC_URL`.
- All calldata functions accept raw binaries (20-byte addresses, 32-byte memos), not hex strings
- Error format: `{:ok, result} | {:error, String.t()}`

## Git Commit Configuration

**Configured**: 2026-03-28

### Commit Message Format

**Format**: imperative-mood

#### Imperative Mood Template
```
<description>
```
Start with imperative verb: Add, Update, Fix, Remove, etc.
