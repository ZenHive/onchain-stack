# CLAUDE.md

@~/.claude/includes/verification-policy.md

@~/.claude/includes/critical-rules.md
@~/.claude/includes/elixir-security-adjudications.md

<!--
  Selective-load: the eager floor is `critical-rules` (ambient guardrails) +
  the verification policy + the security adjudications this repo's
  `deps.audit.gated` and Sobelow steps need. Everything else is
  skill-on-demand: `elixir:ex-unit-json`, `elixir:dialyzer-json`,
  `elixir:agent-economy` (Descripex `api()`), `elixir:code-style`,
  `workflow:rmap`, `workflow:git-worktrees`.
-->

---

## Project overview

**faucet_ex** — programmatic testnet funding for integration tests. One
top-up loop (`Faucet.TopUp`: read → request → wait → verify, request budget,
per-address `:global.trans/2` lock) over pluggable `Faucet.Source` adapters.
Consumed `only: :test` by onchain-stack packages, mpp and aave_sim; it
replaced four independent faucet helpers (see CHANGELOG 0.1.0).

Remote: `git@github.com:ZenHive/faucet_ex.git`, default branch `main`.
Standalone on purpose, like descripex and zen_websocket: it is consumed beyond
the onchain family, so it does not live in the onchain-stack monorepo.

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

Self-contained so it survives into `AGENTS.md` on regen.

- Pin: `.tool-versions` (erlang 29.1, elixir 1.20.4-otp-29).
- **Dispatch check:** `mix check.dispatch` — format and compile only. Add
  focused tests for the changed behavior (`mix test.json test/path_test.exs`).
- **Full post-merge QA:** `mix ci` (= `precommit.full`): format check, compile
  `--warnings-as-errors`, `credo --strict`, `doctor --raise`,
  `ex_dna --max-clones 0`, `reach.check --dead-code --arch --smells`,
  `sobelow --skip --exit low`, `deps.audit.gated`, `test.json --cover
  --cover-threshold <floor>` (MIX_ENV=test), `dialyzer` (MIX_ENV=dev),
  `agents.check`. Check scheduling follows the imported verification policy.
- `mix precommit` is the fast local subset (no clones, reach, audit, dialyzer).
- **Coverage floor** lives in `@cover_threshold` in `mix.exs` and is a
  measured ratchet — raise it with real coverage, never pad it.
- **`deps.audit.gated`** runs `bin/advisory-freshness.sh` first (vendored from
  zen_websocket): `mix_audit` discards its own sync exit status, so a frozen
  mirror would otherwise read as clean. Never run `mix ci` concurrently with
  another repo's gate — they share the advisory clone.
  `.mix_audit_ignore` carries exactly one entry, the adjudicated gun/cowboy
  mirror-grouping false positive (`GHSA-w4f7-4cxr-rv3c`, see the imported
  security adjudications); never add another id to it.
- **`agents.check`** runs `bin/sync-agents-md.sh --check`; regenerate with
  `bin/sync-agents-md.sh` after editing this file.
- **Integration tests** are tagged `:integration` and excluded by default.
  They hit live providers and need credentials / funded keys; run them on
  purpose: `mix test --include integration`.
- Tidewave MCP: `iex -S mix tidewave` on port **4038** (`.mcp.json`, registry
  `~/.claude/tidewave-ports.md`).

## After every task

- `CHANGELOG.md` under `[Unreleased]`.
- `README.md` when a source or public function is added.
- This file's module layout when files are added, removed or renamed.
- `bin/sync-agents-md.sh` to regenerate `AGENTS.md`.
- `roadmap/tasks.toml` via the `workflow:rmap` skill.

## Publish

Human-gated (Hex 2FA). Terminal state for an agent is publish-ready: green
`mix ci`, bumped `@version`, CHANGELOG section dated, committed and pushed.
State the exact `mix hex.publish` command and stop. Tag `v<ver>` after the
publish, by hand.
