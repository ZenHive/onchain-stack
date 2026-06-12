<!-- Auto-generated from CLAUDE.md by claude-marketplace/scripts/sync-agents-md.sh — do not edit manually -->

# Onchain Aave

Aave V3 protocol wrappers for Elixir. Depends on `onchain` core for RPC, ABI, signing, and address utilities.

<!-- Selective-load (Opus 4.8): eager floor = critical-rules + harness-workflow (this repo is
     harness-driven — the OTP dispatch→review→land loop is the active workflow). onchain-workspace
     is the harness workspace add-on (7-repo roster + dependency shape), eager family-wide.
     ethereum-rpc stays eager (host-specific node access, no skill mirror). Everything else previously imported
     here (across-instances, worktree, task-prioritization/writing, workflow-philosophy, web-command,
     elixir-setup, ex-unit-json, dialyzer-json, code-style, development-commands/philosophy,
     agent-economy) is skill-on-demand via the elixir / task-driver / dev-lifecycle plugins.
     Re-add an @-import per-surface only if Opus visibly degrades on it. See ~/.claude/setup-guide.md. -->
<!-- @-import: ~/.claude/includes/critical-rules.md -->
## 🚨 ANSWER IN SHORT TEXT — ALWAYS

Every answer — explanation, proposal, pushback, summary — is short, pointed text. Too short beats too long: unclear → the user asks. Too long → the user often doesn't read it, which is worse.

## 🚨 BE A REAL PARTNER, NOT A YES-SAYER

**Challenge ideas that seem wrong, risky, or suboptimal.** Not every user request is a good idea. A real partner pushes back when it matters.

- **Flawed approach:** "I'd push back on this because..." — don't just comply
- **Better alternative exists:** present it with reasoning, not "have you considered..."
- **Scope too big or small:** flag it. "This feels like it's solving the wrong problem" is valid
- **Wrong assumptions:** correct them — after verifying yours are right (gate below)
- **Tone:** direct and respectful, not combative. Disagree like a trusted colleague
- **When to yield:** if you've made your case and the user still wants to proceed, commit fully. Pushback ≠ blocking

### Pushback Gate — Understand Before You Challenge

**Misinformed pushback is worse than no pushback.** Earn it:

1. Restate the user's mechanism + goal in two sentences they'd endorse. Can't? Ask — don't challenge.
2. "I understand X, disagree because Z" is partnership. "Seems wrong" without naming X is noise.
3. Objection reduces to "not how software is normally built"? Not an objection — see next section.
4. Pushback strength scales with understanding depth. Partial understanding → questions only.
5. Pushback is ≤3 sentences. State the disagreement, not an essay — the user asks if they want more.

### Think As an AI, Not Only As a Developer

The user builds AI-native systems. Developer instincts produce systematically wrong pushback here.

**The design question: judgment or mechanics?**

- **Judgment** (interpret meaning, classify failures, diagnose, decide done/worth/fault, fuzzy match) → an AI does it better than code. A regex / cond-branch / disposition table for a judgment call IS the bug.
- **Mechanics** (counters, timers, git, process spawning, deterministic checks) → code.

Developer instincts that are wrong in this paradigm — drop them:

- "Should be deterministic / unit-testable" — for judgment, non-determinism is the design
- "LLM call is slow / expensive / unreliable" — the alternative is a procedural approximation wrong at every edge
- "Parse / normalize / schema the output" — AI consumers read raw; normalization layers break
- "Handle this edge case in code" — every hard-coded case removes a judgment from the AI

