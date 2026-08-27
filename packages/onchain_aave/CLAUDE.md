# Onchain Aave

Aave V3 and V4 protocol wrappers for Elixir. Depends on `onchain` core for RPC, ABI, signing, and address utilities.

<!-- Selective-load (Opus 4.8): eager floor = critical-rules + harness-workflow (this repo is
     harness-driven — the OTP dispatch→review→land loop is the active workflow). onchain-workspace
     is the harness workspace add-on (monorepo layout + sibling/3 + dependency shape), eager
     family-wide. ethereum-rpc stays eager (host-specific node access, no skill mirror). Everything
     else previously imported here (across-instances, worktree, task-prioritization/writing,
     workflow-philosophy, web-command, elixir-setup, ex-unit-json, dialyzer-json, code-style,
     development-commands/philosophy, agent-economy) is skill-on-demand via the elixir / task-driver
     / dev-lifecycle plugins. Re-add an @-import per-surface only if Opus visibly degrades on it.
     See ~/.claude/setup-guide.md. -->
@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md
@~/.claude/includes/onchain-workspace.md
@~/.claude/includes/ethereum-rpc.md
@~/.claude/includes/node-portability.md

See the root `CLAUDE.md` for the family layout, the sibling/3 mechanism, and
the shared gate adjudications (reach #36, cowlib/gun, sobelow). This file
carries only what's specific to this package.

## Toolchain & check commands (read before judging a build)

Canonical gate: **`mix ci`** (= `mix precommit.full`), same shape as every
other package (root `CLAUDE.md` § Gates). Coverage floor here is **65%**
against a 68.44% measured baseline (2026-08-01) — **critical modules
(`Aave.Math` and any signing/money path) target 95%; standard logic 80%** per
`critical-rules.md` § coverage tiers, the repo-wide alias floor is a
conservative measured baseline, not a per-module target. `mix precommit` is
the fast local loop (no dialyzer, no coverage).

- `deps.audit.gated` runs against `.mix_audit_ignore` (symlinked from the
  root file — see root `CLAUDE.md` § Adjudicated findings).

## Architecture

- All modules use `Onchain.*` namespace (e.g., `Onchain.Aave.Pool`) — same as when they lived in the monolith
- Pure Elixir, no native deps
- All dependencies resolve from hex.pm — no path or git deps outside the
  monorepo's own sibling/3 mechanism, so the package is publishable as-is:
  `sibling(:onchain, "~> 0.12")`

## Node Portability

The family-wide law is `node-portability.md` (`@`-imported above). This package is the
easy case and should stay that way:

- **Everything here is `eth_call` against a deployed contract**, routed through
  `Onchain.RPC` / `Onchain.Contract`. No `debug_*`/`trace_*`, no client extensions, no
  WebSocket. A new module that needs any of those is a design smell — check whether the
  value is reachable from a standard call first.
- **Historical reserve state is the one archive dependency.** Reading rates, reserve data,
  or user positions at a past block requires an archive node; a pruned or plan-limited
  endpoint answers `-32001`. Say so in the `@doc` of any function that takes a block
  parameter, and don't let an integration test that only ever runs against our archive
  node stand as evidence the function is portable.
- **Contract addresses are chain-specific.** Portability here also means "does this chain
  have Aave V3 at this address" — see `Onchain.Aave.Types` and the address-verification
  section below.

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
  v4/oracle.ex                # V4 Spoke-scoped IAaveOracle + Chainlink reads
  v4/position_manager.ex      # V4 Giver/Taker writes + Taker allowances
  v4/spoke.ex                 # V4 Spoke reads (reserve/user data)
  v4/tokenization_spoke.ex    # V4 ERC-4626 Tokenization Spoke reads (lookup, share accounting)
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

- **onchain** — Core Ethereum primitives: `sibling(:onchain, "~> 0.12")`
- **onchain_evm** — Rust NIFs + codegen: `sibling(:onchain_evm, "~> 0.6", only: [:dev, :test])` — dev/test-only, used by the revm math cross-validation suites and V4 fork-write evidence
