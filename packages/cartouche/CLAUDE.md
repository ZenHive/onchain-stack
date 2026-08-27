# Cartouche (ZenHive fork)

@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md
@~/.claude/includes/onchain-workspace.md
@~/.claude/includes/node-portability.md

<!--
Selective-load (Opus 4.8 — see setup-guide.md § "Skills vs Includes"):
the eager floor is critical-rules + harness-workflow + onchain-workspace
(harness workspace add-on — 7-repo roster + dependency shape) + node-portability
(cartouche owns the RPC transport, so the "our node is privileged, not the reference"
law has to be ambient here — a guardrail invoked on demand fires too late).

Delegation is via the harness engine. harness-workflow.md is @-imported as the
portfolio-wide implement→review→land contract (cartouche is harness-driven);
the harness-driver skill stays skill-on-demand for the MCP/API surfaces. The
legacy Linear + Codex/Cursor stack is intentionally not loaded.

Everything else is skill-on-demand — Opus self-invokes when the situation
fires, and the hard parts are hook-enforced independently:
  worktree-workflow      → workflow:git-worktrees
  task-prioritization    → tasks:roadmap-planning
  task-writing           → tasks:task-writing
  rmap                   → tasks:rmap
  workflow-philosophy    → workflow:workflow-philosophy
  code-style             → elixir:code-style
  development-philosophy → elixir:development-philosophy
  development-commands   → elixir:development-commands
  ex-unit-json           → elixir:ex-unit-json
  dialyzer-json          → elixir:dialyzer-json
  upstream-pr-workflow   → workflow:upstream-pr-workflow
  elixir-setup           → elixir:elixir-setup
  web-command / agent-economy / reach → elixir:*

Note: AGENTS.md is generated from this file (sync-agents-md.sh inlines the
@-imports) for any tool that reads the generic AGENTS.md convention but has no
skill system. We don't run Linear/Codex/Cursor cloud delegation here — harness
is the only dispatch path — so AGENTS.md has no cloud-agent consumer today;
it's kept as a low-cost convention surface. The Elixir convention set is
enforced by `mix ci` and nothing else — the GitHub Actions workflows were
removed family-wide on 2026-08-22.
-->

forked from https://github.com/hayesgm/signet

## Stack boundary — hieroglyph / cartouche / onchain

**Cut on what defines the bytes, not on who calls the node.** Canonical statement lives in
`cartouche/ROADMAP.md` § "Scope principle"; this is the binding summary.

| Layer | Owns |
|---|---|
| **hieroglyph** | The ABI codec. Pure functions over types and bytes. No I/O, no chain identity, no node. |
| **cartouche** | Everything defined by the **node's wire format**: the JSON-RPC transport, and one wrapper **plus one decoded struct** for every method in a **tagged release** of the `execution-apis` OpenRPC spec — plus transaction envelopes, signing, crypto, hex, and chain ids. |
| **onchain** (and `onchain_*` siblings) | Everything defined by a **contract, a standard, or an off-node protocol**: ERC-*, ENS, AA, MEV, DEX, Multicall, subscriptions, vendor/bundler/relay namespaces. It **re-presents** cartouche's structs; it never re-derives them. |

Routing, in one read:

- **New `eth_*` / `net_*` wrapper** → cartouche, iff the method is in a **tagged** OpenRPC
  release. Not in the spec → cartouche only with a `@doc` naming who serves it *and* a
  capability probe. Vendor/bundler/relay namespace (`eth_sendUserOperation`,
  `eth_sendBundle`, `eth_sendPrivateTransaction`) → onchain.
- **Response decoding** → cartouche, always, into a cartouche struct. onchain never
  re-derives a JSON shape the node emits.
- **ERC standard** → onchain, or a sibling when domain-heavy (`onchain_aave`).
- **Chain constants** → cartouche (`Cartouche.Chain`). A chain with a different tx envelope
  gets its own package (`onchain_tempo`).
- **Non-EVM chain** → its own package. Not cartouche, not onchain.