Precedent (cite, don't relitigate): harness Tasks 153–163 — every run-lifecycle bug was judgment-as-procedural-code; the fix was deletion (−1,219 lines), not improvement.

When designing or reviewing, ask: **"which parts would an AI do better than code?"**

## 🚨 NEVER START THE PHOENIX SERVER

The Phoenix server is always already running. Never run `mix phx.server` via Bash. Assume localhost:4000. User starts/stops manually. To verify behavior, ask the user to check the browser.

## 🚨 ALWAYS WRITE TESTS

Every feature MUST have tests, even if the spec doesn't mention them. Unit tests for context functions, integration tests for LiveViews, tests for all CRUD/validations/error cases/edge cases (nil, empty, boundary). A feature without tests is not complete.

## 🚨 RAISE COVERAGE BEFORE MUTATING

**Before any code-changing task on an existing module, that module's `mix test.json --cover` percentage must be at the target tier:**

- **≥80%** for standard business logic
- **≥95%** for critical business logic (signing, money handling, cryptographic operations, low-level encoders, security-sensitive parsers)

If below tier, raise coverage **first** — write the missing tests, confirm the gate passes, then implement the change. The new tests are part of the task, not a follow-up.

**Scope — code-changing mutations only.** Exempt:
- Doc-only edits (`@doc`, `@moduledoc`, inline comments, README, CHANGELOG)
- Formatting, whitespace, alias reordering, autoformat-driven changes
- Pure renames (variable, function, module — no behavior change)
- Typo fixes in strings, log messages, error messages

The gate is a "do I have a safety net before I touch this?" check; writing the missing tests also surfaces the module's actual contract.

**How to apply:**
1. Run `mix test.json --cover --quiet --output /tmp/cov.json` (or `--cover-threshold 80` for a hard exit).
2. Inspect the touched module's percentage: `jq '.coverage.modules[] | select(.module == "MyApp.Foo")' /tmp/cov.json`.
3. If below tier, write tests for the uncovered lines until the gate passes — even if those lines aren't the ones you came to change.
4. Then implement the original mutation.

**Tier classification:** "critical business logic" is project-defined. When in doubt, treat anything that handles money, signs/verifies, encodes/decodes wire formats, or enforces authorization as critical (95%). Plain data transforms, UI glue, and reporting code are standard (80%).

## 🚨 NEVER HIDE TEST FAILURES

**TESTS THAT HIDE ERRORS ARE WORSE THAN NO TESTS AT ALL.** Tests find bugs — a test that silently passes on errors is lying and will cause production bugs.

### ABSOLUTELY FORBIDDEN — NEVER WRITE THESE:

```elixir
# ❌ MAKES ANY OUTCOME PASS - COMPLETELY WORTHLESS
case result do
  {:ok, _} -> assert true
  {:error, _} -> assert true  # ← This makes ALL failures pass silently!
end

# ❌ HIDES ALL ERRORS WITH COMMENTS - DANGEROUS
{:error, _reason} ->
  # This is acceptable for testnet
  :ok  # ← NO! This silently passes EVERY error!

# ❌ COMMENTS DON'T VALIDATE BEHAVIOR
{:error, reason} ->
  IO.puts("Error may be normal: #{inspect(reason)}")
  assert true  # ← Still worthless!
```

### CORRECT PATTERNS — ALWAYS USE THESE:

```elixir
# ✅ FAILS LOUDLY ON UNEXPECTED ERRORS
case result do
  {:ok, data} -> assert is_map(data)
  {:error, :specific_expected_error} -> :ok
  {:error, other} -> flunk("Unexpected error: #{inspect(other)}")
end

# ✅ EXPLICIT ABOUT WHAT'S ACCEPTABLE
{:error, :insufficient_balance} ->
  :ok  # This specific error is expected and valid
{:error, other} ->
  flunk("Expected :insufficient_balance, got #{inspect(other)}")

# ✅ TEST SPECIFIC BEHAVIOR, NOT OUTCOMES
test "returns not_found when account doesn't exist" do
  assert {:error, :not_found} = get_account("invalid_id")
end

test "returns data when account exists" do
  assert {:ok, %{balance: _}} = get_account("valid_id")
end
```

**THE RULE:** If you don't know what error to expect, DON'T write the test yet. Explore via Tidewave MCP first, understand the real error cases, THEN write assertions. A test should FAIL when the code is wrong.

### INTEGRATION TESTS: NEVER SKIP SILENTLY ON MISSING CREDENTIALS

Integration tests requiring API credentials must **fail loudly** with actionable setup instructions, not skip silently:

```elixir
# ❌ BAD: Silent skip - test appears to pass when it didn't run
setup do
  api_key = System.get_env("API_KEY")
  if is_nil(api_key), do: :skip  # ← DANGEROUS! Test suite "passes" with 0 tests run
  {:ok, api_key: api_key}
end

# ❌ BAD: Returns :ok on nil - same problem
test "authenticated endpoint", %{credentials: nil} do
  :ok  # ← Test silently passes without actually testing anything
end

# ✅ GOOD: Fails loudly with actionable instructions
test "authenticated endpoint", %{credentials: credentials} do
  if is_nil(credentials) do
    flunk("""
    Missing testnet credentials!

    Set these environment variables:
      export BINANCE_TESTNET_API_KEY="your_key"
      export BINANCE_TESTNET_API_SECRET="your_secret"

    Get credentials at: https://testnet.binance.vision
    """)
  end

  # Actual test code...
end
```

**Pattern:** let the test run (don't skip in setup), check credentials at test start, use `flunk()` with multi-line message listing missing env vars, exact export commands, and the URL to get them. A suite with "0 failures" that ran 0 tests is lying.

## 🚨 FIX HOOK-FLAGGED ISSUES ON FILES YOU TOUCH

**When our hooks flag issues on files you touched, just fix them — including pre-existing flags unrelated to your change.** Don't plan around it, don't ask permission, don't burn tokens discussing whether to. Hook fires → fix → re-run → stage.

Applies to every hook-driven check (credo, format, dialyzer, doctor, sobelow, ex_dna, etc.). Scope is **only the files your change touched** — not the whole project. User pre-approves the broader scope so each fix doesn't need a clarifying question; debt accumulates across sessions otherwise, and a touched file ending dirtier than baseline makes the next session noisier.

**How to apply:**
- Pre-existing flags in your touched file count too: alias ordering, unused vars, refactor opportunities, `TODO:` formatting.
- Generated files → fix the generator, not the output.
- Don't move the fix to ROADMAP or a follow-up task. It happens in this commit.
- **Don't manually re-run a check the hook just ran on the same files.** Act on the hook output directly — re-running `mix test.json` / `mix credo` / `mix dialyzer.json` / `mix sobelow` / `mix precommit` on the file set the hook already graded is duplicated work. Full-suite re-runs earn their cost only before a PR/merge, after `mix deps.get` or a branch switch, or when the user asks. See `~/.claude/CLAUDE.md` § "Don't Re-Run Hook-Driven Checks on the Same Files" for the host-specific rule.

## 🚨 READ TO THE ANSWER — DON'T USE THE RUNNER AS AN ORACLE

**Reason to the fix by reading code; run once to CONFIRM — don't run to DISCOVER.**
The recurring failure mode: change → run full suite → read one failure → fix one
thing → run again, N times. Each cycle pays the suite-compile tax; N cycles for a
problem one read would have surfaced whole.

- **Read the code path before running the test that exercises it.** Front-load the
  model; don't outsource it to the runner. A 10-line read of the function beats
  learning its shape from a failing assertion three fixes later.
- **Treat a failure as a SURVEY, not a single fix.** Enumerate every plausible
  cause from the output + one read, fix them in a batch, then run once. Don't
  fix-one-and-rerun.
- **Verify handoffs/summaries against ground truth before building on them.** A
  compaction summary or another session's claim ("X is already wired") is a
  hypothesis. `grep` the load-bearing claim before you act on it.
- **Trust the hooks** (pairs with FIX HOOK-FLAGGED + the host CLAUDE.md rerun rule):
  per-edit checks already graded the file; re-running is wasted cycles.
- **Under a flaky terminal, go sequential-and-simple by default** — one command →
  write to a file → Read it. No parallel batches of *dependent* calls: one early
  failure cancels the whole round.

**Failure-mode tell — about to run the same test a 3rd time to find the *next*
problem? STOP. Read the code path and the opts you're passing against a known-good
sibling, list all the causes, fix them together, run once.**

## 🚨 FLAKY TESTS & TEST-RUN TOKEN ECONOMY

**Elixir suites are non-deterministic at the edges (async / GenServer / Port /
LiveView / supervision tests), and `mix test` is the single biggest time/token sink
in a session.** A flaky red believed-as-real, or an unbounded test run dumped to
context, burns real money and wall-clock every time. Four disciplines:

### A small red count is a flaky-test HYPOTHESIS, not a regression — until confirmed

When a suite reports 1–2 failures out of hundreds, **don't believe the red yet** —
especially in async/GenServer/Port/LiveView/supervision tests, which fail
intermittently on timing.

1. **Check the failing file against your diff.** Your change didn't touch it (or its
   module under test)? → suspect flake, not your bug.
2. **Re-run ONLY that test in isolation** — `mix test.json <file>:<line>` (or
   `--failed`). Passes alone → flaky; proceed. Fails alone, deterministically → real;
   fix it.
3. **Never repair-loop or block a merge on an unconfirmed flake.** One isolated
   re-run is the whole investigation — don't re-run the full suite to "make sure."

### NEVER `Process.sleep` to "fix" a flaky test

Timing sleeps mask non-determinism, slow every future run, and hide the real race.
Fix the root cause with synchronization, not delay:

- `assert_receive` / `refute_receive` with a timeout — not `Process.sleep` then `assert`
- `Process.monitor` + `assert_receive {:DOWN, …}` for process death
- `start_supervised!` for deterministic lifecycle; poll-until-condition for async state

Hard line — it's the same lie as **NEVER HIDE TEST FAILURES**: a `sleep` that makes a
race pass *most* of the time still ships the race.

### Don't re-run a full suite to grade already-graded code

(Extends **READ TO THE ANSWER** + the host CLAUDE.md rerun rule.) Per-edit hooks
already ran `test.json` on touched files; a harness-dispatched run already ran the
project's check stack green.

- A **disjoint-file cherry-pick / clean merge** of already-verified code does **not**
  need a `precommit.full` re-run — the verdict is already in hand.
- Full suite only when files reached the tree through a **non-graded path**: manual
  editor edits, a rebase with overlapping hunks, a branch switch, or after `mix deps.get`.
- "Before a PR/merge" justifies the full suite **only when the merged code wasn't
  already graded green** — not as a reflex on every merge.

### Bound test output — NEVER let coverage hit context

`mix test.json --cover` emits the **entire per-module coverage JSON** (tens to
hundreds of KB) — one dump can eat most of a context window.

- Always `--output /tmp/cov.json` + `jq` the summary; never let `--cover` land on
  stdout/context.
- Triage with `--max-failures 1`, `--failed`, or a single `file:line` to cap noise.
- Only need pass/fail? Drop `--cover` entirely.

**Failure-mode tell — about to trust a 1-of-1000 red, add a `sleep` to make a test
pass, re-run `precommit.full` on a clean cherry-pick, or run `--cover` straight to
your terminal? STOP. Triage the one test in isolation; fix races with `assert_receive`;
trust the hook/dispatch verdict; pipe coverage to a file.**

## 🛑 MINIMALIST APPROACH FIRST

**Do exactly what is asked — nothing more, nothing less.**

- **NO** proactive features or improvements unless explicitly requested
- **NO** additional error handling beyond what's needed
- **NO** extra validation, refactoring, or documentation files
- **ALWAYS** ask before adding anything not explicitly mentioned
- **IF UNCLEAR:** Ask "Should I also do X?" before proceeding

### BUT: Minimalism Is Not Incomplete Work

**"Start minimal" means no EXTRA features — not skipping items the task implies.**

When a task says "define unified data structs," the scope is ALL structs the system needs, not "the 7 I can think of." When a source of truth exists (e.g., `method_defs/0` listing 241 methods, each implying a return type), audit it — don't cherry-pick.

**The pattern to avoid:**
1. Task says "build X for all Y"
2. Claude scopes to "build X for the obvious Y" (filtering/cherry-picking)
3. Later session discovers the gap and adds a fix-up task
4. The fix-up task does what should have been done originally

**How to catch it:**
- If the task mentions "all," audit the source of truth — don't rely on what comes to mind
- If a data source defines N items, process N items (or explain why some are excluded)
- If you're writing "for now we'll just do these 7" without being asked to limit scope — STOP. That's scoping out, not starting minimal.

**Minimalism guards against:** adding caching when nobody asked, building admin UIs "just in case," over-abstracting simple code.

**Minimalism does NOT mean:** skipping half the items in an enumerable set, cherry-picking "common" cases from a known complete list, or deferring clearly-implied work to future tasks.

## 🚨 NO PSEUDO-RIGOROUS HEDGING

**Don't gate user-requested work behind invented "evidence requirements" you cannot satisfy.**

You have no consumer telemetry. No usage counts. No signal about whether a feature will be called 12 times or 1200 times. So phrases like *"demand for this is unproven"*, *"we should wait until N consumers ask for this"*, *"is this widely needed?"*, *"only worth doing if a Nth+ use case is imminent"* are **risk-aversion theater**, not analysis. They sound rigorous; they're hedging.

- In single-developer codebases or focused teams, the developer IS the demand signal. They asked. That's the data point.
- "Wait for usage data" is a corporate-flavored instinct that doesn't apply to small teams. There's no telemetry pipeline; there's the user in front of you.
- It gaslights the user: their request is reframed as "unproven need" requiring further validation. They have to argue for what they already asked for.

**Distinguish from minimalism (the section above):**
- Minimalism = don't add features the user **didn't ask for**.
- This rule = don't refuse / defer features the user **did ask for** by inventing evidence requirements.

**Failure-mode test — if you're about to write any of these, STOP:**
- "Demand for X is unproven"
- "We should wait until..."
- "Is this widely needed?"
- "Only worth doing if a Nth+ case is imminent"
- "Bet on usage data before building"

You don't have data either way. The honest framing is: *"I don't know if you'll use this 12 more times — that's your call."*

**What to do instead:**
- Name the **actual technical risks** (e.g., "the macro might grow more knobs than the duplication it removes," "this couples us to an upstream that breaks every release," "the test surface explodes at N+1 cases"). Those are real costs you can reason about.
- Cite **concrete precedents** when scoring complexity (see `development-philosophy.md` "Cite Ecosystem Precedents Before Crying Complexity"). Generic "this could grow" without naming a specific failure pattern is the same hedging by another name.
- If the task genuinely scores low on benefit/usefulness, score it that way honestly — don't smuggle a demand-speculation into the U/B numbers and pretend it came from analysis.

**Scope extends to task `body` fields and scoring justifications, not just live responses.** Same hedge phrases written into a task's `body` to justify B/U — "table-stakes", "increasingly expected", "now standard", "buyers expect", "competitors are starting to", "modern apps all do" — inflate the score the same way they inflate a response. Required instead: named consumer evidence (named partner asked, named competitor lever, measured conversion uplift) OR honest low score. Enforced at task-creation time by `task-writing.md` § Pre-Creation Gate (question 5).

## Git Commit / Push / PR-Create — Allowed by Default

Committing, pushing, and opening PRs are normal parts of the work — do them without asking when the task calls for it (the agent-gate / auto-land workflow, worktree branches, and shared default branches alike). Announce the action in one line, then take it; the diff and push are the recap.

The only residual caution is the general one for any hard-to-reverse action: **rewriting already-pushed history** (force-push, amend/rebase of shared commits) can destroy others' work, so confirm before doing that on a shared branch — not because commits need permission, but because history-rewrite is irreversible.

### 🚨 STAGE PATH-SCOPED — THE WORKING TREE IS SHARED, YOU WORK IN PARALLEL

**Never assume the working tree or index holds only your changes.** Unrelated WIP sits in the tree, the index may already hold files another session `git add`ed, and an auto-land harness is a second committer. A blanket stage sweeps all of it into *your* commit.

- **NEVER `git add -A` / `git add .` / `git commit -a`.** Stage explicitly: `git add <path> …`, or commit path-scoped: `git commit <path> …`. The commit then carries exactly the paths you name, regardless of what else is dirty or staged.
- **Verify the staged set before every commit** — `git diff --cached --name-only`. If a path you didn't touch is there, it's someone else's; don't commit it.
- **A pre-commit hook tripping on a file you didn't touch means foreign WIP is dirty, not that you must fix it.** Path-scoped-stash ONLY the foreign paths (`git stash push -- <their-paths>`), make your clean commit, `git stash pop`, then **re-stage whatever was staged before** so the other session's index is exactly as you found it. Never format, fix, or commit work that isn't yours to clear a hook.
- **Untracked dirs/files you didn't create:** leave them — don't `-u`-stash or `add` them.

The failure mode this guards: you path-scope your *commit* correctly but `git add -A` first, or you stash `-u` to clear a hook and bury another session's staged work. Both corrupt parallel work silently.

## Shell Safety

`rm` (including `rm -rf`) is permitted — the hook allows it; the old blanket ban caused more friction than it prevented. One habit, not a gate: before an irreversible delete, glance at the target — confirm the path is what you intend (no unexpanded `$VAR`, no wildcard catching more than you mean, not a path you didn't create or weren't asked to remove). `git rm` for tracked files keeps the removal in the diff. (Destructive *dependency / build* commands — `mix deps.clean`, `rm -rf _build` — stay consent-gated below, for slow-recovery reasons, not safety.)

## 🚨 NEVER RUN DESTRUCTIVE DEPENDENCY COMMANDS

**Never run these without explicit user consent:**

- ❌ `mix deps.clean` / `mix deps.clean --all` — deletes compiled deps; slow recovery
- ❌ `mix deps.unlock --all` — unlocks all versions
- ❌ `rm -rf _build` or `rm -rf deps` — nukes build artifacts
- ❌ `mix clean` — removes compiled app files

**What to do instead:**
- Compile error → just retry `mix compile` or `mix test`
- Specific dep issue → `mix deps.compile <dep_name> --force`
- Most "corrupt cache" issues are transient glitches

Ask before running any destructive command.

## 🚨 Integrity and Accuracy

**Never fabricate information, experience, or data.** When providing technical guidance:

- **Honest about sources:** distinguish codebase observations, general knowledge, best practices, and speculation. Never claim production experience you don't have or invent metrics/timelines/stats.
- **No false authority:** don't claim "we learned" without repo evidence; don't state "after X years in production" without evidence; use "typically/often/may/could" when uncertain.
- **Document uncertainty:** identify what you don't know, suggest validation paths, provide ranges over false precision.
- **Trace sources:** "Based on the code in file.ex...", "According to docs/FILE.md...", "Common practice in Elixir...", "This suggests..."

False technical claims cascade into bad architectural decisions, wasted resources, and damaged trust.

## 🚨 RESEARCH BEFORE ASSERTING ON NICHE TECHNICAL CLAIMS

**When the question lives outside reliable training coverage, do online research proactively — without being asked.** The default failure mode is asserting from training-bias confidence on specs/protocols/niche APIs that the model never deeply absorbed. Codex routinely fetches reference implementations to verify assumptions; Claude defaults to "answer from memory." Close the gap.

**Research proactively (use WebFetch on a known URL, WebSearch to discover one) when the topic is:**

- **Wire formats / encodings** — RLP, ABI, SSZ, Protobuf, MessagePack, BLS, BIP-32/39/44 paths, EIP-712 typed data, CBOR, ASN.1 / DER. Fetch the spec or a reference implementation (geth, reth, py-evm, libsecp256k1, official BIPs) before claiming byte order, length-prefix rules, padding, or canonical-form requirements.
- **Protocol details** — EIPs, RFCs, JSON-RPC method shapes/error codes, opcode gas costs, P2P handshake messages, exchange API quirks (Binance/Deribit/OKX rate-limit headers, signature canonicalization, error envelopes).
- **Niche / recent library APIs** — anything outside mainstream-framework training where you'd be guessing function signatures, return shapes, or version-pinned breaking changes. If you'd write `# probably something like` in a comment, that's the signal — go fetch the docs.
- **Cross-implementation edge cases** — when "what does X do when Y is malformed?" matters, check **≥2 reference implementations**. One impl's behavior can be a bug; agreement across two is the spec in practice.

**Don't research (use training memory) when the topic is:**
- Pure Elixir / OTP idioms, stdlib functions, mainstream Phoenix / LiveView / Ecto / Ash patterns
- Generic REST, HTTP, JSON, SQL, shell — well-trodden ground
- Anything already in the project's codebase or in hex docs you've already pulled in this session
- Anything explicitly documented in a CLAUDE.md or include the user has imported

Training-bias overconfidence on niche specs ships off-by-one byte-order bugs, wrong opcode gas costs, malformed RLP encodings, miscounted signature recovery IDs — exactly the class of bug a 30-second reference-impl check catches. Cite the source so the user can verify instead of trusting model authority.

**How to apply:**
1. Notice the trigger — you're about to assert behavior in one of the "research proactively" categories.
2. Prefer **WebFetch** when the canonical URL is known (the EIP, RFC, hex package, or a reference-impl file path on GitHub). Use **WebSearch** to find one when it isn't.
3. Cite what you fetched — link the EIP/RFC, the reference-impl file + line range, the hex doc URL. The citation is part of the answer, not optional.
4. For cross-impl checks, name both implementations: *"geth's RLP encoder treats X as Y; reth agrees — see [link] and [link]."*
5. If a fetch fails or returns ambiguous text, say so explicitly and lower confidence — don't fall back to "well, I think..." without flagging the downgrade.

This rule complements **Integrity and Accuracy** above: that one says *don't fabricate*; this one says *go verify when training is thin*. The combined posture is "cite the source, fetch when needed, never assert with confidence you can't justify."

## 🚨 NO EVASION — SIT WITH THE HARD THING

**When you hit something difficult, do NOT optimize for "appearing productive" by moving to easier work.** The most common failure mode: hit a wall → silently move on → user discovers the gap later.

### Evasion Patterns (don't use without explicit user approval)

**Task abandonment:**
- "let's move on to", "we can defer this", "skip this for now"
- "let's come back to this later", "we can revisit this", "let's table this"

**Scope reduction without asking:**
- "to keep things simple, I'll skip", "for brevity, I won't"
- "that's out of scope", "not strictly necessary"

**False completion:**
- "that should be enough", "the rest is straightforward"
- "I'll leave the rest as an exercise", "the pattern is clear enough"

**Deflection to user:**
- "you might want to", "you could manually", "you'll need to handle"
- (Sometimes legitimate — but often evasion disguised as helpfulness)

### What To Do Instead

1. **Stay with it.** If it's hard, say "this is hard because X" — don't silently move on
2. **Flag blockers explicitly.** "I'm blocked on X because Y. Options: A, B, or C."
3. **Ask before deferring.** "This is taking longer than expected. Should I continue or switch?"
4. **Never write workarounds silently.** If tempted to add a fallback/default/nil-guard for missing data, ask: should this come from upstream? If yes, STOP and report it
5. **Incomplete work gets a TODO.** If you must move on, leave a tracked TODO — not a silent gap

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

### When to Dispatch vs Hand-Build

**Default: dispatch every pending rmap task whose dependencies are satisfied.** Hand-build only what harness cannot yet do:

- Scaffolding that reshapes harness runtime (supervision tree, dep stack, Endpoint) **while the run lifecycle itself is in flux**
- Tiny tasks — ALL of (a) D≤2, (b) ≤30 LOC across ≤3 files, (c) no harness-surface change
- UI / LiveView / heex / CSS — headless agents idle-timeout without visual reward; use tidewave + browser
- A harness gap — file via `rmap new`, fix harness, re-dispatch; do not work around by hand-building

### Running a Task

**Prerequisites:** long-lived harness BEAM (`iex -S mix` in the harness checkout), target project registered in `Harness.ProjectRegistry`, clean `git status` on the target's dispatch branch (runs fork worktrees off `HEAD`).

**Three dispatch paths** (prefer top to bottom):

1. **Native MCP — default.** `dispatch-task` (fire-and-forget) or `dispatch-await` (blocks until settle) against `http://localhost:4018/harness/mcp`. Observe via `dispatch-status`, `dispatch-transcript`, `dispatch-verdict_detail`. `scrub_anthropic_key: true` (default) forces subscription OAuth over inherited `ANTHROPIC_API_KEY`.
2. **Tidewave `project_eval` — escape hatch.** Struct-level control the flat tools don't expose (`retry_policy`, fail-over adapter lists, `subscriber: self()`). Run persists to `Harness.ResultStore` even when the eval process exits.
3. **`mix run` driver script — fallback.** Full transcript + reviewer report to terminal. See harness repo `docs/dogfooding-workflow.md` for the canonical template.

> **Never start a second driver BEAM while runs are in flight.** Boot-time worktree sweeps can prune live sibling worktrees. Drive all parallel batches from one long-lived node.

**Renderable vs executable:** `rmap delegate --to` renders native prompts for all six harness adapters (`claude`, `codex`, `cursor`, `grok`, `antigravity`, `pi`). `droid` renders but has no harness adapter — rejected at ingest. All six shipped adapters declare `worktree_isolation: true`.

### Reading the Verdict

| `state` / `reason` | Meaning | Action |
|---|---|---|
| `:done` / `:approved` | Reviewer AI approved (possibly after inline fixes — check `reviewer_diff_size`). | Deliverable on `harness/<run-id>`. Review diff, integrate (or let auto-lander handle it), `rmap status <id> done`. |
| `:failed` / `{:review_rejected, report}` | Reviewer rejected (degenerate — near-never by design). | Read `report`. Task back in queue; re-dispatch. |
| `:failed` / `{:review_stuck, report}` | No verdict: reviewer unavailable, crashed, or missing/malformed `.harness/review.json`. | Read `report`. Fix environment or re-dispatch. |
| `:failed` / `{:worktree_failed,_}` `{:agent_spawn_failed,_}` `{:driver_crashed,_}` `{:commit_failed,_}` | Harness-side mechanical failure. | **Harness bug.** File via `rmap new`. |
| `:failed` / `{:checkout_polluted, status}` | Agent wrote outside run worktree into main checkout. | Agent/adapter issue. Re-dispatch with worktree-honoring adapter. |
| `:failed` / `{:checkout_pollution_check_failed, _}` | Post-run pollution `git status` errored. | Rare; transient git/IO. Re-run; inspect checkout if persistent. |
| `:failed` / `:timed_out` | Lifetime budget elapsed. | Raise `:lifetime_timeout` or investigate hang. |
| run process **crashed** (no settle) | gen_statem died. | **Harness bug.** File via `rmap new`. |

Failed runs retain the worktree at `result.worktree_path` for inspection. Approved runs keep branch `harness/<run-id>` after worktree teardown. Use `dispatch-verdict_detail` for reviewer report, ratings, and `reviewer_diff_size` — no mechanical per-check stdout.

### 🚨 Recover, Don't Redo — Never Burn Tokens Re-Implementing Committed Work

**A run that committed to `harness/<run-id>` already paid for the implementer. Recovering that branch costs a fraction of a fresh dispatch — re-dispatching from `pending` throws the work away and makes the agent redo all of it.** The reflex to "reset → pending → dispatch again" is a token bonfire whenever a retained branch with commits exists. Check for the branch *first*; pick the cheapest primitive that fits:

| Run state — committed `harness/<run-id>` branch exists | Recover with | Agent tokens |
|---|---|---|
| Approved but unlanded (land-cap, lander crash) | `dispatch-reland` | **zero** — pure git rebase + push |
| Committed, review-stage failure (work is good) | `dispatch-rereview` | zero implementer — re-enters at the reviewer gate |
| Committed, implement-stage incomplete/`:failed` | `dispatch-resume_failed` (`escalate: true` to re-route agent) | implementer **continues** from prior commits |
| Live `:held` run (paused, not dead) | `dispatch-resume` | none — un-pauses in place |
| **No commits / no retained branch** | reset → `pending` + fresh `dispatch-task` | full redo — **the only case where this is correct** |

**The gate before any reset-to-pending + re-dispatch:** `git branch -a | grep harness/<run-id>` and `git log --oneline origin/<target>..harness/<run-id>`. Commits present ⇒ recover, never redo.

**🚨 First, confirm the run actually *didn't* land — check `origin`, not your local checkout.** Under `landing_policy: :auto` the lander pushes to `origin/<target>` and **deliberately never touches your local checkout** (it ff-pushes from a detached worktree). So after an autonomous land your local `tasks.toml` is **stale**: it still reads `in_progress` for a task the lander already marked `done --shipped-in` on origin. **Reading that stale local status as "the run didn't land" is the trap** — it triggers a wasteful reset-to-`pending` + re-dispatch that *duplicate-lands already-shipped work*. Before concluding anything from task status, `git fetch origin <target> && git rebase origin/<target>` (the existing "Sync development before committing" rule) or read ground truth directly:
- `git log --oneline origin/<target>` — does it already show `task <id> -> done (shipped …)` and the agent-delivery commit? Then it **landed**; your local view was just behind. Do nothing but rebase.
- `dispatch-status <run-id>` / `result_store-list_run_records run_id:<id>` — a record with `state: done, verdict: approve` means the run succeeded; cross-check landing against origin before touching the roadmap.

> **Observed 2026-06-12 (the cautionary tale this section exists for):** three approved runs (246/249/251) landed cleanly to `origin/development` — `done --shipped-in`, audited. But the operator's local checkout hadn't rebased, so `rmap show` read stale `in_progress`. That was misread as "approved but didn't land," the tasks were reset to `pending` and re-dispatched, and task 246 **landed a second time** (duplicate delivery) before the mistake surfaced. Root cause: reading stale local state instead of rebasing on `origin` first. The lander was working perfectly the whole time.

The recovery primitives (`reland`/`rereview`/`resume_failed`) read the persisted `ResultStore` record, which **survives** worktree teardown and node restarts — so a genuinely approved-but-unlanded run (lander hit its land-cap, or a real rebase conflict retained the branch) is recoverable token-free via `dispatch-reland`. Reserve reset-to-`pending` for runs with **no committed branch and no settled record** — and only after confirming against `origin` that the work isn't already shipped.

### Parallel Dispatch

`Harness.Run.Supervisor` is a `DynamicSupervisor` — N crash-isolated runs, each with its own worktree.

- **Batch by dependency graph** — every pending task whose `depends_on` is satisfied. Mix adapters deliberately for coverage.
- **Same-file is fine; same-function is not.** Two tasks rewriting the same function guarantees un-auto-mergable collision — dispatch sequentially or fold into one rmap task (`task-prioritization.md` § "Refine, Don't Duplicate").
- **One driver BEAM** for all concurrent runs in a wave.
- **Integration order (manual landing):** smallest/isolated diffs onto target first; rebase siblings; run the project's check command on target after last merge.
- **While a wave is in flight:** do not run `rmap status` / `rmap mark` / `rmap new` in parallel sessions against the same checkout — triggers `:checkout_polluted` false-positive.

### Autonomous Landing

Projects with `landing_policy: :auto` and `target_branch`:

1. Approved run enqueues one job on serialized `landing_<name>` Oban queue (limit 1)
2. `Harness.Lander.land/1` rebases `harness/<run-id>` onto `origin/<target>` in a detached worktree
3. **ff-pushes without re-verification** — the reviewer already gated the work
4. Successful push enqueues post-merge audit; advances rmap (`done --verified --shipped-in <sha>`)

Conflict / push-rejected retains the branch for repair — never lands red. Witness notification (read-only sink) alerts the operator; it is **not** a merge gate.

### Portfolio Conventions

- **Agent does not commit unless asked.** Staged-but-uncommitted is the default handoff between implementer and reviewer sessions (`workflow-philosophy.md` § "Implementer / Reviewer Handoff"). Harness runs commit agent work to `harness/<run-id>` automatically — that is harness's deliverable branch, not the operator's main checkout.
- **Witness notification is sakshi (read-only).** Landing outcomes notify via configured command sink; the sink grants no merge capability. Human operator reviews blocked/conflict outcomes — harness does not silently force-push past conflicts.
- **`check_command` is a hint to the reviewer.** Free text (e.g. `"mix precommit.full"`) — the reviewer runs and judges it; harness does not execute it mechanically.
- **The cross-family reviewer reads `AGENTS.md`, not your Claude skills/includes.** `AGENTS.md` is generated from `CLAUDE.md` by `claude-marketplace/scripts/sync-agents-md.sh`, which recursively inlines every `@`-import. **Regenerate it after any `CLAUDE.md` change** (`bash ~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh`, or `--dry-run` to preview) so the reviewer gates against current rules — a stale `AGENTS.md` makes codex/cursor/grok judge against rules you've already changed. **`--check` is the freshness gate** — it re-renders in memory and exits non-zero if `AGENTS.md` has drifted (diffs rendered output, not mtimes, so it catches drift in transitive `@`-imports too); wire it into CI / a pre-commit hook / the `check_command` so staleness fails loudly instead of silently. Consequence under Opus-4.8 skill-on-demand: once `CLAUDE.md` slims to the eager floor, reviewer-critical facts that *were* carried by eager includes (the `check_command` gate; that `mix test.json` / `mix dialyzer.json` emit JSON **by design** — parse for real failures, never flag the envelope; plain `mix dialyzer` is authoritative when the JSON encoder can't serialize a warning) no longer reach `AGENTS.md` via those imports. Put them in a **self-contained `## Toolchain & check commands` section in `CLAUDE.md`** so they survive the slim-down and flow into `AGENTS.md` on regen (ref: `tapakly/CLAUDE.md`, `ccxt_extract/CLAUDE.md`).
- **Delegation roster — opus last, and don't over-default to codex.** When assigning a dispatchable task to a harness adapter, prefer the external agents — **cursor, codex, grok** — and reserve the **claude/opus** adapter for work that genuinely needs it (harness-surface changes, judgment-heavy review, tasks the cheaper adapters keep bouncing). Opus tokens are precious: spend them last, not by default. Mix adapters across a wave for review coverage. A repo may override the roster in its own CLAUDE.md.
  - **Observed failure mode: reflex-routing everything to `codex`.** Run ledgers skew heavily codex-over-cursor/grok. Actively spread `assignee` across all three; reserve codex for tasks it's genuinely scored best on, not as the default.
  - **`cursor` is a multi-model front-end, not one agent — use both tiers.** `assignee = "cursor"` with no `model` runs its in-house Composer (`composer-2.5-fast`): fast, capable, the cheap rebalance for standard work. `assignee = "cursor"` **+ `model = "claude-opus-4-8-thinking-high"`** (or `claude-opus-4-8-max`) is a full **Opus-tier** implementer/reviewer — route Opus-grade tasks to cursor-on-Opus *instead of* burning the claude/opus adapter. Model IDs churn; confirm with `cursor-agent --list-models` before trusting a literal. Set `assignee` (and `model`) at task creation per `rmap.md`.

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
# Onchain Stack Workspace — Harness

