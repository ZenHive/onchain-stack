# Changelog

## v0.10.0 — node portability docs + descripex 1.0 floor + monorepo (2026-08-27)

### Documentation

- **`README.md` § "Which endpoint serves what"** — states that this package is
  Tempo-specific by design rather than portable to an arbitrary Ethereum provider,
  and tabulates which surfaces need no node at all, which work on any Tempo
  endpoint, which use the `eth_sendRawTransactionSync` Tempo extension, and which
  are Moderato-only (the faucet). Documents the previously source-only
  **`TEMPO_RPC_URL`** environment variable read by `Onchain.Tempo.Faucet.rpc_url/0`.

  Companion change outside the package: `CLAUDE.md` gains a **Node Portability**
  section (and imports the shared `node-portability.md` include), so the rule that
  our archive node is a privileged environment rather than the reference one is
  ambient for every agent working in this checkout, not folklore.

### Changed

- **`{:descripex, "~> 0.12"}` → `{:descripex, "~> 1.0"}`.** descripex 1.0.0 is
  the stable major line, behaviourally equal to 0.13.0 per its own CHANGELOG
  ("No behavioural change over 0.13.0"). A requirement narrowing, hence this
  minor.
- **Repo moved into the `onchain-stack` monorepo.** Source, issue tracker and
  release tags now live at `github.com/ZenHive/onchain-stack`, under
  `packages/onchain_tempo/`; the tag scheme is `onchain_tempo-v<version>` (was
  a bare `v<version>` in the standalone repo). The standalone
  `ZenHive/onchain_tempo` GitHub repo is archived. The Hex package name,
  module namespace and public API are unchanged.

## [0.9.2] - 2026-08-22

No public API or runtime behaviour changed.

### Changed

- Widened the `descripex` requirement from `~> 0.12.0` to `~> 0.12`. The
  three-segment cap turned every additive descripex minor into a forced
  nine-repo release cascade while protecting nothing in-family — `mix.lock` is
  committed, so a new descripex only ever lands through a deliberate
  `mix deps.update` behind `mix ci`.
- Resolved the refreshed family upstreams: onchain 0.13.0, cartouche 0.7.1,
  hieroglyph 1.6.2, zen_websocket 0.7.1 and descripex 0.13.0.
- Adopted `ex_ast` 0.13.1 via `override: true`, which reach 2.8.2 would
  otherwise cap at 0.12.10. Measured on onchain: `mix reach.check --dead-code
  --arch --smells` produces identical output under 0.12.10 and 0.13.1.

---

## [0.9.1] - 2026-08-18

No public API or runtime requirement changed.

### Changed

- Verified the library against the published family updates: onchain 0.12.1,
  cartouche 0.7.0, descripex 0.12.1, hieroglyph 1.6.1 and zen_websocket 0.6.1.
- Updated the development lock to Sobelow 0.15.0 and Tidewave 0.8.4. All
  installable dependencies are current; ex_ast remains on the 0.12.x line
  required by reach 2.8.2.
- Corrected the README installation example from the old `~> 0.7` line to
  `~> 0.9`.

---

## [0.9.0] - 2026-08-01

`lib/` is untouched: no module, function, arity or return shape changed. Most of
this entry is tooling, CI and agent config. `req` resolves to 0.7.2.

**It is still a minor, not a no-op release.** An earlier draft of this section
said "no version bump: no runtime dependency requirement moved" — that was true
when it was written and is no longer, because the `descripex` narrowing below
moves a requirement that ships in the published package.

### Changed — `{:onchain, "~> 0.11"}` → `{:onchain, "~> 0.12"}`

onchain 0.12.0 is the release that raises `zen_websocket` to `~> 0.6.0`, which
*requires* the gun version carrying the GHSA-w4f7-4cxr-rv3c fix rather than
merely permitting it. `~> 0.11` admits 0.12.0 but does not require it, so this
package's lock would have kept resolving onchain 0.11.0 → zen_websocket 0.4.2,
whose looser gun bound only happens to have landed on a fixed 2.5.0 — a lock
entry that still satisfies its bound is never re-resolved.

The lock now carries onchain 0.12.0 and zen_websocket 0.6.0. onchain 0.12.0 also
narrows `descripex` to `~> 0.12.0`, matching what this package now declares
directly (below). No code change was needed: onchain 0.12.0 makes no public API
change, and the suite is green against it.

