# Cartouche — Cleanup Backlog

Overflow tasks from the `mix credo --strict` / `mix doctor` / `mix dialyzer.json` audit run on 2026-04-22 against `development` branch.

**Scope:** this file covers items NOT already in [ROADMAP.md](ROADMAP.md). ROADMAP Phases 1–6 already track the 142 real-code dialyzer warnings. Everything here is net-new: credo style, doctor coverage gaps, the auto-generated-file noise floor, and Elixir 1.20 compile warnings.

**Scoring:** `[D:n/B:n/U:n → Eff:x]` per `~/.claude/includes/task-prioritization.md`.
- `B` = impact magnitude (noise reduction, CI signal-to-noise, onchain unblocks).
- `U` = unlock leverage (makes future dialyzer/credo/doctor runs actionable; enables a quality gate).

**When closing a task here:**
1. Mark it ✅ in this file (don't delete — keep for traceability until cleanup.md itself is retired).
2. If the same change also closes a task in [ROADMAP.md](ROADMAP.md) (Phases 1–6 overlap with real-code dialyzer fixes in particular), mark the ROADMAP task ✅ too and add the changelog entry per `~/.claude/includes/task-prioritization.md`.
3. When every task in a phase here is ✅, collapse the phase to a one-line summary.
4. When all phases are ✅, delete `cleanup.md` — the green-tool state is the living record.

---

## Audit snapshot

| Tool | Total | Real / actionable | In ROADMAP | New (here) |
|---|---|---|---|---|
| `mix credo --strict` | 72 | 72 | 0 | **72** |
| `mix doctor` | 13 failing modules | 13 | 0 | **13** |
| `mix dialyzer.json` | ~~6 620~~ 1 626 post-A1 | 142 real + ~~6 478~~ 1 525 generated | 142 (Phases 1–6) | ~~**6 478**~~ **1 525** + misc (A1b) |
| `mix compile` (1.20-rc.4) | 2 warnings | 2 | 0 | ~~2~~ 0 (C1 ✅; unrelated `@doc` redefinition at `signer.ex:30` remains) |

The 6 478 `i_console.ex` warnings are one root cause amplified across 1 130 auto-generated decode functions. Fix the generator or the helper signature and most evaporate in a single change.

---

## 🎯 Current Focus

**Phase A — kill the noise floor.** Every `mix dialyzer.json` run is 98% noise from one generated file, which hides the 142 real findings Phases 1–6 already plan to fix. Phase A is 1–2 days of work that unblocks the signal.

Phase B (credo quick wins) and Phase C (Elixir 1.20 compile warnings) are small and independent — run them in parallel worktrees after Phase A lands.

Doctor coverage (Phase D) is the longest slog and purely QoL for consumers — defer until `0.1.0` ships and Phases 1–6 are closed.

---

## Documentation policy

This repo treats AI agents as first-class consumers alongside humans. All public modules follow:

1. **`api()` for agents** — every public function uses the `descripex` `api()` macro to declare params (with `:kind` — `:value` vs `:exchange_data`), return shape, errors, and composition hints. This generates the machine-readable `@doc hints:` slot consumed by MCP tools, EIP-8004 validators, and the manifest endpoint. See `~/.claude/includes/agent-economy.md`.
2. **`@doc` for humans** — plain-prose docstring placed *after* `api()` so it overwrites slot 4 only, leaving slot 5 (hints) intact.
3. **Avoid `@moduledoc false` / `@doc false`** — hiding from ExDoc also hides from `Code.fetch_docs/1`, which breaks agent discovery. Mark internal-only modules with `api(..., kind: :internal, ...)` plus a short `@moduledoc` explaining scope. Use `false` only when there's a specific, documented reason (e.g., test-support shims, truly private compile-time helpers).

Auto-generated code (IConsole, Sleuth contract bindings) must emit `api()` from the generator — see Task D1 below. Verify `:descripex` is in `mix.exs` deps before starting D1/D2/D5.

---

## Phase A — Auto-generated file noise floor

- [x] ✅ **A1: Root-cause the `i_console.ex` no_return / call cascade** [D:3/B:9/U:9 → Eff:3.0]
      Root cause was upstream in `:abi` (missing `@spec`s + singular-vs-list `returns:` type in `FunctionSelector.t()`). Full investigation narrative + counts in [CHANGELOG.md](CHANGELOG.md) `## [Unreleased]`. Residual ~1 525 warnings tracked in A1b.

- [x] ✅ **A2: Regenerate `i_console.ex` after A1 and commit the diff** [D:1/B:3/U:5 → Eff:4.0]
      Not needed — runtime data shape was correct all along. The fix lived in the consumer's typespecs, not the generated code. No regen required.

- [ ] **A1b: Root-cause the residual i_console no_return cascade in `Cartouche.VM`** [D:5/B:5/U:5 → Eff:1.0] 📋
      ~1 525 i_console warnings remain. Two hypotheses ruled out by direct measurement (PLT confirmed fresh via `mix dialyzer.json --plt`):
      - **Not** the `decode_error/1` `if true do … else end` catchall — patching it to `@spec decode_error(binary()) :: {:ok, String.t(), binary()} | :not_found; def decode_error(_), do: :not_found` dropped total by exactly 1 (the dead pattern itself); cascade unaffected.
      - **Not** `ABI.decode/3` returning narrowly — widening `@spec decode/3 :: [any()] | map()` (to cover `decode_structs: true` returning a map) had zero effect.

      Real source: dialyzer flags `Cartouche.VM.push_n/3` (vm.ex:416), `run_code/3` (vm.ex:903), `exec/2` (vm.ex:932) as `no_return` directly. That cascades through `exec_call/3` into every `exec_vm_*` function in `i_console.ex`. Likely related to bitstring success typing post-C1 (the size-var pins were syntactic; success typing on `<<x::size(^n), rest::binary>>` patterns may still narrow). Investigation needed: (1) read each VM warning chain, (2) determine whether the `no_return` is genuine (function actually has no terminating clause for some input) or a 1.20 type-checker artifact. **Validation:** `mix dialyzer.json --plt` then `jq '[.warnings[] | select(.file | endswith("vm.ex")) | select(.warning_type == "no_return")] | length' /tmp/d.json` — driving this to 0 should collapse the i_console cascade.

- [ ] **A3: If A1b can't drive i_console below ~50, add `.dialyzer_ignore.exs` pattern** [D:2/B:5/U:7 → Eff:3.0] 🎯
      Fallback only. Add a file-scoped ignore entry with a comment linking back to A1b. DialyzerJSON honours `.dialyzer_ignore.exs` (see `dialyzer-json.md`) — ignored items move to `summary.skipped`, keeping the signal clean.

---

## Phase B — Credo quick wins (lib)

50 lib findings. Group by effort.

### B1: Mechanical fixes — batch PR [D:2/B:3/U:5 → Eff:2.0] 🚀

- [ ] TrailingWhiteSpace — `lib/cartouche/receipt.ex:26` (1)
- [ ] ExpensiveEmptyEnumCheck — `lib/mix/cartouche.gen.ex:746` (1) — `Enum.count/1` → `Enum.empty?/1`
- [ ] MaxLineLength — `block.ex:67`, `receipt.ex:20,30,119` (4). Some are long ABI/JSON strings that likely can't wrap — add `# credo:disable-for-next-line` with justification where wrapping breaks clarity.
- [ ] AliasUsage — `lib/cartouche/solana/signer.ex:109`, `lib/cartouche/vm.ex:47` (×2) (3)
- [ ] FunctionNames — `lib/cartouche/base58.ex:53` (1) — one camelCase fn to rename OR add `# credo:disable-for-lines:N` if it matches an external protocol name.

### B2: Test-support external-method names — allowlist, don't rename [D:1/B:3/U:5 → Eff:4.0] 🎯

- [ ] `test/support/client.ex` has 17 `FunctionNames` violations — `eth_getBalance`, `eth_newFilter`, etc. These mirror JSON-RPC method names on purpose. Add a scoped disable to the module via `# credo:disable-for-this-file Credo.Check.Readability.FunctionNames` with a one-line comment explaining the convention mirror. Never rename — they're a test fixture for wire-compatibility.

### B3: Test AliasUsage [D:1/B:1/U:3 → Eff:2.0] 📋

- [ ] 7 AliasUsage warnings in `test/` — mechanical `alias` hoisting to top of module. Defer to B1's PR or a separate test-cleanup pass.

### B4: Nesting depth violations — read before fixing [D:5/B:3/U:3 → Eff:0.6] ⚠️

16 lib nesting violations. Most are `case` inside `with` or nested `if`. Walk each with a judgment call:
- [ ] `rpc.ex:105, 194, 1399, 1588` — RPC dispatch; likely ok-as-is, extract helper only if it improves read
- [ ] `vm.ex:510, 554, 757` — VM interpreter; depth 5 at 757 may justify extraction
- [ ] `assembly.ex:335`, `open_chain.ex:87`, `sleuth.ex:142`, `solana/token.ex:56,99`, `solana/transaction.ex:208`, `typed.ex:588`, `mix/cartouche.gen.ex:153,337`
- Rule: extract only if the inner block is named/reusable. Otherwise `# credo:disable-for-next-line Credo.Check.Refactor.Nesting` with a one-line reason.
- Do NOT pre-extract to satisfy credo — that produces one-use helpers and hurts readability.

### B5: CyclomaticComplexity — design-level [D:7/B:3/U:3 → Eff:0.43] ⚠️

8 lib violations, including:
- [ ] `assembly.ex:503` (complexity **84**) — likely the opcode dispatch
- [ ] `vm.ex:590` (complexity **77**) — likely the VM opcode interpreter
- [ ] `mix/cartouche.gen.ex:247` (complexity **55**) — codegen dispatch
- [ ] `rpc.ex:42, 86, 1350`, `sleuth.ex:104`, `mix/cartouche.gen.ex:170` (10–12)

Big dispatch tables on opcodes/methods are legitimate — the alternative is a scattered map of `{opcode => fn}` that's worse to read. Recommend per-function `@credo :disable` with a note, rather than forced refactor. Treat the 10–12 mid-tier ones case by case.

### B6: FunctionArity 9–12 in `transaction.ex` [D:5/B:3/U:3 → Eff:0.6] ⚠️

- [ ] `transaction.ex:285 (9), 312 (12), 790 (9), 865 (9)` — transaction-field encoders. Ethereum transaction structs have 9–12 fields; accepting them positionally mirrors the underlying spec. Options: (a) accept a struct and pattern-match in head (best), (b) credo-disable with note. Decide per-function.

### B7: Exception naming consistency [D:3/B:1/U:3 → Eff:0.67] ⚠️ DISCUSS

- [ ] `ExceptionNames`: `Cartouche.Hex.HexError`, `Cartouche.VM.VmError` clash with the `Invalid*` strategy used elsewhere (`InvalidAssembly`, `InvalidCode`, `InvalidOpcode`, `InvalidFileError`). Rename is a **breaking API change** (`HexError` appears in public `@doc` examples). Options:
  1. Keep names, credo-disable in both files with a note ("public API name — frozen").
  2. Rename `Invalid*` → `*Error` for internal consistency (more breakage, wider blast).
  3. Accept inconsistency permanently, raise credo's priority threshold for this check.
- Recommendation: **(1)**. Don't break public API for a style check.

### B8: RaiseInsideRescue [D:1/B:3/U:3 → Eff:3.0] 🚀

- [ ] `lib/cartouche/sleuth.ex:204` — change `raise` inside rescue → `reraise __STACKTRACE__` to preserve origin stack. Real correctness win.

### B9: TagTODO [D:0/B:0/U:0] — SKIP

- 2 lib + 1 test `TagTODO` findings are working as designed (project policy is `TODO:` prefix REQUIRED for tracked tech debt — see `~/.claude/includes/development-philosophy.md`). These are informational, not actionable.

---

## Phase C — Elixir 1.20-rc.4 compile warnings

- [x] **C1: Pin bitstring size vars across the codebase** [D:1/B:5/U:7 → Eff:6.0] 🎯 ✅ 2026-04-22
      Originally scoped to lines 346, 349 in `solana/transaction.ex`'s `read_instructions/3`. On fix, the same 1.20 rule was firing in more places — all pinned in one pass:
      - `lib/cartouche/solana/transaction.ex:346,349` — `^num_accounts`, `^data_len`
      - `lib/cartouche/assembly.ex:287` — `^n` in `disassemble_opcode/1`
      - `lib/cartouche/vm.ex:479` — `^index`, `^count` in `Memory.read_memory/3`
      - `lib/cartouche/vm.ex:490` — `^offset`, `^value_size` in `Memory.write_memory/3`
      - `lib/cartouche/vm.ex:508` — `^val_len` (×2) in `Operations.sign_extend/2`
      - `lib/cartouche/vm.ex:524` — `^i` (×2) in `Operations.get_byte/2`
      - `lib/cartouche/vm.ex:546` — `^ret_size` in `static_call/1`
      Behaviour-preserving: pinned form reads the already-bound value from surrounding scope as size, which is exactly what the un-pinned form did pre-1.20. Verified with 166 tests passing across `test/solana/transaction_test.exs`, `test/assembly_test.exs`, `test/vm_test.exs`. Clean on `mix compile` under Elixir 1.20-rc.4 for these sites — only remaining compile warning is the unrelated `@doc` redefinition at `signer.ex:30` (tracked separately).

---

## Phase D — Doctor coverage (defer)

**Status:** 5.5% `@doc` / 4.0% `@spec` coverage. 100% `@moduledoc`. Fails the 50% threshold.

Failing modules ranked by function count × current gap:

| Module | Functions | @doc | @spec | Treatment |
|---|---|---|---|---|
| `Cartouche.Contract.IConsole` | 3 816 | 0% | 0% | Generator-side fix (see D1) |
| `Mix.Tasks.Cartouche.Gen` | 24 | 4% | 4% | Codegen task; docs on `run/1` + private-fn `@spec` |
| `Cartouche.Contract.Sleuth` | 22 | 0% | 0% | Codegen target; likely also auto-generated |
| `Cartouche.VM` | 19 | 11% | 0% | Core VM module; invest in docs, ties to ROADMAP Phase 5/6 |
| `Cartouche.Sleuth` | 6 | 0% | 0% | Unused — see D3 (some fns already flagged unused_fun) |
| `Cartouche.VM.{Operations, Memory, FFIs, Context, ExecutionResult}` | 1–4 each | 0% | 0–100% | Internal types/helpers; `@moduledoc false` is legitimate if internal |
| `Cartouche.OpenChain.API` | 3 | 33% | 67% | Small gap; fill in |
| `Cartouche.Filter.Log` | 1 | 0% | 0% | One fn; fill in |

### Tasks

- [ ] **D1: Add `api()` + `@doc` + `@spec` emission to the `Cartouche.Contract.*` generator** [D:6/B:9/U:9 → Eff:1.5] 🚀
      Edit `lib/mix/cartouche.gen.ex` to emit, for every generated contract function:
      - `api(name, description, params: [...], returns: %{...}, errors: [...])` — params built from ABI inputs (kind: `:value` for scalars, `:exchange_data` for `bytes32` ids / addresses the agent must fetch), returns from ABI outputs, errors from Solidity custom errors where available.
      - `@doc` — NatSpec prose where present, else ``"Calls `<contract>.<function>` (selector `0x...`)."``.
      - `@spec` from ABI types.
      Regenerate `lib/cartouche/contract/i_console.ex` and `lib/cartouche/contract/sleuth.ex`. Covers D1 + D3's "document if reachable" path in one pass. Lifts doctor coverage above 50% AND makes every onchain method visible to MCP tool generation.

- [ ] **D2: Minimal `api()` + `@moduledoc` for VM internals and `Filter.Log`** [D:2/B:3/U:5 → Eff:2.0] 🚀
      Per the documentation policy, avoid `@moduledoc false`. Audit `Cartouche.VM.{Operations, Memory, FFIs, Context, ExecutionResult}` and `Cartouche.Filter.Log`:
      - Add a one-paragraph `@moduledoc` describing scope (e.g., "internal to VM — not part of the public API").
      - For each public function, add `api(name, description, params: [...], returns: %{...})` with a short description — enough that an agent slicing a VM bug via `mix reach.impact` can read what the helper does.
      - Only use `@moduledoc false` if the module is genuinely a private compile-time artifact (none of these six qualify).

- [ ] **D3: Document or remove `Cartouche.Sleuth` internals** [D:3/B:3/U:3 → Eff:1.0] 📋
      3 fns (`try_decode/3`, `try_decode_bytes/1`, `postprocess/3`) are flagged `unused_fun` by dialyzer. Delete if dead, document if reachable via dynamic dispatch. See E1.

- [ ] **D4: Fill remaining small gaps** [D:3/B:3/U:3 → Eff:1.0] 📋
      `Cartouche.OpenChain.API` (3 fns), `Mix.Tasks.Cartouche.Gen` public `run/1`, `Cartouche.VM` core API. Tie to ROADMAP Phase 4/5 when those files are open anyway.

- [ ] **D5: `api()` annotation sweep for public modules** [D:7/B:7/U:7 → Eff:1.0] 📋
      Module-by-module: add `api()` to every public function in the public Cartouche API surface. Priority order by agent-utility:
      1. `Cartouche.RPC` — external surface most agents call first
      2. `Cartouche.Transaction` (+ `V1`, `V2`), `Cartouche.Signer`, `Cartouche.Hex`, `Cartouche.Base58`
      3. `Cartouche.Solana.{RPC, Keys, PDA, ATA, Token, Programs, Transaction.*}`
      4. `Cartouche.{Erc20, Filter, Receipt, Block, FeeHistory, OpenChain, Typed, DebugTrace, Trace, Recover, Assembly}`
      5. `Cartouche.VM` — core entry points (`exec/2`, `run/1` etc.); internals covered by D2
      Add `use Descripex, namespace: "/..."` per module. Wire a `Cartouche.Manifest` wrapper (`Descripex.Manifest.build([...])`) and a `Cartouche.describe/{0,1,2}` facade per `agent-economy.md` progressive disclosure pattern. Bundle with whatever file is already open during other cleanup work — don't block on a single sweep PR.

---

## Phase E — Dialyzer items NOT in ROADMAP

ROADMAP Phases 1–6 cover `invalid_contract` + most `no_return` / `call` / `pattern_match` on `hex.ex`, `rpc.ex`, `signer.ex`, `trace.ex`, `trace_call.ex`, `typed.ex`, `erc_20.ex`, `vm.ex`. These are the leftovers:

- [ ] **E1: Remove 13 `unused_fun` warnings** [D:2/B:3/U:5 → Eff:2.0] 🚀
      - `sleuth.ex`: `try_decode/3`, `try_decode_bytes/1`, `postprocess/3` — verify dead, delete
      - `vm.ex`: `pop2_and_push/2`, `unsigned_op1/2`, `unsigned_op2/2`, `unsigned_op3/2`, `signed_op2/2`, `unsigned_signed_op2/2`, `static_call/1`, `pop_call_args/1`, `word_to_address/1`, `run_code/2` — likely scaffolding for incomplete VM opcodes. Delete or mark `@dialyzer {:nowarn_function, ...}` with a TODO(Phase 5) pointer. Ties to ROADMAP Phase 5 investigation.

- [ ] **E2: 3 `unknown_type` warnings** [D:1/B:3/U:3 → Eff:3.0] 🚀
      Inventory and fix — usually a stale `@spec` referencing a renamed type. Small.

---

## Execution order (suggested)

1. **Phase C** (1 hr) — compile clean first. No dependencies.
2. **Phase A1 + A2** (1–2 days) — biggest single noise reduction. Must land before real-code dialyzer phases pay off.
3. **ROADMAP Phases 1–6** — existing plan, now against a quiet dialyzer.
4. **Phase B1 + B2 + B8** (half day) — batch credo quick wins as one PR.
5. **Phase E1 + E2** (half day) — clean up dialyzer tail.
6. **Phase B4–B7** — case-by-case, bundle with whatever file is open.
7. **Phase D** — D1 first (generator emits `api()`, unblocks IConsole + Sleuth automatically). D2, D4, D5 bundled opportunistically during normal work. Full completion deferred until after `0.1.0`.

A–C + E1 + E2 roughly = 3 focused days. B and D are background work to bundle opportunistically.

---

## Natural session bundles

Cleanup tasks cluster by the *file set they touch* and *the tool they're gated on*. Each bundle below is sized to one Claude Code session (one fresh context, one PR, one review).

### Session 1 — "Compile clean" (~30 min, 1 PR)
**Tasks:** C1.
**Files:** `lib/cartouche/solana/transaction.ex` only.
**Why bundled:** both warnings are in one function (`read_instructions/3`), both are the same fix pattern (`^num_accounts` / `^data_len`). Zero coupling to anything else.
**Verification:** `time mix compile` under 1.20-rc.4 shows 0 warnings.

### Session 2 — "Kill the residual VM cascade" (half–1 day, 1 PR)
**Tasks:** A1b (+ A3 fallback only if A1b falls short).
**Files:** `lib/cartouche/vm.ex` — dialyzer flags `push_n/3` (:416), `run_code/3` (:903), `exec/2` (:932) as `no_return`, cascading through `exec_call/3` into every `exec_vm_*` in `i_console.ex`.
**Why bundled:** A1 + A2 already closed (root cause was upstream in `:abi`, see CHANGELOG `## [Unreleased]`). The residual ~1 525 warnings trace to VM-internal success typing, not the generator — so this is now a VM spec investigation, not a codegen task.
**Verification:** `mix dialyzer.json --plt` then `jq '[.warnings[] | select(.file | endswith("vm.ex")) | select(.warning_type == "no_return")] | length' /tmp/d.json` → 0 collapses the i_console cascade.

### Session 3 — "Credo quick wins" (half day, 1 PR)
**Tasks:** B1 + B2 + B8.
**Files:** `lib/cartouche/receipt.ex`, `lib/mix/cartouche.gen.ex`, `lib/cartouche/block.ex`, `lib/cartouche/solana/signer.ex`, `lib/cartouche/vm.ex`, `lib/cartouche/base58.ex`, `lib/cartouche/sleuth.ex`, `test/support/client.ex`.
**Why bundled:** all mechanical or one-line changes, all verified by a single `mix credo --strict --format json` run. B8 (raise → reraise) is correctness-adjacent and worth landing next to style fixes for a cleaner commit log.
**Verification:** `mix credo --strict --format json` — targeted issues gone; count drops from 72 to ~30.

### Session 4 — "Dialyzer tail" (half day, 1 PR)
**Tasks:** E1 + E2 + D3.
**Files:** `lib/cartouche/sleuth.ex`, `lib/cartouche/vm.ex`.
**Why bundled:** D3 ("document or remove Sleuth internals") and E1's Sleuth deletion check overlap completely — same three functions, same decision (dead or reachable via dynamic dispatch). The VM half of E1 lives in the same module as Phase 5 ROADMAP work, so either run this *after* Phase 5 (if Phase 5 deletes them) or run it *with* Phase 5 (fold E1 VM items into that session).
**Verification:** `mix dialyzer.json --summary-only` — `unused_fun` at 0, `unknown_type` at 0.

### Session 5 — "Generator emits api()" (1 day, 1 PR) — D1
**Tasks:** D1 alone.
**Files:** `lib/mix/cartouche.gen.ex`, regenerated `lib/cartouche/contract/{i_console,sleuth}.ex`. Also `mix.exs` if `:descripex` isn't a dep yet.
**Why solo:** touches codegen and produces the largest diff in the repo (1,130+ functions gain `api()` + `@doc` + `@spec`). Mixing with anything else makes the diff unreviewable. Depends on Session 2 landing first (so the generated file is clean before we pile `api()` into it).
**Verification:** `mix doctor` passes > 50% on IConsole + Sleuth; `Cartouche.Contract.IConsole.__api__/0` returns a populated map.

### Session 6 — "VM internals annotation" (half day, 1 PR) — D2
**Tasks:** D2 (+ optionally E1's VM half if not done in Session 4).
**Files:** `lib/cartouche/vm/{operations,memory,ffis,context,execution_result}.ex`, `lib/cartouche/filter/log.ex`.
**Why bundled:** same conceptual layer (VM internals + one filter helper), same doctor pass for verification, same `@moduledoc`/`api()` pattern applied six times. Small enough to hold in one context window end-to-end.
**Verification:** `mix doctor` — all six modules pass; `Cartouche.VM.Operations.__api__/0` returns populated.

### Session 7+ — "Public API annotation sweep" (D5, chunked)
D5 does NOT fit in one session. Chunk by the priority tiers already listed in D5:
- **Session 7a:** `Cartouche.RPC` alone (large module, high agent impact). Wire `Cartouche.Manifest` + `Cartouche.describe/{0,1,2}` here — this is where the agent-discovery entry points land.
- **Session 7b:** tier 2 — Transaction + V1/V2 + Signer + Hex + Base58.
- **Session 7c:** tier 3 — all Solana modules.
- **Session 7d:** tier 4 — remaining standalone modules (Erc20, Filter, Receipt, Block, FeeHistory, OpenChain, Typed, DebugTrace, Trace, Recover, Assembly).
- **Session 7e:** tier 5 — `Cartouche.VM` public entry points.
Each sub-session is one namespace + its tests + one doctor run. Bundle with ROADMAP work when a tier-N file is already open for other reasons.

### Session "drift" — case-by-case (bundle opportunistically)
**Tasks:** B3, B4, B5, B6, B7, D4.
**Rule:** when a file from these tasks is already open for ROADMAP work or a bug fix, pay down its cleanup items in the same PR. Never schedule a dedicated session for these — the context-switch cost exceeds the fix.

### Session dependency graph

```
S1 (C1) ──────────────────┐
                          ├── independent, can run in parallel worktrees
S3 (B1+B2+B8) ────────────┘

S2 (A1+A2) ──► S5 (D1) ──► S7a..e (D5, chunked)
                                │
                                └── S6 (D2) can run anytime after S1; independent of D1

S4 (E1+E2+D3) ──► run after or during ROADMAP Phase 5 (same VM files)
```

Critical path: **S1 → S2 → ROADMAP 1–6 → S5 → S7 sweep**. Everything else is bolt-on.