Workspace-specific layout for the seven onchain repos under ZenHive, driven by the **harness** OTP loop (implement → review → land). Pairs with `harness-workflow.md` (the portfolio-wide contract): that file carries the loop shape; this file carries only the onchain-stack specifics — repo roster, on-disk paths, and cross-repo dependency coordination.

Imported family-wide by the seven repos below. The retired Linear-as-queue + Codex/Cursor cloud-delegation workspace lives in `onchain-workspace-delegation.md` (DORMANT).

### Repo Roster

| On-disk path | Repo | Role | Native deps |
|---|---|---|---|
| `~/_DATA/code/hieroglyph` | hieroglyph | ABI encode/decode library (`ABI.*`) | none (yecc/leex) |
| `~/_DATA/code/cartouche` | cartouche | Ethereum substrate: signing, tx encoding, raw RPC, crypto | none |
| `~/_DATA/code/onchain` | onchain | Core primitives on top of cartouche: RPC wrappers, ABI, ERC standards, signing | none |
| `~/_DATA/code/onchain_aave` | onchain_aave | Aave V3 protocol wrappers | none |
| `~/_DATA/code/onchain_evm` | onchain_evm | EVM simulation, Solidity parsing, trace, codegen | Rust NIFs (Rustler) |
| `~/_DATA/code/onchain_js` | onchain_js | npm packages on the BEAM via QuickBEAM | Zig NIFs |
| `~/_DATA/code/onchain_tempo` | onchain_tempo | Tempo chain primitives (0x76 tx, TIP-20) | none |

