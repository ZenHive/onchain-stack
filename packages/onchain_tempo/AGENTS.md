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


<!-- Selective-load (Opus 4.8): eager floor = critical-rules + harness-workflow (this repo is
     harness-driven — the OTP dispatch→review→land loop is the active workflow). onchain-workspace
     is the harness workspace add-on (monorepo layout + sibling/3 + dependency shape), eager
     family-wide. Everything else previously imported here (across-instances, worktree, task-prioritization/writing, rmap,
     workflow-philosophy, web-command, elixir-setup, ex-unit-json, dialyzer-json, code-style,
     development-commands/philosophy, agent-economy) is skill-on-demand via the elixir / task-driver
     / dev-lifecycle plugins. The Linear-as-queue + Codex/Cursor delegation flow (delegation +
     onchain-workspace) is retired — harness replaced it. Re-add an @-import per-surface only if
     Opus visibly degrades on it. See ~/.claude/setup-guide.md § "Skills vs Includes". -->
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

<!-- @-import: ~/.claude/includes/node-portability.md -->
## Node Portability — Our Node Is Privileged, Not the Reference

**We do not develop only against our own node.** These are open-source libraries other
people run against Alchemy, Infura, pruned Geth, and self-hosted nodes of every shape.
Our archive node (`localhost:8545`, full-history reth) is a *privileged* environment, not
the reference one: it serves `trace_*`/`debug_*`, complete history, and client-specific
extensions most consumer endpoints do not.

Developing only against it silently encodes its capabilities as the library's
assumptions. The failure is invisible here — it works — and lands on the consumer.

### The four rules

1. **Establish that a method is standard** — present in a **tagged release** of the
   OpenRPC spec, not in `main`. Erigon/Geth/provider extensions are not standard however
   reliably our node answers. **Read the tag, never the branch:** a method can sit on
   `execution-apis@main` for months before any release carries it, and re-vendoring from
   `main` would silently reclassify it as standard — that is exactly how `eth_baseFee`
   would flip (see the worked example). Spec residency also proves nothing about
   *availability*: a method merged to the spec and implemented by every major client can
   still be refused by the endpoint your consumer uses, because hosted providers gate
   their method allowlists independently. Rule 1 bounds the claim; only rule 4 tests it.
   (Note: `Onchain.RPC.Codegen.ensure_known_method!/1` reads the *merged* OpenRPC +
   `erigon-methods.json` map, so it does **not** enforce this distinction — and
   `erigon-methods.json` is a 21-entry `ots_*`/`trace_*` scrape, not an Erigon method
   census, so it does not carry `eth_*` extensions at all. Rule 1 is currently a judgment
   call, not a compile-time gate.)
2. **Prefer the portable construction.** If a value is reachable from a standard method,
   read it that way — `base_fee` via the final `baseFeePerGas` of
   `eth_feeHistory(1, "latest", [])`, not via `eth_baseFee`.
3. **When only a non-standard method will do, say so in the `@doc`** — name who serves it
   and the error consumers get without it — and expose a capability probe rather than
   failing deep in a pipeline (precedent: `Onchain.Trace.available?/1`).
4. **Verify on a second, unprivileged endpoint before claiming portability.** Green on
   `localhost:8545` alone proves nothing. A hosted endpoint's *real refusal* is evidence;
   our node's `{:ok, _}` is not.

### The worked example (2026-08-25, sharpened 2026-08-27)

