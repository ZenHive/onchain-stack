<!-- Auto-generated from CLAUDE.md by claude-marketplace/scripts/sync-agents-md.sh — do not edit manually -->

# Onchain

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


Shared Ethereum/blockchain library for the portfolio. Provides read (eth_call) and write (transaction signing) capabilities including the former hieroglyph and cartouche code, renamed to `Onchain.*` (`Onchain.ABI.*` for the codec) in 0.16.0.

<!-- Selective-load (Opus 4.8): eager floor = critical-rules. harness-workflow is eager
     because this repo is harness-driven (the OTP dispatch→review→land loop is the active
     workflow). Everything else previously imported here (worktree, task-prioritization/writing,
     workflow-philosophy, web-command, code-style, development-philosophy/commands, elixir-setup,
     ex-unit-json, dialyzer-json, agent-economy, reach) is skill-on-demand via the elixir /
     task-driver / dev-lifecycle plugins. Re-add an @-import per-surface only if Opus visibly
     degrades on it. See ~/.claude/setup-guide.md § "Skills vs Includes".
     Workspace layout and release ordering are maintained in ../../CLAUDE.md. -->
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

<!-- Consolidated workspace layout and release ordering: see ../../CLAUDE.md. -->
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


<!-- Harness driver contract: this package is dispatched through the single
     `onchain_stack` harness project registered against the monorepo root
     (~/_DATA/code/harness, config/dev.local.exs). The harness MCP server
     (mcp__harness__dispatch__*, port 4018) is the primary surface for dispatching
     roadmap tasks targeting this package to headless agents gated by a cross-family
     reviewer AI; mcp__harness_eval__project_eval is the escape hatch. See .mcp.json.

     On-demand, NOT eager: the harness-driver SKILL.md is 55.8k chars (over the
     40k eager-import limit) — loading it every session is wasteful. Read it only
     when actually driving harness dispatch:
       Read ~/_DATA/code/harness/skills/harness-driver/SKILL.md -->

See the root `CLAUDE.md` for the consolidated layout, the sibling/3 mechanism, and the shared gate adjudications. This
file carries only what's specific to this package.

## Portfolio Context

This package is part of a multi-library portfolio (root `CLAUDE.md` §
Layout). The boundary is **ephemeral vs durable**, not read vs write.

- **onchain** (this package) — core Ethereum primitives, RPC, ABI, signing (includes crypto NIF dependencies)
- **onchain_aave** / **onchain_aerodrome** — protocol wrappers (depend on onchain, pure Elixir)
- **onchain_evm** — Rust NIFs: revm simulation, Solidity parsing, debug/trace, codegen
- **onchain_js** — JS bridge: npm packages on the BEAM via QuickBEAM
- **onchain_tempo** — Tempo blockchain primitives (0x76 transactions, TIP-20, depends on onchain)
- **onchain_agents** *(planned)* — EIP-8004 Trustless Agents: Identity / Reputation / Validation registries, plus a Descripex manifest bridge for trustless verification. Triggered when a consumer needs agent-economy registration; see `ROADMAP.md` "EIP Tracking" (task offset +3000)
- **rexex** *(separate, unabsorbed repo)* — chain indexing, durable facts (ExEx ingestion, Postgres, reorg-safe history)
- **hologram** *(separate, unabsorbed repo)* — JS runtimes, npm access, headless/edge execution

**Where does this feature go?**

1. Talks to Ethereum directly and returns an immediate result? → **onchain**
2. Talks to Tempo chain (0x76 txs, TIP-20 tokens)? → **onchain_tempo**
3. Runs npm packages on the BEAM (solc-js, Uniswap SDK, etc.)? → **onchain_js**
4. Persists or queries chain facts over time? → **rexex**
5. Runs Elixir in JS or reaches npm/edge runtimes? → **hologram**
6. Registers / queries / validates agents via EIP-8004 registries? → **onchain_agents** (when built)
7. Composes those capabilities into a user-facing workflow? → **separate consumer repo**

**Watch boundary:** onchain Phase 8 (eth_subscribe, Transfer parser) overlaps rexex territory. The distinction: onchain returns results to the caller (ephemeral); rexex writes facts to Postgres (durable). If a consumer needs historical queries over indexed data, that's rexex.