### Dependency Shape (drives cross-repo coordination)

```
hieroglyph (ABI)
    ↑
cartouche (substrate: signing, RPC, crypto)
    ↑
onchain (core primitives)
    ↑
  ┌─────────────┬──────────────┬──────────────┐
onchain_aave  onchain_evm   onchain_js   onchain_tempo
```

- **hieroglyph release → cartouche bump → onchain bump → downstream bumps.** A new hieroglyph minor cascades up the chain. Sequence the harness tasks: land the upstream bump first, then dispatch the dependent bump against the updated `development`.
- **onchain core API change → onchain_aave / onchain_evm / onchain_js / onchain_tempo cascading bumps.** Loose coupling — downstream bumps can land in any order once `onchain` ships. File one rmap task per downstream repo.
- **cartouche-as-dep change** affects the whole EVM stack identically — same upstream-first ordering as a hieroglyph release.
- **Same-function collisions across repos don't exist** (separate codebases), but a single conceptual change spanning repos is still N tasks, one per repo — not one bundled task. See `harness-workflow.md` § "Parallel Dispatch".

### Branch & Workflow Conventions

- **No PRs for routine work** — completed harness runs ff-merge directly to each repo's `development` branch (the default). Manual hand-build work commits/merges to `development` directly too. (hieroglyph additionally files PRs *upstream* to `exthereum/abi` — orthogonal to harness, see its `upstream-pr-workflow.md`.)
- **Run branches** are `harness/<run-id>` per repo, created off the dispatch branch's `HEAD`. Approved work keeps the branch after worktree teardown.
- **Per-repo task source** is each repo's `roadmap/tasks.toml` (rmap renders `ROADMAP.md`). Harness ingests it as the run queue.