### Changed — hieroglyph 1.6.0 in the lock, `elixir: "~> 1.17"` → `"~> 1.18"`

`mix.exs` gains no `hieroglyph` line — it arrives transitively through
onchain/cartouche, whose published bounds already admit it — but the lock now
carries 1.6.0, which restores `ABI.Event.decode_event/4`'s documented total
contract (unnamed event inputs no longer raise; an array length prefix that
cannot fit the remaining payload is rejected before the element list is
allocated) and makes `decode_structs: true` work on the event path.

The Elixir floor moves with it: hieroglyph 1.6.0's encode path uses
`Enum.sum_by/2` (1.18+), so declaring `~> 1.17` here would let this package
resolve on 1.17 and then fail compiling a dependency — the same class of loud
compatibility break as the `descripex` narrowing below.

### Changed — `{:descripex, "~> 0.11"}` → `{:descripex, "~> 0.12.0"}`

descripex 0.12.0 changed `short_name` in `describe/1` output from an atom to a
string — a consumer-visible contract change shipped at a *minor* bump, which the
old two-segment `~> 0.11` (`>= 0.11.0 and < 1.0.0`) would have absorbed on any
fresh resolution without a version bump here. The requirement is now
three-segment (`< 0.13.0`): a 0.x package that breaks on minor earns the tighter
form, and the cap gets raised deliberately after reading its release notes.
Narrowing a runtime bound can fail resolution for a consumer pinned to descripex
0.11.x — loud rather than silent, but still a compatibility break.

onchain_tempo does not read `short_name` — nothing in `lib/` or `test/`
references it, and the suite (142 tests) is green against descripex 0.12.0 with
no code change. The break is in the *bound*, not the behaviour.

### Changed — the gates now actually gate

- **`smells: [strict: true]` in `.reach.exs`.** The permissive `.reach.exs` the
  rollout below added was not yet a gate: `reach.check --smells` raises only when
  `opts[:strict] || config.smells.strict`, so it reported findings and exited 0.