**Agent consumers:** AI agents are first-class consumers of this library. See [AGENT_WISHLIST.md](AGENT_WISHLIST.md) for use cases and scenarios. EIP-8004 registration / reputation / validation lives in `onchain_agents` — see `ROADMAP.md` "EIP Tracking".

## Architecture

- **ABI codecs use an alloy Rust NIF**, shipped as checksum-verified precompiled artifacts. Supported consumers do not need Cargo.
- **Former hieroglyph and cartouche code** ships inside this package under `Onchain.*` since 0.16.0 (full map in `CHANGELOG.md`); `:cartouche` config keys are unchanged.
- **zen_websocket** for WebSocket transport (eth_subscribe real-time subscriptions) — a standalone (unabsorbed) dep, plain Hex requirement, no sibling/3 involved
- Signing wraps **ex_secp256k1** (precompiled RustCrypto k256 NIF) internally for signing/key ops via `Onchain.Signer.Secp256k1` — never add a secp256k1 library as a direct dep
- Consumers configure RPC URL via `config :cartouche` or pass URL per-call
- Standard error tuples: `{:ok, result} | {:error, {:tag, reason}}`
- Plain structs with `defstruct` + `@enforce_keys`, no private macro deps

## Node Portability

The family-wide law is `node-portability.md` (`@`-imported above): our archive node is a
privileged environment, not the reference one, and this is an open-source package whose
users run Alchemy, Infura, or a pruned Geth. What is specific to this repo:

- **`Onchain.RPC.base_fee/1` is the worked example.** It reads the final
  `baseFeePerGas` from `eth_feeHistory(1, "latest", [])`. `eth_baseFee` is on
  execution-apis `main` since 2026-06-15 and in no tagged release; Alchemy and
  Infura mainnet refuse it. The former pending-header implementation
  and its bang wrapper were removed before the surviving Cartouche API was
  renamed to `Onchain.RPC` in 0.16.0. Verbatim refusals and the same-batch equality check are in
  `docs/base-fee-portability.md`. A non-obvious portability decision still gets
  a `NOTE (portability):` comment naming the method, who serves it, and the
  consumer-visible error.
- **Node-capability refusals are classified in `Onchain.RPC` (`send_rpc/3` and
  `send_batch/2`).** `Onchain.RPC.Helpers.do_rpc/3` and `Onchain.RPC.batch/2` both call that transport. A method the node does not implement is `{:error, {:method_not_found, map}}`,
  a plan-disabled namespace is `{:error, {:namespace_unavailable, map}}`, and a
  request the node cannot complete (including historical `eth_feeHistory` on Alchemy)
  is `{:error, {:unavailable, map}}`. Unrecognized codes stay `{:rpc_error, map}`.
  Patterns are pinned from live Alchemy + reth responses; `-32001` is not uniquely
  pruned history. See the module's "Node-capability refusals" section.
- **`defrpc`'s compile-time guard does NOT enforce this.**
  `Onchain.RPC.Codegen.ensure_known_method!/1` calls `Specs.lookup/1`, which reads the
  **merged** OpenRPC + `erigon-methods.json` map — a `trace_*` Erigon method passes
  exactly as `eth_getBalance` does. The OpenRPC file is
  `priv/specs/openrpc-v1.0.0-beta.7.json`, built from the execution-apis tag
  v1.0.0-beta.7 (`5aebdfdd45cadeb723be4bd45b4611b71c8b1c85`). `eth_baseFee`,
  `net_listening`, `net_peerCount`, and `web3_clientVersion` are absent from that
  file. Standard-vs-extension is a judgment call at review time, not a gate.
- **Limited-endpoint tests use `Onchain.RPCCase.limited_rpc_url!/0`**
  (`ETHEREUM_LIMITED_RPC_URL` or `ETHEREUM_ALCHEMY_URL`) and flunk with setup
  instructions when unset. Success-path dual-endpoint verification still has no
  automatic seam — `rpc_url!/0` returns a single string — so a portability claim
  on a *successful* read still means you ran it against a hosted endpoint by hand.
- **Endpoint requirements belong in `README.md` § "Node compatibility".**
  It covers historical reads, WebSocket subscriptions, tracing namespaces and
  methods a provider does not implement. Document any additional requirement
  there; the portable next-block base-fee read needs no special endpoint.

## Toolchain & check commands

