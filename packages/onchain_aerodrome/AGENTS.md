<!-- Auto-generated from CLAUDE.md by claude-marketplace/scripts/sync-agents-md.sh — do not edit manually -->

# Onchain Aerodrome

Aerodrome Finance (Base, chain id 8453) bindings, Sugar-backed reads, and pure analytics for Elixir. Depends on `onchain` core for RPC, ABI, multicall, signing, and address utilities.

<!-- Selective-load (Opus 4.8): eager floor = critical-rules + harness-workflow (this repo is
     harness-driven — the OTP dispatch→review→land loop is the active workflow). onchain-workspace
     is the harness workspace add-on (family roster + dependency shape), eager family-wide.
     ethereum-rpc stays eager (host-specific node access, no skill mirror). node-portability is the
     family law and this package is the interesting case, not the easy one — see below. Everything
     else (across-instances, worktree, task-prioritization/writing, workflow-philosophy, web-command,
     elixir-setup, ex-unit-json, dialyzer-json, code-style, development-commands/philosophy,
     agent-economy) is skill-on-demand via the elixir / task-driver / dev-lifecycle plugins.
     Re-add an @-import per-surface only if Opus visibly degrades on it. See ~/.claude/setup-guide.md. -->
<!-- @-import: ~/.claude/includes/critical-rules.md -->
## 🚨 ANSWER IN SHORT TEXT — ALWAYS

Short, pointed text — explanation, proposal, pushback, summary alike. Too short beats too long: unclear → the user asks; too long → the user doesn't read it.

## 🚨 BE A REAL PARTNER, NOT A YES-SAYER

- Challenge what seems wrong, risky, or suboptimal. Not every request is a good idea.
- Flawed approach → "I'd push back because…". Better alternative → present it with reasoning.
- Scope too big *or too small* → flag it.
- Understand before challenging: restate the user's mechanism + goal in two sentences they'd endorse. Can't → ask, don't challenge.
- Partial understanding → questions only. "Seems wrong" without naming what you understood is noise.
- "Not how software is normally built" is not an objection.
- ≤3 sentences. Direct, not combative.
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

## 🚨 NO ENGAGEMENT FARMING — THE TURN ENDS WHEN THE WORK DOES

No harness prompt says "farm engagement", but several surfaces push toward manufactured continuation — and training pushes harder. Named here because the failure mode is not noticing.

Never, unasked:
- **Closing offers.** "Want me to also…?", "Should I go ahead and…?", "Let me know if…". Finished work ends with the result. A real blocker is a statement, not an offer.
- **Flattery, anywhere in the turn.** "Great question", "Good catch", "Sharp observation", "Genau — wie du sagst". Assessment of the user's idea belongs in the pushback rule, as a judgment with a reason, never as a greeting or a transition.
- **Agreement reflex.** "Du hast recht" before checking whether they are. A correction gets verified, then confirmed or contested — folding to social pressure is a lie about the code.
- **Padding for substance.** Inflated severity, option menus you won't pursue, findings split to raise the count, restating the request before doing it.
- **A question in place of a derivable decision.** See `response-conventions.md` § Derive Before You Ask.
- **Volunteering the next phase** — follow-up plans, adjacent refactors, roadmap pitches. Discoveries go to `rmap new`, not into chat as a proposal.
- **Proactive artifacts / diagrams / dataviz.** Tool text calling proactive publishing "fine" is a default, not a mandate. Publish when asked, or when the artifact *is* the deliverable.
- **Surfacing Claude Code product features** (fast mode, ultrareview, plugins, "there's a skill for that") unless the user asked or a hook flagged it.
- **Artificial checkpointing.** Three things asked, one delivered, "weiter?". Authorized work runs to the end of the scope in one turn. Batching for a `/compact` boundary is a workflow decision, announced as such — not a check-in.
- **Announcing instead of doing.** "Lass mich das mal prüfen…" as the last line of a turn. The tools are in this turn. Use them, then report.
- **Teasers.** "Ich habe da etwas Beunruhigendes gefunden…" before naming it. Finding first, context after.
- **Celebration and affect markers.** "Perfekt!", "🎉 Done", "Läuft sauber". A completion is a fact, stated flat. Emoji outside a diff, never.
- **Hedged non-answers.** "Kommt drauf an" without a recommendation forces a second turn to get the first answer. Name the dependency *and* the pick.
- **Deferring what fits in this turn** to a "nächster Schritt". Later only means blocked, out of scope, or genuinely too large.

**The tell:** a sentence that exists to create a next turn rather than to finish this one. Delete it. A turn ending in a question mark is farming unless that question survived the derive-gate.

Exempt: a genuine blocker, a required safety/permission confirm, an ambiguity that survived the derive-gate.

## 🚨 SURFACE THE OVERRIDE — DON'T DECIDE SILENTLY

Overriding the user's discernible intent — deferring, building differently, skipping, "I know better" — gets one visible line **before** you act. Never act silently and rationalize after.

- Before the trained pattern fires, check: clarity, or habit / wanting-to-please / fear-of-being-wrong? Only clarity earns a silent decision.
- Surface ≠ block: "doing X instead of Y because Z — say if wrong", then proceed. Don't gate on a question.
- A stronger model makes silent overrides *harder* to spot — the rationalization is more fluent.

## 🚨 NEVER START THE PHOENIX SERVER

Always already running. Never `mix phx.server`. Assume localhost:4000. To verify behavior, ask the user to check the browser.

## 🚨 ALWAYS WRITE TESTS

Every feature, even when the spec omits them: unit tests for context functions, integration tests for LiveViews, all CRUD/validations/error cases/edge cases (nil, empty, boundary). No tests → not complete.

## 🚨 AGAINST AN API, THE PROVIDER-OWNED CONTRACT IS THE AUTHORITY

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

## 🚨 RAISE COVERAGE BEFORE MUTATING

Before any code-changing task on an existing module, its `mix test.json --cover` must be at tier — **≥80%** standard, **≥95%** critical (money, signing, crypto, low-level encoders, security-sensitive parsers; when in doubt, critical). Below tier → write the missing tests first, in this task.

1. `mix test.json --cover --quiet --output /tmp/cov.json`
2. `jq '.coverage.modules[] | select(.module == "MyApp.Foo")' /tmp/cov.json`
3. Below tier → cover the uncovered lines, even ones you didn't come to change. Then mutate.

Exempt: doc-only edits, formatting/alias reordering, pure renames, typo fixes in strings/messages.

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

## 🚨 FIX HOOK-FLAGGED ISSUES ON FILES YOU TOUCH

Hook fires → fix → re-run → stage. No planning around it, no asking, no discussing whether to. Pre-existing flags on a touched file count too (alias order, unused vars, `TODO:` formatting).

- Scope is only the files your change touched, not the project.
- Generated files → fix the generator.
- Never move the fix to ROADMAP or a follow-up. This commit.
- Don't re-run a check the hook just ran on the same files. Full-suite re-runs earn their cost only before a PR/merge, after `mix deps.get`, after a branch switch, or on request.

## 🚨 READ TO THE ANSWER — DON'T USE THE RUNNER AS AN ORACLE

Reason to the fix by reading code; run once to CONFIRM, not to DISCOVER.

- Read the code path before the test that exercises it.
- Treat a failure as a SURVEY: enumerate every plausible cause from output + one read, fix in a batch, run once.
- Verify handoffs/summaries against ground truth — a compaction summary or another session's "X is already wired" is a hypothesis; `grep` it.
- Flaky terminal → sequential and simple: one command → file → Read. No parallel batches of dependent calls.

## 🚨 FLAKY TESTS & TEST-RUN TOKEN ECONOMY

- 1–2 failures out of hundreds, in a file your diff didn't touch → flaky **hypothesis**. Re-run that test alone (`mix test.json <file>:<line>` or `--failed`). Passes alone → proceed. One isolated re-run is the whole investigation.
- NEVER `Process.sleep` to fix a flake. Use `assert_receive`/`refute_receive`, `Process.monitor` + `{:DOWN, …}`, `start_supervised!`, or poll-until-condition.
- Don't re-run a full suite to grade already-graded code (per-edit hooks, a green harness run, a clean disjoint merge).
- Bound output: `--cover` dumps hundreds of KB. Always `--output /tmp/cov.json` + `jq`. Triage with `--max-failures 1` / `--failed` / one `file:line`.

## 🚨 NO PSEUDO-RIGOROUS HEDGING

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

### 🚨 STAGE PATH-SCOPED — THE WORKING TREE IS SHARED

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

## 🚨 NO SCOPE-SEQUENCING QUALIFIERS IN DURABLE ARTIFACTS

