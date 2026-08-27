# Cartouche Fork Roadmap

**Vision (updated 2026-04-22):** This repo is now a workspace for **on-demand upstream PRs** to `zenhive/cartouche`. Active development has moved to `cartouche` — an attributed fork under ZenHive ownership. See [Strategic decision](#-strategic-decision-forked-to-cartouche-2026-04-22) below for the decision record. Phase 0–1 upstream PR candidates still live here; Phase 2–10 material migrates to cartouche's own ROADMAP once that repo exists.

**Status references:** ⬜ pending · 🔄 in progress (name branch) · 🔶 blocked · ✅ merged upstream

**Scoring:** `[D:n/B:n/U:n → Eff:x]` per `~/.claude/includes/task-prioritization.md`. `B` = downstream unblock (onchain's `@dialyzer` suppressions or feature exposure). `U` = likelihood Geoff Hayes merges the upstream PR × cartouche-user value — only relevant for tasks where we intend to send an upstream PR (Phase 0–1, and optionally Phase 2, 7.1, 7.2, 8). Cartouche-only tasks carry no `U` pressure; we ship them regardless.

**PR style (observed in `git log upstream/main`):** narrow, single-concern, lowercase conventional-commit subject (`fix:`, `chore:`, `feat:`). Recent merged examples: #126, #121, #119 — each one module, one behaviour. Match that shape.

---

## Scope principle (what belongs here vs. in onchain)

cartouche = primitives; onchain = application/protocol. A feature is a cartouche-PR candidate only if it requires cartouche internals. If it can be built on top of cartouche's public surface from outside, it lives in onchain and we don't pitch it upstream.

| In cartouche's scope | In onchain's scope |
|---|---|
| Transaction type encoding (V1, V2, V3 blob, V4 auth-list) | RPC method wrappers (`eth_getProof`, `eth_syncing`, batch requests) |
| Signer internals, key management, CloudKMS | Helpers that compose cartouche structs (fee suggestion on `FeeHistory`) |
| Hex / ABI / typed-data / chain crypto primitives | Protocol parsers (ENS, ERC-20/721/1155, Transfer events) |
| Raw transaction encode **and decode** | Subscription management, Multicall, wallet classification |
| `Cartouche.RPC.send_rpc/3` transport-level concerns | Observability facades (telemetry, retry/backoff wrappers) |

**Why the split still matters post-fork:** even though cartouche is now our own package, the scope principle keeps cartouche focused on primitives — no creeping protocol-layer features — which means onchain stays the right home for RPC wrappers, ERC parsers, and observability. Resist the temptation to add "while we're here, just this once" helpers to cartouche; they belong in onchain.

### EIP triage rubric

New EIPs arrive constantly. Triage by category:

| EIP type | Where | Notes |
|---|---|---|
| Core — new transaction type (4844, 7702, future) | **cartouche** | Modifies `Cartouche.Transaction` encode/sign; must land upstream |
| Core — new signer scheme / crypto primitive | **cartouche** | Primitive layer |
| Interface — new JSON-RPC method | **onchain** | Wrapper over `Cartouche.RPC.send_rpc/3` |
| ERC — contract standard (ERC-20/721/1155/4626/8004/…) | **onchain** or sibling | Pure contract calls; spin a sibling package (`onchain_agents`, `onchain_aave`, …) when domain-heavy |
| Core — new precompile | **onchain** usually | Contract-call wrapper; cartouche only if bespoke encoding required |
| Networking / Meta / Informational | **ignore** | Not a client-library concern |

**Never chase EIPs speculatively.** An EIP enters the roadmap only when a consumer project needs it. See `../onchain/ROADMAP.md` "EIP Tracking" for the live list.

---

## 🎯 Sharing this roadmap with upstream

Optional courtesy now that the fork decision is made. If we share, trim:

- Internal scoring (`[D/B/U]` brackets) — keep findings, drop our framework
- Branch names (`fork/…`) — our workflow, not his concern
- Any mention of the cartouche fork — this document's purpose from upstream's perspective is "PR candidates," not "what we forked"
- Onchain-specific suppression context in prose (fine to mention as one bullet, not the central narrative)
- Anything marked "investigate" — only share what we've actually confirmed

Keep: the spec-mismatch tables (they're evidence, grounded in dialyzer output), the "tracking only" items so he knows what we chose NOT to bring.

---

## 🧭 Strategic decision: forked to `cartouche` (2026-04-22)

**Status:** ✅ Decided — attributed fork under the name `cartouche`, on-demand upstream PRs.

### What we committed to

| Decision | Answer |
|---|---|
| Fork model | **B — attributed fork.** Cartouche is clearly a fork of `zenhive/cartouche`; we cherry-pick upstream commits when we want the fix, open PRs upstream when we have something genuinely upstream-worthy. Reversible: if upstream collaboration becomes impractical, we can move to Option A (hard rename) without another migration. |
| Package name | **`cartouche`** — hex name verified free (HTTP 404 on `https://hex.pm/api/packages/cartouche`, 2026-04-22). Metaphor family matches cartouche: a cartouche is the oval frame around a royal name — a signing/identification artifact, same semantic lineage as "cartouche" (seal ring). Distinctive, not crypto-cliché. |
| Sync cadence with upstream | **On-demand only.** No scheduled rebase, no per-release cherry-pick. Both directions are event-driven — pull upstream fixes when we care, push PRs when we have something clean to contribute. No SLA either way. |
| Mechanical rename | Use the `rename` hex package — [hex.pm/packages/rename](https://hex.pm/packages/rename), v0.1.0. Handles app name, module names, file paths, tests, and docs in one pass. Run inside the new cartouche repo, not here. |
| Fate of open cartouche PRs (#129, future) | Leave open by default. Merged = free win, strip the patch from cartouche's first commit. Stalls = no loss, fix already ships in cartouche. |
| Messaging | cartouche README: "cartouche is a fork of `zenhive/cartouche`. We upstream fixes where it makes sense. Attribution to the original maintainer is in CHANGELOG." No commentary on cadence or comparative pace — keep it friendly and factual. |

### What drove the decision

Not Geoff's review cadence — recent upstream PRs (#119, #121, #126) merged same-day, and #129 is live without friction. The real driver was **harness-efficiency per change.** Our Claude Code setup (dev-stack hooks, two-branch workflow, `ex_unit_json`/`dialyzer_json`/`credo`/`sobelow`/`doctor` enforcement) is calibrated for ZenHive-owned repos. In this cartouche fork, each change pays ~3–5× the friction of the same change in a repo we own:

- Stash/commit WIP to switch between `zenhive/dev` (tooled) and PR branch (pristine)
- Verify on `zenhive/dev` — vanilla tooling doesn't exist on the PR branch
- Dialyzer verification transfers by code-identity (upstream has no `dialyxir`)
- `git commit` on the PR branch blocks inside Claude's session — requires separate terminal
- Branch switches recompile (different dep sets)

Tolerable for 2–3 spec fixes. Compounds badly against a 1–2 year stream of "cartouche needs to do X" coming out of onchain's trajectory. Onchain's iteration speed is the scarce resource; everything else follows.

### Model A (hard rename) considered and rejected

Permanent, un-attributed fork with its own identity was on the table. Rejected because:

- Loses Geoff's ongoing free work (bug fixes, security patches, transitive-dep bumps)
- Forces us to be *the* ETH-primitives maintainer for ZenHive in perpetuity — a real ownership cost
- Signals competition where cooperation is available; bad community posture
- Reversible to A later if review collaboration deteriorates; not reversible the other way

Model A becomes attractive only if a fundamental values conflict surfaces in upstream (e.g., "I don't care about dialyzer-green specs"). No evidence today.

### Delegated / handled elsewhere

- **onchain `mix.exs` flip** (`cartouche` → `cartouche`): handled on the onchain side. Not tracked here.
- **cartouche repo creation, rename execution, `mix rename` run, first hex publish**: happens in a separate session when the new repo exists. This cartouche repo stays as-is for now.
- **Full ROADMAP restructure under cartouche**: pending. Most Phase 2–10 material below migrates to cartouche's own ROADMAP. This repo's ROADMAP scopes down to Phase 0–1 (the upstream PR candidates).

### Reversibility triggers

If the relationship deteriorates (upstream rejects cleanly-evidenced spec fixes, or a values conflict surfaces), flip from B to A: stop opening upstream PRs, stop cherry-picking from upstream, make cartouche fully independent. No code migration needed — same package name, same module tree.

---

## 🎯 Current Focus

**Upstream PR candidates — Phase 0 (cosmetic specs) and Phase 1 (`Cartouche.Hex` return types).** Under on-demand posture, these aren't gating anything on our side — the fixes themselves ship in cartouche regardless. But they're clean, low-risk, and visibly useful, so they're good-faith contributions to open. Phase 0.1 is in flight on `fix/recovery-bit-no-return-typo`.

Everything in Phase 2–10 below is now **cartouche work**, not cartouche-fork work. Those tasks stay documented here until the cartouche ROADMAP is set up, at which point they migrate.

---

## Phase 0: Cosmetic spec corrections

Three standalone one-commit PRs. Ship them paced one-at-a-time as a courtesy — nobody likes being swarmed with trivial PRs — but no longer gated on rapport-probing since the fork decision is made.

### Phase 0.1: `Cartouche.Util.RecoveryBit` `:no_return` atom → `no_return()` type

Two specs declare the literal atom `:no_return` instead of the type `no_return()`. Dialyzer silently accepts unknown atoms in unions, so this isn't flagged — but it makes the specs semantically meaningless and misleads downstream analysis.

| Function | Line | Current `@spec` fragment | Should be |
|----------|------|--------------------------|-----------|
| `RecoveryBit.normalize/2` | `util.ex:388` | `\| :no_return` | `\| no_return()` |
| `RecoveryBit.normalize_signature/2` | `util.ex:419` | `\| :no_return` | `\| no_return()` |

| # | Task | Status | Notes |
|---|------|--------|-------|
| 1 | Fix both `:no_return` atom typos [D:1/B:2/U:6 → Eff:4.0] 🎯 | 🔄 `fix/recovery-bit-no-return-typo` | Two-line change in `lib/cartouche/util.ex`. No test needed (pure spec, no runtime effect) |

**PR checkpoint:** branch `fix/recovery-bit-no-return-typo` from `main`. Title: `fix: correct :no_return atom → no_return() type in RecoveryBit specs`. Body: short paragraph noting atoms in spec unions are silently accepted, so this is cosmetic but clarifies intent. Verify vanilla `mix format --check-formatted` + `mix test` pass on the PR branch before pushing (upstream has no `dialyxir`; dialyzer confidence comes from `mix dialyzer.json` on `zenhive/dev` where source files are bit-identical to the PR branch).

### Phase 0.2: `Cartouche.Util.to_wei/1` narrow `number()` → `non_neg_integer()`

`@spec to_wei/1 :: number()` (line 257) but every clause returns `integer()` and amounts are non-negative by domain (wei is a discrete count).

| # | Task | Status | Notes |
|---|------|--------|-------|
| 2 | Narrow `to_wei/1` return type [D:1/B:1/U:5 → Eff:3.0] 🎯 | ⬜ | One-line change. No test needed |

**PR checkpoint:** branch `chore/to-wei-narrow-spec` from `main`. Title: `chore: narrow Cartouche.Util.to_wei/1 return to non_neg_integer()`. Open only after Phase 0.1 merges or gets a thumbs-up — avoid swarming the maintainer with three trivial PRs at once.

### Phase 0.3: `Cartouche.Signer.sign_direct/4` `mfa()` → `{module(), atom(), list()}`

Dialyzer reports `signer.ex:141 invalid_contract`. 3rd arg specced as `mfa()` (which Elixir defines as `{module(), atom(), arity :: non_neg_integer()}`) but impl receives `{module(), atom(), args :: list()}`. The third element type does not overlap.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 3 | Replace `mfa()` with an explicit `{module(), atom(), [any()]}` tuple type in the `@spec` [D:1/B:3/U:5 → Eff:4.0] 🎯 | ⬜ | One-line change + one doctest/unit test exercising the path (upstream wants in-repo evidence of real return shape — see CLAUDE.md) |

**PR checkpoint:** branch `fix/signer-sign-direct-mfa-spec` from `main`. Title: `fix: correct Cartouche.Signer.sign_direct/4 3rd-argument spec`. Body should explain that `mfa()` means `{m, f, arity}` per Elixir typespec docs, but this function takes `{m, f, args}` — a clear type mismatch. Include the doctest in the diff.

---

## Phase 1: Core fix — `Cartouche.Hex` return-type specs

**Why:** This is the load-bearing PR for our onchain integration. Unblocks `@dialyzer` suppressions in `Onchain.Hex`, `Onchain.ABI`, `Onchain.Contract`, `Onchain.ERC20/721/1155`, `Onchain.ENS`, `Onchain.Log`, `Onchain.Multicall`, `Onchain.Transfer`.

### Tasks

| # | Task | Status | Notes |
|---|------|--------|-------|
| 4 | Fix `decode_hex/1` + private `decode_hex_/1` return type: spec `\| :error`, impl returns `\| :invalid_hex` [D:1/B:7/U:9 → Eff:8.0] 🎯 | ⬜ | See bug detail below |
| 5 | Fix `decode_hex_number/1` return type: same `:error` vs `:invalid_hex` issue [D:1/B:7/U:9 → Eff:8.0] 🎯 | ⬜ | Same PR as Task 4 (one-liner, same module) |
| 6 | Fix `from_hex/1` + `from_hex!/1` return type: spec `t() -> String.t()`, impl returns `t() -> {:ok, t()} \| :invalid_hex` / `t() -> t()` [D:1/B:7/U:9 → Eff:8.0] 🎯 | ⬜ | Confirmed by dialyzer: `hex.ex:91 invalid_contract`. Doc examples already show correct shape |
| 7 | Reproduction tests: doctests or unit tests proving the real return shape for each of the four specs [D:2/B:7/U:9 → Eff:4.0] 🎯 | ⬜ | Required for upstream acceptance; folds into the same PR |

**PR checkpoint:** branch `fix/hex-specs` from `main`. Title: `fix: correct Cartouche.Hex return-type specs`. Open after Phase 0 has at least one merge (so we have a pattern established). Single concern: "specs in Hex are wrong." Must pass vanilla `mix test` before push (dialyzer verification happens on `zenhive/dev` with `mix dialyzer.json` — upstream has no dialyxir).

### Bug detail

**Root cause:** private `Cartouche.Hex.decode_hex_/1` (`lib/cartouche/hex.ex:374`) returns `{:ok, t()} | :invalid_hex` but is specced `{:ok, t()} | :error`. All public callers inherit this:

| Function | Line | Current `@spec` | Actual return |
|----------|------|-----------------|---------------|
| `decode_hex/1` | 80 | `{:ok, t()} \| :error` | `{:ok, t()} \| :invalid_hex` |
| `decode_hex_number/1` | 245 | `{:ok, integer()} \| :error` | `{:ok, integer()} \| :invalid_hex` |
| `from_hex/1` | 91 | `t() -> String.t()` | `t() -> {:ok, t()} \| :invalid_hex` (alias for `decode_hex`, not `to_hex`) |
| `from_hex!/1` | 102 | `t() -> String.t()` | `t() -> t()` (alias for `decode_hex!`) |

Doctests and `@doc` examples already show the correct shape; only the `@spec` lines disagree. Fix is surgical — update the four specs, no implementation change.

**Downstream impact once merged:** onchain strips its `@dialyzer {:no_match, …}` blocks from `Onchain.Hex` and (via cascade through `Contract.call/5 → ABI.decode_response/2`) from the ABI / ERC / ENS / Multicall modules. Full downstream strip additionally needs the external-package `abi` fix (Phase 8).

---

## Phase 2: `Cartouche.RPC.send_rpc/3` error-shape spec

**Why:** onchain carries `@dialyzer {:no_match, do_rpc: 3}` because upstream spec promises `%{code: int, message: str}` for all errors, but `send_rpc/3` actually returns several other error shapes at runtime.

Confirmed runtime error shapes (`lib/cartouche/rpc.ex:84–203`, `lib/cartouche/util.ex:481–495`):

| Source | Returned shape |
|--------|----------------|
| Finch non-2xx | `{:error, %Finch.Response{}}` |
| Finch transport | `{:error, "[Cartouche] HTTP client error: …"}` (string) |
| Finch unknown | `{:error, "[Cartouche] Unknown error: …"}` (string) |
| Invalid JSON-RPC envelope | `{:error, %{code: -999, message: "…"}}` |
| Revert with decoded error (code 3) | `{:error, %{code:, message:, revert:, error_abi:, error_params:}}` (extra fields vs spec) |
| `decode: :hex` path with bad hex | bare `:invalid_hex` atom (not wrapped in `{:error, …}`) |
| Custom `decode:` fn raises | `{:error, "failed to decode `<method>` response: <inspect>"}` |

### Tasks

| # | Task | Status | Notes |
|---|------|--------|-------|
| 8 | Audit `send_rpc/3` `@spec` vs runtime error shapes on current `upstream/main` [D:3/B:6/U:7 → Eff:2.17] 🚀 | ⬜ | Cross-check table above — recent PRs #119, #121 already tightened Finch propagation; confirm no shapes were closed since this roadmap was written |
| 9 | Widen error type (or split into tagged errors) with doctest coverage per shape [D:3/B:7/U:7 → Eff:2.33] 🚀 | ⬜ | Depends on Task 8. Propose a union type; keep `%{code, message}` as the JSON-RPC-error branch |

**Blast radius (mix reach.impact Cartouche.RPC.send_rpc/3):** 6 direct callers break on signature change (`get_balance/2`, `get_transaction_count/2`, `eth_block_number/1`, `eth_chain_id/1`, `set_filter/1`, `Cartouche.Filter.handle_info/2`), 1 transitive (`Cartouche.Signer.init/1`), no return-value dependents. MEDIUM risk per reach — behavior-preserving spec-widening is low-risk; a union-type split would need all 6 direct callers to still type-check against the new spec.

**PR checkpoint:** branch `fix/rpc-error-spec` from `main` once Tasks 8–9 done. Title: `fix: broaden Cartouche.RPC.send_rpc/3 error-return spec`. Include at least one doctest demonstrating a non-`%{code, message}` error path.

---

## Phase 3: `Cartouche.Trace` + `Cartouche.TraceCall` deserialize specs

**Why:** Dialyzer reports `trace.ex:408` and `trace_call.ex:124` as `invalid_contract`. The struct returned by `deserialize/1` has fields with union types (`nil | binary()`, `nil | <<_:160>>`, etc.) that the module's `@type t` declaration doesn't allow. Spec says `t() | no_return()`; the concrete struct shape doesn't unify.

### Tasks

| # | Task | Status | Notes |
|---|------|--------|-------|
| 10 | Update `Cartouche.Trace.@type t` (and nested `Cartouche.Trace.Action` type) to match the fields dialyzer infers [D:3/B:2/U:4 → Eff:1.0] 📋 | ⬜ | Compare dialyzer's success typing (see `/tmp/cartouche-dialyzer.json`) against current `@type t`; extend field types to `nil \| …` where runtime proves it |
| 11 | Update `Cartouche.TraceCall.@type t` analogously [D:2/B:2/U:4 → Eff:1.5] 📋 | ⬜ | Same pattern; piggybacks on Task 10 changes if `TraceCall` embeds `Trace.t()` |
| 12 | Add unit tests exercising `deserialize/1` on representative JSON (with and without optional fields) [D:2/B:2/U:4 → Eff:1.5] 📋 | ⬜ | Proves the widened type is grounded in runtime behaviour |

**PR checkpoint:** branch `fix/trace-deserialize-specs` from `main` bundling Tasks 10–12. Title: `fix: align Cartouche.Trace/TraceCall deserialize specs with returned struct shape`. Vanilla verification is `mix test` only (upstream has no dialyxir). Verify both warnings disappear on `zenhive/dev` via `mix dialyzer.json --quiet --filter-type invalid_contract` — the source edits carry across branches so dialyzer-green on `zenhive/dev` is sufficient evidence.

---

## Phase 4: `Cartouche.Typed` internal-function specs

**Why:** Dialyzer reports `typed.ex:571` (`encode_value_map/3`) and `typed.ex:585` (`find_type/2`) as `invalid_contract`. Both specs completely disagree with the success typing:

- `encode_value_map/3`: spec returns a map; impl returns a `bitstring()`.
- `find_type/2`: spec returns `Typed.Type.t()`; impl returns a 2-tuple.

Looks like copy-paste from the wrong function or a stale spec after a refactor.

### Tasks

| # | Task | Status | Notes |
|---|------|--------|-------|
| 13 | Read current impls, derive the true return types, rewrite both `@spec` lines [D:2/B:1/U:3 → Eff:1.0] 📋 | ⬜ | Consider `@doc false` if these really are internal — keeps the `@spec` for dialyzer but removes them from generated docs |
| 14 | If either fn is meant to be public API (doc'd in module), adjust impl to match the documented intent instead of changing the spec [D:3/B:2/U:3 → Eff:0.83] ⚠️ | ⬜ | Judgment call — ask Geoff in PR body |

**PR checkpoint:** branch `fix/typed-internal-specs` from `main`. Title: `fix: correct Cartouche.Typed encode_value_map/3 and find_type/2 specs`. In the PR body, ask for input on Task 14 direction.

---

## Phase 5: Investigate — `VM.exec/3`, `VM.exec_call/3`, `Erc20.Call.*`

**Why:** Four dialyzer `invalid_contract` warnings where success typing is `(_, _, _) -> none()`. `none()` means dialyzer believes the function cannot return normally — likely a cascade from an unreachable pattern, a `raise` on every traced path, or a macro-generated function dialyzer can't trace (Erc20.Call looks like a nested module used via delegation).

These are NOT necessarily spec bugs. Investigation first; PR only if the root cause is a real, surgical defect.

**Reach findings (2026-04-21) — downgrade signal:**
- `mix reach.impact Cartouche.VM.exec/3` → **0 internal callers** (direct, transitive, or return-value dependents). Only external consumers (onchain, downstream libraries) call it.
- `mix reach.impact Cartouche.Erc20.transfer/4` → **0 internal callers.** Same pattern.
- Both already declare `@spec`s: `VM.exec/3` returns `{:ok, ExecutionResult.t()} \| {:error, vm_error()}`, `Erc20.transfer/4` returns `{:ok, binary()} \| {:error, term()}`.
- By contrast, `VM.exec_call/3` has ~37+ internal callers (autogenerated `Cartouche.Contract.IConsole.exec_vm_log_*` functions) — not the `none()` source.
- **Implication:** the `none()` cascade on these entry points isn't a missing- or wrong-spec problem. It's likely transitive — `none()` propagates up from deeper callees where dialyzer's success-typing narrows (possibly `Curvy`, `ABI`, `ExRLP`, or internal VM primitives that raise-on-error). Without internal call sites to constrain the top-level signature, dialyzer's whole-program success typing collapses.
- **This is hard to fix surgically in upstream.** The maintainer would need to either (a) narrow or widen internal specs that currently collapse to `none()`, (b) add `@dialyzer {:no_contracts, [exec: 3, transfer: 4]}` which is essentially what onchain already does downstream, or (c) trace each `none()` back to its actual originating callee — multi-day work.

### Tasks

| # | Task | Status | Notes |
|---|------|--------|-------|
| 15 | Run `mix dialyzer.json --filter-type invalid_contract` on `upstream/main` and `zenhive/dev`, then trace each Phase 5 warning back through `mix reach.deps <fn>/<ar>` + `mix reach.slice <file>:<line>` to find the first callee whose success typing is `none()` [D:5/B:3/U:3 → Eff:0.6] ⚠️ | ⬜ | Half-day to day of work. Only pursue if onchain's Phase 5-adjacent suppressions are specifically blocking a release |
| 16 | Read `lib/cartouche/erc_20.ex` around lines 49–99; confirm `Cartouche.Erc20.Call` submodule encoding functions and whether they genuinely can reach `none()` at runtime or if the flag is purely inferential [D:2/B:2/U:3 → Eff:1.25] 📋 | 🔶 | Deprioritized; reach shows this is a library entry-point cascade, not a bug we're likely to fix upstream |
| 17 | For each: (a) real bug → surgical fix + PR, (b) dialyzer cascade from a fixable source → fix upstream cascade, (c) unfixable without restructuring → document here, stop chasing. Default expectation after reach findings: (c) [D:1/B:3/U:3 → Eff:3.0] 🎯 | ⬜ | Don't burn maintainer time on (c) |

**PR checkpoint:** conditional on Task 17 outcome. After reach analysis, (c) is the likely outcome — Phase 5 may not yield any upstream PR at all. That's fine; knowing is the win. Onchain keeps its `@dialyzer {:no_return, :no_contracts}` suppressions for these specific functions and scoping the suppression to exact MFAs is a valid long-term stance.

---

## Phase 6: `Cartouche.VM.Context.init_from/2` spec

**Why:** `vm.ex:104 invalid_contract`. Spec says `:: t()` but success typing is the concrete struct literal with every field inferred, suggesting `@type t` is too loose (or missing). Low-impact standalone; may naturally bundle with Phase 5 if that opens a VM PR.

### Tasks

| # | Task | Status | Notes |
|---|------|--------|-------|
| 18 | Align `Cartouche.VM.Context.@type t` with dialyzer's inferred struct shape, or relax `init_from/2` to return `struct()` [D:2/B:1/U:3 → Eff:1.0] 📋 | ⬜ | Internal type — `B` is low because onchain doesn't use `Cartouche.VM` |

**PR checkpoint:** bundle into Phase 5's VM PR if Phase 5 opens one; otherwise standalone `fix/vm-context-init-spec`, title `fix: align Cartouche.VM.Context.init_from/2 spec with returned struct`.

---

## Phase 7: Dependency freshness

Two classes:

- **Constraint-blocked bumps** — cartouche's `mix.exs` constraint prevents a newer version from resolving. These are real PR targets: (a) loosen the constraint, (b) read the intervening changelog for breaking changes AND new features, (c) if new features are relevant to cartouche's public surface, propose exposing them in a follow-up PR.
- **Lockfile-stale** — constraint already allows the newer version; `mix.lock` just hasn't been refreshed. Not our PR target — maintainers do this on release cycles. Mention in passing if we're already opening a PR that touches deps.

### Phase 7.1: `google_api_cloud_kms` 0.38.1 → 0.43.0 (constraint-blocked)

`mix.exs:55` pins `~> 0.38.1` which resolves `< 0.39`. Cartouche uses this dep in `lib/cartouche/signer/cloud_kms.ex` via two methods: `cloudkms_..._get_public_key` and `cloudkms_..._asymmetric_sign`. Both are mature KMS APIs unlikely to have breaking changes, but five minors of drift likely includes new key types (Ed25519, HMAC) or new methods worth surfacing.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 19 | Read `google_api_cloud_kms` CHANGELOG between 0.38.1 and 0.43.0; flag breaking changes affecting `get_public_key` / `asymmetric_sign`, and any new methods or key types relevant to Ethereum signing (Ed25519 for future chains, HMAC for attestation) [D:2/B:2/U:4 → Eff:1.5] 📋 | ⬜ | Don't skim — these release notes are dense; read every minor |
| 20 | Loosen constraint to `~> 0.38 and >= 0.38.1` (or broader, per findings); run `mix deps.update google_api_cloud_kms`; verify vanilla `mix test` on PR branch and `mix dialyzer.json` on `zenhive/dev` [D:2/B:3/U:4 → Eff:1.75] 🚀 | ⬜ | One-line `mix.exs` change + lockfile update |
| 21 | If Task 19 surfaces a cartouche-relevant new feature (e.g., Ed25519 support, new auth model), propose it in a SEPARATE follow-up PR with accompanying docs + tests — do not mix with the constraint-loosen PR [D:5/B:4/U:4 → Eff:0.8] ⚠️ | ⬜ | Conditional. Upstream maintainer prefers single-concern PRs; don't stuff features into a chore |

**PR checkpoint (Task 20):** branch `chore/bump-cloud-kms-range` from `main`. Title: `chore: widen google_api_cloud_kms constraint to pick up 0.38.1..0.43.0`. Body: enumerate any behaviour changes noticed, link to CHANGELOG headings for transparency. Keep feature exposure out (Task 21 follow-up).

### Phase 7.2: `ex_doc` 0.31.1 → 0.40.1 (constraint-blocked, dev-only)

`mix.exs:52` pins `~> 0.31.1`. Dev dep, zero runtime risk. 0.40 has substantial improvements to typespec rendering and search — helps anyone reading cartouche's HexDocs.

**Note (2026-04-21):** `zenhive/dev` has already bumped this constraint to `~> 0.40` locally (needed so `:reach` could resolve — reach pulls in `makeup_elixir ~> 1.0` which conflicts with ex_doc 0.31.1's `~> 0.14` pin). PR branches fork from `main` and keep upstream's `~> 0.31.1`, so the dev-branch bump never leaks into PRs. When we open the Phase 7.2 PR, it's the upstream-facing version of the same change.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 22 | Loosen `ex_doc` constraint to `~> 0.38` or `~> 0.40`; regenerate `mix docs`; verify output is at minimum equivalent (no lost pages, no warnings) [D:1/B:2/U:5 → Eff:3.5] 🎯 | ⬜ | Good maintenance pitch — zero risk, better docs immediately |

**PR checkpoint:** branch `chore/bump-ex-doc` from `main`. Title: `chore: widen ex_doc constraint to pick up 0.40`. Solo PR, no doctests needed.

### Phase 7.3: `finch` 0.19 → 0.21 features investigation (constraint already allows)

`mix.exs:54` pins `~> 0.19` which resolves to `< 1.0`, so 0.21 is already reachable on any `mix deps.update`. Two minors of drift — Finch has been actively evolving HTTP/2 and pool semantics. Cartouche uses Finch via `http_client().request(request, finch_name(), …)` in `lib/cartouche/rpc.ex:167` and in the error-normalizer (`util.ex:481`). New Finch features could simplify or strengthen these paths.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 23 | Read `finch` CHANGELOG 0.19 → 0.21; identify any new options relevant to `Finch.request/3` or to error classification (we currently hand-build strings from `%Finch.Error{}`) [D:2/B:3/U:4 → Eff:1.75] 🚀 | ⬜ | Investigate first; propose improvements only if genuinely cleaner |
| 24 | If Task 23 finds a concrete improvement (cleaner error variants, better pool config, HTTP/2 telemetry), propose a separate PR adopting it — do NOT open a "bump finch" PR by itself, maintainers handle lockfile refreshes [D:3/B:3/U:3 → Eff:1.0] 📋 | ⬜ | Conditional |

**PR checkpoint (Task 24):** branch `feat/finch-<feature-name>` from `main`. Title: `feat: use Finch <feature> for <benefit>`. This is a `feat:` PR, not `chore:` — include tests.

### Phase 7.4: Lockfile-stale deps — `ex_sha3`, `goth`, `finch`, `junit_formatter`

Constraint already allows the newer version; `mix.lock` just hasn't caught up. Not our PR territory.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 25 | If an unrelated PR touches `mix.lock` for other reasons, also bump these in the same PR so the diff is clean. Otherwise leave alone — maintainers refresh locks on release cycles. | 🔶 | Tracking only |

---

## Phase 8: Refactor — `Cartouche.Transaction.V2.encode/1` duplication

**Why:** `mix ex_dna` surfaces one Type I (exact) clone in `lib/cartouche/transaction.ex`: both `encode/1` clauses of `Cartouche.Transaction.V2` (unsigned at line 394, signed at line 423) share 10 lines of identical struct destructuring and the same `<<0x02>> <> ExRLP.encode([chain_id, nonce, max_priority_fee_per_gas, max_fee_per_gas, gas_limit, destination, amount, data, access_list])` prefix. The signed clause differs only by appending three extra RLP elements (normalized `signature_y_parity`, `String.trim_leading(signature_r, <<0>>)`, `String.trim_leading(signature_s, <<0>>)`) and transforming `access_list` via `Enum.map/2`.

Natural extraction: a private helper that returns the prefix-list `[chain_id, nonce, ..., access_list_shape]` from the struct. Each clause then either encodes that list as-is (unsigned) or concatenates the signature triple before encoding (signed).

**Caveat — upstream acceptability:** This is a `refactor:` touching a hot-path encode function. Maintainer PR history shows `fix:` / `chore:` bias, not refactors. Risk: maintainer prefers the duplication because it keeps the two clauses visually parallel and easy to audit against EIP-1559. Under the cartouche decision this ships in cartouche regardless; the upstream PR is optional. If we do pitch it upstream, wait until Phase 0–1 PRs have merged so we have a confirmed positive interaction pattern first. Likely upstream outcome: either cleanly accepted or politely declined with "I prefer the clauses parallel." Both fine — cartouche gets the refactor either way.

### Tasks

| # | Task | Status | Notes |
|---|------|--------|-------|
| 26 | Verify both encode clauses have doctest coverage; if the unsigned clause lacks one, add it FIRST as a standalone PR before any refactor [D:2/B:2/U:4 → Eff:1.5] 📋 | ⬜ | Refactors without test coverage are maintainer-hostile |
| 27 | Extract `defp unsigned_rlp_list/1` (or equivalent); rewrite both clauses to call it; verify byte-exact output equivalence via the existing doctests [D:3/B:2/U:3 → Eff:0.83] ⚠️ | ⬜ | Ships in cartouche directly. `B` score reflects the upstream PR value, which may or may not land (see caveat above). In cartouche the refactor is low-risk |

**PR checkpoint:** branch `refactor/transaction-v2-encode-dedup` from `main`. Title: `refactor: extract shared prefix in Cartouche.Transaction.V2.encode/1 clauses`. PR body should be disarming: "happy to close this if you prefer the parallel clauses — just wanted to surface the duplication an AST-level duplication scan picked up." Include a note that the existing doctest output was bit-verified unchanged.

**Do not run `mix ex_dna --literal-mode abstract` on upstream's behalf.** It finds near-misses that are often intentional (EIP version pairs, opcode groupings). Only Type I / exact duplication is safe to pitch upstream.

---

## Phase 9: External packages — tracking only

Fixes that live outside cartouche but affect the onchain dialyzer story.

| # | Task | Status | Notes |
|---|------|--------|-------|
| 28 | `ABI.decode/2` specced as `no_return()` in `poanetwork/ex_abi` | 🔶 | Separate fork + PR if pursued. Only chase if Phase 1 merges and onchain's remaining dialyzer noise is clearly bounded by this |

---

## Phase 10: New transaction types + raw decode (cartouche — no upstream gating)

**Why:** The only three features that genuinely require cartouche internals. Everything else from the broader brainstorm (telemetry, batch RPC, `eth_getProof`, `eth_syncing`, fee helpers, retry/backoff) belongs in onchain per the Scope principle above.

**Under the cartouche decision, these ship in cartouche immediately** — no longer gated on upstream review cadence. Upstream PRs are optional courtesy after the cartouche implementation is stable and battle-tested; no reason to block onchain's EIP-4844 / EIP-7702 adoption on Geoff's schedule. If we do open upstream PRs later, they're clean cherry-picks from cartouche's implementation with whatever test vectors we accumulated in production use.

### Tasks

| # | Task | Status | Notes |
|---|------|--------|-------|
| 30 | EIP-4844 blob transactions (`Cartouche.Transaction.V3`) — encode, sign, RLP round-trip, `max_fee_per_blob_gas` + `blob_versioned_hashes` fields [D:6/B:7/U:6 → Eff:1.08] 📋 | ⬜ | Medium PR. L2 rollups have posted blob txs since Dencun (Mar 2024). Include doctest + representative test vector from mainnet |
| 31 | EIP-7702 authorization-list transactions (`Cartouche.Transaction.V4`) [D:5/B:5/U:5 → Eff:1.0] 📋 | ⬜ | Smaller than Task 30. Adds `authorization_list` field, tx type 0x04. Active on mainnet since Pectra (May 2025) |
| 32 | Raw transaction decode — inverse of `Cartouche.Transaction.Vn.encode/1` across V1/V2/V3/V4 [D:4/B:4/U:5 → Eff:1.13] 📋 | ⬜ | Useful for mempool tooling, explorers. Maintainer's existing surface feels incomplete without it. Bundle with Task 31 if review cadence is fast; otherwise solo PR |

**PR checkpoint:** Tasks 30 and 31 warrant separate branches (`feat/blob-transactions`, `feat/auth-list-transactions`) — one concern each. Task 32 may bundle with Task 31 or solo as `feat/transaction-decode`. All three must pass vanilla `mix test` + `mix dialyzer` on the PR branch. No Styler, no custom tooling in the diff.

---

## Completed

_None yet._

---

## Audit provenance

Findings come from:

- `mix hex.outdated` on `zenhive/dev` (2026-04-21) — drove Phase 7 dep tasks
- `mix dialyzer.json --quiet --output /tmp/cartouche-dialyzer.json` on `zenhive/dev` (2026-04-21) — 11 `invalid_contract` warnings drove Phases 0.3, 1, 3, 4, 5, 6
- `mix ex_dna` on `zenhive/dev` (2026-04-21) — one Type I clone drove Phase 8 (41 files analyzed, 1 clone found, ~28 duplicated lines)
- `mix reach.hotspots` + `mix reach.coupling` + `mix reach.impact` on `zenhive/dev` (2026-04-21, reach 1.6.0) — confirmed Phase 2 blast radius (32 callers of `send_rpc/3`, 6 direct breakage points, MEDIUM risk); downgraded Phase 5 after discovering `VM.exec/3` and `Erc20.transfer/4` have 0 internal callers (the `none()` cascade is transitive from deeper callees, not a top-level spec bug); identified pervasive `Cartouche.VM` submodule cycles (VM ↔ Context / Memory / Input / IConsole) that likely feed the cascade; 4 `reach.otp` "unmatched handler" warnings on `signer.ex` and `solana/signer.ex` were verified false positives — all handler clauses exist.
- Manual audit of `lib/cartouche/rpc.ex` + `lib/cartouche/util.ex` + `lib/cartouche/signer/cloud_kms.ex` — drove Phases 0.1, 0.2, 2, 7.1

Before opening any PR, re-run `mix dialyzer.json --quiet --group-by-file` on the current `zenhive/dev` — catches regressions introduced by intervening upstream work.

---

## Re-probe procedure (for onchain)

Once onchain flips its `mix.exs` from `cartouche` to `cartouche` (handled on the onchain side), the dialyzer re-probe runs against cartouche:

```bash
cd ../onchain
mix deps.update cartouche
# confirm cartouche is on a version that includes the Phase 1 Hex spec fixes
mix dialyzer.json --quiet
# if the Onchain.Hex / Onchain.ABI warnings are gone, strip those @dialyzer blocks
```

Cartouche includes the Phase 1 fixes from day one (they ship in our fork regardless of upstream merge status). If the upstream PR also lands, onchain's cartouche dep could alternatively be re-probed against the upstream-merged version — but under the cartouche decision, onchain has no reason to track upstream cartouche anymore.

See `onchain/ROADMAP.md` Task 43 for the full strip checklist.
