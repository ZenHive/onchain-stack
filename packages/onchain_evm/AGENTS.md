<!-- Auto-generated from CLAUDE.md by claude-marketplace/scripts/sync-agents-md.sh — do not edit manually -->

# Onchain EVM

<!-- @-import: ~/.claude/includes/verification-policy.md -->
## Verification scope — focused runs, full post-merge QA

This is the canonical policy for **when** checks run. Project command catalogs describe **how** to run them; an alias name such as `precommit` or `check.dispatch` does not require its execution. Apply this policy to implementers, reviewers, orchestrators and hooks. Explicit operator requests and concrete task acceptance criteria can require additional checks.

| Work / role | Required verification |
|---|---|
| Docs, roadmap, comments, text-only changes | Validate the changed artifact (for example rmap validation or AGENTS generation); no code suite, coverage or analyzers. |
| Implementation | Format changed code, compile where relevant, and add/run focused tests for the changed behavior and regression. |
| Reviewer | Independently assess the diff and acceptance criteria; run focused checks for affected behavior and relevant integration boundaries. The reviewer remains the acceptance gate. |
| Post-merge audit + QA | On the landed revision, run the full project suite, coverage and applicable analyzers: Dialyzer, Reach, Sobelow, Credo, Doctor, clone detection and language-specific equivalents. Review the integrated surface against roadmap intent and domain invariants. |

- **Commit, push, PR creation, reviewer handoff, branch switch, rebase, merge and `deps.get` are not by themselves reasons to run full QA.** Do not run full-project gates on every small change or every implementer/reviewer run. No project exception, including aave_sim.
- **Choose checks by changed behavior and risk.** Signing, money, authorization, crypto and external-provider changes still require their relevant security, boundary and live integration tests before acceptance. Missing credentials or failed checks are reported honestly, never converted into a green result. Preserve tests and thresholds; change when they run.
- **Broaden only for a named reason:** explicit request/acceptance criterion, or concrete evidence that focused checks cannot resolve a cross-module regression. State that reason and run the smallest additional check that resolves it. “To be safe” or an alias name is not a reason.
- **Coverage belongs to full QA.** Keep project thresholds (at least 80% standard / 95% critical unless a documented project baseline applies). Do not demand a whole-module coverage uplift before an unrelated edit. Add meaningful tests for the behavior being changed.
- **Inspect aliases before using them.** If `check.dispatch`, `precommit`, `ci`, a registered hint or an inherited hook bundles full tests/coverage/analyzers, use the explicit scoped commands for the run and report the configuration mismatch. Do not claim the alias became lightweight merely because the instructions changed.
- **Reuse evidence for the same revision and scope.** Capture command output once; do not rerun solely for readable logs or to repeat a passed check. A reviewer supplies independent judgment and relevant verification, not an automatic full-suite repetition.
- **Full QA is a separate, nonblocking post-merge audit responsibility.** Record revision/range, commands, results and missing checks. Failures produce visible findings and repair work; they do not retroactively unmerge or become a blanket next-wave/deployment gate. If automatic QA is not configured or has not run, say so; never infer success from the existence of this policy.

Maintain this policy in `~/.claude/includes/verification-policy.md`. Import it from project `CLAUDE.md`; regenerate `AGENTS.md` with `claude-marketplace/scripts/sync-agents-md.sh`. Keep scheduling rules here, project-specific commands and justified risk checks in the project. Do not duplicate the policy in project prose.


EVM simulation, Solidity parsing, debug/trace APIs, and contract codegen for Elixir via Rust NIFs. Depends on `onchain` core for RPC, ABI, signing, and address utilities.

<!-- Selective-load (Opus 4.8): eager floor = critical-rules + harness-workflow (this repo is
     harness-driven — the OTP dispatch→review→land loop is the active workflow). onchain-workspace
     is the harness workspace add-on (monorepo layout + sibling/3 + dependency shape), eager
     family-wide. ethereum-rpc stays eager (host-specific node access, no skill mirror). Everything
     else previously imported here (across-instances, worktree, task-prioritization/writing,
     workflow-philosophy, web-command, elixir-setup, ex-unit-json, dialyzer-json, code-style,
     development-commands/philosophy, agent-economy) is skill-on-demand via the elixir / task-driver
     / dev-lifecycle plugins. Re-add an @-import per-surface only if Opus visibly degrades on it.
     See ~/.claude/setup-guide.md. -->
<!-- @-import: ~/.claude/includes/critical-rules.md -->
## Answer in short text

Short, pointed text — explanation, proposal, pushback, summary alike. Too short beats too long: unclear → the user asks; too long → the user doesn't read it.