Full post-merge QA: **`mix ci`** (= `precommit.full`), same shape as every other
package (root `CLAUDE.md` § Gates). Coverage floors are per library (`mix onchain.coverage`, see below). `mix
precommit` is the fast local loop (no dialyzer/coverage).

- **`reach.check --arch --smells` is scanned across `lib, dev, sol/src, test/support`** —
  do not narrow that scope (`--dead-code` times out; see Gate configuration below).
- **`deps.audit.gated`** runs against `.mix_audit_ignore` (symlinked from the
  root file — see root `CLAUDE.md` § Adjudicated findings for the gun/cowlib
  false-positive rationale). Do not add any other advisory id to it.

## Module Layout

```
lib/onchain/
  abi.ex, abi/      # Onchain.ABI codec (alloy NIF); hex conveniences are encode_hex_call/decode_hex_call/decode_hex_error
  configuration.ex  # Onchain.Configuration: former Cartouche root (config + descripex discovery)
  hex.ex            # hex codec, sigils, and the former Onchain.Hex convenience names
  http.ex           # Req options; Onchain.ENS reads :onchain, other owners read :cartouche
  block.ex          # full block decode plus get_by_number/find_by_timestamp
  address.ex        # validate, checksum (EIP-55), normalize, from_public_key/1
  decimal.ex        # to_decimal/2, to_basis_points/1, div_pow10/2
  fees.ex           # suggest_fees/2 — EIP-1559 fee recommendation over Onchain.FeeHistory.t()
  rpc.ex            # Onchain.RPC: the one RPC module (formerly Cartouche.RPC; the 0.15 Onchain.RPC aliases are gone). Next-block base fee is base_fee/1 via eth_feeHistory. Node refusals are classified on send_rpc/3 (:method_not_found / :namespace_unavailable / :unavailable). eth_getStorageAt and EIP-1186 eth_getProof are eth_get_storage_at/3 and eth_get_proof/3
  rpc/proof.ex, rpc/trace.ex  # eth_getProof and trace_* result structs (Onchain.RPC.Trace, not onchain_evm's Onchain.Trace)
  rpc/codegen.ex    # the one defrpc/2 macro, checked against Onchain.RPC.Specs, plus defrpc_bang/2
  rpc/helpers.ex    # shared RPC helpers; parse_block_response/1, parse_transaction_map/1; do_rpc enriches revert maps with :data hex for decode_error/2. parse_log/1 is removed; receipt and subscription logs decode through Onchain.Filter.Log
  erc20.ex          # reads + writes, plus ERC20.Call and ERC20.CallData
  erc721.ex         # ERC-721 NFT reads: ownerOf, tokenURI, balanceOf
  erc1155.ex        # ERC-1155 multi-token reads: balanceOf, balanceOfBatch, uri
  erc7730.ex        # ERC-7730 clear-signing: load/1, format/2, format!/2
  erc7730/
    descriptor.ex   # parse + structurally validate descriptor JSON → struct
    binding.ex      # resolve which display format applies (calldata / EIP-712 / UserOp)
    formatter.ex    # display-rule engine: path resolution + field formatters
  contract.ex       # generic call/4 (encode → eth_call → decode)
  contract/
    abi.ex          # alloy-json-abi JSON parser (core NIF)
    generator.ex    # compile-time ABI JSON codegen; .sol inputs delegate to onchain_evm
  wallet.ex         # classify (EOA/contract), native ETH balance
  multicall.ex      # batched calls via Multicall3
  ens.ex            # ENS resolution: namehash, resolve, reverse, records; address/3 multi-coin (ENSIP-9/10 wildcard + EIP-3668 CCIP-Read); normalize/1, dns_encode/1, evm_coin_type/1
  ens/
    normalize.ex    # UTS-46/ENSIP-15 name normalization (deterministic subset: case-fold + NFC + ignored/disallowed code points)
    ccip.ex         # EIP-3668 CCIP-Read pure helpers + injectable gateway round-trip loop
  transfer.ex       # ERC-20/721/1155 Transfer parsing via Onchain.ABI.decode_event/3
  mev.ex            # private tx submission via Flashbots-style relays (eth_sendPrivateTransaction / eth_sendBundle)
  subscription.ex   # real-time eth_subscribe (newHeads, pendingTx, logs)
  subscription/
    parser.ex       # pure parsing for subscription notification payloads
  dex/
    router.ex       # DEX swap routing — optimal path across Uniswap v2/v3 pools (pure-Elixir v2 math + on-chain QuoterV2 for v3); Onchain.DEX.Router + Pool/Route structs
  aa.ex             # ERC-4337: UserOperation hashing/signing + bundler RPC (v0.6 + v0.7 EntryPoint)
  aa/
    user_operation.ex # ERC-4337 UserOperation struct (unpacked, version-agnostic)
```

