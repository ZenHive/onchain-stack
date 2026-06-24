# Onchain EVM

EVM simulation, Solidity parsing, debug/trace APIs, and contract codegen for Elixir via Rust NIFs. Depends on `onchain` core for RPC, ABI, signing, and address utilities.

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

## Architecture

- All modules use `Onchain.*` namespace (e.g., `Onchain.EVM`) — same as when they lived in the monolith
- Rust NIFs via Rustler: `otp_app: :onchain_evm` (not `:onchain`)
- Two native crates: `native/onchain_evm/` (revm) and `native/onchain_solidity/` (Alloy + solang-parser)
- Hex dependency: `{:onchain, "~> 0.5"}`
- Standard error tuples: `{:ok, result} | {:error, {:tag, reason}}`

## Module Layout

```
lib/onchain/
  bang_helper.ex              # defbang macro: generates bang (!) wrappers for ok/error functions
  evm.ex                      # Rustler NIF: revm local EVM execution
  solidity.ex                 # Rustler NIF: Alloy-powered Solidity ABI parser
  trace.ex                    # debug/trace APIs (trace_transaction, trace_call, storage_at)
  contract/
    generator.ex              # macro: .sol → typed Elixir module at compile time
native/
  onchain_evm/                # Rust crate (revm, alloy)
  onchain_solidity/           # Rust crate (alloy-json-abi, solang-parser)
priv/
  abis/
    chainlink_aggregator.json
    aave_pool.json            # test fixture for parser tests
  contracts/
    test_interface.sol        # test fixture
    real/                     # vendored upstream Solidity for import resolution tests
```

## Dependencies from onchain core

| Module | Used for |
|--------|----------|
| `Onchain.Address` | Validation |
| `Onchain.Hex` | Hex encoding/decoding |
| `Onchain.RPC.Helpers` | Shared RPC helpers (Trace + EVM: `ensure_hex_address`, `ensure_hex_data`, `normalize_block`) |
| `Onchain.Contract` | Generic contract call (Generator runtime) |
| `Onchain.ABI` | ABI encoding (Generator runtime) |
| `Onchain.Signer` | Transaction signing (Generator runtime) |

## Testing

```bash
mix test.json --quiet                          # Unit tests only
mix test.json --quiet --include integration    # Unit + integration (requires RPC)
```

Integration tests require `ETHEREUM_API_URL` or `ETH_RPC_URL` env var.

**Note:** `priv_dir` references in tests use `:onchain_evm` (not `:onchain`).

## Related Packages

- **onchain** — Core Ethereum primitives: `{:onchain, "~> 0.5"}`
- **onchain_aave** — Aave V3 wrappers: `{:onchain_aave, "~> 0.1"}`
