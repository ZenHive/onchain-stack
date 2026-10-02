@~/.claude/includes/verification-policy.md

@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-guardrails.md
@~/.claude/includes/onchain-workspace.md

# FaucetEx

## Project overview

**faucet_ex** — programmatic testnet funding for integration tests. One
top-up loop (`Faucet.TopUp`: read → request → wait → verify, request budget,
per-address `:global.trans/2` lock) over pluggable `Faucet.Source` adapters.
Consumed `only: :test` by onchain-stack packages, mpp and aave_sim; it
replaced four independent faucet helpers (see CHANGELOG 0.1.0).

Lives in the onchain-stack monorepo since 0.2.0 (absorbed with history; the
standalone `ZenHive/faucet_ex` repo is archived). See the root `CLAUDE.md`
for the family layout, the sibling/3 mechanism, the shared gates and the
publish workflow; this file carries only what is specific to this package.

## Module layout

| Module | Role |
|---|---|
| `Faucet` | Public entry: `ensure_min_balance/4`, `!/4`, `fund/3`, `balance/3`; `Descripex.Discoverable` root |
| `Faucet.Source` | Behaviour: `balance/2`, `fund/2`, `unit/0`, optional `wait_confirmed/3`; the loop passes `:deficit` to `fund/2` |
| `Faucet.TopUp` | The loop. Private to the library (`@doc false`) |
| `Faucet.Wait` | Deadline-bounded polling (`until/2`, `validate/1`) |
| `Faucet.JSONRPC` | One-shot JSON-RPC 2.0 over Req; `:req_options` is the `Req.Test` injection point |
| `Faucet.EVM` | eth_getBalance, ERC-20 `balanceOf`, receipt polling, fresh keypairs (needs `onchain`) |
| `Faucet.ForkOverride` | `state_overrides` builder for `Onchain.EVM` (mapping-slot keccak needs `onchain`) |
| `Faucet.Error` | Exception raised by the bang variant, formats provider reasons |
| `Faucet.Source.CDP` | Coinbase Developer Platform faucet, EdDSA JWT auth (`CDP_API_KEY_ID` / `CDP_API_KEY_SECRET`) |
| `Faucet.Source.Tempo` | Moderato `tempo_fundAddress`; polls the fee token (pathUSD) by default |
| `Faucet.Source.Solana` | `requestAirdrop` / `getBalance` |
| `Faucet.Source.XRPL` | altnet faucet HTTP API + `account_info` |
| `Faucet.Source.ERC20Mint` | Aave-style `mint(token,to,amount)` faucet contract; signs via `Onchain.Signer` (injectable `:send_transaction`) |

## Design rules

- **The loop knows only the behaviour.** `.reach.exs` forbids `core → sources`.
  New providers are new `Faucet.Source.*` modules, never branches in `TopUp`.
- **`onchain` is optional.** Anything that signs, ABI-encodes or hashes lives
  behind `Code.ensure_loaded?/1` and returns `{:error, :onchain_not_available}`
  (or raises `ArgumentError` for `ForkOverride`). Everything else is plain
  Req + Jason so Solana / XRPL / gas-only consumers never pull the EVM stack.
- **Verify on the node, never trust the provider.** Balances and receipts are
  read from `:rpc_url`; a provider's own success response is only a reference.
- **Fail loudly, never skip.** Missing credentials return
  `{:missing_credential, name, hint}` before any request; the bang variant
  raises `Faucet.Error` with the provider's reason. No `ExUnit` skip paths.
- **Never log or inspect key material.** Signer errors may contain the key;
  tests inject `:send_transaction` rather than exercising a real signer.
- **Every public function carries a Descripex `api()` hint**; the test in
  `test/faucet_test.exs` ("discoverability") fails when one is missing.

## Toolchain & check commands

- Toolchain pin and gate helpers come from the monorepo root
  (`.tool-versions`, `shared/mix_helpers.exs`, root `.credo.exs` and
  `.mix_audit_ignore` via symlinks).
- **Dispatch check:** `mix check.dispatch` — format and compile only. Add
  focused tests for the changed behavior (`mix test.json test/path_test.exs`).
- **Full post-merge QA:** `mix ci` (= `precommit.full`). Same shape as the
  other packages; coverage floor is `@cover_threshold` in `mix.exs`, a
  measured ratchet — raise it with real coverage, never pad it.
- **Integration tests** are tagged `:integration` and excluded by default.
  They hit live providers and need credentials / funded keys; run them on
  purpose: `mix test --include integration`.
- Tidewave MCP: `iex -S mix tidewave` on port **4038**.

## After every task

Follow the root `CLAUDE.md` § "After every task"; update this file's module
layout when files are added, removed or renamed.
