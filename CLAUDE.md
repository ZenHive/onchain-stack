# Onchain EVM

EVM simulation, Solidity parsing, debug/trace APIs, and contract codegen for Elixir via Rust NIFs. Depends on `onchain` core for RPC, ABI, signing, and address utilities.

@~/.claude/includes/across-instances.md
@~/.claude/includes/critical-rules.md
@~/.claude/includes/skills-awareness.md
@~/.claude/includes/task-prioritization.md
@~/.claude/includes/task-writing.md
@~/.claude/includes/web-command.md
@~/.claude/includes/code-style.md
@~/.claude/includes/development-philosophy.md
@~/.claude/includes/documentation-guidelines.md
@~/.claude/includes/ai-coder-docs.md
@~/.claude/includes/workflow-philosophy.md
@~/.claude/includes/agent-economy.md
@~/.claude/includes/elixir-patterns.md
@~/.claude/includes/elixir-setup.md
@~/.claude/includes/development-commands.md
@~/.claude/includes/ex-unit-json.md
@~/.claude/includes/dialyzer-json.md
@~/.claude/includes/library-design.md

## Architecture

- All modules use `Onchain.*` namespace (e.g., `Onchain.EVM`) — same as when they lived in the monolith
- Rust NIFs via Rustler: `otp_app: :onchain_evm` (not `:onchain`)
- Two native crates: `native/onchain_evm/` (revm) and `native/onchain_solidity/` (Alloy + solang-parser)
- Path dependency: `{:onchain, path: "../onchain"}`
- Standard error tuples: `{:ok, result} | {:error, {:tag, reason}}`

## Module Layout

```
lib/onchain/
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

- **onchain** — Core Ethereum primitives: `{:onchain, path: "../onchain"}`
- **onchain_aave** — Aave V3 wrappers: `{:onchain_aave, path: "../onchain_aave"}`
