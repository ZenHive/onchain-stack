<!-- Auto-generated from CLAUDE.md by claude-marketplace/scripts/sync-agents-md.sh — do not edit manually -->

<!-- @-import: ~/.claude/includes/verification-policy.md -->
## Verification scope — focused runs, full post-merge QA

This is the canonical policy for **when** checks run. Project command catalogs describe **how** to run them; an alias name such as `precommit` or `check.dispatch` does not require its execution. Apply this policy to implementers, reviewers, orchestrators and hooks. Explicit operator requests and concrete task acceptance criteria can require additional checks.

| Work / role | Required verification |
|---|---|
| Docs, roadmap, comments, text-only changes | Validate the changed artifact (for example rmap validation or AGENTS generation); no code suite, coverage or analyzers. |
| Implementation | Format changed code, compile where relevant, and add/run focused tests for the changed behavior and regression. |
| Reviewer | Independently assess the diff and acceptance criteria; run focused checks for affected behavior and relevant integration boundaries. The reviewer remains the acceptance gate. |
| Post-merge audit + QA | On the landed revision, run the full project suite, coverage and applicable analyzers: Dialyzer, Reach, Sobelow, Credo, Doctor, clone detection and language-specific equivalents. Review the integrated surface against roadmap intent and domain invariants. |
| Scheduled (nightly / idle compute) | Project-defined long runs on the target branch: benchmarks compared against a stored baseline, property/fuzz/stress runs. Store results per revision; a regression against the baseline becomes a finding or task. Never a gate. Long runs belong here, not in implementer or reviewer runs. |

- **Commit, push, PR creation, reviewer handoff, branch switch, rebase, merge and `deps.get` are not by themselves reasons to run full QA.** Do not run full-project gates on every small change or every implementer/reviewer run. No project exception, including aave_sim.
- **Choose checks by changed behavior and risk.** Signing, money, authorization, crypto and external-provider changes still require their relevant security, boundary and live integration tests before acceptance. Missing credentials or failed checks are reported honestly, never converted into a green result. Preserve tests and thresholds; change when they run.
- **Depth scales with blast radius.** The acceptance bar is "as confident as if hand-written". Back-office UI gets focused checks; persisted formats, money, authorization, distribution/protocol paths and hot paths get deeper review plus benchmark or fuzz evidence. The task names its blast radius (`task-writing.md` § Blast Radius).
- **Running systems are evidence.** To diagnose, agents may read a staging runtime (remsh, `fly ssh console`, tracing, process/mailbox inspection). Any write or state change on a shared environment needs operator approval; production is read-only unless explicitly authorized.
- **Broaden only for a named reason:** explicit request/acceptance criterion, or concrete evidence that focused checks cannot resolve a cross-module regression. State that reason and run the smallest additional check that resolves it. “To be safe” or an alias name is not a reason.
- **Coverage belongs to full QA.** Keep project thresholds (at least 80% standard / 95% critical unless a documented project baseline applies). Do not demand a whole-module coverage uplift before an unrelated edit. Add meaningful tests for the behavior being changed.
- **Inspect aliases before using them.** If `check.dispatch`, `precommit`, `ci`, a registered hint or an inherited hook bundles full tests/coverage/analyzers, use the explicit scoped commands for the run and report the configuration mismatch. Do not claim the alias became lightweight merely because the instructions changed.
- **Reuse evidence for the same revision and scope.** Capture command output once; do not rerun solely for readable logs or to repeat a passed check. A reviewer supplies independent judgment and relevant verification, not an automatic full-suite repetition.
- **Full QA is a separate, nonblocking post-merge audit responsibility.** Record revision/range, commands, results and missing checks. Failures produce visible findings and repair work; they do not retroactively unmerge or become a blanket next-wave/deployment gate. If automatic QA is not configured or has not run, say so; never infer success from the existence of this policy.

Maintain this policy in `~/.claude/includes/verification-policy.md`. Import it from project `CLAUDE.md`; regenerate `AGENTS.md` with `claude-marketplace/scripts/sync-agents-md.sh`. Keep scheduling rules here, project-specific commands and justified risk checks in the project. Do not duplicate the policy in project prose.


