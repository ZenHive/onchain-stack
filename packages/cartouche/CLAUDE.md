# Cartouche (ZenHive fork)

@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md
@~/.claude/includes/onchain-workspace.md
@~/.claude/includes/node-portability.md

forked from https://github.com/hayesgm/signet

See the root `CLAUDE.md` for the hieroglyph/cartouche/onchain stack-boundary
routing rule, the sibling/3 mechanism, and the shared gate adjudications
(reach #36, cowlib/gun, sobelow, `.mix_audit_ignore`). This file carries only
what's specific to this package.

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
  answers `-32600`. Tracked in the root roadmap (task 2127, offset +2000) — do not "fix"
  it by asserting an error string nobody probed, and **do not reclassify it as standard by
  reading `main`**: that is the trap rule 1 now names explicitly.
- **Four wrappers are non-standard and currently say nothing.** `trace_trx/2`
  (`rpc.ex:1435`), `trace_call/2` (`:1586`), `trace_call_many/2` (`:1790`) and
  `debug_trace_call/2` (`:1872`) are absent from `execution-apis` — the `trace_*`
  namespace is OpenEthereum-origin (Erigon, reth) and `src/debug/trace.yaml` carries
  only `traceBlockByNumber`/`traceBlockByHash`/`traceTransaction`. They ship with no
  `@doc` caveat and no capability probe. Roadmap task 2135.
- **The `@doc` is the consumer's only warning.** Cartouche has no capability-probe
  convention of its own yet; until it does, a non-standard method must name its client
  and the consumer-visible error in its `@doc`, the way `README.md` § "Node
  compatibility" now does.
- **Node access for tests lives in a flunk message** (`test/support/live.ex`), not in this
  file — if you are adding node-dependent tests, read it there.

## Toolchain & check commands

Canonical gate: **`mix ci`** (= `mix precommit.full`), same shape as every other
package in the monorepo (root `CLAUDE.md` § Gates). **`mix check.dispatch`** is
the harness reviewer's dispatch-scale gate (no dialyzer, no coverage pass, no
`agents.check` — a harness worktree carries an ephemeral `AGENTS.md` preamble
that would always read as drift). Fast local loop: `mix precommit`. All three
are pinned to `MIX_ENV=test` via `def cli`.

- **`mix precommit.full` runs, in order:** `compile --warnings-as-errors`,
  `format --check-formatted`, `credo --strict` (ignoring TODO/FIXME tags;
  ExSlop plugin enabled), `doctor --raise`, `ex_dna --max-clones 0`,
  `reach.check --arch --smells`, `sobelow --config`, `deps.audit.gated`,
  `test.json --cover --cover-threshold 85 --summary-only --exclude integration
  --exclude dev_node`, `dialyzer`, `agents.check`.
- **This package's dialyzer runs under `MIX_ENV=test`**, so it compiles and
  analyzes `test/support/`; a bare `mix dialyzer` (dev) does not. A clean
  `mix dialyzer` therefore does **not** imply a clean `mix ci`. When `mix ci`
  fails dialyzer but plain `mix dialyzer` is green, the culprit is almost
  always a `test/support/` module. Reproduce the gate's view with
  `MIX_ENV=test mix dialyzer`.
- **`dialyzer` config** pins `plt_add_deps: :apps_direct` (skips transitive dep
  recursion) and `plt_ignore_apps: [:goth, :bandit, :tidewave]` — Goth is an
  optional runtime dep for the CloudKMS signer (calls KMS via `Req` directly;
  Goth only mints the bearer token), and the other two are dev-only Tidewave
  plumbing never called from `lib/`. Without this, every Tidewave/Bandit minor
  bump invalidates the PLT and drags incremental rebuilds back into the
  20+ minute range.
- **This package carries its own `.credo.exs`** on top of the root-consolidated
  ExSlop policy — see root `CLAUDE.md`'s open item on whether that's still
  deliberate or leftover drift; don't assume either without checking.
- **`deps.audit.gated`** — this package's dep tree carries no `gun`, so it
  audits clean with no `.mix_audit_ignore` needed.
- `docs: [skip_undefined_reference_warnings_on: ["CHANGELOG.md"]]` — CHANGELOG
  entries reference hidden generated modules (e.g. `Cartouche.Contract.IConsole`,
  `@moduledoc false`) as historical narrative, not API documentation. Skip is
  scoped to `CHANGELOG.md` only; README and source docstrings stay strict.

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

`.sobelow-skips` is **tracked** — it is the project's accepted-pending-fix security baseline. Each fingerprint should map to a roadmap task that, when shipped, will resolve the finding (currently: the `Cartouche.Sleuth` `String.to_atom` cluster and the generator's `String.to_atom`/`File.{read!,mkdir_p!,write!}` paths — see root `ROADMAP.md`, task IDs offset +2000 for this package). Fingerprints are deterministic (file:line + rule), so the file doesn't churn unless code or sobelow rules change. `mix ci` runs `mix sobelow` against `.sobelow-conf` (`exit: "Low"`, `skip: true`) — without `.sobelow-skips` tracked, every run would fail on the accepted-pending-fix findings, so the file must be in version control. Don't hand-edit; regenerate via `mix sobelow --mark-skip-all` when fingerprints change.

**The drift check that guarded this file is gone family-wide** — see root `CLAUDE.md`'s open item. A drifted entry (the line number is part of the fingerprint, so inserting a line *above* a suppressed finding invalidates it) suppresses nothing while looking like it suppresses something. Until the check comes back, verify by hand after any edit near a suppressed site.