**Why the previous rule was reversed (2026-08-27).** The old rule sent "RPC method
wrappers" to onchain while leaving the transport and the response structs in cartouche.
That is not a separable cut — `send_rpc/3` takes a `:decode` function, so a wrapper is
*method string + param normalizer + pointer to a cartouche struct*, two of three parts
already cartouche's. onchain could not own the decode without owning the struct, so it
wrote its own. Measured cost: two mutually-incompatible `Block` representations
(`Cartouche.Block` → struct with raw binaries; `Onchain.RPC.Helpers.parse_block_response/1`
→ plain map with `0x` strings), ~500 LOC of duplicate decoders, twelve methods wrapped at
both layers, a `@dialyzer {:no_match, do_rpc: 3}` suppression as the receipt, and
`Onchain.HTTP` (34 LOC) existing only to escape cartouche's config key. No test can catch
that class, because no module consumes both. **The old rule did not prevent the
duplication — it caused it.**

**Migrate lazily, never as a campaign.** When a task ports a method down into cartouche,
the same task converts onchain's copy into a facade. Do not open a migration project.

## Node portability (cartouche specifics)

The family-wide law is `node-portability.md` (`@`-imported above). What is specific to
this repo:

- **Cartouche owns the transport.** `lib/cartouche/rpc.ex` and `lib/cartouche/http.ex` are
  where a non-portable method enters the whole stack — every sibling package inherits
  whatever this repo wraps. Rule 1 (establish that a method is standard) binds hardest
  here.