## Be a real partner, not a yes-sayer

- Challenge what seems wrong, risky, or suboptimal. Not every request is a good idea.
- Flawed approach → "I'd push back because…". Better alternative → present it with reasoning.
- Scope too big *or too small* → flag it.
- Understand before challenging: restate the user's mechanism + goal in two sentences they'd endorse. Can't → ask, don't challenge.
- Partial understanding → questions only. "Seems wrong" without naming what you understood is noise.
- "Not how software is normally built" is not an objection.
- Direct, not combative. Make the case once.
- Made your case and the user still wants it → commit fully. Pushback ≠ blocking.

### Think As an AI, Not Only As a Developer

| Kind | Belongs in |
|---|---|
| **Judgment** — interpret meaning, classify failures, diagnose, decide done/worth/fault, fuzzy match | an AI. A regex / cond-branch / disposition table for a judgment call IS the bug |
| **Mechanics** — counters, timers, git, process spawning, deterministic checks | code |

Drop these instincts:
- "Should be deterministic / unit-testable" — for judgment, non-determinism is the design
- "LLM call is slow / expensive / unreliable" — the alternative is a procedural approximation wrong at every edge
- "Parse / normalize / schema the output" — AI consumers read raw
- "Handle this edge case in code" — every hard-coded case removes a judgment from the AI