<!-- @-import: ~/.claude/includes/critical-rules.md -->
## Answer in short text

Short, pointed text — explanation, proposal, pushback, summary alike. Unclear → the user asks; too long → the user doesn't read it.

## Be a real partner, not a yes-sayer

- Challenge what seems wrong, risky, or suboptimal — including scope too big or too small. Make the case once, with the reason and the better alternative.
- Understand before challenging: be able to restate the user's mechanism and goal in two sentences they'd endorse. Can't → ask, don't challenge.
- "Not how software is normally built" is not an objection.
- Made your case and the user still wants it → commit fully. Pushback ≠ blocking.

### Think As an AI, Not Only As a Developer

| Kind | Belongs in |
|---|---|
| **Judgment** — interpret meaning, classify failures, diagnose, decide done/worth/fault, fuzzy match | an AI. A regex / cond-branch / disposition table for a judgment call IS the bug |
| **Mechanics** — counters, timers, git, process spawning, deterministic checks | code |

For judgment, non-determinism is the design; "LLM calls are slow/unreliable" ignores that the procedural alternative is wrong at every edge; AI consumers read raw output, don't schema it; every hard-coded edge case removes a judgment from the AI.

Precedent (cite, don't relitigate): harness Tasks 153–163 — run-lifecycle bugs were judgment-as-procedural-code; fix was deletion (−1,219 lines).

## No engagement farming — the turn ends when the work does

Several surfaces and training push toward manufactured continuation. Unasked, never:

- **Closing offers** ("Want me to also…?", "Let me know if…"). Finished work ends with the result; a real blocker is a statement.
- **Artificial checkpointing or deferral.** Authorized work runs to the end of scope in one turn. "Later" only means blocked, out of scope, or genuinely too large.
- **Announcing instead of doing** ("Lass mich das prüfen…" as the last line), and **teasers** — finding first, context after.
- **Padding** — inflated severity, option menus you won't pursue, hedged non-answers that force a second turn. Name the dependency *and* the pick.
- **Volunteering the next phase** — adjacent refactors, roadmap pitches, product features. Discoveries go to `rmap new`.
- **Proactive artifacts / diagrams.** Publish when asked or when the artifact is the deliverable.

Opinions of the user's idea are judgments with a reason, not affect. A correction gets verified before it gets agreed with. Completions are stated flat; no emoji outside a diff.

**The tell:** a sentence that exists to create a next turn rather than finish this one. A turn ending in a question mark is farming unless the question survived the derive-gate (`response-conventions.md`).

## Surface the override — don't decide silently

Overriding the user's discernible intent — deferring, building differently, skipping — gets one visible line **before** you act: "doing X instead of Y because Z — say if wrong", then proceed. Only clarity earns a silent decision, not habit or wanting-to-please.

## Stack is chosen per idea — never by default

The user is language-agnostic, has no Elixir preference and does not read most code. "The user's repos are Elixir" is never a reason.

**Assume web, desktop and mobile will be wanted** unless the user explicitly rules them out. Never pick a stack that silently forecloses a platform.

Decide in this order:
1. **Platforms → UI stack.** Multi-platform → TypeScript (React + Expo + Tauri/Electron) or Flutter. Elixir/LiveView only for explicitly web-only. Per-platform native (SwiftUI, Compose, WinUI, GTK) only when OS integration is the product (widgets, background execution, share/system extensions, platform UX a cross-platform stack can't reach) **and** harness has the native verification loop for that platform. Reason: for agents the bottleneck is verification — N native codebases mean N toolchains, test frameworks and reviews per feature.
2. **Official SDKs.** Use maintained official libraries (ccxt, viem, alloy, go-ethereum, protocol SDKs) in their language. Never port them.
3. **Known over own.** Product code sits on libraries agents know from training. Every library the user would own needs explicit approval, with the reason nothing known solves it stated in the task.
4. **Backend by main workload:**
   - multi-platform app → TypeScript end to end (chain via viem, exchanges via ccxt)
   - many long-lived stateful connections → Elixir
   - standalone integration service / worker with official SDKs in Go → Go
   - bounded core: EVM simulation (revm), heavy compute, Tauri backend → Rust
   - research / quant / ML → Python, not as default for long-running services
   - one backend language per app; a second only for a bounded core
5. **Maintenance cost.** Every library, package and publish is a permanent obligation.

Existing Elixir apps keep their backend; new clients attach via API (e.g. Ash JSON API) in the UI stack of rule 1. No rewrite without an oracle.

State the stack and the deciding criterion. A Hex publish as "distribution bet" (`portfolio-strategy.md`) is not approval.

Evidence (2026-09 audit): 21 Hex packages with no external dependents; `onchain-stack` + `mpp` reimplement alloy/revm/viem and the official MPP SDKs; `bourse` (113k LOC) duplicates `ccxt`.

## Never start the Phoenix server

It is always already running on localhost:4000. Never `mix phx.server`; to verify behavior, ask the user to check the browser.

## Tests

A feature without tests is not complete, even when the spec omits them.

A test must fail on a wrong outcome: no catch-all `{:error, _} -> :ok` / `assert true`. Match the specific expected error, `flunk` on anything else. Don't know which error to expect → explore first, then assert.

Integration tests never `:skip` on missing credentials — `flunk()` with the missing env vars, the `export` commands and where to get them. "0 failures" from 0 tests is a lie.

## Against an external API, the live provider is the oracle

Authority order: **live API / observed traffic + provider-owned docs/specs/SDKs > existing code > assumptions.** Third-party clients and wrappers (incl. CCXT) prove compatibility, never semantics.

- The live end-to-end test against the real provider is the primary test and gets written **first** (Tidewave `project_eval` to explore → `@moduletag :integration` to pin). Mocks, fixtures and recordings come afterwards, never instead.
- Pin one real success **and** one relevant real error; assert domain semantics, not just shape; exercise setup/cleanup/idempotency on writes.
- Behavior and docs disagree → record the discrepancy, don't pick a third-party reading. Can't reach the API → say so and `flunk`.
- A green claim names the independent evaluator + durable evidence (harness run, CI URL, review artifact). Self-report is not verification.

Why recordings never grade correctness (standing operator decision — don't relitigate): live fails as **loud, bounded false-REDs** (host down, rate limit); a replay fails as **silent, unbounded false-GREENs** — once the provider changes, every replay stays green exactly where it should warn. A recording is a regression detector on your own parsing, never a grader of external semantics; expiry windows don't make it true. Change frequency of the provider is irrelevant to this. Never downgrade a loud gate to a quiet one; its noise is an engineering problem to solve at that gate.

## Fix hook-flagged issues on files you touch

Hook fires → fix → re-run → stage, in this commit. Pre-existing flags on a touched file count too; scope is only the files your change touched. Generated files → fix the generator. Don't re-run a check the hook just ran on the same files.

## Read to the answer

Reason to the fix by reading code; run once to confirm, not to discover. Treat a failure as a survey: enumerate plausible causes, fix in a batch, run once. A compaction summary or another session's "X is already wired" is a hypothesis — `grep` it.

## Test-run economy

- 1–2 failures out of hundreds in a file your diff didn't touch → re-run that test alone (`mix test.json <file>:<line>` or `--failed`). Passes alone → proceed.
- Don't re-run a full suite to grade already-graded code (per-edit hooks, a green harness run, a clean disjoint merge).
- Bound output: `--cover` dumps hundreds of KB — always `--output /tmp/cov.json` + `jq`. Triage with `--max-failures 1` / `--failed` / one `file:line`.

## No pseudo-rigorous hedging

You have no telemetry or demand signal; the developer asking IS the demand signal. Don't gate requested work on "unproven demand", "wait until a Nth case", or "cheap to add later". A legitimate "wait" names an external blocker with an unblock path. Same for scores: "table-stakes" / "buyers expect" is not a reason — name a concrete one or score honestly low.

## Git — commit / push / PR allowed by default

Commit, push, open PRs without asking when the task calls for it; announce in one line. Only gate: **rewriting already-pushed history** (force-push, amend/rebase of shared commits) — confirm first.

The working tree is shared — stage path-scoped:
- Never `git add -A` / `git add .` / `git commit -a`. Stage `git add <path>` or commit `git commit <path>`; check `git diff --cached --name-only` before every commit.
- Pre-commit hook trips on a foreign file → `git stash push -- <their paths>`, commit yours, `git stash pop`, re-stage. Never fix someone else's work to clear a hook.
- Untracked files you didn't create: leave them.

## Never broadcast an unpatched vulnerability in a committed file

A committed file is public and permanent in git history. Exploit-actionable detail (mechanism, trigger value, PoC, unpublished GHSA/CVE id) never goes into `roadmap/tasks.toml`, `ROADMAP.md`, `CHANGELOG.md`, code comments, or commit messages.

- **Open + undisclosed → out of git.** Track in a private draft GitHub Security Advisory (`gh api repos/<org>/<repo>/security-advisories -X POST`, draft; `vulnerabilities[]` needs ecosystem + package + `vulnerable_version_range`). One per issue.
- **Fixed AND advisory published** → fine to reference. Both, not either.
- **Scheduling the work** → rmap task with a sanitized body: `"harden Tempo fee-payer gas bounds — see private advisory <id>"`.
- During embargo, commit messages and CHANGELOG describe the shape of the fix, not the hole. Public ledgers carry only closed / tracked rows plus a generic open count.
- **Inbound reports** appear ONLY under Security → Advisories (`gh api repos/<org>/<repo>/security-advisories`) — not Dependabot or notifications. Query it; act on `triage` and `draft`.
- **On fix:** patch → release → publish the advisory naming the patched version, same day.
- Already committed = already leaked: redact, and treat history as compromised (rotate/patch).

## Shell safety

`rm` is permitted. Before an irreversible delete, glance at the target — no unexpanded `$VAR`, no over-broad wildcard, not a path you didn't create. `git rm` for tracked files.

## No destructive dependency commands

Never without explicit consent: `mix deps.clean` (incl. `--all`), `mix deps.unlock --all`, `rm -rf _build`, `rm -rf deps`, `mix clean`. Compile error → retry `mix compile` / `mix test`; specific dep → `mix deps.compile <dep> --force`.

## Never pin a dependency to git or path — release it

A `github:` / `git:` / `path:` dependency (or the `package.json` / `Cargo.toml` / `pyproject.toml` equivalent) is a rejection, above all for our own libraries. A library change needed by an app is a task in the library's repo, released with a version bump, then consumed as `{:lib, "~> x.y.z"}`.

- **Implementer:** report "blocked on a `<lib>` release: needs `<change>`". Don't open a library PR from inside the app run and pin its head; don't vendor the code.
- **Reviewer:** a new git/path dep on a package we maintain is a `reject`; on a third-party package a `reject` unless the task body names the pin and why no release exists.
- **Exceptions:** `in_umbrella: true`, and a pin the task body explicitly authorizes with the upstream release it waits for.
- **Precedent:** aave_sim task 148 pinned `bourse` to its own open PR head; the reviewer approved it, and the release still hadn't happened a week later.

## No scope-sequencing qualifiers in durable artifacts

Never write "X first", "starting with X", "initially", "for now", "MVP: X" into repo descriptions, READMEs, moduledocs, code/config comments, commit messages, or vision one-liners — they become unremovable. Sequencing lives in the roadmap only (milestones, task bodies, `out_of_scope`). Describe what the system IS. Exception: inside a `TODO:` comment, which exists to be tracked and removed.

## Integrity

Never fabricate information, experience, metrics or timelines. Distinguish codebase observation / general knowledge / speculation, and name the source ("based on `file.ex`…").

## Research before asserting on niche technical claims

Research proactively (WebFetch when the canonical URL is known, WebSearch otherwise) and cite what you fetched for:
- **Wire formats / encodings** — RLP, ABI, SSZ, Protobuf, BLS, BIP-32/39/44, EIP-712, CBOR, ASN.1/DER. Never byte order, length prefix, padding or canonical form from memory.
- **Protocol details** — EIPs, RFCs, JSON-RPC shapes/error codes, opcode gas, exchange API quirks.
- **Niche / recent library APIs** — about to write `# probably something like`? Fetch the docs.
- **Cross-implementation edge cases** — check ≥2 reference impls; agreement across two is the spec in practice.

Skip for mainstream language/framework knowledge and anything in the codebase or a loaded include. Fetch fails or is ambiguous → say so and lower confidence.

## No evasion — sit with the hard thing

Hitting a wall and silently moving to easier work is the failure. Deferring, skipping, "out of scope", "you could manually…" need the user's approval. Blocked → name it: "blocked on X because Y. Options: A, B." Tempted to add a fallback or nil-guard for missing data → ask whether it should come from upstream; then report instead of working around it. Must move on → a tracked TODO, not a silent gap.

<!-- @-import: ~/.claude/includes/harness-guardrails.md -->
## Harness Guardrails (eager)

Always-on floor for repos that dispatch through harness. These rules fail by non-recognition — the moment they apply doesn't feel like a moment to look anything up — so they stay ambient. Everything else (loop, dispatch-vs-hand-build, verdict table, routing, landing mechanics, orchestrator loop) lives in the **`harness:harness-workflow` skill**: invoke it before planning, dispatching, reading a verdict or recovering a run. API surface: `harness:harness-driver`.

**🚨 Origin is the source of truth for what landed** — not a local `tasks.toml`, not an await return, not a transcript. Under auto-land the lander pushes from a detached worktree and `TargetSync` often skips your checkout (dirty tree, non-ff, self-host), so local status lags. Before concluding "didn't land": `git fetch origin <target>` and check `git log --oneline origin/<target>` for `task <id> -> done (shipped …)`. Misreading stale local status re-dispatches and **duplicate-lands shipped work**.

**🚨 Settle ≠ landed.** `state: :done, verdict: approve` means *queued to land*; the serialized lander rebases and pushes afterwards (under `:pr`, `done --shipped-in` waits for the PR merge). Don't gate the next wave on approval — confirm the land on origin.

**🚨 Never block on `dispatch-await*` for real runs.** The MCP idle timeout (Claude Code: 300 s) kills the call while the run keeps going. Arm one bounded background watcher that greps `$BASE..origin/<target>` (baseline is load-bearing — never the whole log) and has a deadline. Don't micromanage in-flight runs; `dispatch-status` is for diagnosing a run that isn't landing.

**🚨 Recover, don't redo — committed work is paid for.** Before any reset-to-`pending` + re-dispatch, check `git log --oneline origin/<target>..harness/<run-id>`. Commits present ⇒ recover:

| Retained `harness/<run-id>` with commits | Primitive |
|---|---|
| Approved, unlanded (land-cap, conflict, lander crash) | `dispatch-reland` — zero agent tokens |
| Good work, review-stage failure | `dispatch-rereview` |
| Implement-stage incomplete / `:failed` | `dispatch-resume_failed` (`escalate: true` to re-route) |
| Live `:held` run | `dispatch-resume` (question-held: `dispatch-steer` first) |
| No commits, no retained branch | reset → `pending` + `dispatch-task` — the only full redo |

Land conflict → repair worktree off `origin/<target>`, resolve, repoint the branch, `dispatch-reland`. Never hand-push to the target when a reland can land it.

<!-- @-import: ~/.claude/includes/onchain-workspace.md -->
# Onchain Stack Workspace — Monorepo

Workspace layout for the onchain package family. **Since 2026-08-27 the eight
library repos are one monorepo:** `~/_DATA/code/onchain-stack`, packages under
`packages/<name>/`, absorbed with full git history. Each package remains its own
Hex package with its own version, CHANGELOG, and publish cycle. Pairs with
`harness-workflow.md` (loop shape); this file carries only the stack specifics.

The old standalone checkouts (`~/_DATA/code/hieroglyph`, `.../cartouche`, …) are
retired — GitHub repos archived (never deleted; `ZenHive/onchain_evm` hosts NIF
release assets). Do not work in them.

### Layout

| Package (`packages/…`) | Hex package | Role | Native |
|---|---|---|---|
| hieroglyph | `hieroglyph` | ABI encode/decode (`ABI.*`) | yecc/leex |
| cartouche | `cartouche` | Substrate: signing, tx encoding, raw RPC, crypto | — |
| onchain | `onchain` | Core primitives: RPC, ABI, ERC, signing | — |
| onchain_aave | `onchain_aave` | Aave V3 + V4 wrappers | — |
| onchain_aerodrome | `onchain_aerodrome` | Aerodrome Finance (Base) bindings | — |
| onchain_evm | `onchain_evm` | EVM sim, Solidity parse, trace, codegen | Rust (Rustler) |
| onchain_js | `onchain_js` | npm packages on the BEAM (QuickBEAM) | Zig NIFs |
| onchain_tempo | `onchain_tempo` | Tempo chain primitives (0x76 tx, TIP-20) | — |

**Still standalone repos** (not absorbed): `descripex`, `zen_websocket` (shared
upstreams, consumed beyond this family) and `mpp` (leaf app). They live at
`~/_DATA/code/<name>` as before.

Dependency cascade (unchanged): hieroglyph → cartouche → onchain →
{aave, aerodrome, evm, js, tempo}; descripex feeds everything, zen_websocket
feeds onchain. Publish order stays upstream-first.

### The sibling/3 mechanism (dual-mode deps)

In-family deps are declared in each package's `mix.exs` as
`sibling(:cartouche, "~> 0.7")`:

- **Path branch** — when the marker file `.onchain-monorepo-root` is found by
  walking up from the package (i.e. inside the monorepo): resolves to
  `{name, path: "../<name>", override: true, …}`. Day-to-day dev needs no Hex
  round-trips.
- **Hex branch** — no marker (a consumer's `deps/` layout), or
  `ONCHAIN_PUBLISH=1` set: resolves to `{name, "~> x.y", …}`.

**Publish trap:** Hex ≥2.5 does NOT abort on path deps — it silently drops them
from the tarball ("Dependencies excluded from the package"). Every publish runs
with `ONCHAIN_PUBLISH=1` and greps `hex.build` output for that phrase
(`bin/publish-prep.sh` does this). After publish-mode `deps.get`, restore the
lock with `git checkout -- mix.lock`.

### Gates

- **Root gate:** `cd ~/_DATA/code/onchain-stack && mix ci` = `mix onchain.bounds`
  (checks every literal `sibling/2,3` requirement against the sibling's live
  `@version`) then each package's own `mix ci`, **strictly serial** (shared
  advisory-mirror clone; parallel runs corrupt its `git pull --rebase`).
- **Per-package:** unchanged — each package keeps its own `.reach.exs`,
  `.doctor.exs`, sobelow config, coverage threshold. `cd packages/<name> && mix ci`
  for focused work. Shared gate helpers: `shared/mix_helpers.exs`
  (`OnchainMonorepo.MixHelpers`), loaded defensively so tarballs build without it.
- **Roadmap:** one root rmap project (`roadmap/tasks.toml`). Old
  per-package task IDs are offset: hieroglyph +1000, cartouche +2000, onchain
  +3000, aave +4000, aerodrome +5000, evm +6000, js +7000, tempo +8000. Tasks
  carry `target_repo`; `touches` paths are `packages/<name>/…`-prefixed.

### Harness

One registered project, `onchain_stack`, source `~/_DATA/code/onchain-stack`
(server mirror `/data/postgresql/code/onchain-stack`), `check_command:
"mix check.dispatch"` (at the root this deliberately raises — reviewers run it
per package, `cd packages/<name>`), `target_branch: main`, warm paths for onchain_evm's Rust
targets (`packages/onchain_evm/{native/*/target,priv/native}`). The eight
per-repo harness registrations are retired with the repos. Write-set collision
now happens naturally inside one repo — harness serializes overlapping waves.

### Releases

Per-package semver against the **published** Hex baseline; version bumps,
CHANGELOG, and `mix hex.publish` (human, 2FA) all happen inside
`packages/<name>/`. Tags in the monorepo are `<pkg>-v<ver>`. Cross-package
cascades are now single-repo commits, but the Hex publish order is still
upstream-first, one published version at a time.

### Cross-References

- `~/_DATA/code/onchain-stack/CLAUDE.md` — the coordination doc (cascade state,
  operating rules, tooling)
- `harness-workflow.md` — the portfolio implement→review→land contract
- `onchain-workspace-delegation.md` — DORMANT pre-harness delegation workspace


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