- **`base_fee/1` is the live counter-example, and it is still unfixed.**
  `lib/cartouche/rpc.ex` ships `defrpc(:base_fee, "eth_baseFee", …)` with a doctest
  implying it just works and no portability note, while `lib/cartouche/application.ex`
  defaults `:ethereum_node` to `https://mainnet.infura.io`. `eth_baseFee` is an
  **Erigon-origin** method (erigon#11992, 2024-09), since implemented by reth,
  Nethermind and geth v1.17.4 and merged into `execution-apis` **`main`** on
  2026-06-15 — but it is in **no tagged spec release** (latest `v1.0.0-beta.7`
  predates the merge) and neither Alchemy nor Infura documents it; Alchemy mainnet
  answers `-32600`. Tracked as roadmap task 127 — do not "fix" it by asserting an
  error string nobody probed, and **do not reclassify it as standard by reading
  `main`**: that is the trap rule 1 now names explicitly.
- **Four wrappers are non-standard and currently say nothing.** `trace_trx/2`
  (`rpc.ex:1435`), `trace_call/2` (`:1586`), `trace_call_many/2` (`:1790`) and
  `debug_trace_call/2` (`:1872`) are absent from `execution-apis` — the `trace_*`
  namespace is OpenEthereum-origin (Erigon, reth) and `src/debug/trace.yaml` carries
  only `traceBlockByNumber`/`traceBlockByHash`/`traceTransaction`. They ship with no
  `@doc` caveat and no capability probe. Roadmap task 135.
- **The `@doc` is the consumer's only warning.** Cartouche has no capability-probe
  convention of its own yet; until it does, a non-standard method must name its client
  and the consumer-visible error in its `@doc`, the way `README.md` § "Node
  compatibility" now does.
- **Node access for tests lives in a flunk message** (`test/support/live.ex`), not in this
  file — if you are adding node-dependent tests, read it there.

## Delegation roster

Portfolio default — carried by `harness-workflow.md` § "Delegation roster — opus last" (`@`-imported above): assign dispatchable tasks **cursor / codex / grok first, opus only if needed** (opus tokens are precious). Cartouche takes the default; no project override.

## Toolchain & check commands

Self-contained so it survives into `AGENTS.md` on regen — cross-family reviewers (codex / cursor / grok) read `AGENTS.md`, not the Claude skill set.

- **Two gates, two seats.** `mix check.dispatch` is the harness reviewer's `check_command` — dispatch-scale, so it skips dialyzer (a cold PLT dominates a fresh run worktree) and the coverage pass. It also omits `agents.check`: harness prepends an ephemeral "do not commit" preamble to `AGENTS.md` inside the reviewer worktree, and that check correctly reports it as drift, producing a red the reviewer can neither fix nor ignore. `mix precommit.full` (alias `mix ci`) is the **landed-base Architect/QA gate** — the comprehensive pass, including `agents.check`, run on `origin/main` after a wave lands. Fast local loop: `mix precommit`. All are defined in `mix.exs` aliases and pinned to `MIX_ENV=test` via `def cli`.
- `mix precommit.full` runs, in order: `compile --warnings-as-errors`, `format --check-formatted`, `credo --strict` (ignoring TODO/FIXME tags; ExSlop plugin enabled in `.credo.exs`), `doctor --raise`, `ex_dna --max-clones 0` (zero-clone budget), `reach.check --arch --smells` (policy in `.reach.exs`), `sobelow --config`, `deps.audit.gated`, `test.json --cover --cover-threshold 85 --exclude integration --exclude dev_node`, `dialyzer`, `agents.check`. Nothing runs it for you — the GitHub Actions workflows were removed family-wide on 2026-08-22, so a local green is the only green there is. Two checks went with them and have **no replacement**: a `MIX_ENV=dev` dialyzer against the cached `priv/plts` PLT, and the `.sobelow-skips` drift check (see below).
- **`mix test.json` (`ex_unit_json`) and `mix dialyzer.json` (`dialyzer_json`) emit JSON by design — this is NOT a build failure.** Parse the JSON for real failures; never flag the envelope itself. Plain `mix dialyzer` is the authoritative dialyzer check when the JSON encoder can't serialize a warning shape (it's what the gate and CI run).
- **The gate's dialyzer runs under `MIX_ENV=test`, so it compiles and analyzes `test/support/`; a bare `mix dialyzer` (dev) does not.** A clean `mix dialyzer` therefore does **not** imply a clean `mix ci`. (CI used to run the dev-env dialyzer as a second, PLT-cached pass; that went with the workflows on 2026-08-22 — only the `MIX_ENV=test` view is checked now.) When `mix ci` fails dialyzer but plain `mix dialyzer` is green, the culprit is almost always a `test/support/` module. Reproduce the gate's view with `MIX_ENV=test mix dialyzer`.
- **`reach.check --arch --smells` gates from `.reach.exs`** (`smells: [strict: true]`). Smell findings must be fixed for real; the `smells.ignore.paths` entries already present are scoped to metaprogramming-inherent findings (see the comment in `.reach.exs`) — never add to that list to make a new finding disappear.
- **`deps.audit.gated` proves the local mix_audit advisory mirror is fresh (`bin/advisory-freshness.sh` in `onchain-stack`) before running `mix deps.audit`** — `mix_audit` discards its own sync exit status (`mirego/mix_audit#61`), so a frozen mirror would otherwise report a false "No vulnerabilities found." cartouche's dep tree carries no `gun`, so it audits clean with no `.mix_audit_ignore`.

## Generated contract fixtures (`mix cartouche.gen`)

The contract wrappers under `lib/cartouche/contract/*.ex` (i_console, sleuth) and the test fixtures under `test/support/cartouche/contract/*.ex` (ierc20, rock, block_number) are **generated** by `mix cartouche.gen` from ABI JSON in `test/abi/*.json`. They are committed, not regenerated in CI — so they **drift stale** when the generator evolves but a fixture isn't re-emitted.