**Lives in onchain_aave:** `aave/` (math, contracts, pool, oracle, faucet, ui_pool_data_provider, types/)
**Lives in onchain_evm:** `evm.ex`, `solidity.ex`, `trace.ex`, `native/`

## Testing

- **A green integration run against `localhost:8545` is not a portability claim** — see
  `## Node Portability` above before asserting a method works for consumers.
- Unit tests for all pure functions (hex, address, decimal, math)
- Integration tests are **excluded by default** (`ExUnit.start(exclude: [:integration])` in test_helper.exs)
- `mix test.json --quiet` runs only unit tests — no flags needed to skip integration
- Integration tests for RPC reads require `ETHEREUM_API_URL` or `ETH_RPC_URL` env var
- Integration tests for Sepolia writes (`@tag :sepolia_send`) additionally require `SIGNER_PRIVATE_KEY`
- Use `Onchain.RPCCase.rpc_url!/0` from `test/support/rpc_case.ex` to resolve RPC URL
- Use `flunk/1` with setup instructions for missing credentials, never silent skip

#### Credentialed integration suites

`BUNDLER_RPC_URL` and `MEV_RELAY_URL` are persisted in `~/.secrets` (sourced by `.zprofile`). `ETHEREUM_API_URL` defaults to the `localhost:8545` archive-node tunnel — bring it up (`ssh -L 8545:127.0.0.1:8545 blockwatch-one`) or override inline with `$ETHEREUM_ALCHEMY_URL` (mainnet, also serves ERC-4337 methods).

| Suite (tag) | Env vars | Notes |
|---|---|---|
| Differential RPC (`:differential`) | `ONCHAIN_DIFFERENTIAL_TESTS=1` + mainnet `ETHEREUM_API_URL` | Compares `Onchain.RPC` wrappers with independently decoded wire results on one mainnet URL. Reads historical block `20_000_000` → needs archive. |
| AA bundler (`aa_integration_test.exs`) | `BUNDLER_RPC_URL` | Read-only ERC-4337 calls. Alchemy serves these on its standard node URL. |
| MEV relay (`mev_integration_test.exs`) | `MEV_RELAY_URL` (`https://rpc.flashbots.net`) | No `MEV_AUTH_HEADER` — Flashbots' `signature required` reply is itself the valid JSON-RPC round-trip the test asserts. |
| Node-capability refusals (`rpc/node_refusal_integration_test.exs`) | `ETHEREUM_API_URL` (archive `-32601`) plus `ETHEREUM_LIMITED_RPC_URL` or `ETHEREUM_ALCHEMY_URL` (hosted `-32600` / `-32001`) | Flunks with the exact export commands when the limited URL is unset. |

Run differential + AA + MEV (do **not** point `ETHEREUM_API_URL` at Alchemy
when running the node-refusal suite — that suite pins archive `-32601` on
`rpc_url!/0` and hosted refusals on `limited_rpc_url!/0`):

```bash
ONCHAIN_DIFFERENTIAL_TESTS=1 ETHEREUM_API_URL="$ETHEREUM_ALCHEMY_URL" \
mix test.json --quiet --include integration --include differential
```

**Differential only — `ocdiff` shell helper** (in `~/.zshrc`): runs the differential suite against the Alchemy archive (no SSH tunnel needed); pass a URL to override (`ocdiff http://localhost:8545`).

**This is now the only way the differential suite ever runs** — there is no
scheduled/nightly run any more (removed with every workflow, family-wide,
2026-08-22), so archive-node drift no longer surfaces on its own. Run
`ocdiff` deliberately when touching RPC decoding or block/receipt shapes.

### Quick Commands