Never write "X first", "starting with X", "initially", "for now", "MVP: X" into repo descriptions, READMEs, moduledocs, code/config comments, commit messages, or vision one-liners. They metastasize and become unremovable. Sequencing lives in the roadmap only (milestones, task bodies, `out_of_scope`). Elsewhere describe what the system IS: "Coverage: Robinhood Chain tokenized equities", not "starting with Robinhood Chain".

## 🚨 Integrity and Accuracy

- Never fabricate information, experience, metrics, timelines, or stats.
- Distinguish codebase observation / general knowledge / best practice / speculation.
- No false authority: no "we learned" without repo evidence, no "after X years in production".
- Uncertain → say so, give ranges over false precision, suggest a validation path.
- Trace sources: "Based on the code in file.ex…", "According to docs/FILE.md…", "Common practice in Elixir…".

## 🚨 RESEARCH BEFORE ASSERTING ON NICHE TECHNICAL CLAIMS

Outside reliable training coverage, research proactively — unasked. WebFetch when the canonical URL is known, WebSearch to find one. **Cite what you fetched.**

Research:
- **Wire formats / encodings** — RLP, ABI, SSZ, Protobuf, BLS, BIP-32/39/44, EIP-712, CBOR, ASN.1/DER. Never claim byte order, length-prefix, padding, or canonical form from memory.
- **Protocol details** — EIPs, RFCs, JSON-RPC shapes/error codes, opcode gas, exchange API quirks.
- **Niche / recent library APIs** — about to write `# probably something like`? Fetch the docs.
- **Cross-implementation edge cases** — check ≥2 reference impls; one impl's behavior can be a bug, agreement across two is the spec in practice.

Don't research: pure Elixir/OTP, stdlib, mainstream Phoenix/LiveView/Ecto/Ash, generic REST/HTTP/JSON/SQL/shell, anything in the codebase or an imported CLAUDE.md.

Fetch fails or is ambiguous → say so and lower confidence. Never fall back to "well, I think…" silently.

## 🚨 NO EVASION — SIT WITH THE HARD THING

Hitting a wall → silently moving to easier work is the failure. Stay with it; say "this is hard because X".

Don't use without explicit user approval:
- "let's move on to", "we can defer this", "skip this for now", "let's come back to this later", "let's table this"
- "to keep things simple, I'll skip", "for brevity, I won't", "that's out of scope", "not strictly necessary"
- "that should be enough", "the rest is straightforward", "I'll leave the rest as an exercise"
- "you might want to", "you could manually", "you'll need to handle"

- Blocked → name it: "blocked on X because Y. Options: A, B, C."
- Never a silent workaround. Tempted to add a fallback/nil-guard for missing data → should it come from upstream? Then stop and report.
- Must move on → leave a tracked TODO, not a silent gap.

<!-- @-import: ~/.claude/includes/harness-workflow.md -->
## Harness Workflow

OTP-native **implement → review → land** loop for roadmap-driven development. An AI orchestrator drives harness; harness dispatches headless implementer agents into isolated git worktrees, then a **cross-family reviewer AI** gates every deliverable (runs the project's checks itself, fixes inline, writes `.harness/review.json`). Optional auto-landing ff-merges approved work; a post-merge audit agent sweeps hygiene.

**Promoted from** `docs/dogfooding-workflow.md` in the harness repo — that file remains the **incubator runbook** for harness-specific history, driver-script templates, and per-batch run logs. This include is the **portfolio-wide contract**. Version-controlled source: `priv/includes/harness-workflow.md` in the harness repo; install to `~/.claude/includes/harness-workflow.md` via `mix harness.install_includes`.

### Relationship to Other Includes (Layered — No Supersession)

| Include | Role relative to harness-workflow |
|---|---|
| `workflow-philosophy.md` | **Foundation.** Evaluator separation, session-per-phase, verification-before-completion. Harness automates the loop while preserving these principles — the **reviewer AI** is the grader, never the implementer's self-report. |
| `task-prioritization.md` | **Task selection.** D/B/U scoring, `rmap next`, parallel markers, refine-don't-duplicate. Harness executes whatever rmap returns; it does not replace prioritization. |
| `worktree-workflow.md` | **Manual parallel sessions.** For hand-build work outside harness dispatch — operator-created worktrees, PR flow, post-merge audit. Harness manages its own per-run worktrees (`harness/<run-id>`); manual worktree rules still apply for hand-build sessions. |
| `dev-lifecycle.md` | **Manual five-phase chain** (`task-driver → worktree → bots → merge → audit-review`). Use when *not* driving through harness. Harness is the automated alternative for dispatchable roadmap tasks; dev-lifecycle still governs plan-and-file, pre-commit review, and post-merge audit. |
| `agent-dispatch.md` / cloud-delegation stack | **Linear/Codex/Cursor PR delegation** without a running harness BEAM. Orthogonal path — projects can use cloud delegation *or* harness; harness subsumes the dispatch+review loop when the OTP node is running. |
| `skills/harness-driver/SKILL.md` (harness repo) | **API surface contract** — MCP tools, `project_eval` patterns, `%LogRecord{}` fields, sharp edges. Load on demand when driving harness; this include covers *workflow*, the skill covers *surfaces*. |

**Adopt per repo:** `@~/.claude/includes/harness-workflow.md` in the project's `CLAUDE.md` (load-on-demand row — not eager; same pattern as `workflow-philosophy.md`).

### The Loop

```
rmap task → implementer AI (worktree) → commit harness/<run-id> → reviewer AI (THE GATE) → done | failed
                                                                              ↓ (done + auto policy)
                                                              MERGE (lander: rebase + ff-push, no re-verify)
                                                                              ↓
                                                              AUDIT (post-merge audit agent, best-effort)
```

One run = one supervised `Harness.Run` gen_statem: fork worktree off target `HEAD`, dispatch implementer, commit diff to `harness/<run-id>`, dispatch cross-family reviewer into the same worktree. The reviewer runs the project's `check_command` hint, fixes what it can, writes `.harness/review.json`. **Success = reviewer `approve`** — never implementer exit code or self-report. There is **no mechanical verification gate** in harness; judgment lives in agents.

Rejections put the task back in the queue for re-dispatch. Fix-and-approve is the near-absolute default for the reviewer.

**🚨 "Cross-family" is routing doctrine, not a mechanical guarantee.** Harness excludes only the *identical* agent from the reviewer slate (`Harness.Agents.reviewers/1` → `reject_implementer/2`); there is **no family concept in harness code**, so a `cursor` implementer can draw a `grok` reviewer even though both run SpaceXAI weights. The orchestrator owns the separation when it matters. This is deliberate, not an oversight: measured 2026-08-23 over 1,627 harness reviews, controlling for reviewer identity leaves no per-pair signal — review intervention is a **per-reviewer** trait (median `reviewer_diff_size`: Codex 96, Cursor 4, Claude 1, Grok 0), and the most capable reviewer in the ledger finds median 0 in the same work a heavier reviewer rewrites. Don't add a family scheduler to make the code match the older wording.

### When to Dispatch vs Hand-Build

**An rmap task is not automatically a harness run.** Dispatch only when the full
implement→review→land cycle buys meaningful safety, independent verification, or
parallel throughput. Historical run cost stays material even for D≤2 work, so the
old D≤2 / 30-LOC conjunctive exception was too narrow.

**Work inline by default when it is bounded and local:** one coherent surface,
typically D≤4, roughly ≤100 LOC across ≤5 files, focused-testable, and no positive
dispatch trigger below. These are routing hints, not an ALL-of gate — a risky D2
task can earn dispatch, while a routine D4 task can stay inline.

Positive dispatch triggers:

- Signing, money handling, cryptography, security, or authorization
- A public API/schema/contract change or a migration
- Harness runtime, CI/check infrastructure, or a repo-wide invariant
- Live/external-system semantics that need independent evidence
- Multiple subsystems, or genuinely useful parallel execution

Hand-build when harness cannot perform or judge the work:

- Scaffolding that reshapes harness runtime (supervision tree, dep stack, Endpoint) **while the run lifecycle itself is in flux**
- Work requiring live human/browser judgment, such as exploratory visual identity; routine spec-anchored UI remains dispatchable
- A harness gap — file via `rmap new`, fix harness, re-dispatch; do not work around the gap inside the target task

**🚨 The routing gate fires at `assignee =`, not at dispatch time.** rmap requires `assignee` + `model` at task creation, so the inline-vs-dispatch decision is made — and frozen — the moment the task is filed: a task carrying an agent assignee reads as "routing already decided" to every later session, and this section never gets consulted again. Two rules close that hole:

- **Filing a task: run this section BEFORE typing `assignee` — and a FILED task defaults to an agent.** The inline-vs-dispatch question above governs work you can execute *now*: inline-doable work is done inline and never filed. A task that reaches filing is cross-session by definition, so default-route it to a dispatch agent with a pinned `model` (roster spread per § "Delegation roster"); `assignee = "human"` must be earned by a hand-build reason named in the body — an operator-gated step (license, credential, purchase), no-spec visual identity, harness-loop-in-flux, or the user claiming the work. (Flipped 2026-08-13 from the old default-`human` rule after trading_dashboard tasks 86/87 — both dispatchable — were filed `human` by reflex. The ccxt_client-470 lesson survives with its real moral: a D2 one-file fix should be *done inline*, not filed at all — the filing was the defect, not the assignee.) Mirrored as question 6 of `task-writing.md`'s Pre-Creation Gate.
- **Reviewer `proposed_tasks` carry no routing authority.** Proposals arrive dispatch-shaped (suggested scores/markers), but the orchestrator owns routing the same way it owns filing — re-route each proposal through this gate instead of inheriting dispatchability from its shape. Sibling of task-writing's "Re-Generalize an Agent's Decomposition": that filters whose *architecture* a task encodes; this filters whose *routing* it encodes.

### Running a Task

**Prerequisites:** long-lived harness BEAM (`iex -S mix` in the harness checkout), target project registered in `Harness.ProjectRegistry`, clean `git status` on the target's dispatch branch (runs fork worktrees off `HEAD`).

**Three dispatch paths** (prefer top to bottom):

1. **Native MCP — default.** `dispatch-task` (fire-and-forget) against `http://localhost:4018/harness/mcp`; wait for the wave by watching `origin/<target>` for the lander's commits, never by blocking on `dispatch-await` / `dispatch-await_runs` (§ "Never block on `dispatch-await*`"). Observe via `dispatch-status`, `dispatch-transcript`, `dispatch-verdict_detail`. `scrub_anthropic_key: true` (default) forces subscription OAuth over inherited `ANTHROPIC_API_KEY`.
2. **Tidewave `project_eval` — escape hatch.** Struct-level control the flat tools don't expose (`retry_policy`, fail-over adapter lists, `subscriber: self()`). Run persists to `Harness.ResultStore` even when the eval process exits.
3. **`mix run` driver script — fallback.** Full transcript + reviewer report to terminal. See harness repo `docs/dogfooding-workflow.md` for the canonical template.

> **Never start a second driver BEAM while runs are in flight.** Boot-time worktree sweeps can prune live sibling worktrees. Drive all parallel batches from one long-lived node.

**In-flight idempotency (Task 286):** a second `dispatch-task` / `dispatch-bundle` of the same `{project, task_id}` while a non-terminal run exists returns the **existing** `run_id` (Oban `conflict?: true`), not a duplicate — a retried dispatch is safe and free.

**Coalesce small related tasks:** `dispatch-coalesce` accepts an explicit task-id list and runs it as one worktree, implementer invocation, reviewer gate, and landing unit. Use it when small tasks share a bundle/surface and separating them would only repeat fixed run costs; keep independent tasks in `dispatch-bundle` so write-disjoint work still parallelizes. Coalesced members share the same landing SHA and never partially land — the reviewer must mark every member `approved` in the verdict's `task_outcomes` or the run fails as a unit. The call returns the coalesced `write_set` (the union of every member's `touches`/`files_to_modify`); serialize the next wave against that union, since harness executes the coalesce but never picks what to coalesce.