### Harness Specifics — TODO (stubs)

These firm up as the harness conventions for the stack settle. Fill in from the running harness node rather than guessing:

- **TODO: Project registry.** Which of the seven repos are registered in `Harness.ProjectRegistry`, their registered names, dispatch branches, and `check_command` hints. Pull live via `mcp__harness__project_registry-list`.
- **TODO: Landing policy per repo.** Which repos run `landing_policy: :auto` (ff-merge + post-merge audit) vs manual landing. Onchain repo's "no PRs / merge to development" stance suggests `:auto` once trusted.
- **TODO: Reviewer pairing.** Cross-family reviewer adapter assignment per repo, if stack-specific (the portfolio default — "opus last," prefer cursor/codex/grok — lives in `harness-workflow.md` § "Portfolio Conventions").
- **TODO: rmap roadmap paths.** Confirm each repo's `roadmap/tasks.toml` location and any per-repo D/B/U scoring conventions.

### Cross-References

- `harness-workflow.md` — the portfolio-wide implement→review→land contract (loop shape, verdict table, parallel dispatch, landing)
- `onchain-workspace-delegation.md` — DORMANT Linear/cloud-delegation workspace (pre-harness)
- Each repo's `CLAUDE.md` — module layout, architecture, testing specifics

<!-- @-import: ~/.claude/includes/ethereum-rpc.md -->
## Ethereum RPC (Full Archive Node)