cartouche 0.8.0's `base_fee/1` calls `eth_baseFee` — an **Erigon-origin method**
(erigontech/erigon#11992, 2024-09-18), adopted by reth, Nethermind and go-ethereum
(v1.17.4) in mid-2026 and **merged into `ethereum/execution-apis` `main` on 2026-06-15**
(PR #795) — but present in **no tagged spec release** (latest is `v1.0.0-beta.7`,
2026-06-10, five days *before* the merge), absent from the vendored
`openrpc-v1.0.0-beta.7.json`, and documented as supported by **neither Alchemy nor
Infura**. Our reth node serves it; Alchemy mainnet answers
`-32600 "eth_baseFee is not available on the ETH_MAINNET"`. It was caught only by
hand-probing both endpoints.

**Why this example is worth more than "extension ⇒ not portable".** Spec residency is a
*lagging* indicator of node availability and a leading indicator of nothing. Reading the
spec today gives the **wrong** answer here — `main` says standard, the consumer's endpoint
says `-32600`. Only the hand-probe gives the right one. That is rule 4's whole case.

Since onchain 0.16.0 the one wrapper is `Onchain.RPC.base_fee/1` (the former
`Cartouche.RPC.base_fee/1`, renamed with the cartouche fold-in). It returns the final
`baseFeePerGas` of `eth_feeHistory(1, "latest", [])`: the next block's base fee, from a
method in every tagged spec release since beta.4, without the `pending` tag. On reth one
batch of `eth_baseFee`, that fee-history read and the pending header returned the same
value. Infura answers `eth_baseFee` with HTTP 200 and `-32601 "The method eth_baseFee does
not exist/is not available"`; Alchemy with HTTP 400 and `-32600`. Both serve fee history.
onchain 0.15's `Onchain.RPC.base_fee/1` (a pending-header read) is gone; 0.16.0 reuses
the name for the fee-history wrapper. The verbatim
refusals and the equality batch are in onchain-stack
`packages/onchain/docs/base-fee-portability.md`.

### Wording to reuse

House idioms, already established in the roadmap tasks — reuse verbatim rather than
paraphrasing:

- *"a real result or its real refusal, never a skip"*
- *"the consumer's node — not ours — as the case that matters"*
- *"the identical green run on both endpoints is what the portability claim rests on"*

### Honest limits

- **The multi-endpoint seam covers named portability tests only.** onchain's
  `rpc_portability_test.exs` runs `base_fee` against archive, Alchemy and Infura and
  flunks with export instructions when a hosted URL is missing. Most integration files
  still use the single-URL `Onchain.RPCCase.rpc_url!/0`, so any other portability claim
  still means re-running against a hosted endpoint by hand.
- **No CI in any repo** (`.github/workflows` is empty across the stack), so none of this
  is machine-enforced beyond local `mix ci`. Real enforcement is the reviewer reading
  `AGENTS.md`.


# OnchainTempo

Tempo blockchain primitives for Elixir. Extracted from MPP (Machine Payments Protocol) to provide standalone 0x76 transaction handling, TIP-20 encoding, RPC, and event parsing.

See the root `CLAUDE.md` for the family layout, the sibling/3 mechanism, and
the shared gate adjudications (reach #36, cowlib/gun, sobelow). This file
carries only what's specific to this package.

## Toolchain & check commands

Full post-merge QA: **`mix ci`** (= `mix precommit.full`), same shape as every
other package (root `CLAUDE.md` § Gates). Coverage floor here is **90%**
(`test.json --cover --cover-threshold 90 --exclude integration`, run under
`MIX_ENV=test` since `preferred_envs` in `def cli` is ignored inside alias
steps). `mix precommit` is the fast local loop.

- `mix ci` audits every native crate with `cargo audit` through the root shared
  helper. Vulnerabilities and offline fetch failures fail; warnings pass.
  Missing Cargo skips visibly; missing cargo-audit fails with
  `cargo install cargo-audit --locked`. See root Gates for the ignore policy.
- `.reach.exs` carries no `smells.ignore` entries — this package's smell pass
  is clean without any workaround.
- `deps.audit.gated` runs against `.mix_audit_ignore` (symlinked from the
  root file — see root `CLAUDE.md` § Adjudicated findings).

## Commands

```bash
mix test.json --quiet              # Unit tests (AI-friendly JSON)
mix test.json --quiet --failed     # Re-run failures
mix test.json --quiet --include integration  # + integration tests
mix dialyzer.json --quiet          # Type checking
mix credo --strict --format json   # Static analysis
mix sobelow                        # Security scanner
mix doctor                         # Docs/specs coverage
mix format                         # Auto-format (Styler)
```

## Architecture

This is a **library** (not a Phoenix app). It provides Tempo-specific blockchain primitives that any Elixir project can use.

### Module Map

```
OnchainTempo                       — Root module, Discoverable entry point
Onchain.Tempo.TIP20                — TIP-20 selectors, calldata encoders, DEX address
Onchain.Tempo.Transaction          — 0x76 struct, deserialize, payment matching, fee payer co-signing
Onchain.Tempo.Transaction.Builder  — Build + sign 0x76 transactions from scratch
Onchain.Tempo.RPC                  — broadcast_async/sync, fetch_receipt, parse_receipt, simulate (pre-broadcast eth_simulateV1)
Onchain.Tempo.Transfer             — TransferWithMemo event log parsing
Onchain.Tempo.Faucet               — Moderato testnet faucet (tempo_fundAddress) wrapper
```

### Node Portability (constrained, not portable)

The family-wide law is `node-portability.md` (`@`-imported above): our own node is a
privileged environment and consumers run something else. **This repo is the deliberate
exception to its rule 2** — and the exception has to be stated, not assumed:

- **Tempo-specific methods are the product here, not a portability bug.**
  `eth_sendRawTransactionSync` (`lib/onchain/tempo/rpc.ex`) and `tempo_fundAddress`
  (`lib/onchain/tempo/faucet.ex`) are Tempo protocol extensions; a generic Ethereum
  endpoint answers `-32601`. Wrapping them is correct. What rule 2 still demands is that
  you don't reach for an extension where a standard method would do — check first.
- **What varies for the consumer is *which Tempo endpoint*, not which chain.** Mainnet
  (4217, `https://rpc.tempo.xyz`) and Moderato (42431,
  `https://rpc.moderato.tempo.xyz`) do not serve the same surface: **the faucet is
  Moderato-only**. A new function must say which networks serve it, in its `@doc`.
- **`TEMPO_RPC_URL` is a real, consumer-visible override** read by
  `Onchain.Tempo.Faucet.rpc_url/0`. It was undocumented outside the source until
  2026-08-25; keep it in `README.md` § "Tempo Networks" if its behaviour changes.
- **The offline surface is the majority of the package** — `Transaction`, `Builder`,
  `TIP20`, `Transfer` need no node at all. Prefer growing that side; a new function that
  needs a live endpoint should justify why the work can't be done offline.

### Key Design Decisions

- **Signing uses the local secp256k1 backend directly** — `tempo-primitives` supplies the digest; `Onchain.Signer.Secp256k1.sign_payload/2` returns the signature and recovery bit. Sender recovery is native, with high-s normalization. `Onchain.Signer` handles EIP-1559 only.
- **TIP20 owns all selectors** — Single source of truth, eliminates duplication.
- **RPC uses plain errors** — `{:error, "message"}` not wrapped error structs.
- **Encoding belongs to tempo-primitives** — The separate `onchain_tempo` NIF owns transaction decoding, signing payloads, fee-payer hashes, and serialization. `Transaction` exposes typed named fields and signature unions; `Codec` is the internal JSON boundary. No public serde map or positional RLP field list is retained. ExRLP remains only in independent verification tests.

### Dependencies

- `onchain` — Core Ethereum utilities (RPC, ABI, signing, logs), via `sibling(:onchain, ...)`
- `req` — HTTP client for RPC calls
- `jason` — JSON encoding for RPC payloads
- `descripex` — Self-describing APIs
- `plug` — Required for Req.Test stubs (dev/test only)

### Tempo Network Chain IDs

| Network | Chain ID | RPC URL |
|---------|----------|---------|
| Mainnet | `4217` | `https://rpc.tempo.xyz` |
| Moderato (testnet) | `42431` | `https://rpc.moderato.tempo.xyz` |

### Dialyzer Notes

`.dialyzer_ignore.exs` carries exactly one entry: `~r/Function ExRLP\./`. ExRLP is transitive (onchain → cartouche → ex_rlp), used only from `test/support`, and transitive deps are not in the `:apps_direct` PLT — a false positive. Everything else (Jason/Req/Cartouche/Onchain/Descripex) resolves via the sibling/3 path branch since the monorepo; the standalone-era suppressions for those were pruned 2026-08-27. If a new unknown-function warning appears, regenerate the file wholesale rather than appending.

### Conventions

- Styler is the formatter plugin (runs automatically via `mix format`)
- `test/support/` is compiled in test env
- Integration tests live under `test/onchain/tempo/integration/`, tagged `:integration`, excluded by default. They self-fund fresh wallets via the Moderato `tempo_fundAddress` faucet RPC — no env var required. Override the endpoint with `TEMPO_RPC_URL`.
- All calldata functions accept raw binaries (20-byte addresses, 32-byte memos), not hex strings
- Error format: `{:ok, result} | {:error, String.t()}`

## Native build

`native/onchain_tempo` pins `tempo-primitives = 1.11.0`, with default features
disabled and only `std` + `serde`. Rust 1.95 or newer and a C/C++ toolchain
are required for source builds (aws-lc/commonware dependencies). No Tempo or
commonware dependency is added to the core ABI NIF.

`Onchain.Precompiled` supplies the shared targets and release naming.
`ONCHAIN_TEMPO_BUILD=1` forces a source build; a checkout without a checksum
also builds locally. Release assets belong under `onchain_tempo-v<VERSION>`.
Run `scripts/build-precompiled.sh`, have the human create the release with the
artifacts (never an agent; root CLAUDE.md publish step 10), then generate and
commit `checksum-Elixir.Onchain.Tempo.Native.exs` before publishing Hex.
The initial Tempo artifacts/checksum are not published by this change.

The native decoder adapts only the fee-payer-service `0x00` marker before
calling the upstream decoder: 1.11.0 emits this marker but its consensus
RLP decoder rejects it. All encodings come from upstream. Our signing remains Secp256k1-only. Decode, serialize, signing/transaction hashes,
fee-payer cosigning and sender recovery support all upstream signature types,
including P-256, WebAuthn and keychain V1/V2. Keychain recovery does not prove
on-chain authorization. Malformed signatures, incomplete calls,
and invalid validity windows now fail during decoding.

Focused verification (set `ONCHAIN_BUILD=1` if core release assets are unavailable):

```bash
cargo test --locked --manifest-path native/onchain_tempo/Cargo.toml
mix test test/onchain/tempo/verification/all_signatures_test.exs test/onchain/tempo/transaction_test.exs test/onchain/tempo/transaction test/onchain/tempo/verification/native_test.exs test/onchain/tempo/verification/differential_test.exs test/onchain/tempo/verification/property_test.exs
mix test test/onchain/tempo/integration/native_encoding_test.exs --include integration
mix check.dispatch
```

The live native test requires Moderato chain 42431, a working `tempo_fundAddress`
faucet, `eth_call`, `eth_getTransactionCount`, `eth_sendRawTransaction`, and
`eth_getTransactionReceipt`. Set `TEMPO_RPC_URL` to override the default.
It fails on unavailable setup. A plain run only verifies. The tracked evidence
files (`priv/verification/0x76/native_live_evidence.json` and
`all_signatures_live_evidence.json`: successful receipts plus a rejected
malformed envelope) are rewritten only with `ONCHAIN_TEMPO_RECORD_EVIDENCE=1`.
Do that deliberately and commit the files with the encoding change they prove.

See `docs/native-encoding-verification.md` for versioned parity and build evidence.

## 0.13 typed transaction contract

`fields` is removed. Use named integer quantities, binary addresses/data,
`:placeholder` for fee sponsorship, and typed atom-key maps for key authorizations.
`signature` is a tagged primitive or `{:keychain, version, user_address, inner}`.
The README carries the 0.11/0.12 migration table. Keep the upstream-field parity
test when adding fields or bumping tempo-primitives.

The ox oracle is pinned in `priv/verification/0x76/oracle/package-lock.json`.
Run `npm ci --prefix priv/verification/0x76/oracle` and then
`npm run generate --prefix priv/verification/0x76/oracle` to regenerate vectors.
The live native test uses Node.js plus that install to produce a fresh P-256
transaction and records `all_signatures_live_evidence.json`. Setup failures fail
loudly. `MIX_ENV=test mix run scripts/check-transaction-coverage.exs` grades
Transaction's 95% floor with focused tests.