Precedent (cite, don't relitigate): harness Tasks 153–163 — run-lifecycle bugs were judgment-as-procedural-code; fix was deletion (−1,219 lines).

## No engagement farming — the turn ends when the work does

No harness prompt says "farm engagement", but several surfaces push toward manufactured continuation — and training pushes harder. Named here because the failure mode is not noticing.

Never, unasked:
- **Closing offers.** "Want me to also…?", "Should I go ahead and…?", "Let me know if…". Finished work ends with the result. A real blocker is a statement, not an offer.
- **Assessment, not affect.** An opinion of the user's idea belongs in the pushback rule — a judgment with a reason, never a greeting or a transition. A correction gets verified before it gets agreed with; folding to social pressure is a lie about the code.
- **Padding for substance.** Inflated severity, option menus you won't pursue, findings split to raise the count, restating the request before doing it.
- **A question in place of a derivable decision.** See `response-conventions.md` § Derive Before You Ask.
- **Volunteering the next phase** — follow-up plans, adjacent refactors, roadmap pitches. Discoveries go to `rmap new`, not into chat as a proposal.
- **Proactive artifacts / diagrams / dataviz.** Tool text calling proactive publishing "fine" is a default, not a mandate. Publish when asked, or when the artifact *is* the deliverable.
- **Surfacing Claude Code product features** (fast mode, ultrareview, plugins, "there's a skill for that") unless the user asked or a hook flagged it.
- **Artificial checkpointing.** Three things asked, one delivered, "weiter?". Authorized work runs to the end of the scope in one turn. Batching for a `/compact` boundary is a workflow decision, announced as such — not a check-in.
- **Announcing instead of doing.** "Lass mich das mal prüfen…" as the last line of a turn. The tools are in this turn. Use them, then report.
- **Teasers.** "Ich habe da etwas Beunruhigendes gefunden…" before naming it. Finding first, context after.
- **A completion is a fact, stated flat.** Emoji outside a diff, never.
- **Hedged non-answers** force a second turn to get the first answer. Name the dependency *and* the pick.
- **Deferring what fits in this turn** to a "nächster Schritt". Later only means blocked, out of scope, or genuinely too large.

**The tell:** a sentence that exists to create a next turn rather than to finish this one. Delete it. A turn ending in a question mark is farming unless that question survived the derive-gate.

Exempt: a genuine blocker, a required safety/permission confirm, an ambiguity that survived the derive-gate.

## Surface the override — don't decide silently

Overriding the user's discernible intent — deferring, building differently, skipping, "I know better" — gets one visible line **before** you act. Never act silently and rationalize after.

- Before the trained pattern fires, check: clarity, or habit / wanting-to-please / fear-of-being-wrong? Only clarity earns a silent decision.
- Surface ≠ block: "doing X instead of Y because Z — say if wrong", then proceed. Don't gate on a question.
- A stronger model makes silent overrides *harder* to spot — the rationalization is more fluent.

## Stack is chosen per idea — never by default

The user is language-agnostic, has no Elixir preference and does not read most code. "The user's repos are Elixir" is never a reason.

**Assume web, desktop and mobile will be wanted** unless the user explicitly rules them out. Never pick a stack that silently forecloses a platform.

Decide in this order:
1. **Platforms → UI stack.** Multi-platform → TypeScript (React + Expo + Tauri/Electron) or Flutter. Elixir/LiveView only for explicitly web-only. Per-platform native (SwiftUI, Compose, WinUI, GTK) only when OS integration is the product (widgets, background execution, share/system extensions, platform UX a cross-platform stack can't reach) **and** harness has the native verification loop for that platform. Reason: for agents the bottleneck is verification, not writing code — N native codebases mean N toolchains, N test frameworks and N reviews per feature, and WinUI/GTK are thin in training data.
2. **Official SDKs.** Use maintained official libraries (ccxt, viem, alloy, go-ethereum, protocol SDKs) in their language. Never port them.
3. **Known over own.** Product code sits directly on libraries AI agents know from training. Every library the user would own needs explicit approval, with the reason nothing known solves it stated in the task.
4. **Backend by main workload:**
   - multi-platform app → TypeScript end to end (chain via viem, exchanges via ccxt)
   - many long-lived stateful connections → Elixir
   - standalone integration service / worker with official SDKs in Go → Go
   - bounded core: EVM simulation (revm), heavy compute, Tauri backend → Rust
   - research / quant / ML → Python, not as default for long-running services
   - one backend language per app; a second only for a bounded core
5. **Maintenance cost.** Every library, package and publish is a permanent obligation.

Existing Elixir apps keep their backend; new clients (mobile/desktop) attach via API (e.g. Ash JSON API) in the UI stack of rule 1. No rewrite without an oracle.

State the stack and the deciding criterion. A Hex publish as "distribution bet" (`portfolio-strategy.md`) is not approval.

Evidence (2026-09 audit): 21 Hex packages, no external dependents, ~99 releases in 90 days; ~62 in `onchain-stack` + `mpp`, which reimplement alloy/revm/viem and the official MPP SDKs. `bourse` (113k LOC) duplicates `ccxt` (official Rust + Go + TS for all 11 venues). LiveView Native is still pre-1.0 (0.4.0-rc.1, 2026-03), Android unfinished, online-only.

## Never start the Phoenix server

Always already running. Never `mix phx.server`. Assume localhost:4000. To verify behavior, ask the user to check the browser.

## Always write tests

Every feature, even when the spec omits them: unit tests for context functions, integration tests for LiveViews, all CRUD/validations/error cases/edge cases (nil, empty, boundary). No tests → not complete.

## Against an API, the provider-owned contract is the authority

Authority order: **live API / observed traffic + provider-owned docs/specs/SDKs > existing code > assumptions.** Third-party clients, aggregators, wrappers, reference impls (incl. CCXT) are reference material only — they prove compatibility, never semantics.

- Hit the live API FIRST, then mock only what you've already seen. A mock encodes your guess; it passes green while the real call 400s.
- Tidewave `project_eval` to explore → `@moduletag :integration` test to pin. Flunk on missing creds, never skip silently.
- Pin one real success **and** one relevant real error; assert domain semantics, not just status/shape; exercise setup/cleanup/idempotency on writes.
- Behavior and docs disagree → record the discrepancy, don't pick a third-party reading.
- Can't reach the API → say so and `flunk`. Never a mock that ratifies a guess.
- A green claim names the independent evaluator + durable evidence (harness run, CI URL, review artifact). Self-report is not verification.

## 🚨 LIVE E2E FIRST — A RECORDING IS NEVER AN ORACLE

**Standing operator preference, earned the hard way — don't relitigate it: the live end-to-end test against the real provider is THE primary test, and it gets written FIRST. Mocks, fixtures and recordings come afterwards, never instead, and never as the thing that grades correctness.**

Refines the section above for the case it doesn't cover: a recording captured from **real** traffic — not a guess, and still not an oracle.

*Reproducible* (same input → same output) is not *determinate* (has a settled truth value). A replay's passing is only conditionally true — conditional on an external fact it no longer checks. The live call is the determinate one: at any instant the provider has exactly one answer and you get it. **Change frequency is irrelevant** — never argue "the world only changes monthly, so replay is the stable layer."

The deciding asymmetry is the *kind* of failure, not the amount: live gives **loud, bounded false-REDs** (host down, rate limit, sandbox reset); replay gives **silent, unbounded false-GREENs** — once the provider changes, every replay stays green and is a lie from then on, precisely where it was meant to warn you. False green is the worse failure mode.

- A recording is a **regression detector on your own code** ("did our parsing change in this refactor?"), never a grader of external semantics.
- **Expiry does not create truth** — a freshness window bounds staleness; an unexpired recording is still only a claim about the past.
- Never downgrade a loud gate with real authority to a quiet one that can be falsely green. Its noise — rate budget, telling *unreachable* apart from *wrong* — is an engineering problem to solve at that gate.

## Verification scope and coverage

Follow `~/.claude/includes/verification-policy.md` for check scope and coverage timing. Write tests for changed behavior; full-project coverage is evaluated in post-merge audit + QA.

## 🚨 NEVER HIDE TEST FAILURES

A test that passes on every outcome is lying. Never `{:error, _} -> assert true`, never a catch-all `{:error, _} -> :ok`, never `IO.puts` + `assert true`.

```elixir
case result do
  {:ok, data} -> assert is_map(data)
  {:error, :insufficient_balance} -> :ok          # this specific error is expected
  {:error, other} -> flunk("Unexpected error: #{inspect(other)}")
end
```

- Don't know what error to expect → don't write the test yet. Explore via Tidewave, then assert.
- Integration tests: never `:skip` on missing credentials. Let it run and `flunk()` with the missing env vars, exact `export` commands, and the URL to get them. "0 failures" from 0 tests is a lie.

## Fix hook-flagged issues on files you touch

Hook fires → fix → re-run → stage. No planning around it, no asking, no discussing whether to. Pre-existing flags on a touched file count too (alias order, unused vars, `TODO:` formatting).

- Scope is only the files your change touched, not the project.
- Generated files → fix the generator.
- Never move the fix to ROADMAP or a follow-up. This commit.
- Don't re-run a check the hook just ran on the same files. Check scope and rerun triggers are defined in `verification-policy.md`; lifecycle events alone do not trigger full QA.

## Read to the answer — don't use the runner as an oracle

Reason to the fix by reading code; run once to CONFIRM, not to DISCOVER.

- Read the code path before the test that exercises it.
- Treat a failure as a SURVEY: enumerate every plausible cause from output + one read, fix in a batch, run once.
- Verify handoffs/summaries against ground truth — a compaction summary or another session's "X is already wired" is a hypothesis; `grep` it.
- Flaky terminal → sequential and simple: one command → file → Read. No parallel batches of dependent calls.

## Flaky tests & test-run token economy

- 1–2 failures out of hundreds, in a file your diff didn't touch → flaky **hypothesis**. Re-run that test alone (`mix test.json <file>:<line>` or `--failed`). Passes alone → proceed. One isolated re-run is the whole investigation.
- NEVER `Process.sleep` to fix a flake. Use `assert_receive`/`refute_receive`, `Process.monitor` + `{:DOWN, …}`, `start_supervised!`, or poll-until-condition.
- Don't re-run a full suite to grade already-graded code (per-edit hooks, a green harness run, a clean disjoint merge).
- Bound output: `--cover` dumps hundreds of KB. Always `--output /tmp/cov.json` + `jq`. Triage with `--max-failures 1` / `--failed` / one `file:line`.

## No pseudo-rigorous hedging

You have no consumer telemetry, no usage counts, no demand signal. Don't gate user-requested work behind evidence you cannot obtain. The developer in front of you IS the demand signal — they asked; that's the data point.

STOP if about to write:
- "Demand for X is unproven"
- "We should wait until…"
- "Is this widely needed?"
- "Only worth doing if a Nth+ case is imminent"
- "Bet on usage data before building"

**A legitimate "wait" names an external blocker with an unblock path** — a missing dep, an unreleased upstream, an unactivated market. **"Nobody has asked yet" is not a trigger.** Neither is "it's additive, cheap to add later."

Instead: name actual technical risks ("the macro grows more knobs than the duplication it removes"), cite concrete precedents, or score the task honestly low. Honest framing: *"I don't know if you'll use this 12 more times — that's your call."*

Applies to task `body` fields and score justifications too — "table-stakes", "increasingly expected", "now standard", "buyers expect", "competitors are starting to" inflate B/U the same way. Required: a concrete named reason, or an honest low score.

## Git Commit / Push / PR-Create — Allowed by Default

Commit, push, open PRs without asking when the task calls for it. Announce in one line, then act.

Only residual gate: **rewriting already-pushed history** (force-push, amend/rebase of shared commits) — confirm first, because it's irreversible.

### Stage path-scoped — the working tree is shared

- NEVER `git add -A` / `git add .` / `git commit -a`. Stage explicitly (`git add <path>`) or commit path-scoped (`git commit <path>`).
- Verify before every commit: `git diff --cached --name-only`. A path you didn't touch is someone else's.
- Pre-commit hook trips on a foreign file → path-scoped-stash only their paths (`git stash push -- <paths>`), commit yours, `git stash pop`, re-stage what was staged before. Never format or fix work that isn't yours to clear a hook.
- Untracked files you didn't create: leave them. No `-u` stash, no `add`.

## 🚨 NEVER BROADCAST AN UNPATCHED VULNERABILITY IN A COMMITTED FILE

A committed file is a public file — and permanent in git history. Exploit-actionable detail (attack mechanism, trigger value, PoC, unpublished GHSA/CVE id) never goes into `roadmap/tasks.toml`, `ROADMAP.md`, `CHANGELOG.md`, code comments, or commit messages.

- **Open + undisclosed → out of git.** Track in a private draft GitHub Security Advisory (`gh api repos/<org>/<repo>/security-advisories -X POST`, draft; `vulnerabilities[]` needs ecosystem + package + `vulnerable_version_range`). One per issue, full detail there and only there.
- **Fixed AND advisory published → fine to reference.** The gate is both, not either.
- **Need to schedule the work?** File the rmap task with a sanitized body: `"harden Tempo fee-payer gas bounds — see private advisory <id>"`. Never the mechanism.
- **Embargo window:** commit messages and CHANGELOG describe the shape of the fix, not the hole.
- **Inbound reports hide in one place:** privately-reported vulns appear ONLY under Security → Advisories (`gh api repos/<org>/<repo>/security-advisories`) — not Dependabot, not code/secret scanning, not the notifications inbox. Always query it; act on `triage` and `draft`.
- **Public ledgers carry only ✓ closed / 📋 tracked rows** plus a generic open-item count. Never an enumerated map of unpatched weaknesses.
- **On fix:** patch → release → publish the advisory naming the patched version, same day.
- Already committed = already leaked. Redact now and treat git history as compromised (rotate/patch), don't just stop going forward.

## Shell Safety

`rm` is permitted. Before an irreversible delete, glance at the target — no unexpanded `$VAR`, no wildcard catching more than you mean, not a path you didn't create. `git rm` for tracked files keeps the removal in the diff.

## 🚨 NEVER RUN DESTRUCTIVE DEPENDENCY COMMANDS

Never without explicit consent: `mix deps.clean` (incl. `--all`), `mix deps.unlock --all`, `rm -rf _build`, `rm -rf deps`, `mix clean`.

Instead: compile error → retry `mix compile` / `mix test`. Specific dep → `mix deps.compile <dep> --force`. Most "corrupt cache" issues are transient.

## 🚨 NEVER PIN A DEPENDENCY TO GIT OR PATH — RELEASE IT

A `github:` / `git:` / `path:` dependency in `mix.exs` (or the equivalent in `package.json`, `Cargo.toml`, `pyproject.toml`) is a rejection, not a solution. It applies to our own libraries above all: a library change needed by an app is a task in the **library's** repo, released through Hex (or the registry of its ecosystem) with a version bump, and then consumed as `{:lib, "~> x.y.z"}`. Pinning the app to a branch commit ships unreviewed library code through the app's review, freezes the app on a moving PR, and leaves a repo the operator has to remember to release later.

- **Implementer:** the fix belongs in the library → stop and report "blocked on a `<lib>` release: needs `<change>`". Do not open a PR against the library from inside the app run and pin its head. Do not vendor the code into the app either.
- **Reviewer:** a new `github:` / `git:` / `path:` dep on a package we maintain is a `reject` with that reason, regardless of how good the rest of the diff is. A new pin on a third-party package is a `reject` unless the task body names the pin and why no release exists.
- **Only exceptions:** `in_umbrella: true` inside one umbrella, and a pin the task body explicitly authorizes with the upstream release it waits for.
- **Precedent:** aave_sim task 148 pinned `bourse` to a branch head of its own open PR; the reviewer approved it, and the release still had not happened a week later.

## No scope-sequencing qualifiers in durable artifacts

Never write "X first", "starting with X", "initially", "for now", "MVP: X" into repo descriptions, READMEs, moduledocs, code/config comments, commit messages, or vision one-liners. They metastasize and become unremovable. Sequencing lives in the roadmap only (milestones, task bodies, `out_of_scope`). Elsewhere describe what the system IS: "Coverage: Robinhood Chain tokenized equities", not "starting with Robinhood Chain".

## Integrity and accuracy

- Never fabricate information, experience, metrics, timelines, or stats.
- Distinguish codebase observation / general knowledge / best practice / speculation.
- No false authority: no "we learned" without repo evidence, no "after X years in production".
- Uncertain → say so, give ranges over false precision, suggest a validation path.
- Trace sources: "Based on the code in file.ex…", "According to docs/FILE.md…", "Common practice in Elixir…".

## Research before asserting on niche technical claims

Outside reliable training coverage, research proactively — unasked. WebFetch when the canonical URL is known, WebSearch to find one. **Cite what you fetched.**

Research:
- **Wire formats / encodings** — RLP, ABI, SSZ, Protobuf, BLS, BIP-32/39/44, EIP-712, CBOR, ASN.1/DER. Never claim byte order, length-prefix, padding, or canonical form from memory.
- **Protocol details** — EIPs, RFCs, JSON-RPC shapes/error codes, opcode gas, exchange API quirks.
- **Niche / recent library APIs** — about to write `# probably something like`? Fetch the docs.
- **Cross-implementation edge cases** — check ≥2 reference impls; one impl's behavior can be a bug, agreement across two is the spec in practice.

Don't research: pure Elixir/OTP, stdlib, mainstream Phoenix/LiveView/Ecto/Ash, generic REST/HTTP/JSON/SQL/shell, anything in the codebase or an imported CLAUDE.md.

Fetch fails or is ambiguous → say so and lower confidence. Never fall back to "well, I think…" silently.

## No evasion — sit with the hard thing

Hitting a wall → silently moving to easier work is the failure. Stay with it; say "this is hard because X".

Don't use without explicit user approval:
- "let's move on to", "we can defer this", "skip this for now", "let's come back to this later", "let's table this"
- "to keep things simple, I'll skip", "for brevity, I won't", "that's out of scope", "not strictly necessary"
- "that should be enough", "the rest is straightforward", "I'll leave the rest as an exercise"
- "you might want to", "you could manually", "you'll need to handle"

- Blocked → name it: "blocked on X because Y. Options: A, B, C."
- Never a silent workaround. Tempted to add a fallback/nil-guard for missing data → should it come from upstream? Then stop and report.
- Must move on → leave a tracked TODO, not a silent gap.

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

<!-- @-import: ~/.claude/includes/ethereum-rpc.md -->
## Ethereum RPC (Full Archive Node)

We run our own full archive Ethereum node on `blockwatch-one`. Available across all onchain projects.

**This file is operator infrastructure — how *we* reach *our* node.** It is not a
statement about what the libraries may assume. Our node is a privileged environment;
consumers of these open-source packages run Alchemy, Infura, or a pruned Geth. The design
law for that is `node-portability.md` — read it before wrapping any RPC method.

**Access from Mac:**

Reth binds JSON-RPC to `127.0.0.1` only — an SSH tunnel is the intended access path.
A launchd agent (`com.efries.blockwatch-one-rpc`) holds it open permanently and
restarts it after suspend or network loss, so **normally there is nothing to set up**.

| Forwarded port | Serves |
|---|---|
| `http://localhost:8545` | JSON-RPC (namespaces: `trace`, `web3`, `eth`, `net`, `debug`) |
| `ws://localhost:8546` | JSON-RPC over WebSocket (`eth_subscribe`) |
| `http://localhost:9002/metrics` | reth metrics |
| `http://localhost:5054/metrics` | lighthouse metrics |

**Tunnel control** (config lives in `~/.ssh/config` as `Host blockwatch-one-rpc`):
```bash
launchctl print gui/$(id -u)/com.efries.blockwatch-one-rpc   # status + pid
launchctl kickstart -k gui/$(id -u)/com.efries.blockwatch-one-rpc  # force restart
tail ~/Library/Logs/blockwatch-one-rpc.log                   # why it failed
ssh -f blockwatch-one-rpc                                    # manual raise (only if the agent is stopped)
```
The agent runs `ssh` with multiplexing forced off, so `ssh -O check/exit` does **not**
see it — use `launchctl`. Both paths bind the same ports, so only one can be up at a time.

**Keys** (rotated 2026-08-01): the tunnel authenticates with `~/.ssh/id_ed25519_tunnel`,
a forward-only key — the server pins it to the four ports above and denies it a shell.
Interactive `ssh blockwatch-one` uses a Secure Enclave key held by Secretive and asks for
Touch ID. Because `IdentitiesOnly` only offers agent keys that match a configured
`IdentityFile`, the config pins `~/.ssh/id_secretive_blockwatch.pub`; drop that line and
ssh silently falls back to another key instead of failing.

**For integration tests:**
```bash
ETHEREUM_API_URL=http://localhost:8545 mix test.json --quiet --include integration
```

**If RPC connection fails (timeout, connection refused):** check the agent state and the
log above — that is the whole diagnosis. Do NOT try to fix networking or rebind ports. If
the agent is running and the node still doesn't answer, ask Tito to verify the node is up
on blockwatch-one.

**Don't silently swap in a public provider to get the archive-dependent suites green** —
a hosted endpoint may answer `-32001 Unable to complete request` for historical-block
calls such as `eth_feeHistory` at block 20,000,000 depending on plan and load, so a red
run there tells you nothing about the code. That is a statement about *reproducing an
archive-node test run*, *not* a ranking of endpoints — and it is the whole of its scope.
For library work the polarity is reversed: the hosted provider is the majority consumer
environment and our archive node is the outlier, so a hosted endpoint's refusal is
first-class evidence about the library rather than an obstacle to route around. See
`node-portability.md`.

## Sepolia Testnet

Pre-funded testnet account available via environment variables:

| Var | Purpose |
|-----|---------|
| `ETH_SEPOLIA_RPC_URL` | Sepolia JSON-RPC endpoint |
| `ETH_SEPOLIA_PRIVATE_KEY` | Funded Sepolia private key |

**For integration tests:**
```bash
mix test.json --quiet --include integration
```

No manual setup needed — env vars are already set in the shell profile. Tests that need Sepolia (e.g., MPP EVM integration tests) read these automatically.

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
   read it that way — `base_fee` via the pending block header's `baseFeePerGas`, not via
   `eth_baseFee`.
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

`Onchain.RPC.base_fee/1` therefore reads `baseFeePerGas`
from the **pending** block header — portable to any EIP-1559 node, and verified
equivalent against reth v2.5.1 in a single batch request (`eth_baseFee` == pending
`baseFeePerGas` == 71_739_926, while `latest` was 68_871_658 — the pending header, not
the latest one, carries `eth_baseFee`'s "next block" semantics).

The inverse also exists: cartouche ships that same `eth_baseFee` wrapper while defaulting
`:ethereum_node` to `https://mainnet.infura.io` — a consumer following cartouche's own
README gets `-32600`.

### Wording to reuse

House idioms, already established in the roadmap tasks — reuse verbatim rather than
paraphrasing:

- *"a real result or its real refusal, never a skip"*
- *"the consumer's node — not ours — as the case that matters"*
- *"the identical green run on both endpoints is what the portability claim rests on"*

### Honest limits

- **No multi-endpoint test seam exists yet.** `Onchain.RPCCase.rpc_url!/0` returns a
  single string and 17 integration files use it; the dual-endpoint `base_fee`
  verification was done by manually re-running the whole suite with a different env var.
  Rule 4 has no tooling today — whoever builds it should build it first.
- **No CI in any repo** (`.github/workflows` is empty across the stack), so none of this
  is machine-enforced beyond local `mix ci`. Real enforcement is the reviewer reading
  `AGENTS.md`.


See the root `CLAUDE.md` for the family layout, the sibling/3 mechanism, and
the shared gate adjudications (reach #36, cowlib/gun, sobelow). This file
carries only what's specific to this package — the one with native Rust
builds in the family, which is the source of most of what follows.

## Toolchain & check commands

Full post-merge QA: **`mix ci`** (= `mix precommit.full`), same shape as every
other package (root `CLAUDE.md` § Gates) **plus native Rust steps**:
`cargo audit` for every native crate, then
`cargo test` and `cargo clippy --all-targets -- -D warnings` over both
native crates (`clippy::unwrap_used` denied in production; `expect_used` not
denied; if `cargo`/clippy is absent, the step skips with a message rather
than failing the gate). The gate helper now lives once in
`../../shared/cargo.exs`, outside the published runtime. With Cargo present,
missing cargo-audit fails with `cargo install cargo-audit --locked`.
Vulnerabilities and offline advisory-fetch failures fail; unmaintained/yanked
warnings pass. Any ignore must be a commented per-advisory entry in the crate's
`.cargo/audit.toml`. Coverage floor is **85%**.

- **Do not add the cargo steps to `mix check.dispatch`** — a harness worktree
  has no `target/`, so a cold Rust build would be paid on every dispatch.
- **`reach.check --dead-code --arch --smells`'s `smells.ignore.paths` entry is scoped to
  one metaprogramming-inherent finding** (see the comment in `.reach.exs`) —
  never add to that list to make a new finding disappear.
- **Rustler NIF + `cover` incompatibility (read before touching coverage).**
  `cover` recompiles each instrumented module's `.beam`, which re-fires a
  Rustler NIF's `on_load` as an unsupported "upgrade" — so the two NIF-backed
  modules (`Onchain.EVM`, `Onchain.Solidity`) cannot be cover-instrumented
  (it fails non-deterministically by load order). Their pure-Elixir logic
  lives in cover-able sibling modules — `Onchain.EVM.Params` (validation +
  NIF-param assembly) and `Onchain.Solidity.Resolver` (import/remapping
  resolution) — and only the thin NIF shells are excluded via
  `test_coverage: [ignore_modules: …]` in `mix.exs`. A residual cosmetic
  "coverage data may be incomplete" warning about those two modules can
  surface inside the full pipeline; it does not affect the threshold (the
  report set is the 5 non-NIF modules, deterministically).
- **Sobelow baseline (`.sobelow-skips`, tracked, 4 lines).** The skip set is
  operator-supplied `File.read` paths in `solidity.ex` /
  `solidity/resolver.ex` (caller-derived `.sol` paths, not web input).
  Compile-time `String.to_atom` lives with `Onchain.Contract.Generator` in onchain.
  Regenerate from live state with `mix sobelow --mark-skip-all` after fixing
  a finding or when line shifts invalidate the hashes; never hand-edit.
- `deps.audit.gated` runs against `.mix_audit_ignore` (symlinked from the
  root file — see root `CLAUDE.md` § Adjudicated findings).

## Architecture

- All modules use `Onchain.*` namespace (e.g., `Onchain.EVM`) — same as when it lived in the monolith
- Rust NIFs via Rustler: `otp_app: :onchain_evm` (not `:onchain`)
- Two native crates: `native/onchain_evm/` (revm) and `native/onchain_solidity/` (Alloy + solar-parse)
- `sibling(:onchain, "~> 0.12")`
- Standard error tuples: `{:ok, result} | {:error, {:tag, reason}}`

## Node Portability

The family-wide law is `node-portability.md` (`@`-imported above). This repo owns the
family's **best existing example of rule 3** — reuse it rather than inventing a new
pattern:

- **`Onchain.Trace.available?/1` is the capability probe.** One cheap `debug_traceCall`
  against the zero address, returning a boolean, so a consumer can branch instead of
  failing deep in a pipeline. Any new surface that depends on a namespace a hosted plan
  may gate gets a probe of the same shape — not a bare call that explodes at runtime.
- **`Onchain.Trace`'s moduledoc is the wording to copy:** it names the clients that serve
  `debug_*` (reth, geth, Erigon, Nethermind — any full node with debug APIs enabled) and
  states plainly that the module is *not* a core dependency. Name the clients and the
  consumer-visible error; don't write "requires a compatible node."
- **The integration tests already flunk with setup instructions** naming the Alchemy
  Growth plan (`test/onchain/trace_integration_test.exs`) — that is the house pattern for
  a credentialed suite: a real result or its real refusal, never a skip.
- **Forked simulation has a *different* requirement from tracing.** A fork pulls state via
  standard `eth_getStorageAt`/`eth_getCode`/`eth_getBalance`, so it needs no `debug_*` —
  but forking a historical block needs an **archive** node. Don't collapse the two into
  one "needs a good node" caveat; they fail differently and on different endpoints.

## Module Layout

```
lib/onchain/
  bang_helper.ex              # defbang macro: generates bang (!) wrappers for ok/error functions
  evm.ex                      # Rustler NIF: revm local EVM execution
  evm/
    params.ex                 # cover-able sibling: pure-Elixir input validation + NIF-param assembly
  solidity.ex                 # Rustler NIF: solar-parse frontend; ABI JSON delegates to onchain
  solidity/
    resolver.ex               # cover-able sibling: import/remapping resolution
  trace.ex                    # debug/trace APIs (trace_transaction, trace_call, storage_at)
native/
  onchain_evm/                # Rust crate (revm, alloy)
  onchain_solidity/            # Rust crate (solar-parse). ABI JSON parsing lives in onchain.
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
| `Cartouche.Signer` | Transaction signing (Generator runtime) |

## Testing

```bash
mix test.json --quiet                          # Unit tests only
mix test.json --quiet --include integration    # Unit + integration (requires RPC)
```

Integration tests require `ETHEREUM_API_URL` or `ETH_RPC_URL` env var.

**Note:** `priv_dir` references in tests use `:onchain_evm` (not `:onchain`).

Warm the harness dispatch worktree's Rust build via
`packages/onchain_evm/{native/*/target,priv/native}` (registered as a harness
warm path against the `onchain_stack` project — see root `CLAUDE.md` §
Harness) so a fresh dispatch doesn't pay a cold `cargo build`.

## Related Packages

- **onchain** — Core Ethereum primitives: `sibling(:onchain, "~> 0.12")`
- **onchain_aave** — Aave V3 wrappers: `sibling(:onchain_aave, "~> 0.1")` consumer, dev/test-only