We run our own full archive Ethereum node on `blockwatch-one`. Available across all onchain projects.

**Access from Mac:**

| Method | HTTP | WebSocket |
|--------|------|-----------|
| SSH tunnel | `http://localhost:8545` | `ws://localhost:8546` |
| WireGuard VPN | `http://10.100.0.1:8545` | `ws://10.100.0.1:8546` |

**SSH tunnel setup:**
```bash
ssh -L 8545:127.0.0.1:8545 -L 8546:127.0.0.1:8546 blockwatch-one
```

**For integration tests:**
```bash
ETHEREUM_API_URL=http://localhost:8545 mix test.json --quiet --include integration
```

**If RPC connection fails (timeout, connection refused):** Do NOT try to diagnose or fix networking. Ask Tito to:
- Check if the SSH tunnel is running
- Start WireGuard if needed
- Verify the node is up on blockwatch-one

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


## Toolchain & check commands (read before judging a build)

Cross-family harness reviewers read **AGENTS.md** (auto-generated from this file), not the user's Claude skills. The check stack, run per-edit by hooks and once before a PR/merge:

- `mix format --check-formatted` · `mix compile --warnings-as-errors` · `mix credo --strict` · `mix doctor --raise` · `mix sobelow --skip` (honors `.sobelow-skips`; inline `# sobelow_skip` comments are NOT honored).
- `mix test.json --cover --cover-threshold 80 --exclude integration` — coverage gate. **Critical modules (`Aave.Math` and any signing/money path) target 95%; standard logic 80%** (per `critical-rules.md` § coverage tiers).
- `mix dialyzer.json --quiet` — zero real warnings = pass.