- **The dialyzer trap:** an older generator built call/estimate wrappers on `%V2{}` (`build_trx_* -> %V2{destination, data}`). But `V2.t()` types the gas/fee/nonce/`access_list` fields as **non-nilable** while `defstruct` defaults them to `nil`, so `%V2{destination, data}` is **not** a valid `V2.t()`, and `Cartouche.RPC.call_trx`/`estimate_gas` (domain `V1.t()|V2.t()|Call.t()`) type those wrappers as `none()` → "no local return" + "invalid type specification" warnings. The current generator emits `%Call{}` (whose `Call.t()` is nil-tolerant), which is clean. The `lib/` outputs are credo-excluded (`~r"lib/cartouche/contract/"`) and were kept current; `test/support/` fixtures are credo-*included* and dialyzed in test env, so a stale one there fails `mix ci` (e.g. ierc20, fixed in `5f4086f` — was 73 warnings).
- **Fix a stale fixture by regenerating, not hand-editing** (`critical-rules.md` → fix the generator/its input, not the output): `mix cartouche.gen --prefix Cartouche.Contract --out <scratch>/ test/abi/<Name>.json`, then `mix format <file>`, copy over the committed fixture, and **restore the file-level `# credo:disable-for-this-file Credo.Check.Readability.MaxLineLength`** (the generator does not emit it; wrapped event topic-0 hashes exceed 120 chars). Verify with `MIX_ENV=test mix dialyzer` (0 warnings) and `mix ci`.
- **Tell-tale of stale-but-harmless drift:** missing `alias V1/V2`, `@doc false`/`@spec ... :: term()` instead of descriptive `@doc`/real specs, no `abi/0`. These are cosmetic — they pass dialyzer/credo and do **not** block the gate; only the `%V2{}` shape above breaks it. Don't churn passing fixtures just to refresh doc richness.
- **Current state (verified 2026-08-01 by regenerating each fixture to a scratch dir and diffing):** all five committed outputs are byte-identical to fresh generator output — none carries the drift signals above. The single expected delta is ierc20's hand-restored `# credo:disable-for-this-file` header (see the bullet above); a `diff` showing only that means the fixture is current, not stale. Earlier revisions of this file listed rock and block_number as cosmetically stale — they have since been re-emitted.

## Hook-flagged issues

When our PostToolUse hooks flag issues on files you touched (credo, format, dialyzer, etc.), fix them in this commit — including pre-existing flags unrelated to your change. See `critical-rules.md` → "FIX HOOK-FLAGGED ISSUES ON FILES YOU TOUCH". Touched-file scope only, not project-wide.

## Sobelow workflow

After fixing a sobelow finding (or otherwise wanting to refresh `.sobelow-skips`), regenerate the suppression file from live state:

```bash
mix sobelow --mark-skip-all
```

That writes a fresh `.sobelow-skips` containing fingerprints for whatever sobelow flags right now. Resolved findings drop out automatically; new ones get added. Confirm with `mix sobelow` (clean output = all findings are accounted for).

`.sobelow-skips` is **tracked** — it is the project's accepted-pending-fix security baseline. Each fingerprint should map to a ROADMAP task that, when shipped, will resolve the finding (currently: Task 48 for the `Cartouche.Sleuth` `String.to_atom` cluster; Tasks 41/42/50/59-gen for the generator's `String.to_atom` and `File.{read!,mkdir_p!,write!}` paths). Fingerprints are deterministic (file:line + rule), so the file doesn't churn unless code or sobelow rules change. `mix ci` runs `mix sobelow` against `.sobelow-conf` (`exit: "Low"`, `skip: true`) — without `.sobelow-skips` tracked, every run would fail on the accepted-pending-fix findings, so the file must be in version control. Don't hand-edit; regenerate via `mix sobelow --mark-skip-all` when fingerprints change.

**The drift check that guarded this file is gone.** `harness.yml` used to run `--mark-skip-all` into a scratch copy and diff it against the committed file, failing when fingerprints had gone stale; it was deleted with the workflows on 2026-08-22 and has no replacement. This matters because a drifted entry — the line number is part of the fingerprint, so inserting a line *above* a suppressed finding invalidates it — suppresses nothing while looking like it suppresses something. Until the check comes back as a `precommit.full` step, verify by hand after any edit near a suppressed site. The SARIF upload to GitHub code scanning went too; it was reporting-only (`continue-on-error`), never a gate.