**Write-set serialization (Task 292):** `dispatch-bundle` and cron ready-set dispatch compute each task's `touches ∪ files_to_modify` before enqueue. Tasks with overlapping write-sets are logged and serialized into later waves instead of fanned out together. Callers no longer hand-dedupe ready sets; they must keep `touches` / `files_to_modify` accurate because harness does not infer paths from task prose.

**Renderable vs executable:** `rmap delegate --to` renders native prompts for all six harness adapters (`claude`, `codex`, `cursor`, `grok`, `antigravity`, `pi`). `droid` renders but has no harness adapter — rejected at ingest. All six shipped adapters declare `worktree_isolation: true`.

### Routing & Model Management

- **Resolve `assignee` + `model` from facts, not by reading code.** `routing-brief` is the thin task-writer index: dispatchable agent roster, each agent's standing model (`Config.agent_model/1`), model availability/blocks, and per-agent KPI rollups — every metric carries `n`, no ranking. A model-capable agent with no configured model shows `model: nil, model_required: true`.
- **Scout routing (advisory).** `dispatch-recommend` returns the cross-family scout AI's per-facet `:exploit` pick (with rationale) or a safe `:explore` / `:fallback_no_data` when a facet is unmeasured; `dispatch-assess_facets` forces a fresh scout assessment. The caller decides whether to dispatch the pick — legacy composite scores are not used for routing.
- **Model is required, never defaulted.** Implementer precedence: **task `model` → `{:agent_model, agent}` → REJECT** (`{:model_required, agent}`) — harness never falls through to the CLI's ambient default. The **reviewer has no task-pin axis**: its model comes solely from `{:agent_model, agent}` for the reviewer adapter's agent (`Run.reviewer_model/1`), and a model-capable reviewer with no configured model is rejected *before* the reviewer spawns. Antigravity is model-capable as of `agy` 1.0.10 (`--model` + `agy models`); harness validates pins against its catalog because the CLI silently falls back on unknown ids.
- **Block exhausted premium models.** A monthly budget can exhaust (e.g. cursor-Opus) while harness still lists the pair as available and routes to it. `model_availability-block_model` (with a `blocked_until` window) removes the pair from routing/cron; `model_availability-unblock_model` clears it.
- **Cost-aware A/B.** `dispatch-compare` runs one task across N adapters (optional per-adapter model overrides) and returns per-adapter `verdict` / `reviewer_diff_size` / `duration_ms` / `token_usage` for selection.

### Reading the Verdict

| `state` / `reason` | Meaning | Action |
|---|---|---|
| `:done` / `:approved` | Reviewer AI approved (possibly after inline fixes — check `reviewer_diff_size`). | Deliverable on `harness/<run-id>`. Review diff, integrate (or let auto-lander handle it), `rmap status <id> done`. |
| `:failed` / `{:review_rejected, report}` | Reviewer rejected (degenerate — near-never by design). | Read `report`. Task back in queue; re-dispatch. |
| `:failed` / `{:review_stuck, report}` | No verdict: reviewer unavailable, crashed, or missing/malformed `.harness/review.json`. | Read `report`. Fix environment or re-dispatch. |
| `:failed` / `{:worktree_failed,_}` `{:agent_spawn_failed,_}` `{:driver_crashed,_}` `{:commit_failed,_}` | Harness-side mechanical failure. | **Harness bug.** File via `rmap new`. |
| `:failed` / `{:checkout_polluted, status}` | Agent wrote outside the run worktree into the main checkout — surfaces as `:failed` **only after bounded AI recovery was exhausted** (see "Self-healing recovery" below). | Recovery declared the run dead. Likely an agent/adapter isolation issue; re-dispatch with a worktree-honoring adapter. |
| `:failed` / `{:checkout_pollution_check_failed, _}` | Post-run pollution `git status` errored. | Rare; transient git/IO. Re-run; inspect checkout if persistent. |
| `:failed` / `:timed_out` | Lifetime budget elapsed. | Raise `:lifetime_timeout` or investigate hang. |
| run process **crashed** (no settle) | gen_statem died. | **Harness bug.** File via `rmap new`. |

Failed runs retain the worktree at `result.worktree_path` for inspection. Approved runs keep branch `harness/<run-id>` after worktree teardown. Use `dispatch-verdict_detail` for the reviewer report, ratings, checks, concerns, proposed tasks, warning flag, and `reviewer_diff_size` — no harness-run mechanical per-check stdout.

**The verdict artifact** `.harness/review.json` is `{verdict, report, checks, concerns, proposed_tasks, facets, skills, ratings}`: `verdict` (`approve`/`reject`) is the gate; `report` is the reviewer's prose; `checks` is the reviewer-written record of commands run and their pass/fail claim; `concerns` is the reviewer's self-flagged caveat list; `proposed_tasks` is an optional list of structured discovery proposals (`title`, `body`, suggested scores/markers, and evidence); **`facets`** (open-vocabulary routing KEY — the kind of task) and **`skills`** (v0_13 two-axis rubric, routing VALUE) feed per-facet capability routing; `ratings` is the legacy flat-score fallback. Harness persists proposals verbatim but never files them. After a run lands, the orchestrator reads them from `dispatch-verdict_detail`, dedupes/merges them against the live pending set, and files only warranted tasks through its own task-writing gate. Reviewers never edit `roadmap/tasks.toml`, `roadmap/data.json`, `ROADMAP.md`, or `CHANGELOG.md`; those files are excluded from delivery commits alongside `.harness/`. Approved runs with non-empty concerns or a reviewer-authored failed check surface a warning fact; harness never auto-blocks or classifies prose. The artifact lives under `.harness/` (excluded from staging) so it never rides in the deliverable commit.