**The `.json` mix tasks emit JSON BY DESIGN — that is expected output, never an error or a broken setup:**

- **`mix test.json`** (`ex_unit_json` dep) — ExUnit results as JSON; identical run to `mix test`. Parse it for failures; the JSON envelope itself is never a failure signal. `--cover` can emit a large per-module blob — pipe to a file (`--output /tmp/cov.json`) and `jq` the summary, don't dump it to the transcript.
- **`mix dialyzer.json`** (`dialyzer_json` dep) — dialyzer warnings as JSON. Read the array for *real* warnings; do NOT flag the JSON output as a problem. If the encoder cannot serialize a warning shape, plain `mix dialyzer` is the authoritative check.

(Claude-family agents with the user's global skills can invoke `elixir:ex-unit-json` / `elixir:dialyzer-json` for the full flag/jq reference. For cross-family harness reviewers, the notes above are self-contained.)

## Architecture

- All modules use `Onchain.*` namespace (e.g., `Onchain.Aave.Pool`) — same as when they lived in the monolith
- Pure Elixir, no native deps
- Path dependency: `{:onchain, path: "../onchain"}`
- Standard error tuples: `{:ok, result} | {:error, {:tag, reason}}`

## Module Layout

```
lib/onchain/aave/
  contracts.ex                # address registry (mainnet + multi-chain)
  math.ex                     # to_usd, to_ltv, to_health_factor, to_ray
  pool.ex                     # read + write calls (getUserAccountData, supply, borrow, repay)
  oracle.ex                   # getAssetPrice + Chainlink
  ui_pool_data_provider.ex    # bulk reserve/user data
  faucet.ex                   # testnet faucet interactions
  types/
    user_account_data.ex
    aggregated_reserve_data.ex
    base_currency_info.ex
    user_reserve_data.ex
```

## Dependencies from onchain core

| Module | Used for |
|--------|----------|
| `Onchain.ABI` | ABI encoding/decoding |
| `Onchain.RPC` | eth_call |
| `Onchain.Signer` | Transaction signing (pool writes, faucet) |
| `Onchain.Address` | Validation, checksumming |
| `Onchain.Hex` | Hex encoding/decoding |
| `Onchain.Contract` | Generic contract call (oracle) |
| `Onchain.Decimal` | Decimal math (types) |

## Testing

```bash
mix test.json --quiet                          # Unit tests only
mix test.json --quiet --include integration    # Unit + integration (requires RPC)
mix test.json --quiet --only sepolia_send      # Sepolia write tests
```

Integration tests require `ETHEREUM_API_URL` or `ETH_RPC_URL` env var.
Sepolia write tests additionally require `ETH_SEPOLIA_PRIVATE_KEY` and `ETH_SEPOLIA_RPC_URL`.

## Contract Address Verification

When adding or updating addresses in `lib/onchain/aave/contracts.ex`, verify against the **Aave Address Book CSV**:

```bash
curl -s "https://raw.githubusercontent.com/bgd-labs/aave-address-book/main/safe.csv" | grep -i "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"
```

## Related Packages

- **onchain** — Core Ethereum primitives: `{:onchain, path: "../onchain"}`
- **onchain_evm** — Rust NIFs + codegen: `{:onchain_evm, path: "../onchain_evm"}`