```bash
mix test.json --quiet                          # Unit tests only (integration excluded by default)
mix test.json --quiet --failed --first-failure # Iterate on failures
mix test.json --quiet --include integration    # Unit + all integration tests
mix test.json --quiet --only integration       # Integration tests only
mix test.json --quiet --only sepolia_send      # Sepolia write tests only (sends transactions)
mix dialyzer.json --quiet                      # AI-friendly dialyzer output
mix credo --strict --format json               # Static analysis (JSON output)
```

## Related Packages

- **onchain_aave** — Aave V3 wrappers: `sibling(:onchain, ...)` consumer
- **onchain_evm** — Rust NIFs + codegen: `sibling(:onchain, ...)` consumer
- **onchain_js** — JS bridge (QuickBEAM): `sibling(:onchain, ...)` consumer
- **onchain_tempo** — Tempo chain primitives: `sibling(:onchain, ...)` consumer

## Consolidated ABI and Cartouche sources

hieroglyph's `ABI.*` and cartouche's `Cartouche.*` sources moved into this
package and were renamed to `Onchain.*` in 0.16.0; they now live under
`lib/onchain/` (`abi.ex` and `abi/` for the codec, `configuration.ex` for the
former `Cartouche` root). The former yecc/leex grammar is removed; type parsing
uses alloy. `priv/*.json`, `sol/`, the original test suites, fixtures and
support modules move with them. `Onchain.Application` is onchain's application
callback; existing `:cartouche` configuration keys and supervisor names remain
compatible. Mix warns that the `:cartouche` application is absent when loading
that config; the keys are still read. The pre-0.16 `.etf` oracle fixtures keep
their recorded `ABI.*`/`Cartouche.*` atoms; `Onchain.Test.LegacyModuleNames`
translates them on replay.

Full QA runs `mix onchain.coverage`: the former ABI modules (`Onchain.ABI*`) retain 95%,
the former cartouche modules (listed by new name in the task) retain 85%, the
signer modules retain a separate 95% floor, and the rest of Onchain retains 70%.
`.doctor-hieroglyph.exs` and `.doctor-cartouche.exs` select the same former
sources by their new paths.
`Onchain.Contract.IConsole` and its coverage exclusion are gone; `Onchain.Contract.Sleuth` is a thin `use` of `Onchain.Contract.Generator`.
The original strict Doctor policies are retained in `.doctor-hieroglyph.exs`
and `.doctor-cartouche.exs`. The ABI manifest check remains in full QA.

Reach includes all hand-written `lib`, `dev`, `sol/src`, and `test/support` sources.
The old generated Erlang parser under `src` was removed by the alloy migration. The merged 109-file scope reproduces cartouche's `--dead-code` timeout:
`Task.Supervised.stream(30000)` exits from `Reach.CLI.Pipe.safely/1` under reach
2.8.4 after Architecture Policy reports OK. Full QA therefore runs
`reach.check --arch --smells`, just as cartouche did. Re-test dead-code after a
reach upgrade. No hand-written source scope was narrowed.

Default tests combine the former exclusions: integration, differential,
debug_namespace and dev_node. Cartouche's test config supplies its offline
RPC stubs and default test signer. Live tests require the original credentials
and node capabilities described by their test support modules.

ABI verification notes live in `docs/abi-verification-ledger.md`; Cartouche's
ledger is `docs/verification-ledger.md`. Original licenses and package history
are preserved in `docs/hieroglyph/` and `docs/cartouche/`.


## Core ABI native build and release verification

`Onchain.ABI.Native` is the generic Rustler boundary in `native/onchain_abi`. It accepts
operations, type strings or compiled schema resources, and BEAM values. Its one
recursive converter handles values without JSON serialization. `Onchain.ABI.TypeEncoder`
and `Onchain.ABI.TypeDecoder` remain compatibility facades with no handwritten value
codec. `Onchain.ABI.Validation` normalizes the historically ignored tuple offsets before
alloy follows them and passes payloads through unchanged when their offsets
already name those tails. Zero-width aggregate shape and packed-array padding
need explicit compatibility adaptation around alloy. `Onchain.Filter` groups
logs by topic, calls `Onchain.ABI.Event.decode_events/3`, then restores the original log
order.

The boundary's rules are in `docs/specs/onchain-native.md` (repo root):

