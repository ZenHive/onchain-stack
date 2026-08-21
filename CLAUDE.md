# Onchain Aave

Aave V3 protocol wrappers for Elixir. Depends on `onchain` core for RPC, ABI, signing, and address utilities.

<!-- Selective-load (Opus 4.8): eager floor = critical-rules + harness-workflow (this repo is
     harness-driven — the OTP dispatch→review→land loop is the active workflow). onchain-workspace
     is the harness workspace add-on (7-repo roster + dependency shape), eager family-wide.
     ethereum-rpc stays eager (host-specific node access, no skill mirror). Everything else previously imported
     here (across-instances, worktree, task-prioritization/writing, workflow-philosophy, web-command,
     elixir-setup, ex-unit-json, dialyzer-json, code-style, development-commands/philosophy,
     agent-economy) is skill-on-demand via the elixir / task-driver / dev-lifecycle plugins.
     Re-add an @-import per-surface only if Opus visibly degrades on it. See ~/.claude/setup-guide.md. -->
@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md
@~/.claude/includes/onchain-workspace.md
@~/.claude/includes/ethereum-rpc.md

## Toolchain & check commands (read before judging a build)

Cross-family harness reviewers read **AGENTS.md** (auto-generated from this file), not the user's Claude skills. **`mix ci`** (= `mix precommit.full`) is the canonical gate — run it before judging a build green or red. It chains: `compile --warnings-as-errors`, `format --check-formatted`, `credo --strict`, `doctor --raise`, `ex_dna --max-clones 0`, `reach.check --arch --smells`, `sobelow --skip`, `deps.audit.gated`, `test.json --cover --cover-threshold 65 --exclude integration`, `dialyzer`, `agents.check`. `mix precommit` is the fast local loop (no dialyzer, no coverage).

- `mix reach.check --arch --smells` gates from `.reach.exs` (`smells: [strict: true]`). Smell findings must be **fixed, never added to an ignore list**.
- `deps.audit.gated` proves the local advisory mirror is fresh (`bin/advisory-freshness.sh` in the onchain-stack coordination home) before running `deps.audit --ignore-file .mix_audit_ignore` — `mix_audit` silently discards its own sync failure, so a stale mirror would otherwise report false-green.
- `agents.check` fails when `AGENTS.md` has drifted from this file (`sync-agents-md.sh --check`).
- `mix test.json --cover --cover-threshold 65 --exclude integration` — coverage gate (65% floor against a 68.44% measured baseline, 2026-08-01). **Critical modules (`Aave.Math` and any signing/money path) target 95%; standard logic 80%** (per `critical-rules.md` § coverage tiers) — the repo-wide alias floor is a conservative measured baseline, not a per-module target.
- `mix dialyzer` in the alias; `mix dialyzer.json --quiet` for AI-friendly output during dev — zero real warnings = pass.

**The `.json` mix tasks emit JSON BY DESIGN — that is expected output, never an error or a broken setup:**

- **`mix test.json`** (`ex_unit_json` dep) — ExUnit results as JSON; identical run to `mix test`. Parse it for failures; the JSON envelope itself is never a failure signal. `--cover` can emit a large per-module blob — pipe to a file (`--output /tmp/cov.json`) and `jq` the summary, don't dump it to the transcript.
- **`mix dialyzer.json`** (`dialyzer_json` dep) — dialyzer warnings as JSON. Read the array for *real* warnings; do NOT flag the JSON output as a problem. If the encoder cannot serialize a warning shape, plain `mix dialyzer` is the authoritative check.

(Claude-family agents with the user's global skills can invoke `elixir:ex-unit-json` / `elixir:dialyzer-json` for the full flag/jq reference. For cross-family harness reviewers, the notes above are self-contained.)

## Architecture

- All modules use `Onchain.*` namespace (e.g., `Onchain.Aave.Pool`) — same as when they lived in the monolith
- Pure Elixir, no native deps
- All dependencies resolve from hex.pm — no path or git deps, so the package is publishable as-is: `{:onchain, "~> 0.12"}`
- Standard error tuples: `{:ok, result} | {:error, {:tag, reason}}`

## Module Layout

```
lib/onchain/aave/
  contracts.ex                # address registry (mainnet + multi-chain)
  math.ex                     # to_usd, to_ltv, to_health_factor, to_ray
  pool.ex                     # read + write calls (getUserAccountData, supply, borrow, repay)
  oracle.ex                   # getAssetPrice + Chainlink
  ui_pool_data_provider.ex    # bulk reserve/user data
  faucet.ex                   # testnet faucet interactions
  v4/hub.ex                   # V4 Hub reads (member Spokes, credit lines, rate environment)
  types/
    user_account_data.ex
    aggregated_reserve_data.ex
    base_currency_info.ex
    user_reserve_data.ex
```

## Dependencies from onchain core

| Module | Used for |
|--------|----------|
| `Onchain.ABI` | ABI encoding/decoding |
| `Onchain.RPC` | eth_call |
| `Onchain.Signer` | Transaction signing (pool writes, faucet) |
| `Onchain.Address` | Validation, checksumming |
| `Onchain.Hex` | Hex encoding/decoding |
| `Onchain.Contract` | Generic contract call (oracle) |
| `Onchain.Decimal` | Decimal math (types) |

## Testing

```bash
mix test.json --quiet                          # Unit tests only
mix test.json --quiet --include integration    # Unit + integration (requires RPC)
mix test.json --quiet --only sepolia_send      # Sepolia write tests
```

Integration tests require `ETHEREUM_API_URL` or `ETH_RPC_URL` env var.
Sepolia write tests additionally require `ETH_SEPOLIA_PRIVATE_KEY` and `ETH_SEPOLIA_RPC_URL`.

## Contract Address Verification

When adding or updating addresses in `lib/onchain/aave/contracts.ex`, verify against the **Aave Address Book CSV**:

```bash
curl -s "https://raw.githubusercontent.com/bgd-labs/aave-address-book/main/safe.csv" | grep -i "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"
```

## Related Packages

- **onchain** — Core Ethereum primitives: `{:onchain, "~> 0.12"}`
- **onchain_evm** — Rust NIFs + codegen: `{:onchain_evm, "~> 0.5", only: [:dev, :test]}` (hex.pm; dev/test-only, used by the revm math cross-validation suites)