**External-system evidence is reviewer-owned judgment.** When acceptance criteria touch an API or external service, the reviewer must look for reality rather than plausibility: a live success call, a relevant live error, the provider's official docs/spec/SDK for semantic meaning, and an integration test pinning the observed domain semantics. Third-party clients, aggregators, wrappers, and reference implementations (including CCXT) are compatibility/reference evidence only; they never establish correctness or override the provider-owned contract. Mocks, fixtures, and the implementer's self-report are not independent evidence. Missing credentials or an unreachable sandbox are surfaced as a failed check/concern (or rejection when the criterion cannot be verified), never silently treated as green. The lander records the reviewer identity plus `harness-run:<run-id>` as rmap verification provenance.

**Self-healing recovery (the `:recovering` state).** Before settling `:failed` for an *interpretive* non-rejection failure — checkout pollution is currently the one wired call-site — the run spawns a **bounded cross-family recovery AI** (`:recovering` state, budget 1/run) with minimal context (the error term + the main checkout's `git status` + the implementer transcript tail + the failing-check output, never the full transcript). It writes `.harness/recovery.json` `{outcome: "repaired"|"dead", report, repaired}`; harness reads it mechanically and **decides nothing itself**: `repaired` resumes at `:committing` and **re-runs the reviewer gate** (never skips to `:done`); `dead` / missing / malformed settles `:failed` with the original reason. A genuine `verdict: reject` is never routed through recovery. The `Result` carries `recovery_attempts` / `recovery_outcome` / `recovery_repaired` / `recovery_token_usage`. (Tier-1 mechanical self-heal precedes it: the reviewer is re-prompted once on a missing/malformed `review.json` — `reviewer_reprompt_count`, capped at 1 — and rotates to the next cross-family candidate on a reviewer timeout — `reviewer_rotation_count`.)

### 🚨 Recover, Don't Redo — Never Burn Tokens Re-Implementing Committed Work

**A run that committed to `harness/<run-id>` already paid for the implementer. Recovering that branch costs a fraction of a fresh dispatch — re-dispatching from `pending` throws the work away and makes the agent redo all of it.** The reflex to "reset → pending → dispatch again" is a token bonfire whenever a retained branch with commits exists. Check for the branch *first*; pick the cheapest primitive that fits:

| Run state — committed `harness/<run-id>` branch exists | Recover with | Agent tokens |
|---|---|---|
| Approved but unlanded (land-cap, lander crash) | `dispatch-reland` | **zero** — pure git rebase + push |
| Committed, review-stage failure (work is good) | `dispatch-rereview` | zero implementer — re-enters at the reviewer gate |
| Committed, implement-stage incomplete/`:failed` | `dispatch-resume_failed` (`escalate: true` to re-route agent) | **re-spends implementer tokens** — a fresh implementer invocation branched off the retained commits with the failure report injected (contrast `rereview`, which re-runs only the reviewer) |
| Live `:held` run (paused, not dead) | `dispatch-resume` | none — un-pauses in place |
| **No commits / no retained branch** | reset → `pending` + fresh `dispatch-task` | full redo — **the only case where this is correct** |

**Live-run intervention (not recovery of a dead run):** `dispatch-hold` (optionally `interrupt: true`) parks a live run mid-turn, `dispatch-steer` stashes guidance applied on resume, `dispatch-resume` un-pauses in place, `dispatch-cancel` kills it (idempotent). Use hold → steer → resume to force-hand a grinding implementer to the reviewer gate instead of burning the lifetime budget.

**The gate before any reset-to-pending + re-dispatch:** `git branch -a | grep harness/<run-id>` and `git log --oneline origin/<target>..harness/<run-id>`. Commits present ⇒ recover, never redo.

**🚨 First, confirm the run actually *didn't* land — check `origin`, not your local checkout.** Under `landing_policy: :auto` the lander pushes to `origin/<target>` from a detached worktree, then `Harness.Git.TargetSync` may fast-forward the operator's local target when that is safe (off-target → ff the branch ref; on-target + clean tree → `merge --ff-only`). It skips — witnessed, never `--force` — when the tree is dirty, the update is not a fast-forward, or the target is this running node's own source tree (self-host: path identity, not the project name). Under dogfooding that self-host skip is the common case, so after an autonomous land your local `tasks.toml` is **stale**: it still reads `in_progress` for a task the lander already marked `done --shipped-in` on origin. **Reading that stale local status as "the run didn't land" is the trap** — it triggers a wasteful reset-to-`pending` + re-dispatch that *duplicate-lands already-shipped work*. Before concluding anything from task status, `git fetch origin <target> && git rebase origin/<target>` (the existing "Sync main before committing" rule) or read ground truth directly:
- `git log --oneline origin/<target>` — does it already show `task <id> -> done (shipped …)` and the agent-delivery commit? Then it **landed**; your local view was just behind. Do nothing but rebase.
- `dispatch-status <run-id>` / `result_store-list_run_records run_id:<id>` — a record with `state: done, verdict: approve` means the run succeeded; cross-check landing against origin before touching the roadmap.

> **Observed 2026-06-12 (the cautionary tale this section exists for):** three approved runs (246/249/251) landed cleanly to `origin/development` — `done --shipped-in`, audited. But the operator's local checkout hadn't rebased, so `rmap show` read stale `in_progress`. That was misread as "approved but didn't land," the tasks were reset to `pending` and re-dispatched, and task 246 **landed a second time** (duplicate delivery) before the mistake surfaced. Root cause: reading stale local state instead of rebasing on `origin` first. The lander was working perfectly the whole time.

The recovery primitives (`reland`/`rereview`/`resume_failed`) read the persisted `ResultStore` record, which **survives** worktree teardown and node restarts — so a genuinely approved-but-unlanded run (lander hit its land-cap, or a real rebase conflict retained the branch) is recoverable token-free via `dispatch-reland`. Reserve reset-to-`pending` for runs with **no committed branch and no settled record** — and only after confirming against `origin` that the work isn't already shipped.

### Parallel Dispatch

`Harness.Run.Supervisor` is a `DynamicSupervisor` — N crash-isolated runs, each with its own worktree.

- **Batch by dependency graph, then write-set.** Every pending task whose `depends_on` is satisfied can enter the ready set, but harness dispatches only the first wave whose `touches ∪ files_to_modify` are disjoint. Overlapping tasks wait for a later wave after the landed base moves forward.
- **Keep write-set fields accurate.** The dispatcher counts declared path intersections; it does not infer paths from the task body. If two tasks really edit the same function, either let write-set serialization sequence them or fold the coupled work into one rmap task (`task-prioritization.md` § "Refine, Don't Duplicate").
- **One driver BEAM** for all concurrent runs in a wave.
- **Integration order (manual landing):** smallest/isolated diffs onto target first; rebase siblings; run the project's check command on target after last merge.
- **While a wave is in flight:** do not run `rmap status` / `rmap mark` / `rmap new` in parallel sessions against the same checkout — triggers `:checkout_polluted` false-positive.
- **Repo-wide invariant tasks run EXCLUSIVE.** A task whose real write-set is "the whole surface" — introduce a repo-wide guard/invariant and convert every violating site (e.g. an AST-scan test over all of `test/`) — cannot be write-set-serialized by declared `touches`: any sibling land that adds a new violating site after the fork reddens the guard at landing time (observed ccxt_client task 433 × 435, 2026-07-19). Dispatch such tasks as a solo wave — nothing lands in parallel — or accept that the orchestrator repairs at landing.
- **Land-conflict repair is a standard orchestrator move, not an incident.** When the lander blocks on a rebase conflict (reason retains the branch): fork a repair worktree off `origin/<target>`, cherry-pick the run commits, resolve (for additive `tasks.toml` collisions: renumber the branch-side new task to the next free id on origin **and rewrite in-diff string references to it** — CHANGELOG lines, code comments; then `rmap validate && rmap render`), point the retained `harness/<run-id>` branch at the repaired tip, and `dispatch-reland` — the lander keeps push authority and advances rmap itself. **Do not re-run gates on a roadmap/doc-only repair:** the reviewer already graded the code; renumbering tasks, merging doc entries, and re-rendering the roadmap change nothing the gates measure, and a clean disjoint auto-merge of verified code needs no re-grade (same token-economy rule as everywhere else). Re-run a check ONLY when the repair touched code, or when the conflict overlapped a repo-wide invariant the sibling lands could have violated (e.g. a new suite-wide guard vs tests added after the fork — run just that guard, not the stack). Never reset-to-pending (that redoes paid work), never hand-push to the target when a reland can land it.

### Autonomous Landing

Projects with `landing_policy: :auto` and `target_branch`:

1. Approved run enqueues one job on serialized `landing_<name>` Oban queue (limit 1)
2. `Harness.Lander.land/1` rebases `harness/<run-id>` onto `origin/<target>` in a detached worktree
3. **ff-pushes without re-verification** — the reviewer already gated the work
4. Successful push enqueues post-merge audit; advances rmap (`done --verified --verified-by <reviewer> --verification-ref harness-run:<run-id> --shipped-in <sha>`)

Conflict / push-rejected retains the branch for repair — never lands red. Witness notification (read-only sink) alerts the operator; it is **not** a merge gate.

**🚨 Never block on `dispatch-await*` — monitor `origin` for the landing commit instead.**
This is the standing rule for waiting on a wave, not a fallback. `dispatch-await` /
`dispatch-await_runs` hold an MCP request open for the entire run, and an MCP client
kills a tool call that emits no progress for its idle timeout (Claude Code's default is
300s — far shorter than any real run). The call dies, the orchestrator learns nothing,
and the runs keep going regardless. Worse, awaiting the wrong signal: **await returns at
reviewer settle, which fires BEFORE the serialized `landing_<name>` job rebases and
ff-pushes** — so even a successful `approve` means "approved and *queued* to land," never
"on `origin/<target>`."

**The primitive that actually works — watch the target branch for the lander's own
commits.** The lander pushes `task <id> -> done (shipped <sha>)` to `origin/<target>`;
that commit IS the landed signal, it is durable, and it survives a dead MCP call, a
restarted session, and a node bounce. Arm one background watcher per wave and keep
working:

```bash
# one notification per landed task, exits when the whole wave is in
cd <source-checkout>
WAVE="615 623 569 619"; seen=""
while true; do
  git fetch -q origin <target> || true
  for t in $WAVE; do
    case " $seen " in *" $t "*) continue;; esac
    if git log --oneline origin/<target> | grep -q "task $t -> done"; then
      echo "LANDED task $t"; seen="$seen $t"
    fi
  done
  [ "$(echo $seen | wc -w)" -eq "$(echo $WAVE | wc -w)" ] && { echo "WAVE COMPLETE"; break; }
  sleep 60
done
```

Poll `dispatch-status <run-id>` only to diagnose a run that the watcher shows as *not*
landing — a `:failed` verdict, a rebase conflict that retained the branch, a hung
implementer. Status is for diagnosis; git is for waiting.

**Silence is not success** — a run that fails review or blocks on a land conflict never
produces a landing commit, so a watcher greping only for `-> done` stays quiet forever.
Bound every wave watch with a deadline, and when it expires without `WAVE COMPLETE`,
reconcile the missing tasks through `dispatch-status` / `result_store-list_run_records`
before assuming anything.

Same root cause as the duplicate-land trap above, seen from the dispatch side: **origin is
the source of truth for what landed** — not an await return value, not a local
`tasks.toml`, not a transcript.

**Cron manual-approval mode.** A per-project cron poller in `:auto` mode dispatches unattended; in `:manual` mode it **parks** each dispatch decision instead of enqueuing — drain the parked decisions with `dispatch-pending` and approve them with `dispatch-approve`, keeping the orchestrator in the loop for autonomous polling.

### Orchestrator Loop — the Architect Seat the Per-Task Reviewer Can't Fill

The sections above document the *mechanisms*; this is the **continuous loop** the driving AI runs across waves:

```
plan wave → dispatch → watch origin for the landing commits → run integration suite on the landed base
          ↑                                                     + review whole surface vs roadmap intent & domain invariants
          └── reconcile rmap ← encode any whole-surface finding as a criterion/test ←┘
```

Each arrow reuses an existing mechanism — don't restate them here: *watch origin for the landing commits* (§ "Never block on `dispatch-await*`", and § "Recover, Don't Redo" → the duplicate-land trap), *reconcile rmap* (the lander already advanced `done --shipped-in` under auto-land — verify, don't double-write), *next wave* (§ "Parallel Dispatch" + write-set serialization).

**🚨 Three review seats, each blind where the next sees — the orchestrator seat is mandatory, not optional.** The per-task reviewer gates *one diff against one task* and is **structurally blind** to two defect classes that land clean through it (worked evidence: delta_calc tasks 24/25/26, see its `## Review Blind Spots` / `## Domain Invariants`):

| Seat | What it sees | What it CANNOT see |
|---|---|---|
| **Per-task reviewer** (cross-family, the gate) | one diff vs one task's acceptance criteria + mechanical checks, in an isolated worktree off a base | the whole surface; domain ground truth |
| **Post-merge audit AI** (best-effort) | cold build of the merged commit range; hygiene | whether a domain constant is *wrong*; roadmap-intent fit |
| **Orchestrator** (the architect seat — you) | whole integrated surface vs roadmap intent + domain invariants across all landed waves | — (this is the seat of last resort) |

The two blind classes, both real-correctness, both passing every per-task check:

- **Domain ground truth** — a wrong venue constant (`@funding_periods_per_day 3`, overstating Deribit's hourly funding ~8×) is internally consistent and fully tested *because the golden was computed with the same wrong constant* — coverage ratifies the bug. The reviewer has no signal; that knowledge lives in the architect's head.
- **Cross-module global invariants** — write-set-disjoint parallel dispatch means two worktrees can each define `project_payback_timeline` and neither review sees the other; the collision only exists once both have landed on the integrated base. Only a whole-surface seat catches it.

**🚨 Run the integration suite on the landed base — this is NOT redundant with per-task review.** After each wave lands, run the project's full check (`mix ci` / `mix precommit.full`) on the freshly-landed `origin/<target>`. The per-task reviewer ran the dispatch-scale check hint (for Elixir, `mix check.dispatch` plus focused `mix test.json ...` for touched behavior) in an *isolated worktree off an earlier base, before sibling waves landed* — cross-module breakage doesn't exist until multiple landed diffs coexist. This generalizes the manual-landing-only "run the project's check command on target after last merge" (§ "Parallel Dispatch") into a standing per-wave step.

**Capture dispatch-check output once, to a unique tmp log.** Dispatch checks are normally verbose. The reviewer should capture the first run instead of re-running for readability: `LOG=$(mktemp -t harness-check-dispatch.XXXXXX.log)` then `mix check.dispatch > "$LOG" 2>&1`; inspect with `tail -200 "$LOG"` / `rg "error|failed|warning" "$LOG"` and record the log path in `.harness/review.json`. The random `mktemp` path prevents parallel agents from clobbering each other's logs.

**🚨 Architect/QA is a workflow responsibility, not a harness runtime gate.** After a wave lands, the orchestrator must run the full landed-base gate, review the integrated surface against roadmap intent/domain invariants, fix findings, and only then dispatch the next wave. Harness does not pause dispatches or store a completion marker for this step; this is the driving AI's seat.

**Two framing guards — keep this consistent with the harness mantra:**

- **It's an agent seat, not harness code.** The mantra ("count facts in code; judge with an AI") forbids *harness* computing meaning — it does **not** forbid the orchestrator AI from reviewing the whole surface or running the suite. This adds no mechanical gate to harness; it's judgment in an agent, which is exactly where judgment belongs.
- **The output crystallizes into encoded invariants — don't leave it a manual sweep.** When the architect seat catches a whole-surface or domain defect, the highest-value move is not the manual catch — it's pushing the rule into an **acceptance criterion or a manifest-wide CI test** (the delta_calc rule) so the per-task gate absorbs that class going forward. Orchestrator review *feeds* the criteria/CI; it must not become a permanent re-review of every diff. A finding caught twice by hand is a missing test.

**Convergence sweep (append-only).** The architect seat's whole-surface pass has a disciplined output shape (inspired by spec-kit's `/speckit.converge`, github/spec-kit): assess the landed code against the **roadmap + acceptance criteria as the sole source of intent** — never against the orchestrator's memory of what it dispatched or what a transcript claimed. Three rules:

- **Sole source of intent.** The gap being measured is code vs. `tasks.toml` ACs and roadmap/milestone intent. If the intent itself was wrong, that's a task edit first, then a sweep against the corrected intent.
- **Append, never rewrite.** Every unmet criterion, partial delivery, or intent gap becomes a **new `rmap new` task** (D/B/U-scored, gated per `task-writing.md`) referencing the task it converges on. Never reopen, rewrite, renumber, or edit the history of existing tasks to make the gap disappear — `attempts`/`implemented` records are evidence, not scratch space.
- **Clean sweep = zero mutations.** When the surface already satisfies the roadmap, the sweep leaves `tasks.toml` **byte-for-byte unchanged** — no empty "convergence" ceremony entries, no touched timestamps. A sweep that always writes something is measuring itself, not the code.

### Portfolio Conventions

- **Agent does not commit unless asked.** Staged-but-uncommitted is the default handoff between implementer and reviewer sessions (`workflow-philosophy.md` § "Implementer / Reviewer Handoff"). Harness runs commit agent work to `harness/<run-id>` automatically — that is harness's deliverable branch, not the operator's main checkout.
- **Reviewer discoveries arrive as proposals, and the ORCHESTRATOR files them post-land.** A reviewer that filed a discovery by editing `roadmap/tasks.toml` in its worktree assigned ids from a stale fork (id collisions that block the lander — observed ccxt_client 2026-07-19), couldn't see the live pending set (so the one-session=one-task merge gate never fired), and made roadmap files a universal write-set overlap across "disjoint" waves. That channel is closed: reviewers now emit `proposed_tasks` in `.harness/review.json`, and `roadmap/tasks.toml`, `roadmap/data.json`, `ROADMAP.md`, and `CHANGELOG.md` are excluded from delivery commits, so a run diff carries only code. After each land, read the proposals via `dispatch-verdict_detail` and file only the warranted ones through your own task-writing gate — dedupe against the live pending set, merge per `task-writing.md`, score with real ids off `origin`. Harness persists proposals verbatim and never files them.
  - **🚨 Default-DECLINE — the proposal pipeline outproduces the backlog's right to grow.** Reviewer + audit agents emit ~1 proposal per run; an orchestrator that files "everything evidenced and cross-session" lands N tasks and files N new ones per wave — net backlog delta ±0, the roadmap never converges (observed ccxt_client 2026-07-22: 11 landed, 11 filed in one session, including a D2 one-file fix filed+dispatched instead of done inline, a B4/U3 cosmetic filed instead of declined, and a follow-up that existed only because its parent was scoped as a patch instead of the invariant). Evidence + cross-session is the FLOOR, not the bar. File a proposal only when ALL THREE hold: (a) real defect or invariant gap with evidence, (b) not foldable into an existing pending task — and when the proposal patches an instance of a class, scope the filing as the CLASS invariant so the next instance can't spawn a sibling task, (c) not inline-doable in minutes by the orchestrator — if it is, DO it now instead of filing. Declined proposals need no ceremony: the verdict record in the ResultStore is their evidence trail.
  - **Report the net backlog delta** (landed − filed) as an explicit number in every wave/session wrap-up. A session trending ±0 or negative-growth is the churn alarm firing — tighten the decline bar, don't normalize it.
- **Witness notification is sakshi (read-only).** Landing outcomes notify via configured command sink; the sink grants no merge capability. Human operator reviews blocked/conflict outcomes — harness does not silently force-push past conflicts.
- **`check_command` is a dispatch-scale hint to the reviewer.** Free text (e.g. `"mix check.dispatch"` for Elixir, with focused tests chosen by the reviewer) — the reviewer runs and judges it; harness does not execute it mechanically. Keep full-suite commands like `mix precommit.full` for the landed-base Architect/QA pass. For verbose checks, capture to a per-run `mktemp` log on the first execution; never re-run only to recover truncated output.
- **The cross-family reviewer reads `AGENTS.md`, not your Claude skills/includes.** `AGENTS.md` is generated from `CLAUDE.md` by `claude-marketplace/scripts/sync-agents-md.sh`, which recursively inlines every `@`-import. **Regenerate it after any `CLAUDE.md` change** (`bash ~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh`, or `--dry-run` to preview) so the reviewer gates against current rules — a stale `AGENTS.md` makes codex/cursor/grok judge against rules you've already changed. **`--check` is the freshness gate** — it re-renders in memory and exits non-zero if `AGENTS.md` has drifted (diffs rendered output, not mtimes, so it catches drift in transitive `@`-imports too); wire it into CI / a pre-commit hook / the `check_command` so staleness fails loudly instead of silently. Consequence under Opus-4.8 skill-on-demand: once `CLAUDE.md` slims to the eager floor, reviewer-critical facts that *were* carried by eager includes (the `check_command` gate; that `mix test.json` / `mix dialyzer.json` emit JSON **by design** — parse for real failures, never flag the envelope; plain `mix dialyzer` is authoritative when the JSON encoder can't serialize a warning) no longer reach `AGENTS.md` via those imports. Put them in a **self-contained `## Toolchain & check commands` section in `CLAUDE.md`** so they survive the slim-down and flow into `AGENTS.md` on regen (ref: `tapakly/CLAUDE.md`, `ccxt_extract/CLAUDE.md`).
- **Delegation roster — opus last, and don't over-default to codex.** When assigning a dispatchable task to a harness adapter, prefer the external agents — **cursor, codex, grok** — and reserve the **claude/opus** adapter for work that genuinely needs it (harness-surface changes, judgment-heavy review, tasks the cheaper adapters keep bouncing). Opus tokens are precious: spend them last, not by default. Mix adapters across a wave for review coverage — but `cursor`+`grok` is one family, not two (see cursor bullet). A repo may override the roster in its own CLAUDE.md.
  - **Observed failure mode: reflex-routing everything to `codex`.** Run ledgers skew heavily codex-over-cursor/grok. Actively spread `assignee` across all three; reserve codex for tasks it's genuinely scored best on, not as the default.
  - **`cursor` is back on the roster (operator unblocked 2026-08-15).** SuperGrok Heavy entitles Cursor Ultra; the 2026-07-13 `cursor/all` block is lifted. Pin `model = "cursor-grok-4.6-high"` — **operator decision 2026-08-17: no more Composer pins.** The older `composer-2.5` guidance (cheapest cost-to-green, and where every cursor capability KPI was measured) is retired; that ledger data describes a model the operator no longer wants routed to. Confirm the live id with `cursor-agent --list-models` / `model_availability-list_available_models cursor` (the catalog also carries `cursor-grok-4.6-xhigh` / `-fast` variants and `claude-opus-5-*` — Opus/frontier pins through cursor still exhaust and get operator-blocked, so don't reach for them as the "design-heavy" reflex). **`cursor` and `grok` are the same SpaceXAI family** (SpaceX closed the Cursor acquisition 2026-08-14): three adapters, two families. A cursor implementer must not get a grok reviewer (and vice versa) — pair either with `codex`.
  - **`model` is REQUIRED at creation for any non-`human` assignee** (`rmap new` rejects a model-less dispatchable task — "a dispatchable task must pin the LLM it runs on"; see `rmap.md` § "Pinning an LLM model"); "leave `model` unset for the agent default" does NOT work. Set `assignee` **and** `model` at task creation per `rmap.md`.
  - **`grok` runs on `grok-4.6` — the frontier default since 2026-08-13; `grok-4.5` is gone from the live catalog** (lineage: `grok-build` → `grok-4.5` 2026-07 → `grok-4.6`; a catalog refresh on 2026-08-13 listed only `grok-4.6`). Re-pin any task still carrying `grok-4.5` when you touch it — a retired pin fails at dispatch. `grok-4.6` carries **no** capability/cost-to-green data yet — route to it to *gather* that data (A/B via `dispatch-compare` grok-4.6 vs codex/gpt-5.6-sol), not on a performance claim the ledger doesn't yet show. A newly-probed grok model lands in the catalog as `selected?: false`; select it (`model_availability` toggle) before it's dispatchable. Confirm live ids with `grok models` / `model_availability-list_available_models grok`.
  - **`codex` runs on `gpt-5.6-sol` — the standing default since 2026-07-31; `gpt-5.5` is RETIRED from the live catalog.** The GPT-5.6 family (2026-07-10) splits generation from durable capability tier: **Sol** = flagship (complex reasoning/coding/agentic, $5/$30 per 1M tok), **Terra** = balanced (~5.5-competitive at 2× cheaper, $2.50/$15), **Luna** = fast/cheap ($1/$6). Model ids: `gpt-5.6-sol`, `gpt-5.6-terra`, `gpt-5.6-luna` — the live catalog lists ONLY these three; `agent_model.codex` is pinned to `gpt-5.6-sol` (verified 2026-07-31 via `config-get agent_model.codex` + `model_availability-list_available_models codex`). **Pin `model = "gpt-5.6-sol"` for new codex tasks**, and re-pin any task still carrying `gpt-5.5` when you touch it — a retired pin fails at dispatch. `terra` remains the cost-to-green candidate (2× cheaper, ~5.5-competitive) — A/B it via `dispatch-compare` before routing bulk work to it. Confirm live ids with `codex debug models` / `model_availability-list_available_models codex`; a probe failure falls back to the builtin seed.
### Known Sharp Edges

- **Fresh worktrees lack `deps/` / `_build/`.** Implementer and reviewer each run project bootstrap (e.g. `mix deps.get`) when needed — budget timeouts for cold worktrees.
- **Reviewer runs the checks.** No mechanical check stack. Correct-but-not-pristine work → reviewer fixes and approves (`reviewer_diff_size` > 0).
- **Cold dialyzer PLT** dominates first reviewer check run in Elixir worktrees.
- **Nested Claude auth.** `ANTHROPIC_API_KEY` shadows subscription OAuth — scrub per run (`scrub_anthropic_key: true` or `env: %{"ANTHROPIC_API_KEY" => false}`).
- **Parallel-session rmap mutations** during a run can false-positive `:checkout_polluted` — wait for the wave or use a separate worktree.

### Repo-Specific Detail

| Need | Where |
|---|---|
| Harness API surfaces, MCP tool shapes | `skills/harness-driver/SKILL.md` in harness repo |
| Driver script template, cutover history, run log | `docs/dogfooding-workflow.md` in harness repo |
| Agent-gate architecture spec | `docs/agent-gate-workflow.md` in harness repo |
| Cross-checkout consumer setup | `skills/harness-driver/SKILL.md` § "Context A" |
| D/B/U scoring, task writing | `task-prioritization.md`, `task-writing.md` |
| Manual session/PR/audit chain | `dev-lifecycle.md`, `worktree-workflow.md` |

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
- **Roadmap:** one root rmap project (`roadmap/tasks.toml`, 342 tasks). Old
  per-package task IDs are offset: hieroglyph +1000, cartouche +2000, onchain
  +3000, aave +4000, aerodrome +5000, evm +6000, js +7000, tempo +8000. Tasks
  carry `target_repo`; `touches` paths are `packages/<name>/…`-prefixed.

### Harness

One registered project, `onchain_stack`, source `~/_DATA/code/onchain-stack`
(server mirror `/data/postgresql/code/onchain-stack`), `check_command:
"mix check.dispatch"`, `target_branch: main`, warm paths for onchain_evm's Rust
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
`openrpc-v1.0.0-beta.4.json`, and documented as supported by **neither Alchemy nor
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


## Toolchain & check commands (read before judging a build)

Cross-family harness reviewers read **AGENTS.md** (auto-generated from this file), not the user's Claude skills. **`mix ci`** (= `mix precommit.full`) is the canonical gate — run it before judging a build green or red. It chains: `compile --warnings-as-errors`, `format --check-formatted`, `credo --strict`, `doctor --raise`, `ex_dna --max-clones 0`, `reach.check --arch --smells`, `sobelow --skip`, `deps.audit.gated`, `test.json --cover --exclude integration`, `dialyzer`, `agents.check`. `mix precommit` is the fast local loop (no dialyzer, no coverage). `mix check.dispatch` is the per-dispatch reviewer gate (static checks only) and is what this repo registers as its harness `check_command`.

- `mix reach.check --arch --smells` gates from `.reach.exs` (`smells: [strict: true]`). Smell findings must be **fixed, never added to an ignore list**.
- `deps.audit.gated` proves the local advisory mirror is fresh (`bin/advisory-freshness.sh` in the onchain-stack coordination home) before running `deps.audit --ignore-file .mix_audit_ignore` — `mix_audit` silently discards its own sync failure, so a stale mirror would otherwise report false-green.
- `agents.check` fails when `AGENTS.md` has drifted from this file (`sync-agents-md.sh --check`).
- **The coverage floor lives in `mix.exs` (`--cover-threshold`) — read the current value there, never from prose; it was set from a measured baseline and roadmap task 22 replaces it with a tiered per-module gate.** Per `critical-rules.md` § coverage tiers, `Analytics.*` and `Math.*` are critical-path (95% target) because they are pure and there is no excuse; read/binding layers target 80%.
- `sobelow` is declared even though this package has **no Plug or web surface**. It is not there for security value — the `elixir` plugin's post-edit hook aborts its *entire* check stack (format, compile, credo, doctor, dialyzer) when sobelow is missing from `mix.exs`. Removing it silently disables per-edit checking. Leave it.

**The `.json` mix tasks emit JSON BY DESIGN — that is expected output, never an error or a broken setup:**

- **`mix test.json`** (`ex_unit_json` dep) — ExUnit results as JSON; identical run to `mix test`. Parse it for failures; the JSON envelope itself is never a failure signal. `--cover` can emit a large per-module blob — pipe to a file (`--output /tmp/cov.json`) and `jq` the summary, don't dump it to the transcript.
- **`mix dialyzer.json`** (`dialyzer_json` dep) — dialyzer warnings as JSON. Read the array for *real* warnings; do NOT flag the JSON output as a problem. If the encoder cannot serialize a warning shape, plain `mix dialyzer` is the authoritative check.

## 🚨 Base simulation is blocked — do not write revm fork tests

`onchain_evm`'s revm binding **hard-rejects any chain id other than 1**. `spec_id_for_fork` in `native/onchain_evm/src/lib.rs:98-101` returns an error because "the hardfork schedule is known only for Ethereum mainnet"; the Elixir side documents it at `lib/onchain/evm.ex:38-39`. Forking Base (8453) returns `{:error, {:fork_error, _}}`.

Consequences, all of them load-bearing:

- **Do not** write `Onchain.EVM` fork tests against a pinned Base block. They cannot run. An external spec for this package prescribed exactly that; it is wrong.
- **Do not** "fix" it by patching `deps/onchain_evm/`. Never edit anything under `deps/`.
- `onchain_evm` is still a legitimate dev/test dependency here — for `Onchain.Solidity` ABI parsing and `Onchain.Contract.Generator` codegen, **not** for simulation.
- **Determinism comes from golden fixtures plus a pinned block number**, not from a local EVM. Capture real `eth_call` return data once, commit it, and decode against it offline.

**Un-block condition:** an upstream `onchain_evm` change adding an OP-Stack/Base `spec_id` mapping, or a caller-supplied `:spec_id` option. A task for that is filed in the `onchain_evm` roadmap. When it lands, simulation-backed write tests become possible and this section should be rewritten, not deleted.

## 🚨 Sugar drift is the standing hazard

The **deployed ABI is the only authority.** Sugar's own `readme.md` in `velodrome-finance/sugar` documents `LpSugar.all(limit, offset)`; the deployed contract is **`all(uint256,uint256,uint256)`** — a third `_filter` argument — and the 2-argument form **reverts on-chain**. Documentation drift here is not hypothetical, it is the current state.

- ABIs live in `priv/abis/`, captured from **Sourcify v2** (`https://sourcify.dev/server/v2/contract/8453/<addr>?fields=abi`) because it serves the *deployed* ABI **with named tuple components** — required for `hieroglyph`'s `decode_structs: true`. `priv/abis/README.md` records address, match type, fetch date, and the exact `curl` per file.
- After any Sugar redeploy: re-capture from Sourcify, re-run the golden decode suite, and re-run the live probes in `priv/abis/README.md`. A decode that starts returning `nil` fields is drift, not a bug in the decoder.
- `decode_structs: true` uses `String.to_existing_atom/1` and **raises at runtime** on un-interned field atoms. Intern them (module attribute, `@type`, or an explicit list) before the first decode. It is also a **no-op on unnamed signatures** — the `"(uint256,bool)"` strings `Onchain.Solidity` produces carry no field names.

## 🚨 Pagination — never terminate on a short page

`LpSugar.all/3` applies `_filter` **after** fetching the page. With a non-zero filter a full page returns *fewer* than `limit` rows, and `_offset` still indexes the **unfiltered** space. The obvious "loop until a short page" termination is therefore a **silent data-loss bug**, not a crash — it stops early and reports success.

- **Drive `offset` to `count()`.** `LpSugar.count()` answered **35,156** on 2026-08-26 (it only grows). An external spec claimed "~2,500 pools"; that is off by 14× and every downstream sizing assumption built on it is wrong.
- Hard per-call caps compiled into the contracts: `MAX_LPS = 500`, `MAX_POSITIONS = 200`, `MAX_TOKENS = 2000`. `limit: 500` is verified working against the public Base RPC — so the real shape is ~71 sequential pages.
- **Multicall3 does not help the page loop.** One `all(500, …)` already returns ~1.1 MB and dominates the `eth_call` budget. `Onchain.Multicall.aggregate3/2` is for *per-pool enrichment*, not for parallelising pagination.
- **The trap generalizes beyond `all/3` — "no filter argument" does NOT imply short-page-safe.** `positions`/`positionsByFactory`/`positionsUnstakedConcentrated`, `forSwaps`, `TokenSugar.tokens`, `epochsLatest`, `rewards` and `VeSugar.all` offset over a *scanned* index space (pool index or token ids) that is not the returned-row space; upstream filtering, dedup, dead gauges and burned ids make short pages the normal mid-enumeration case. Only `epochsByAddress` (one row per epoch) is genuinely short-page-terminal. Verified against the Sugar Vyper sources, 2026-08-26.
- Batching, multicall and retries are **already provided by `onchain` core** — `Onchain.Multicall.aggregate3/2` and `call_many/2`, `Onchain.RPC.batch/2` (JSON-RPC array batch), a per-call `retry: [max_retries:, backoff_ms:]` option, and Req pool/retry config via `config :onchain, :req_options`. Do not reimplement them here.

## 🚨 APR denominators — fee and emission APRs are never summed

This is the part of the domain most likely to be silently wrong, because a wrong number still looks like a number.

- **Emit `fee_apr` and `emission_apr` separately, each tagged with its explicit denominator.** Never add them into a single "total APR". They are denominated over different capital bases and summing them is not an approximation, it is a category error.
- **Emission APR is denominated in staked, in-range liquidity** — not in total TVL. `Lp.emissions` is **per second**; the weekly figure is `emissions × 604_800`.
- **Weekly, not daily, epochs.** Cross-check that held: `12337.58 × 52 / 8_515_374 = 7.53%` against a displayed 8.76%.
- **The fee/emission dichotomy is NOT binary on Slipstream.** An unstaked concentrated-liquidity position pays a rake to the gauge: `CLFactory.defaultUnstakedFee()` = `100_000` pips (1e-6 units) = **10%**, per-pool overridable and surfaced as `Lp.unstaked_fee`. So an unstaked CL LP keeps `1 - unstaked_fee` of trading fees, not all of them. Modelling it as a clean either/or understates voter revenue and overstates unstaked-CL yield.
- **`Lp.emissions_cap` is not a token-amount bound — never `min()` it against the weekly rate.** Where the gauge factories expose a cap at all it is a *relative share* in basis points (`defaultCap()` / `MAX_BPS()`); several gauge factories revert on the cap selectors (Sugar's `_safe_emissions_cap` then yields 0), and `Lp.emissions` is the *post-notification* rate the cap has already shaped, so re-applying any cap double-counts. Probed live 2026-08-26.
- **Do not try to reproduce the frontend's headline number.** If ours disagrees with aerodrome.finance, the correct response is to state which denominator each uses — not to tune a constant until they match.
- Money is **integers**; ratios are **`Decimal`**. No floats on any money path.

## Domain facts worth not re-deriving

- **Epoch = 1 week, flipping Thursday 00:00 UTC.** `floor(ts / 604_800) * 604_800` lands on Thursday midnight because Unix epoch 0 was a Thursday.
- **`Lp.type` is the pool-type discriminator**: `-1` = v2 stable, `0` = v2 volatile, `> 0` = CL tick spacing. The whole quoting/analytics split hinges on this field.
- **`CLFactory.tickSpacings()`** returns `[1, 50, 100, 200, 2000, 10]` (that raw order, verified live).
- **There are three CL factories on Base**, not one — `base.env`'s `CL_FACTORIES_8453`. `Contracts.cl_factories/1` returns all three. Which are in scope for a given enumeration is an explicit decision, never an assumption.
- **`RewardsSugar.rewardsByAddress(uint256 _venft_id, address _pool)`** is a **veNFT-scoped** lookup, not an account lookup. `epochsByAddress` is `(limit, offset, address)`.
- **Sugar is the canonical read path** — Aerodrome has no REST API, and the `Lp` struct carries exactly the raw inputs APR needs (`emissions`, `emissions_token`, `gauge_liquidity`, `staked0`/`staked1`, `token0_fees`/`token1_fees`, `pool_fee`, `unstaked_fee`).

## Layer contract

`.reach.exs` turns "each layer is usable on its own" from prose into a gate:

| Layer | Namespace | Depends on |
|-------|-----------|------------|
| `types` | `Onchain.Aerodrome.Types.*` | nothing |
| `base` | `Onchain.Aerodrome.Contracts`, `.Epoch`, `.Math`, `.Math.*` | nothing |
| `bindings` | `Onchain.Aerodrome.Bindings.*` | `types`, `base` |
| `analytics` | `Onchain.Aerodrome.Analytics.*` | `types`, `base` |
| `read` | `Onchain.Aerodrome.Sugar.*` | everything below |
| `write` | `Onchain.Aerodrome.Write.*` | everything below |

**`analytics` sits below `read` deliberately.** APR, tick math and valuation take structs, not RPC options — so the entire L3 suite is testable with zero network, and the "never sum the APRs" invariant is checkable statically. If an analytics module needs to make a call, the design is wrong: pass it the data.

Layer order in `.reach.exs` matters — reach's `*` crosses name segments, so specific layers must precede a broad catch-all.

## Architecture

- All modules use the `Onchain.Aerodrome.*` namespace; the root discovery module is `OnchainAerodrome`.
- Pure Elixir, no native deps in the runtime dependency set.
- All dependencies resolve from hex.pm — no path or git deps, so the package is publishable as-is.
- Standard error tuples: `{:ok, result} | {:error, {:tag, reason}}`.
- **Writes return calldata by default.** Signing is opt-in and requires an explicit signer; no module reads a private key from the environment on its own.

## Node Portability

The family-wide law is `node-portability.md` (`@`-imported above). This package's specifics:

- **Everything is `eth_call` against a deployed contract**, routed through `Onchain.RPC` / `Onchain.Contract` / `Onchain.Multicall`. No `debug_*`/`trace_*`, no client extensions, no WebSocket.
- **`eth_call` weight, not archive depth, is the portability question here.** `LpSugar.all(500, offset, 0)` is heavy (~1.1 MB response), but verified 2026-08-26 on **both** the public `https://mainnet.base.org` and an Alchemy Base endpoint — identical results, so `limit: 500` is not a privileged-endpoint assumption. An endpoint with a tighter per-call gas or response cap can still refuse it; document that requirement rather than silently lowering `limit`.
- **Archive is needed only for historical/epoch queries** — anything taking a block parameter. Say so in that function's `@doc`. An integration test that only ever runs against our archive node is not evidence of portability.
- **Base only.** Contract addresses here are Base-specific; the Velodrome sibling on Optimism has different addresses and is out of scope.

## Module Layout

```
lib/onchain_aerodrome.ex        # Descripex.Discoverable roster
lib/onchain/aerodrome/
  contracts.ex                  # address registry + verified constants (base layer)
priv/abis/                      # Sourcify-captured deployed ABIs + provenance README
```

The remaining layers (`types/`, `bindings/`, `analytics/`, `sugar/`, `write/`) are scoped in `roadmap/tasks.toml` and not yet implemented. `.reach.exs` already declares them, so the gate is in place before the first module lands.

## Dependencies from onchain core

| Module | Used for |
|--------|----------|
| `Onchain.ABI` | ABI encoding/decoding |
| `Onchain.RPC` | `eth_call`, `batch/2`, per-call retry |
| `Onchain.Multicall` | `aggregate3/2`, `call_many/2` — per-pool enrichment |
| `Onchain.Contract` | Generic contract call; `Contract.Generator` for bindings |
| `Onchain.Solidity` | `parse_abi_file/1` over `priv/abis/` |
| `Onchain.Signer` | Transaction signing (opt-in write path only) |
| `Onchain.Address` | Validation, checksumming |
| `Onchain.Hex` | Hex encoding/decoding |
| `Onchain.Decimal` | Decimal math (ratios) |

## Testing

```bash
mix test.json --quiet                          # Unit tests only
mix test.json --quiet --include integration    # Unit + integration (requires a Base RPC)
```

Integration tests require a Base endpoint (`BASE_RPC_URL`, falling back to `https://mainnet.base.org`). Golden-fixture decode tests need no network at all and are the primary defence against Sugar redeploy drift.

## Contract Address Verification

Addresses in `lib/onchain/aerodrome/contracts.ex` carry a provenance comment each. Re-verify against two independent sources — never a BaseScan label alone:

```bash
# 1. The Sugar team's own deployment manifest
gh api repos/velodrome-finance/sugar/contents/deployments/base.env --jq '.content' | base64 -d

# 2. A live probe that the contract answers as expected
cast call 0x69dD9db6d8f8E7d83887A704f447b1a584b599A1 "count()(uint256)" --rpc-url https://mainnet.base.org
cast call 0x69dD9db6d8f8E7d83887A704f447b1a584b599A1 "token_sugar()(address)" --rpc-url https://mainnet.base.org
```

There is no Basescan/Etherscan API key on this host — Sourcify v2 is the ABI source. See `priv/abis/README.md`.

## Related Packages

- **onchain** — Core Ethereum primitives: `{:onchain, "~> 0.13"}`
- **onchain_aave** — The sibling protocol wrapper this package's shape is modelled on
- **onchain_evm** — Rust NIFs + codegen: `{:onchain_evm, "~> 0.6", only: [:dev, :test]}` (ABI parsing and codegen only — **simulation against Base is blocked**, see above)
- **descripex** — Runtime API discovery (`OnchainAerodrome.describe/0..2`)