- **`mix_audit` added and wired.** `deps.audit.gated` proves the advisory
  database is current *before* auditing — `mix_audit` discards its own sync exit
  status (mirego/mix_audit#61), so a database that can no longer sync still
  prints "No vulnerabilities found" and exits 0.
- **CI invokes `mix ci`** instead of a hand-maintained check list, so the alias
  and the workflow can no longer drift apart.
- **MCP config mirrored to all four agent families** (`.cursor/`, `.codex/`,
  `.grok/`) — a server declared only in `.mcp.json` is invisible to cross-family
  agents.

---

Analyzer-stack rollout. onchain_tempo was the only repo in the family declaring
neither `reach` nor `ex_dna`, so `mix reach.check` did not exist here and there
was no quality gate beyond the commit hook — `mix ci` was undefined.

### Added — the vibe_kit analyzer baseline

`ex_slop`, `ex_dna`, `ex_ast`, and `reach` as dev/test deps, plus `.credo.exs`
and a permissive `.reach.exs`. New aliases: `precommit` (fast loop),
`precommit.full`, and `ci`.

`Credo.Check.Readability.Specs` is scoped to `lib/onchain/` + `test/support/`
but, unlike onchain_evm, runs **without** `include_defp` — this codebase's
private helpers carry no specs, and requiring them would have meant 60+
signature additions unrelated to the rollout.

The **map** form `checks: %{enabled: [...]}` is authoritative for Credo and
silently discards a plugin's default checks, so ExSlop's are appended via
`ExSlop.recommended_checks()`. The **list** form `checks: [...]` behaves
differently — Credo merges it through the `extra` path, so plugin defaults
survive. Registering the plugin alone is only inert under the map form, and only
without the append.

(An earlier draft of this entry claimed onchain_evm was "running none of its
checks either". That is wrong: onchain_evm uses the same map form *and* the same
`++ ExSlop.recommended_checks()` append, so its ExSlop checks do run. zen_websocket
and mpp use the list form, where the question does not arise.)

### Added — `mix agents.check` in the CI gate

`AGENTS.md` is what the cross-family (codex/cursor/grok) reviewers read, and
nothing verified it still matched `CLAUDE.md`. The gate diffs rendered output
rather than mtimes, so drift inside a transitive `@`-import is caught too. It
found a stale `AGENTS.md` here on its first run.

### Fixed — narrowed two blanket rescues

`recover_sender/2` and `rlp_decode/1` each rescued every exception class, which
meant a bug in our own code was reported as a signature-recovery or
wire-corruption failure. Both are now narrowed to the classes malformed input
actually produces, verified by probing the libraries directly: `RuntimeError`
("Recovery ID not in range 0..3") and `FunctionClauseError` (r/s off the curve,
from `Curvy.Key.from_point/2`) for recovery; `ExRLP.DecodeError` and
`MatchError` (truncated multi-byte length prefix) for decoding. Anything outside
those sets now crashes instead of being relabelled.

### Changed — three smell fixes

`sender/1` split the field list with `List.last/1` plus
`Enum.take(fields, length(fields) - 1)`, traversing three times; it now uses a
single `Enum.split(fields, -1)`. `estimate_gas/3` built the `"0x" <> …` prefix
three times inside its reduce — extracted to a `hex/1` helper. Four test
assertions compared `length/1` against a literal where the following line
already destructured the list; folded into the pattern match.

## v0.8.0

Dependency-declaration release — no code changes. Two of these corrections are
required for downstream consumers to reach `req 0.7`; the rest bring stale
floors in line with what actually resolves.

### Added — `{:cartouche, "~> 0.6"}` declared directly

`lib/onchain/tempo/transaction.ex` and `lib/onchain/tempo/transaction/builder.ex`
call `Cartouche.Signer`, `Cartouche.Transaction`, and `Cartouche.RPC` directly,
but cartouche was never declared here — it resolved transitively through
`onchain`. That worked, and it kept working, which is exactly why it went
unnoticed: an undeclared direct dependency is invisible as long as some other
dependency happens to pull a compatible version. Declaring it makes the real
requirement explicit and pins the `~> 0.6` floor that lifts cartouche's
transitive `req < 0.7` cap.

### Changed — `{:onchain, "~> 0.10"}` → `{:onchain, "~> 0.11"}`

onchain 0.11.0 is the release that carries `cartouche ~> 0.6`. The old
two-segment `~> 0.10` bound (`>= 0.10.0 and < 1.0.0`) *permitted* 0.11.0 but did
not *require* it, so a consumer with an existing lock on onchain 0.10.0 would
have gone on resolving cartouche 0.5.x — and therefore req 0.6.x — through any
number of `mix deps.get` runs, since the lockfile wins over a satisfied bound.
Raising the floor invalidates that lock entry and makes the upgrade happen
without anyone needing to know to run `mix deps.update`.

### Changed — stale floors corrected

- `{:req, "~> 0.5"}` → `{:req, "~> 0.6 or ~> 0.7"}`. The old bound was
  two-segment and always admitted 0.7.x, so this changes nothing about
  resolution; it stops the declaration from understating what runs here.
- `{:descripex, "~> 0.9"}` → `{:descripex, "~> 0.11"}`, matching cartouche 0.6's
  own `descripex ~> 0.11`. Nothing below 0.11 was resolvable regardless.

### Verified

Resolved against onchain 0.11.0 (via a temporary local path dep, since 0.11.0
was not yet on Hex at preparation time): cartouche 0.6.0, descripex 0.11.0,
req 0.7.1. Compiles `--warnings-as-errors` clean; 142 offline tests and 6
integration tests pass, 0 failures.

## v0.7.0

### Pre-broadcast transaction simulation (closes a fee-payer gas-draining DoS)

- **New public API:** `Onchain.Tempo.RPC.simulate/3` dry-runs a co-signed 0x76
  transaction before broadcast so a fee payer can confirm it would SUCCEED before
  paying its gas. Returns `{:ok, :success}`, `{:ok, {:revert, detail}}`,
  `{:ok, :unsupported}`, or `{:error, reason}`. This closes the DoS where a
  malicious client sets `gas_limit` just below what the call needs: the tx reverts
  out-of-gas and the fee payer pays for nothing. Simulating the full envelope
  (with the client's declared gas) pre-broadcast lets the sponsor reject it.
- **New public API:** `Onchain.Tempo.Transaction.sender/1` recovers the sender's
  20-byte address from a parsed transaction (handles fee-payer co-signed txs by
  resetting the placeholder `fee_token`/`fee_payer_signature` the sender signed
  over). `Onchain.Tempo.Transaction.simulate_request/1` reconstructs the
  `eth_simulateV1` call request from the decoded envelope (recovered sender as
  `from`; the tail call folded into `to`/`value`/`input`; the rest in `calls`).
- **Method note:** simulation uses the EVM-standard **`eth_simulateV1`** (with
  `validation: false`), which the Tempo node accepts for 0x76 AA transactions
  (it honors `type`, `feeToken`, and the folded AA call). The `tempo_simulateV1`
  method named by the mpp-rs reference is **not deployed** on Tempo mainnet (4217)
  or Moderato testnet (42431) — both return `-32601` — verified empirically.
  A top-level `eth_simulateV1` execution error (e.g. `-38013` "intrinsic gas too
  low") is reported as `{:ok, {:revert, _}}` so a fail-open caller cannot leak the
  DoS by mistaking an invalid transaction for a node problem.

## v0.6.0

### Faucet polls the fee-token balance

- `Onchain.Tempo.Faucet.fresh_funded_wallet/1` now confirms funding by polling
  the **fee token's** `balanceOf` (via `eth_call`) instead of the address's
  native balance (`eth_getBalance`). `tempo_fundAddress` credits native gas *and*
  the fee token, but gas can land first — polling native balance could return
  before the pathUSD the caller actually needs had arrived. The poll now waits on
  the balance of interest, independent of gas-vs-pathUSD landing order.
- New `:fee_token` option (hex address) on `fresh_funded_wallet/1` overrides the
  polled token; defaults to Moderato's pathUSD
  (`0x20c0000000000000000000000000000000000000`).
- **New public API:** `Onchain.Tempo.TIP20.balance_of_selector/0` (`0x70a08231`)
  and `Onchain.Tempo.TIP20.balance_of_calldata/1` encode `balanceOf(address)`.

## v0.5.0

### Dependency updates

- Moved to the onchain-0.10 / cartouche-0.5 line: `onchain` `~> 0.9` → `~> 0.10`.
  cartouche 0.5.0 dropped the `config :cartouche, :client` Finch transport seam and
  onchain 0.10.0 migrated its HTTP transport to `Req`. No onchain_tempo library code
  changed — single-call RPC (including `Onchain.RPC.eth_estimate_gas/2`) still flows
  through `Cartouche.RPC.send_rpc/3`, now over `Req`.
- **Test-only change:** `builder_estimate_test.exs` stubs the `eth_estimateGas`
  transport via `config :cartouche, Cartouche.RPC, plug: ...` (the cartouche 0.5.0
  `Req.Test` plug seam) instead of the removed `:cartouche, :client` toggle. All
  offline tests green against the new line.

## v0.4.0

### Per-transaction gas estimation

- `Onchain.Tempo.Transaction.Builder` now estimates gas per transaction via
  `eth_estimateGas` (with a 1.25× safety headroom) when `:gas_limit` is omitted,
  instead of a static `@default_gas_limit`. The static default went stale twice —
  a cold-storage TIP-20 transfer on Moderato measures ~560k–810k (the chain
  charges a protocol fee on the transfer path) and OOG-reverted at the old 500k.
  Estimation mirrors `Onchain.Signer`: per-call estimates are summed, headroom is
  applied, and a failed estimate propagates as `{:error, _}` — never a silent
  fallback. An explicit `:gas_limit` is still honored verbatim with no RPC call.
- **Behavior change:** building with `:gas_limit` omitted now performs an RPC
  round-trip and requires a reachable node; previously it used an offline default.
- Requires `onchain ~> 0.9` (`Onchain.RPC.eth_estimate_gas/2`); floor raised from
  `~> 0.8`.

## v0.3.0

### Dependency updates

- Moved to the descripex-0.9 / onchain-0.8 line: `onchain` `~> 0.7.0` → `~> 0.8`,
  `descripex` `~> 0.7` → `~> 0.9`. onchain 0.8.0 relaxes its own descripex/cartouche
  floors to the same line; descripex 0.8/0.9 are additive (spec-derived JSON Schema)
  and the descripex 0.9.1 `safe_convert` fix keeps manifest/`describe` from crashing on
  unconvertible spec types. No onchain_tempo code changes — compile clean under
  `--warnings-as-errors`, 95 offline tests green against the new chain.

## v0.2.2

### Dependency updates

- Bumped `onchain` `~> 0.5.3` → `~> 0.7.0`. onchain 0.7.0 cascades a major
  `decimal` `2.0` → `3.1.1` jump and pulls `descripex` `0.7.0` + `cartouche`
  `0.2.2` transitively.
- Bumped `descripex` `~> 0.6` → `~> 0.7` and dev-tool `doctor` `~> 0.22` →
  `~> 0.23` (0.23 requires `decimal ~> 3.1`, unblocked by the decimal jump).
- `req` resolves to `0.6.1`. No library code changes — compile clean under
  `--warnings-as-errors`, full offline suite green.

### Faucet — poll for funding confirmation instead of fixed sleep

`Onchain.Tempo.Faucet.fresh_funded_wallet/1` now polls `eth_getBalance` on the
fresh address until the funding transaction lands, replacing the previous
fixed 2.5 s `Process.sleep`. The helper returns as soon as the balance is
non-zero, cutting per-call overhead from a flat ~2.5 s to ~one block (~500 ms
on Moderato).

`:settle_ms` is now the poll **timeout** (default `10_000` ms); `settle_ms: 0`
still skips the wait entirely for unit tests that mock the RPC layer. New
`:poll_interval_ms` option (default `200` ms) tunes the poll cadence.

## v0.2.1

### Migrate signing to Cartouche

**Completed** 2026-05-15

**What was done:**
- Switched internal signing/recovery aliases from `Signet.Signer.Curvy` / `Signet.Recover` to `Cartouche.Signer.Curvy` / `Cartouche.Recover` in `Onchain.Tempo.Transaction` and `Onchain.Tempo.Transaction.Builder`. Cartouche is ZenHive's fork of signet — drop-in compatible, available transitively via `onchain`.
- Tightened the `onchain` dep from `~> 0.5` to `~> 0.5.3` to ensure the cartouche-bearing version is resolved.
- Public API unchanged — purely internal refactor for consumers.

### Dialyzer configuration

- Adopted `plt_add_deps: :apps_direct` to keep the PLT scoped to direct deps (tidewave/bandit's HTTP stack bloated the tree to ~800 modules).
- Moved PLT files from `_build/dialyzer/` to `priv/plts/` so they survive `mix clean` / `_build` wipes. Added `/priv/plts/` to `.gitignore`.

## v0.2.0

### Public `Onchain.Tempo.Faucet` helper for `tempo_fundAddress`

**Completed** 2026-04-19 | [D:2/B:5/U:5 → Eff:2.5]

**What was done:**
- Promoted the previously test-only `Onchain.Tempo.TestSupport.ModeratoFaucet` (`test/support/moderato_faucet.ex`) into public `Onchain.Tempo.Faucet` at `lib/onchain/tempo/faucet.ex` so downstream consumers writing their own integration suites can reuse the Moderato faucet recipe without copying it from our test code.
- Public API: `rpc_url/0` (Moderato default, `TEMPO_RPC_URL` override), `fund_address/2` (thin wrapper around the `tempo_fundAddress` JSON-RPC, returns `{:ok, [tx_hash]}`), and `fresh_funded_wallet/1` (generates a 32-byte keypair, funds it, sleeps for settlement). Both accept an opts keyword list with `:rpc_url`, `:req_options`, and (for `fresh_funded_wallet/1`) `:settle_ms`.
- Registered `Onchain.Tempo.Faucet` in `OnchainTempo`'s `Descripex.Discoverable` module list so it surfaces in `OnchainTempo.describe/0`.
- Migrated the integration suite (`test/onchain/tempo/integration/moderato_test.exs`) to the public module and deleted the old `test/support/moderato_faucet.ex`.
- Added unit tests at `test/onchain/tempo/faucet_test.exs` covering happy/error/transport paths via `Req.Test` stubs.

**Key decisions:**
- Kept the wrapper thin — same `{:ok, _} | {:error, String.t()}` contract as the rest of the library, no struct for the wallet (single-shot return value, kept as a plain map to match the original API).
- Single opts keyword list (rather than `(address, rpc_url, opts)` positional) so callers like `fund_address("0xabc", req_options: [...])` don't silently bind the keyword list to `rpc_url`. RPC URL is pulled with `Keyword.pop(opts, :rpc_url, rpc_url())`.
- `fresh_funded_wallet/1` accepts a `:settle_ms` option (defaults to `2_500`) so unit tests can pass `settle_ms: 0` and avoid the real-world post-funding sleep.
- HTTP path closely follows `Onchain.Tempo.RPC.rpc_request/4` — same `Req.request/2` two-list shape, `Jason.encode!` with string keys, and `req_options` pass-through for `Req.Test`; adds `receive_timeout: 15_000` since funding occasionally exceeds the default.
- Carried forward the existing TODO about the fixed-sleep settle, retagged as `TODO(Task 6):` with a matching ROADMAP entry to replace it with a poll loop on `eth_getTransactionCount`/`eth_getBalance`.

## v0.1.1

### Integration tests against Moderato testnet

**Completed** 2026-04-19 | [D:3/B:7/U:6 → Eff:2.17]

**What was done:**
- Added opt-in `:integration` suite at `test/onchain/tempo/integration/moderato_test.exs` exercising the full Builder → RPC pipeline against live Moderato (chain `42_431`, `https://rpc.moderato.tempo.xyz`).
- Three tests cover: Builder real nonce fetch + 0x76 round-trip via `Transaction.deserialize/1`, `RPC.fetch_receipt/2` returning `{:error, "Transaction not found on-chain"}` for unknown hashes, and `RPC.broadcast_sync/2` confirming a self-transfer of pathUSD with a real receipt + logs.
- New `test/support/moderato_faucet.ex` helper wraps the Moderato `tempo_fundAddress` custom JSON-RPC so each test self-funds a fresh keypair — no env var required.

**Key decisions:**
- Fresh keypair per test (vs MPP's hardcoded Hardhat keys) — avoids nonce races between concurrent CI runs and downstream library consumers.
- Loud `flunk/1` on funding failure rather than silent skip (per project critical-rules).
- pathUSD (`0x20c0…0000`) chosen as the canonical TIP-20 test token, sourced from MPP's existing Moderato integration suite.
- Override `TEMPO_RPC_URL` to point the faucet at a different Tempo endpoint; default stays Moderato.

### Builder default gas_limit raised to 500_000

**Completed** 2026-04-19

**What was done:**
- `Onchain.Tempo.Transaction.Builder` `@default_gas_limit` bumped from 200_000 to 500_000 — a stock TIP-20 transfer on Moderato consumes ~272k, so the previous default under-provisioned real transfers.
- Integration test no longer needs a per-call `gas_limit` override; the library default works out of the box.

**Key decisions:**
- 500k is a ceiling, not an amount spent — no real-world cost change; just prevents `out of gas` for the common TIP-20 path.

### Update MPP to use onchain_tempo

**Completed** 2026-04-19 | [D:3/B:8/U:9 → Eff:2.83]

**What was done:**
- Bookkeeping closure — verified the MPP-side migration was already accomplished during the original v0.1.0 extraction (MPP Task 23, 2026-03-28).
- `MPP.Methods.Tempo` aliases `Onchain.Tempo.{RPC, Transaction, Transfer}`; no `MPP.Tempo.Transaction` module remains in `mpp/lib/`.
- Remaining `MPP.Tempo.*` modules (`Store`, `ConCacheStore`, `Methods.Tempo.SessionReceipt`) are MPP-specific concerns (HTTP 402 dedup, session receipt encoding) and intentionally stay in MPP.

**Key decisions:**
- No code changes in either repo. The migration was complete; the roadmap entry was stale.
- Forward-looking: when onchain_tempo v0.2.0 ships with bumped `onchain` / `descripex`, MPP will need a coordinated dep bump — tracked as MPP Task 43.

## v0.1.0

Initial release — extracted Tempo blockchain primitives from MPP.

**What was done:**
- `Onchain.Tempo.TIP20` — TIP-20 function selectors, calldata encoders, stablecoin DEX address
- `Onchain.Tempo.Transaction` — 0x76 transaction struct, RLP deserialization, payment call matching, fee-payer call scope validation, fee-payer co-signing (0x78 domain)
- `Onchain.Tempo.Transaction.Builder` — Build and sign 0x76 transactions (transfer, multicall, fee-payer variants)
- `Onchain.Tempo.RPC` — Tempo JSON-RPC (broadcast async/sync, fetch receipt, parse receipt)
- `Onchain.Tempo.Transfer` — TransferWithMemo event log parsing via `Onchain.Log.decode_event/2`
- `OnchainTempo` — Root module with Descripex Discoverable progressive API discovery
- 77 unit tests covering deserialization, calldata encoding, payment matching, call scope validation, RPC stubs, and builder validation