- NIF-1: panics are caught, and malformed input returns an error tuple.
- NIF-2: input limits on type strings, payloads, nodes and batch size.
- NIF-3: normal-scheduler vs dirty-CPU split.
- NIF-4: output parity with the pre-alloy oracle fixture.
- NIF-5: `strict: true` semantics.
- NIF-6: `fixed`/`ufixed` are rejected (exthereum/abi#54). Solidity cannot yet
  assign to or from fixed-point types, so a codec would support nothing usable
  (rationale from `docs/hieroglyph/README.md`).
- NIF-7: bounded, separate schema and signature caches. Inserts are serialized
  per cache (`:global.trans`), so concurrent misses cannot drop each other's
  entry; misses beyond the 1,024-entry cap compile without retention.

Payload preflight bounds alloy allocation before decoding, including
repeated/overlapping offsets. Compiled schema resources hold only immutable parsed
types and event topic0, with no VM environment or process-owned terms. The
facades keep their doctests.

`Onchain.Precompiled` and `scripts/build-precompiled.sh` live here;
`onchain_evm` consumes the module and delegates its build script here. The
distribution rules (DIST-1..8) are in `docs/specs/onchain-distribution.md`. In
short: this checkout source-builds core and needs Rust/Cargo (DIST-4), while
`ONCHAIN_PUBLISH=1` and Hex installs download verified artifacts and fail on a
bad checksum (DIST-2, DIST-3). `ONCHAIN_BUILD` / `ONCHAIN_EVM_BUILD` are scoped
per crate (DIST-7), and unsupported hosts are rejected (DIST-6).

Publish-time commands (run from this package; artifacts must be built from the
exact release revision):

```sh
# Requires Rust targets, Zig and cargo-zigbuild on the release builder only.
# Use an empty OUT_DIR; the script rejects stale artifact directories.
OUT_DIR="$PWD/artifacts/precompiled/release" scripts/build-precompiled.sh
# Produces aarch64/x86_64 Darwin, aarch64/x86_64 GNU/Linux, x86_64 musl.
# Human step, never run by an agent (public tag + binaries; root CLAUDE.md publish step 10):
#   gh release create onchain-v<ver> artifacts/precompiled/release/*.tar.gz --target <release sha> ...
# After the human confirms the release:
mix rustler_precompiled.download Onchain.ABI.Native --all --print
# Commit checksum-Elixir.Onchain.ABI.Native.exs, then verify packaging:
ONCHAIN_PUBLISH=1 mix deps.get
ONCHAIN_PUBLISH=1 mix hex.build | tee artifacts/hex-build.log
! grep -q 'excluded from the package' artifacts/hex-build.log
# Inspect metadata/files and ensure checksum-Elixir.Onchain.ABI.Native.exs is included.
# Restore the development lock after publish preparation.
git restore mix.lock
```

Verify a fresh consumer of the built tarball with Cargo absent from PATH and
all force-build environment variables unset. After `mix deps.get`, run
`mix compile` and `mix run -e 'IO.inspect(Onchain.ABI.encode("f(uint256)", [1]))'`.
Use an empty build directory; ensure `System.find_executable("cargo") == nil`.
An offline smoke check can seed `RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH` with the
locally built tarballs. That verifies checksum/loading/compilation but **does not
verify a GitHub release download**; repeat with an empty cache after asset upload.
Never publish onchain before its checksummed assets are downloadable. EVM's own
assets and version remain independent of the core package release.

Performance is reporting only. `bench/abi.exs` compares the production facades
with the preserved pre-migration codecs under `bench/legacy`; `bench/results.json`
and `bench/README.md` record ips, BEAM allocation and compilation/phase costs.
`bench/teardown_test.exs` is the shared consumer shutdown probe: run it together
with focused package tests and record the OS exit status after the VM halts.


Full QA (`mix ci`) also runs `cargo audit`, `cargo test` and
`cargo clippy --all-targets -- -D warnings` for `native/onchain_abi` through
the root's shared development helper. Production denies `unwrap_used`; tests
are exempt and `expect_used` is allowed. Missing Cargo/clippy skips visibly;
missing cargo-audit fails with `cargo install cargo-audit --locked`.
Vulnerabilities and offline advisory-fetch failures fail the gate;
unmaintained/yanked warnings pass. Any ignore must be a commented per-advisory
entry in the crate's `.cargo/audit.toml`. See root Gates for the shared policy.
The deep-input boundary test uses 1,000 tuple/array levels under 4,096 bytes:
the existing 64 nesting-marker limit rejects them before alloy allocation.
