# Cartouche Roadmap

**Vision:** Cartouche is an attributed fork of [`hayesgm/signet`](https://github.com/hayesgm/signet) under ZenHive ownership. Active development happens here. Upstream PRs to `hayesgm/signet` are opened **on-demand** when a fix is clean, self-contained, and independently useful — no SLA either direction. The fork decision and rationale live in [`CHANGELOG.md`](CHANGELOG.md) under `0.0.1`; this document is strictly forward-looking.

**Status legend:** ⬜ pending · 🔄 in progress (name branch) · 🔶 blocked/deferred · ✅ complete

**Scoring:** `[D:n/B:n/U:n → Eff:x]` per `~/.claude/includes/task-prioritization.md`.
- `B` = impact magnitude (onchain `@dialyzer` strips, new feature shipped, blocked work unblocked).
- `U` = unlock leverage for **downstream consumers** — primarily [onchain](../onchain), secondarily any future cartouche user. Scoring is decoupled from upstream-merge likelihood. Upstream-merge considerations live in prose in Phase 10 only.

---

## Scope principle (what belongs here vs. in onchain)

**Cut on what defines the bytes, not on who calls the node.**

| Layer | Owns |
|---|---|
| [hieroglyph](../hieroglyph) | The ABI codec. Pure functions over types and bytes. No I/O, no chain identity, no node. |
| **cartouche** | Everything defined by the **node's wire format**: the JSON-RPC transport, and one wrapper **plus one decoded struct** for every method in a tagged release of the `execution-apis` OpenRPC spec — plus transaction envelopes, signing, crypto, hex, and chain ids. |
| [onchain](../onchain) | Everything defined by a **contract, a standard, or an off-node protocol**: ERC-*, ENS, AA, MEV, DEX, Multicall, subscriptions, vendor/bundler/relay namespaces. It **re-presents** cartouche's structs; it never re-derives them. |

### Routing table — answer in one read

| Question | Answer |
|---|---|
| New `eth_*` / `net_*` wrapper? | **cartouche**, iff the method is in a **tagged** OpenRPC release. Not in the spec → cartouche only with a `@doc` naming who serves it *and* a capability probe. Vendor/bundler/relay namespace (`eth_sendUserOperation`, `eth_sendBundle`, `eth_sendPrivateTransaction`) → **onchain**. |
| Response decoding? | **cartouche**, always, into a cartouche struct. onchain never re-derives a JSON shape the node emits. |
| ERC standard? | **onchain**, or a sibling package when domain-heavy (`onchain_aave`). |
| Chain-specific constants? | **cartouche** (`Cartouche.Chain`). A chain with a different tx envelope gets its own package (`onchain_tempo`). |
| Non-EVM chain? | **Its own package.** Not cartouche, not onchain. |

**Why this replaces the previous rule.** The old table assigned "RPC method wrappers" to
onchain while leaving the transport and the response structs in cartouche. That is not a
separable cut: `send_rpc/3` takes a `:decode` function, so a wrapper is *method string +
param normalizer + pointer to a cartouche struct* — two of three parts already cartouche's.
Because onchain could not own the decode without owning the struct, it wrote its own, and
the stack now carries two mutually-incompatible `Block` representations (`Cartouche.Block`
returns a struct with raw binaries; `Onchain.RPC.Helpers.parse_block_response/1` returns a
plain map with `0x` strings), ~500 LOC of duplicate decoders, twelve methods wrapped at
both layers, a `@dialyzer {:no_match, do_rpc: 3}` suppression as the receipt, and 34 LOC of
duplicate HTTP config in `Onchain.HTTP` whose moduledoc says outright that it exists to
escape cartouche's config key. No test can catch that, because no module consumes both.
The old rule did not prevent the duplication — it caused it.

**Enforcement, not prose.** `Onchain.RPC.Codegen.ensure_known_method!/1` already raises at
compile time on a method absent from the vendored spec; `Cartouche.RPC.DSL.defrpc/3` checks
nothing. Moving the vendored spec down into cartouche and porting that guard turns "is this
cartouche's?" into a compile error — the only enforcement that survives a session that
never opens this file. Pin it to a **tagged release**: `execution-apis` `main` now carries
`eth_baseFee`, which no release does.

Resist "while we're here, just this once" helpers — they belong in onchain.

### EIP triage rubric

| EIP type | Where | Notes |
|---|---|---|
| Core — new transaction type (4844, 7702, future) | **cartouche** | Modifies `Cartouche.Transaction` encode/sign |
| Core — new signer scheme / crypto primitive | **cartouche** | Primitive layer |
| Interface — new JSON-RPC method | **cartouche** if in a tagged `execution-apis` release; **onchain** for vendor/bundler/relay namespaces | Reverses the previous routing — see "Why this replaces the previous rule" above |
| ERC — contract standard (ERC-20/721/1155/4626/8004/…) | **onchain** or sibling | Pure contract calls; spin a sibling package (`onchain_agents`, `onchain_aave`, …) when domain-heavy |
| Core — new precompile | **onchain** usually | Contract-call wrapper; cartouche only if bespoke encoding required |
| Networking / Meta / Informational | **ignore** | Not a client-library concern |

---

## Coverage gate for change tasks

Before any task that mutates an existing module, that module's `mix test.json --cover` percentage must be at the target tier (≥80% standard, ≥95% for crypto / signing / RLP). Task 43 set the precedent: raise coverage *first*, mutate *second*. New tasks that touch sub-target modules MUST include an explicit coverage sub-step or be paired with a preceding coverage task. Coverage on auto-generated modules (`Cartouche.Contract.IConsole`) is not load-bearing — exclude when reading the headline %.

---

## Delegation Markers

- `[CX]` — Codex Cloud-eligible (no internet, no Tidewave, no dep changes — see `~/.claude/includes/task-prioritization.md`)
- `[CSR]` — Cursor Background Agent-eligible (broader: hex.pm + mix tasks runnable)
- `[P]` — parallel-eligible (orthogonal to delegation)
- _no marker_ — local only (needs Tidewave / dep change / cross-repo coordination)

Local sessions: do **not** execute `[CX]` / `[CSR]` rows unless explicitly redirected (per `critical-rules.md` § "DON'T STEAL CLOUD-AGENT-DELEGATED TASKS").

---

## 🎯 Current Focus

**Reach 1.8 → 2.2 bump + hygiene pass shipped 2026-05-07 (INE-47 / PR #59, delegated to Cursor; bot-finding follow-ups landed locally on `development` post-merge as `5668c0e`).** Cursor bumped reach 1.8 → 2.2 directly rather than executing the original 1.8 surface — reach 2.2's expanded smell surface (idiom mismatch like `Enum.count/1` → `length/1`, `Enum.at` → `elem`, `is_nil(x) or x == ""` → pattern match) covered the original 1.8 findings plus more. Five `lib/cartouche/**` modules touched: `hex.ex` checksum loop (charlist+`Enum.at` → tuple+`elem`), `sleuth.ex` two count→length + two guard-to-pattern-match splits, `solana/pda.ex` two `Enum.reduce` concats → single iodata, `solana/transaction.ex` `serialize_message/1` + `serialize/1` → `IO.iodata_to_binary` (with explicit `Enum.each` raise-on-malformed validators preserving the original FunctionClauseError contract for non-32-byte account keys / non-64-byte signatures), `vm.ex` two count→length + `:stack_overflow` added to `vm_error` type union (CodeRabbit minor outside-diff). 122-LOC test pass added to `test/solana/transaction_test.exs` covering serialize-message + serialize golden round-trips and pinning the raise-on-malformed contract. Local post-merge bookkeeping resolved CI format failure (PR #60's merge-time alias adds in `transaction_test.exs` overlap region — Styler rewrites long-form refs to short-form), three `@spec`s in `lib/mix/cartouche.gen.ex` (`arg_name/2`, `build_struct_argument_spec/2`, `unused_name_value_pair/1` — CodeRabbit major), and `:stack_overflow` in `vm_error` (CodeRabbit minor outside-diff). `.sobelow-skips` regenerated post-merge on `main` (the `@spec` adds shifted lines in `lib/mix/cartouche.gen.ex`, breaking 6 fingerprints; admin-merge with `--admin` was load-bearing here since per project convention the regen happens post-merge on `main` — agents should not touch `.sobelow-skips`). Closes Task 59 — the `lib/mix/cartouche.gen.ex` sub-items in the original Task 59 scope were either already shipped under the Task 41/42/50 generator-hardening bundle or rolled into PR #59's reach 2.2 surface. See [CHANGELOG `[Unreleased]`](CHANGELOG.md#unreleased).

**Phase 12 fully closed 2026-05-07 with Task 89 (manifest wiring + README) shipped (INE-49 / PR #62, delegated to Cursor).** `mix manifest` alias added to `mix.exs` aliases (`descripex.manifest --pretty --output api_manifest.json --app cartouche` — `--app cartouche` is required by descripex 0.6's task to filter the host-discovery scope down to Cartouche modules). New `Cartouche.Manifest` module wraps `Descripex.Manifest.build(Cartouche.__descripex_modules__())` so HTTP endpoints / MCP servers can serve the live manifest from a running BEAM without an out-of-band JSON artifact. `api_manifest.json` is gitignored — regenerated on demand, never checked in. `README.md` `## API discovery` section documents the three-level `Cartouche.describe/0,1,2` progressive-disclosure surface plus the static-vs-runtime split (`mix manifest` build-time artifact vs `Cartouche.Manifest.build/0` runtime). Path A scope amendment surgically resolved a self-flagged + Codex-GH-bot-flagged P2 blocker (Jason rejects raw 20-byte binary in JSON-encoded annotation metadata): `default: @sleuth_address` → `default: "0xFd946Bf25C47A1Bff567B28bA78a961bf78FF9d2"` (UTF-8 hex string) at three sites in `lib/cartouche/sleuth.ex` (lines 25, 59, 193 — `api(:query, ...)`, `api(:query_annotated, ...)`, `api(:query_v2, ...)` opts blocks). Module attribute `@sleuth_address` (line 13) and the runtime `Keyword.pop(opts, :sleuth_address, @sleuth_address)` paths (lines 151, 214) intentionally stay on the raw 20-byte binary — different shapes for different consumers. CodeRabbit's literal-duplication nitpick (consolidate the 3 hex-string defaults into a single `@sleuth_address_hex` attribute) dropped per ceremony floor — cosmetic, ≤5 LOC, intentional shape-divergence between annotation metadata (Jason-encodable hex) and runtime path (already-decoded binary). CI Harness 54s green; CodeRabbit re-reviewed on the amend SHA. **Phase 12 (descripex adoption) is now fully closed** — Tasks 82-89 plus the five PR-flagged Phase 12 follow-ups (Tasks 93-97) have all shipped. See [CHANGELOG `[Unreleased]`](CHANGELOG.md#unreleased).

**`Cartouche.Solana.Transaction` caller-error guards shipped 2026-05-07 (INE-48 / PR #60, delegated to Cursor; bundled Tasks 91 + 92).** `sign/2` now validates `length(seeds) == message.header.num_required_signatures` at function entry and raises `ArgumentError` with both counts named on mismatch (Task 91); `add_signature/3` guards `0 ≤ index < length(transaction.signatures)` and raises `ArgumentError` on out-of-bounds (Task 92), with `index >= 0` moved from the head guard into the body so negative indices raise `ArgumentError` instead of `FunctionClauseError`. Both adopt the same contract style (raise on caller error) — module's existing `{:error, _}` contract is for parse failures (deserialize family), so raising on caller error matches idiomatic Elixir (`Map.fetch!`/`Keyword.fetch!`) without conflating the two error shapes. Regression coverage in `test/solana/transaction_test.exs` covers undersupplied/oversupplied/exact-match for `sign/2` and off-by-one/negative/far-OOB/in-range for `add_signature/3`. `Cartouche.Solana.Transaction` coverage stayed at 100% (≥95% gate). Tier-1 bot ensemble incomplete on this PR — only CodeRabbit posted ("no actionable comments"); Copilot and Codex GH bot did not run, flagged as repo-config follow-up rather than agent failure (PR was opened non-draft per AC). See [CHANGELOG `[Unreleased]`](CHANGELOG.md#unreleased).

**Phase 12 annotation pass closed 2026-05-07 with Tasks 93 + 94 + 95 + 96 + 97 shipped (INE-46 / PR #56 + INE-45 / PR #57; INE-45 delegated to Cursor).** PR #56 (Task 93) added a real struct-dispatched `Cartouche.Transaction.encode/1` mirroring `decode/1` and removed the synthetic `transaction_dispatch_detail/2` helper from `Cartouche.describe/2` so `:encode` now resolves to real metadata. PR #57 (Tasks 94+95+96+97) bundled the four metadata-only follow-ups: top-level `decode/1` `returns:` enumerates all 7 dispatcher outcomes (V1/V2/V3/V4 ok variants + `:empty_transaction` + `:unknown_envelope_type` + delegated `String.t()` errors); `Cartouche` itself registered in `@descripex_modules` with `:cartouche` alias and `get_contract_address/1` annotated (existing `api(:describe, ...)` covers `describe/0,1,2` via propagation; `__descripex_modules__/0` kept `@doc false` per the metadata-name convention); V1 `value` annotation realigned with the `{2, :wei}` doctest dropping off-spec `:eth`; and `test/descripex_validation_test.exs` gained a misattachment-detection pass (option (c) — cross-check `meta[:hints]` against `Module.__api__/0`). Post-merge bookkeeping refined the new test pass per Codex P2 + CodeRabbit nit on PR #57 — `Map.new` collapse swapped for `Enum.group_by` list-membership (multi-decl-safe; Codex's `{name, arity}` proposal would still have collapsed `V2.new`/`V2.add_signature` overload pairs that share name+arity), plus explicit `{:error, reason}` flunk branch on `Code.fetch_docs/1`. Phase 12's annotation sweep is complete; Task 89 (manifest wiring + README) shipped 2026-05-07 (INE-49 / PR #62) — see paragraph above. See [CHANGELOG `[Unreleased]`](CHANGELOG.md#unreleased).

**Task 66 (`Cartouche.Block.transactions` full-detail JSON deserialization) shipped 2026-05-07 (INE-44 / PR #55, delegated to Cursor; bot-finding follow-ups landed locally as `13f5e50` on `development`).** `Cartouche.Block.deserialize/1` now dispatches per-element on `params["transactions"]` — hash strings preserve the wire shape (with `Hex.decode_word!/1` validation at the boundary), full-detail JSON maps dispatch by `"type"` to `V1/V2/V3/V4.from_json/1`, and EIP-2930 (`"0x1"`) raises a specific "not yet supported" error distinct from the generic `unsupported envelope type`. New `Cartouche.Transaction.JsonField` cross-module helper module documents the six shared decoders. CodeRabbit's two findings (hash-validation P1, V4 authorizationList nil-handling P2) and Codex GitHub bot's type-1 finding all addressed locally — the V4 P2 was kept as documented-symmetric defensive `nil → []` behaviour across V2 accessList / V3 blobVersionedHashes / V4 authorizationList. Cursor's VM OOM'd on the PLT build (per the no-cloud-dialyzer convention); local `mix dialyzer.json` post-merge confirmed zero new warnings. Discovered follow-up: Task 99 (proper `Cartouche.Transaction.V_2930` `from_json/1` support, replaces both bot-finding pinning tests with positive shape assertions when it lands). See [CHANGELOG `[Unreleased]`](CHANGELOG.md#unreleased).

**Task 48 (Sleuth atom-table hardening) shipped 2026-05-06 (INE-43 / PR #53, delegated to Cursor).** Two-phase delivery — Phase A raised `Cartouche.Sleuth` to ≥95% coverage; Phase B swapped the remaining runtime atom mints (`query_by/3` derivations, `try_decode` named-returns preinterning, `name_keyword/1` rescue) to `String.to_existing_atom/1` with the INE-17-shape `{:error, "error decoding: ..."}` envelope on cold-atom paths. `.sobelow-skips` regenerated — all three `lib/cartouche/sleuth.ex` fingerprints dropped out, leaving only generator entries. Local dialyzer post-merge confirmed zero warnings on `sleuth.ex` (Cursor's VM OOM'd on the PLT build per the no-cloud-dialyzer convention; verification ran on `development`). Closes the Sleuth hardening bundle. See [CHANGELOG `[Unreleased]`](CHANGELOG.md#unreleased).

**Task 75 (`@spec` on every `defp` + `.credo.exs` `Specs include_defp:true`) shipped 2026-05-06 (INE-41 / PR #52, delegated to Cursor).** Whole-portfolio backfill across `lib/cartouche/**` and `test/support/**`; `.credo.exs` `:files` scoped to `lib/cartouche/` (excluding the auto-generated `lib/cartouche/contract/`). Local review (Cursor's VM lacks the memory budget for cartouche's full-deps PLT) caught 2 dialyzer regressions where PR-introduced specs referenced `Tesla.Env.client/0` — Tesla is in `:plt_ignore_apps` per the harness OOM workaround — fixed both KMS signers to `term()` with TODO markers. CodeRabbit's three findings (`Recover.decode_signature/1` spec realignment, `solana_client.ex` `amount` param shape, `Solana.Transaction.CompiledInstruction` `0..255` byte-range narrowing) landed before merge. Cursor/Codex VMs cannot dialyze cartouche → the no-cloud-dialyzer rule is now project-CLAUDE.md-pinned. See [CHANGELOG `[Unreleased]`](CHANGELOG.md#unreleased).

**Phase 4 closed 2026-06-05 with Task 98 shipped.** Tasks 19+20 (INE-39 / PR #50) first rewrote `Cartouche.Typed.encode_value_map/3` from the stale map-shaped spec to Dialyzer's conservative `bitstring()` success typing; Task 98 then tightened the implementation with `IO.iodata_to_binary/1` at each encoded-field branch so Dialyzer can infer the durable `binary()` contract. `find_type/2` was left untouched after verifying its committed spec already matched the impl (the Linear issue body's claim of `Typed.Type.t()` was stale). Both functions stay `defp`.

**INE-17 / Phase 11 decode-struct atom audit corrected 2026-05-05.** Verified the generator emits return-field names as strings inside selector metadata, not compile-time atoms; both live `decode_structs: true` paths now explicitly pre-intern bounded ABI field atoms before calling Hieroglyph 1.4.0's `String.to_existing_atom` decoder. See [CHANGELOG `[Unreleased]`](CHANGELOG.md#unreleased).

**`cartouche 0.1.3` cut 2026-05-02.** Phase 7.1 dep refresh — `google_api_cloud_kms` 0.38.1 → 0.43.0, internalising the 0.40 breaking arity change in both KMS signers behind a private `key_version_name/5` helper while preserving public API of `Cartouche.{Signer,Solana.Signer}.CloudKMS` (Tasks 24+25, 26 superseded). Phase 7.4 lockfile refresh closed Tasks 71 (`junit_formatter` 3.4.0 pin loosen) and 72 (`bandit` 1.11.0 lock-only). See [CHANGELOG `[0.1.3]`](CHANGELOG.md#013--2026-05-02).

**`cartouche 0.1.2` cut 2026-05-01.** Dep refresh + `mix.exs` pin tightening — picks up `hieroglyph 1.4.0` (atom-table DOS guard on `decode_structs: true`, plus the silent bug-fix windfall in 1.0.0–1.2.0), `ex_dna 1.4.3`, `ex_ast 0.8.1`. Pin `hieroglyph: "~> 1.4"` raises the consumer floor to match what cartouche is now tested against. See [CHANGELOG `[0.1.2]`](CHANGELOG.md#012--2026-05-01).

**`cartouche 0.1.1` cut 2026-05-01** (superseded same day by 0.1.2 before hex publish). Bundled the Block decoder fork fields (Tasks 63 + 64 + 65) and the two wire-format bugs the new mainnet integration suite (Task 61) caught at first run — `get_block_by_hash/2` missing `fullTransactionObjects` and V1 empty-calldata encoded as `"0x0"` instead of `"0x"`. Both pre-existing in upstream signet for years, masked by the mock client. See [CHANGELOG `[0.1.1]`](CHANGELOG.md#011--2026-05-01).

**Phase 0 fully closed 2026-04-30 — `cartouche 0.1.0` shipped.** First active release under the cartouche namespace. The downstream onchain `@dialyzer {:no_match}` strip across `Onchain.Hex` / ABI / ERC / ENS / Multicall callers is now load-bearing — Phase 1 spec corrections (1.1 RecoveryBit, 1.2 Wei, 1.3 Signer, 1.4 Hex) all in `0.1.0`.

**Block decoder bundle (Tasks 63 + 64 + 65) shipped in `0.1.1`.** `Cartouche.Block` extended with seven Ethereum-hard-fork fields (`base_fee_per_gas` London; `withdrawals_root` + `withdrawals` Shanghai; `parent_beacon_block_root` + `blob_gas_used` + `excess_blob_gas` Cancun; `mix_hash` pre/post-Merge). Nested `Cartouche.Block.Withdrawal` substruct mirrors the `Receipt.Log` precedent. Integration tests at the post-London 15M, post-Shanghai 18M, and post-Cancun 20M anchors strengthen from `refute Map.has_key?/2` → positive assertions. `Cartouche.Block` + `Cartouche.Block.Withdrawal` both at 100% coverage; dialyzer clean on `block.ex`; total `invalid_contract` count holds at 8.

**Mainnet integration suite (Task 61) shipped in `0.1.1`.** `test/rpc_integration_test.exs` opts in via `mix integration` and pins behaviour against historical mainnet anchors via the local archive-node SSH tunnel. Decoder gaps surfaced as Tasks 62 (traces, ✅ shipped under `[Unreleased]`), 63–65 (Block fork fields, ✅ shipped in `0.1.1`), 66 (Block.transactions full details), 67 (Receipt blob fields, ✅ shipped under `[Unreleased]`). Task 68 (originally "DebugTrace EIP-7702 opcodes") closed obsolete 2026-05-01 — premise wrong (AUTH/AUTHCALL were EIP-3074, withdrawn; EIP-7702 introduces no new opcodes); replaced by Task 70 (CLZ for Osaka, blocked on activation).

**Phase 9 fully closed 2026-05-07 with Task 90 (PR #61 / INE-50) shipped.** Raw transaction decode landed across V1/V2/V3/V4 via a single `Cartouche.Transaction.decode/1` dispatcher (Task 33, PR #41 / INE-30, 2026-05-06); the Copilot-flagged EIP-4844 versioned-hash `0x01` byte check followed up as Task 90 (Cursor cloud-agent, single-predicate tightening of `decode_blob_versioned_hashes/1`, one round to merge). Phase 9 done. Next-up surface: Phase 12 descripex follow-ups (Tasks 93-97).

**Generator hardening bundle progressing.** Task 44 (coverage push) shipped 2026-05-05 (INE-20); Task 42 (`decode_error` dead branch) shipped 2026-05-04 (PR #8 / INE-10); Task 41 (bytecode-flag separation) shipped 2026-05-06 (INE-36 / PR #46); Task 50 (`@doc`/`@spec` emission on generated bindings) shipped 2026-05-06 (INE-37 / PR #51) — `.doctor.exs` `ignore_paths` for `lib/cartouche/contract/` retired, `mix doctor` clean across regenerated `IConsole` + `Sleuth`. Remaining items in the bundle: the Task 59 `cartouche.gen.ex` hygiene sub-items.

**VM dialyzer cleanup bundle closed 2026-05-06.** Task 46 raised coverage on `Cartouche.VM.Context`, `Cartouche.Erc20.Call`, and `Cartouche.VM.InvalidVm`, unblocking Tasks 21+22 + 23. Task 23 shipped via INE-29 / PR #40 (`init_from/2` spec narrowed to a concrete struct literal; `Context.t/0` kept broad for post-mutation runtime contexts). Tasks 21+22 (`none()` cascade) closed 2026-05-06 — INE-21 / Task 46 was the actual resolver; INE-42 / PR #54 (Cursor cloud-agent) attempted suppressions that local dialyzer verification proved unnecessary, and the dead annotations were removed in the post-merge bookkeeping commit on `development`.

**Phase 12 (descripex adoption) annotation sweep complete — Tasks 83 + 84 + 85 + 86 + 87 + 88 all landed 2026-05-06.** Task 83 (INE-28 / PR #39) annotated `Cartouche.Signer` + `Cartouche.Keys`; Task 84 (INE-31 / PR #44) annotated `Cartouche.RPC` + the 6 response/trace decoders it returns (`Block`, `Receipt`, `FeeHistory`, `DebugTrace`, `Trace`, `TraceCall`) plus their 4 nested struct modules; Task 85 (INE-32 / PR #42) annotated `Cartouche.Transaction` + nested V1 + V2; Task 86 (INE-33 / PR #43) annotated `Cartouche.Solana.RPC`; Task 87 (INE-34 / PR #45) annotated the Solana stack — `Solana.Signer` + `Solana.Transaction` plus 7 instruction/PDA/ATA/program-id helpers (`Keys`, `PDA`, `ATA`, `Programs`, `SystemProgram`, `TokenProgram`, `Token`); Task 88 (INE-35 / PR #47) annotated the Ethereum utility + primitive bundle — `Hex`, `Erc20` (+ nested `Erc20.CallData` + `Erc20.Call` registered after Codex P2 surfaced the discovery gap), `Sleuth`, `Hash`, `Address`, `Wei`, `Chain`, `Base58`, `RecoveryBit`. All 36 module entries now register in `Cartouche.__descripex_modules__/0`. Bootstrap (Task 82) landed 2026-05-05: `:descripex` promoted to direct dep, `use Descripex.Discoverable` wired into `lib/cartouche.ex`, and a validation test flunks-with-the-function-name when annotation drift hits any registered module. **Task 89 (manifest wiring + README) is now unblocked** — every public module is in the manifest, no partial coverage. Five PR-flagged follow-ups filed as Tasks 93-97 (`Cartouche.Transaction.encode/1` real dispatcher, top-level `decode/1` return-shape metadata fix, discovery-helper self-annotation, V1 `value` annotation realignment, validation-test strengthening) plus two pre-existing `Solana.Transaction` correctness gaps surfaced by the bot ensemble on PR #45 — file as Tasks 91-92 (signer-count validation in `sign/2`; bounds-check on `add_signature/3`'s `List.replace_at/3`).

---

## 📦 Recommended bundles

Tasks below ship more efficiently together. Bundling rationale: same module(s), same coverage gate, sequential dependency where one's prep step *is* the other's prerequisite, or a single regenerate/recompile round-trip that would otherwise be paid multiple times.

D/B/U scores stay on individual rows — bundling is about session ergonomics, not re-pricing. The compound-ID convention (`7+8+9`, `10+11+12+13`, `14+15+35`, etc.) already covers tightly-coupled bundles that share one ROADMAP row; the table below documents the looser sets that retain their individual rows.

| Bundle | Tasks | Why bundle |
|---|---|---|
| **Generator hardening pass** | 44 ✅ → 42 ✅ → 41 ✅ → 50 ✅ → (+ 59-gen sub-items) | 44 was the coverage gate for 41 + 42 + 50 (all shipped). 50 dropped `.doctor.exs ignore_paths` when the regenerated bindings landed clean. Remaining in the bundle: 59's four `lib/mix/cartouche.gen.ex` items (`module_name`/`List.flatten` dead binds, two `Macro.underscore/1` repeats) ride along on the next regeneration round-trip; `.dialyzer_ignore.exs` retires when 59-gen ships |
| **Typed cleanup** | 45 → 19+20 | 45 raises `Cartouche.Typed` coverage to 100% by exercising `encode_value_map/3` and `find_type/2` with representative inputs — the tests that ground 19+20's spec rewrite are produced by the coverage push itself. Splitting wastes a session reading the same impl twice |
| **VM dialyzer cleanup** | 46 → 21+22 + 23 | 46 raises coverage on `Cartouche.VM.Context`, `Cartouche.Erc20.Call`, `Cartouche.VM.InvalidVm` — exactly the territory the `none()` cascade investigation (21+22) and the `VM.Context.@type t` alignment (23) need to reason about. Single VM mental model, one `mix dialyzer.json` baseline run, three modules |
| **KMS upgrade chain** | 24+25 → 26 | 26 is conditional on the 0.38.1 → 0.43.0 changelog audit performed in 24+25. Same `mix.exs` edit, same `mix deps.update` round-trip; if the audit finds nothing new worth surfacing, 26 closes immediately as superseded. Splitting forces a second deps session |
| **Phase 7 dep refresh** | 24+25 + 26 + 71 + 72 | Single `mix.exs` edit, single `mix deps.update`, single `mix test.json` + `mix dialyzer.json` round-trip. KMS audit (24+25) is the bulk; 71 + 72 ride along; 26 likely closes as superseded (Ed25519 shipped via Solana). Critical-tier coverage gate on both KMS signer modules — verify ≥95% before any code mutation triggered by the audit |
| **Sleuth hardening** | (raise `Cartouche.Sleuth` to ≥95% coverage) → 48 ✅ | Internal bundle — Task 48's note already mandated the coverage push before the `String.to_atom` → `String.to_existing_atom` swap (per `critical-rules.md` "RAISE COVERAGE BEFORE MUTATING", Sleuth is critical-tier). Shipped 2026-05-06 as INE-43 / PR #53 — Phase A coverage commit then Phase B atom-swap commit, single delivery |
| **Descripex adoption** | 82 → 83 + 84 + 85 + 86 + 87 + 88 → 89 | Task 82 stands up the wrapper + validation test. Tasks 83-88 are independently `[P]`-eligible — different sessions can annotate Signer / RPC / Transaction / Solana stack / utilities in parallel. Each pairs a primary entry point with its small co-domain helpers (so each annotation session covers one mental-model cluster, no module reopens). Task 89 closes once all 83-88 land. Recommend pause-for-`/compact` after the bootstrap (Task 82) lands, then a second batch covering 1-2 of the larger `[P]` annotation tasks per session (Task 84 is the largest at 7 modules; 87 and 88 each cover 9 modules). Smaller `[P]` tasks (83 with 2 modules, 86 with 1 module) bundle freely |

### Already bundled (compound IDs)

`7+8+9` Phase 1.1–1.3 ✅ · `10+11+12+13` Phase 1.4 Hex ✅ · `14+15+35` RPC error shapes ✅ · `16+17+18` Trace specs ✅ · `19+20` Typed specs · `21+22` VM cascade · `24+25` KMS ✅ · `27+28` Finch ✅ · `29+30` V2 dedup · `71+72` junit_formatter + bandit lock refresh ✅ · `83/84/85/86/87/88` ✅ Phase 12 annotation `[P]` set.

### Standalone (no natural bundle partner)

`6` (publish, user-only) · ~~`39` (RecoveryBit doctest portability)~~ ✅ · ~~`47` (config-only — exclude IConsole from coverage measurement)~~ ✅ · ~~`54` (Transaction.Call extraction — large, structural, spans generator + RPC + Sleuth)~~ ✅ · ~~`58` (single test)~~ ✅ · ~~`59-lib` (Reach 1.8 → 2.2 bump + hygiene pass in `lib/cartouche/**`)~~ ✅ · `31` (EIP-4844) · ~~`32` (EIP-7702)~~ ✅ · `33` (raw decode — sequenced *after* 31 + 32 so it inherits the encoded forms).

---

## Phase 0: Ship `0.1.0`

<!-- TASKS:BEGIN phase=0 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 1 | ✅ | 🎁 **release_010** · Reset mix.exs version 1.6.1 → 0.1.0-dev [D:1/B:3/U:7 → Eff:5.0?] 🎯 |
| Task 2 | ✅ | 🎁 **release_010** · Full mix test.json --quiet pass on the ported code [D:3/B:5/U:7 → Eff:2.0?] 🎯 |
| Task 3 | ✅ | 🎁 **release_010** · mix dialyzer.json --quiet — inventory remaining invalid_contract warnings, confirm they match the pre-rename audit [D:2/B:3/U:6 → Eff:2.25?] 🎯 |
| Task 4 | ✅ | 🎁 **release_010** · mix docs clean build with cartouche branding intact [D:2/B:3/U:5 → Eff:2.0?] 🎯 |
| Task 5 | ✅ | 🎁 **release_010** · Update README.md installation section — replace the 'not recommended yet' placeholder with real install instructions [D:1/B:3/U:7 → Eff:5.0?] 🎯 |
| Task 6 | ✅ | 🎁 **release_010** · Tag 0.1.0, publish to hex [D:1/B:5/U:8 → Eff:6.5?] 🎯 |
| Task 36 | ✅ | 🎁 **release_010** · Silence ex_doc 'documentation references type X but the module is hidden' warnings surfaced by mix docs [D:2/B:2/U:4 → Eff:1.5?] 🚀 |
| Task 37 | ✅ | 🎁 **release_010** · Publish cut — version bump, CHANGELOG release section, mix.exs :package polish, README install activation [D:1/B:3/U:5 → Eff:4.0?] 🎯 |
| Task 40 | ✅ | 🎁 **generator_hardening** · Generator (lib/mix/cartouche.gen.ex) credo cleanup [D:5/B:2/U:3 → Eff:0.5?] ⚠️ |
| Task 38 | ✅ | 🎁 **release_010** · Delete Cartouche.Util grab-bag — redistribute helpers into focused modules, drop @deprecated aliases [D:3/B:3/U:5 → Eff:1.33?] 📋 |
| Task 51 | ✅ | 🎁 **correctness_010** · Cartouche.Trace.t().trace_address typed singular but runtime is a list [D:1/B:5/U:7 → Eff:6.0?] 🎯 |
| Task 52 | ✅ | 🎁 **correctness_010** · Cartouche.TraceCall.t().trace typed singular but runtime is a list [D:1/B:5/U:7 → Eff:6.0?] 🎯 |
| Task 53 | ✅ | 🎁 **correctness_010** · V1.t() Schrödinger r/s/v + latent decode → recover_signer crash [D:4/B:7/U:6 → Eff:1.62?] 🚀 |
| Task 56 | ✅ | 🎁 **correctness_010** · Harden Cartouche.Solana.Transaction.deserialize/1 crash paths [D:2/B:6/U:6 → Eff:3.0?] 🎯 |
| Task 41 `[CX]` | ✅ | 🎁 **generator_hardening** · Generator bytecode-flag separation — init vs deployed [D:3/B:2/U:3 → Eff:0.83?] ⚠️ |
| Task 42 | ✅ | 🎁 **generator_hardening** · Generator decode_error/1 template — drop dead if true ... else ... end branch [D:1/B:1/U:2 → Eff:1.5?] 🚀 |
| Task 44 `[CSR]` | ✅ | 🎁 **generator_hardening** · Generator coverage push — raise Mix.Tasks.Cartouche.Gen to ≥80% before Tasks 41 + 42 [D:3/B:4/U:6 → Eff:1.67?] 🚀 |
| Task 47 | ✅ | 🎁 **generator_hardening** · Exclude generated Cartouche.Contract.IConsole from coverage measurement [D:1/B:1/U:3 → Eff:2.0?] 🎯 |
| Task 49 | ⛔ | 🎁 **generator_hardening** · Resolve Cartouche.Transaction.V2.encode/1 spec duplication — superseded by Task 54 [D:1/B:1/U:1 → Eff:1.0?] 📋 |
| Task 54 `[CSR]` | ✅ | 🎁 **generator_hardening** · Extract Cartouche.Transaction.Call — collapse the V2-as-eth-call-shape lie [D:6/B:5/U:5 → Eff:0.83?] ⚠️ |
| Task 50 `[CX]` | ✅ | 🎁 **generator_hardening** · Generator emits @doc/@spec on generated bindings — drop .doctor.exs ignore_paths [D:3/B:2/U:3 → Eff:0.83?] ⚠️ |
| Task 48 `[CSR]` | ✅ | 🎁 **sleuth_hardening** · Harden Cartouche.Sleuth atom-table risks [D:5/B:4/U:5 → Eff:0.9?] ⚠️ |
| Task 55 | ✅ | 🎁 **trace_hardening** · Harden Cartouche.Trace.deserialize/1 against missing/nil traceAddress [D:1/B:2/U:3 → Eff:2.5?] 🎯 |
| Task 43 | ✅ | 🎁 **coverage_pushes** · Pre-credo coverage push for cleanup-target modules [D:3/B:5/U:7 → Eff:2.0?] 🎯 |
| Task 57 | ✅ | 🎁 **solana_hardening** · Fix Cartouche.Solana.Transaction.sign_partial/2 zero-signer boundary [D:1/B:3/U:3 → Eff:3.0?] 🎯 |
| Task 58 `[CX]` | ✅ | 🎁 **rpc_correctness** · Strengthen Cartouche.Filter expired-filter test — assert recovery-branch fingerprint [D:1/B:2/U:2 → Eff:2.0?] 🎯 |
| Task 59 `[CSR]` | ✅ | 🎁 **generator_hardening** · Reach 1.8 → 2.2 bump + hygiene pass [D:1/B:2/U:1 → Eff:1.5?] 🚀 |
| Task 60 | ✅ | 🎁 **rpc_correctness** · Cartouche.RPC.get_block_by_number/2 integer path crashes on real nodes [D:1/B:3/U:4 → Eff:3.5?] 🎯 |
| Task 61 | ✅ | 🎁 **rpc_correctness** · Mainnet archive integration test suite — read-only RPC sweep [D:3/B:6/U:7 → Eff:2.17?] 🎯 |
| Task 62 | ✅ | 🎁 **rpc_correctness** · v2 traces — integration anchors for trace_transaction, trace_call, trace_callMany, debug_traceCall [D:5/B:5/U:5 → Eff:1.0?] 📋 |
| Task 63 | ✅ | 🎁 **block_fork_fields** · Cartouche.Block — add base_fee_per_gas (London+) [D:1/B:3/U:5 → Eff:4.0?] 🎯 |
| Task 64 | ✅ | 🎁 **block_fork_fields** · Cartouche.Block — add withdrawals_root and withdrawals (Shanghai+) [D:2/B:3/U:5 → Eff:2.0?] 🎯 |
| Task 65 | ✅ | 🎁 **block_fork_fields** · Cartouche.Block — add Cancun fields (parent_beacon_block_root, blob_gas_used, excess_blob_gas, mix_hash) [D:2/B:3/U:5 → Eff:2.0?] 🎯 |
| Task 66 `[CSR]` | ✅ | 🎁 **rpc_correctness** · Cartouche.Block.transactions — implement include_transaction_details: true [D:5/B:4/U:5 → Eff:0.9?] ⚠️ |
| Task 99 | ✅ | 🎁 **rpc_correctness** · Cartouche.Transaction.V_2930 — add EIP-2930 (type 0x1) JSON deserialization [D:3/B:2/U:2 → Eff:0.67?] ⚠️ |
| Task 67 | ✅ | 🎁 **rpc_correctness** · Cartouche.Receipt — add EIP-4844 blob fields (blob_gas_used, blob_gas_price) [D:2/B:3/U:4 → Eff:1.75?] 🚀 |
| Task 68 | ⛔ | 🎁 **eip_opcode_followups** · Cartouche.DebugTrace.StructLog — add EIP-7702 opcodes to the closed whitelist (AUTH, AUTHCALL) — closed obsolete [D:1/B:1/U:1 → Eff:1.0?] 📋 |
| Task 69 | ✅ | 🎁 **bug_triage** · Audit RPC-level requirements bubbling up from defi-skills mining [D:2/B:5/U:4 → Eff:2.25?] 🎯 |
| Task 70 `[CX]` | ✅ | 🎁 **eip_opcode_followups** · Cartouche.DebugTrace.StructLog — add CLZ (EIP-7939/Osaka) to the closed whitelist [D:1/B:2/U:3 → Eff:2.5?] 🎯 |
| Task 73 | ✅ | 🎁 **kms_followups** · KMS signer Goth-path test mocking — clear critical-tier ≥95% gate on both KMS signers [D:3/B:2/U:3 → Eff:0.83?] ⚠️ |
| Task 75 `[CX]` | ✅ | 🎁 **tooling_quality** · Backfill @spec on every defp to enable .credo.exs {Specs, [include_defp: true]} portfolio-wide [D:7/B:5/U:5 → Eff:0.71?] ⚠️ |
| Task 76 | ✅ | 🎁 **tooling_quality** · Restore dialyzer to the standard PR harness — the OOM premise was the Assembly bomb, now fixed [D:3/B:2/U:3 → Eff:0.83?] ⚠️ |
| Task 74 | ✅ | 🎁 **wei_units** · Cartouche.Wei.to_wei/1 — add :eth denomination with Decimal support [D:3/B:3/U:3 → Eff:1.0?] 📋 |
| Task 77 `[CSR]` | ✅ | 🎁 **coverage_pushes** · Cartouche.Solana.RPC coverage push — pre-existing untested option/filter/encoding paths [D:2/B:3/U:4 → Eff:1.75?] 🚀 |
| Task 91 `[CX]` | ✅ | 🎁 **solana_hardening** · Cartouche.Solana.Transaction.sign/2 — reject signer-count mismatch against message.header.num_required_signatures [D:1/B:3/U:3 → Eff:3.0?] 🎯 |
| Task 92 `[CX]` | ✅ | 🎁 **solana_hardening** · Cartouche.Solana.Transaction.add_signature/3 — guard index against length(transaction.signatures) before List.replace_at/3 [D:1/B:3/U:3 → Eff:3.0?] 🎯 |
| Task 103 | ✅ | 🎁 **generator_hardening** · Fix the ~30 GB downstream dialyzer bomb — collapse Assembly.compile/1's 7-arity tuple_set (NOT IConsole) [D:4/B:7/U:6 → Eff:1.62?] 🚀 |
| Task 105 | ⬜ | 🎁 **generator_hardening** · Optional: slim generated IConsole surface (~250 MB dialyzer win, not the bomb) [D:3/B:2/U:3 → Eff:0.83?] ⚠️ |
| Task 104 | ✅ | 🎁 **signer_backends** · Formalize signer backends as a behaviour (pure digest-signer contract) — unlock multi-provider signing [D:4/B:6/U:6 → Eff:1.5?] 🚀 |
| Task 106 | ✅ | 🎁 **generator_hardening** · Generator fixture: unlinked-library / immutable bytecode placeholders through blank_bytecode?/hex! [D:2/B:3/U:3 → Eff:1.5?] 🚀 |
| Task 109 | ✅ | 🎁 **tooling_quality** · Finish + normalize typed-transaction helper extraction (dedup maybe_to_wei/chain_id_value; migrate V3 onto TypedDecode/Signature) [D:2/B:4/U:4 → Eff:2.0?] 🎯 |
| Task 110 | ✅ | 🎁 **tooling_quality** · defrpc macro — generate uniform JSON-RPC wrappers + @spec + @doc + Descripex api() from one declaration [D:5/B:6/U:5 → Eff:1.1?] 📋 |
| Task 111 | ⛔ | 🎁 **tooling_quality** · Spike: evaluate a Cartouche.Transaction.Typed envelope macro across V_2930/V3/V4 [D:2/B:3/U:3 → Eff:1.5?] 🚀 |
| Task 113 | ✅ | 🎁 **coverage_pushes** · 🔒 Property + cross-implementation vector suite for Ethereum tx envelopes and signing [D:4/B:8/U:8 → Eff:2.0] 🎯 |
| Task 114 | ✅ | 🎁 **coverage_pushes** · 🔒 Mutation-adequacy campaign over the signing and transaction paths [D:5/B:7/U:6 → Eff:1.3] 📋 |
| Task 115 | ✅ | 🎁 **phase8_dedup** · Cartouche.Transaction.V_2930 write surface — new/encode/sign/hash/signature/recover [D:3/B:4/U:4 → Eff:1.33] 📋 |
| Task 116 | ✅ | 🎁 **signer_backends** · 🔒 Enforce the Signer.Backend contract at the boundary — payload length, curve, DER parse [D:3/B:6/U:6 → Eff:2.0] 🎯 |
| Task 117 | ✅ | 🎁 **phase9_tx** · 🔒 Encode must not emit wire-non-conformant RLP — close the encode/decode conformance gap across V2/V3/V4 [D:3/B:8/U:7 → Eff:2.5] 🎯 |
| Task 118 | ✅ | 🎁 **signer_backends** · 🔒 Low-s is a library-wide invariant, not a per-backend convention — close the sign_direct/4 bypass [D:3/B:7/U:7 → Eff:2.33] 🎯 |
| Task 119 | 🔶 | 🎁 **coverage_pushes** · 🔒 Re-run the mutation-adequacy campaign once muex can report survivors [D:5/B:7/U:3 → Eff:1.0] 📋 ⛔ muex 0.8.3 fixes survivor reporting (Oeditus/muex#20) but Oeditus/muex#23 (sandboxes share the project _build, so a mutant can be graded on unmutated code) and Oeditus/muex#24 (mutations keyed by reported line, so StatementDeletion and bare-boolean flips are never applied) are open; a 2026-08-24 campaign was run and discarded. Unblocks when a muex release carries both fixes and the per-defect gate in the first acceptance criterion passes |
| Task 120 | ✅ | 🎁 **rpc_correctness** · Cartouche.RPC.create_access_list/2 — eth_createAccessList [D:3/B:7/U:6 → Eff:2.17] 🎯 |
| Task 121 | ✅ | 🎁 **rpc_correctness** · Complete the Cartouche.Filter lifecycle — uninstall, getFilterLogs, and the block/pending filter kinds [D:4/B:7/U:7 → Eff:1.75] 🚀 |
| Task 122 | ✅ | 🎁 **rpc_correctness** · Cartouche.RPC fee reads — eth_baseFee and eth_blobBaseFee [D:2/B:6/U:5 → Eff:2.75] 🎯 |
| Task 123 | ✅ | 🎁 **rpc_correctness** · Cartouche.RPC node introspection — eth_config (EIP-7910) and eth_capabilities [D:4/B:5/U:4 → Eff:1.12] 📋 |
| Task 124 | ✅ | 🎁 **rpc_correctness** · Cartouche.RPC node-custody methods — eth_accounts, eth_coinbase, eth_fillTransaction, eth_sign, eth_signTransaction, eth_sendTransaction [D:4/B:6/U:4 → Eff:1.25] 📋 |
| Task 125 | ✅ | 🎁 **rpc_correctness** · Cartouche.RPC.fill_transaction/2 cannot deserialize a spec-conforming eth_fillTransaction result [D:5/B:5/U:4 → Eff:0.9] ⚠️ |
| Task 126 | ✅ | 🎁 **rpc_correctness** · Spec-path fill_transaction V1 results drop chainId, so encode is pre-EIP-155 [D:4/B:5/U:4 → Eff:1.12] 📋 |
| Task 127 | ⬜ | 🎁 **rpc_correctness** · base_fee/1 portability — probe the real hosted-provider refusal, then decide standard vs extension [D:3/B:7/U:4 → Eff:1.83] 🚀 |
| Task 128 | ⬜ | 🎁 **rpc_read_surface** · Own eth_getLogs in cartouche — stateless log queries, and delete onchain's copy [D:3/B:8/U:7 → Eff:2.5] 🎯 |
| Task 129 | ⬜ | 🎁 **rpc_read_surface** · Own the transaction and receipt read-back in cartouche — 4 methods, and delete onchain's copies [D:4/B:7/U:6 → Eff:1.62] 🚀 |
| Task 130 | ⬜ | 🎁 **rpc_read_surface** · Own the state reads in cartouche — eth_getStorageAt and eth_getProof (EIP-1186) [D:3/B:6/U:5 → Eff:1.83] 🚀 |
| Task 131 | ⬜ | 🎁 **rpc_read_surface** · Own the node-introspection surface in cartouche — and mark the three methods no tagged spec carries [D:3/B:6/U:6 → Eff:2.0] 🎯 |
| Task 132 | ⬜ | 🎁 **rpc_read_surface** · Own eth_simulateV1 in cartouche — the portable simulation entry point [D:5/B:8/U:6 → Eff:1.4] 📋 |
| Task 133 | ⬜ | 🎁 **correctness_010** · 🔒 EIP-712 conformance: encode_type non-termination, bytesN padding direction, array-of-struct support, int types [D:4/B:9/U:8 → Eff:2.12] 🎯 |
| Task 134 | ⬜ | 🎁 **correctness_010** · 🔒 EIP-191 personal_sign byte length, a recovery helper that applies the prefix, and the 65-byte signature invariant [D:3/B:7/U:6 → Eff:2.17] 🎯 |
| Task 135 | ⬜ | 🎁 **rpc_correctness** · Portability contract for the non-standard read surface: trace_* and debug_traceCall [D:3/B:7/U:7 → Eff:2.33] 🎯 |
| Task 136 | ⬜ | 🎁 **rpc_read_surface** · Multi-endpoint live-test seam so node-portability rule 4 can actually be executed [D:3/B:8/U:8 → Eff:2.67] 🎯 |
| Task 137 | ⬜ | 🎁 **rpc_read_surface** · Move the transport hardening into cartouche — retry, telemetry, node-refusal classification, batch [D:5/B:9/U:9 → Eff:1.8] 🚀 |
<!-- TASKS:END -->

**Acceptance:** onchain can `mix deps.update cartouche` against `{:cartouche, "~> 0.1"}` and resolve.

---

## Phase 0.4: Pre-`0.1.0` correctness fixes

Four real bugs caught by the type system / static analysis but not exercised by the test suite. Three surfaced during the doctor-driven typespec sweep (2026-04-26) — Tasks 51 + 52 (consumer-facing MatchError potential — Trace / TraceCall list-vs-singular type mismatch; both ✅ landed 2026-04-26) and Task 53 (latent crash on a public API path — `V1.decode → recover_signer → ArgumentError` on signed RLP; ✅ landed 2026-04-28). A fourth was added by a follow-up Codex consultation (2026-04-26) — Task 56 (`Cartouche.Solana.Transaction.deserialize/1` raises on malformed bytes instead of returning `{:error, _}`; ✅ landed 2026-04-27 bundled with Task 57's zero-signer boundary fix). All Phase 0.4 blockers are cleared; Task 6 (`mix hex.publish`) is the only remaining pre-release item.

_Phase 0.4 rows rendered in the consolidated Phase 0 table above (rmap collapses sub-phases under `phase=0`; bundle `correctness_010` filters Phase 0.4 tasks)._

---

## Phase 0.5: Post-`0.1.0` hardening

Bugs and follow-ups that don't block `0.1.0` and warrant their own commits — initially generator-related (surfaced during the Task 40 staged review 2026-04-26), extended through subsequent Phase 0.4 work (Trace `traceAddress` audit), Sleuth atom-table risk (Task 48), and Solana hardening from the Codex consultation (2026-04-26).

_Phase 0.5 rows rendered in the consolidated Phase 0 table above (rmap collapses sub-phases under `phase=0`; bundles `generator_hardening` / `sleuth_hardening` / `solana_hardening` / `coverage_pushes` / `trace_hardening` / `rpc_correctness` / `block_fork_fields` / `eip_opcode_followups` / `tooling_quality` / `wei_units` / `kms_followups` / `bug_triage` filter Phase 0.5 tasks)._

---

## Phase 1: Spec corrections (immediate onchain wins)

**Why:** These are the load-bearing fixes for onchain's `@dialyzer` suppressions. Every one is grounded in `mix dialyzer.json` output from the pre-rename audit (2026-04-21). All are surgical — spec-only edits, no runtime change.

### 1.1 `Cartouche.RecoveryBit` — `:no_return` atom → `no_return()` type ✅

**Landed 2026-04-25 as part of Task 38** (Util grab-bag deletion). Promotion of `Cartouche.Util.RecoveryBit` to a top-level `Cartouche.RecoveryBit` module corrected both specs in flight:

| Function | Fix |
|----------|-----|
| `RecoveryBit.normalize/2` | `\| :no_return` → `\| no_return()` |
| `RecoveryBit.normalize_signature/2` | `\| :no_return` → `\| no_return()` |

**Follow-up:** `Cartouche.RecoveryBit` doctests for `normalize/2` (`:eip155` branch, returns `46`) and `recover_base/1` (`v=47` raise message bakes `chain_id=5`) are only correct under `chain_id=:goerli` (the cartouche test-config value). Pre-existing in upstream `Cartouche.Util.RecoveryBit`. Not a correctness bug — tests pass — but a portability/documentation hazard. Tracked as Task 39.

<!-- TASKS:BEGIN phase=1 -->
> 3 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-1-spec-corrections-immediate-onchain-wins).
<!-- TASKS:END -->

### 1.2 `Cartouche.Wei.to_wei/1` — narrow `integer()` → `non_neg_integer()` ✅

Spec narrowed input + return both to `non_neg_integer()` with matching `amount >= 0` guards (2026-04-29). Wei is a discrete count by domain; all internal callers already pass non-negative values.

### 1.3 `Cartouche.Signer.sign_direct/4` — `mfa()` → `{module(), atom(), list()}` ✅

Dialyzer reported `signer.ex:141 invalid_contract`. 3rd arg specced as `mfa()` (Elixir defines as `{module(), atom(), arity :: non_neg_integer()}`) but the impl receives `{module(), atom(), args :: list()}`. Fixed 2026-04-26 along with the same regression about to ship via `start_link/1`.

### 1.1–1.3 bundled task ✅

Phase 1.1 landed 2026-04-25 (Task 38). Phase 1.3 landed 2026-04-26 (typespec sweep — see CHANGELOG `[Unreleased]`). Phase 1.2 landed 2026-04-29 (`Cartouche.Wei.to_wei/1` narrowed). All three closed.


### 1.4 `Cartouche.Hex` return-type specs

**Root cause:** private `Cartouche.Hex.decode_hex_/1` (`lib/cartouche/hex.ex:374`) returns `{:ok, t()} | :invalid_hex` but is specced `{:ok, t()} | :error`. All public callers inherit this:

| Function | Line | Current `@spec` | Actual return |
|----------|------|-----------------|---------------|
| `decode_hex/1` | 80 | `{:ok, t()} \| :error` | `{:ok, t()} \| :invalid_hex` |
| `decode_hex_number/1` | 245 | `{:ok, integer()} \| :error` | `{:ok, integer()} \| :invalid_hex` |
| `from_hex/1` | 91 | `t() -> String.t()` | `t() -> {:ok, t()} \| :invalid_hex` (alias for `decode_hex`) |
| `from_hex!/1` | 102 | `t() -> String.t()` | `t() -> t()` (alias for `decode_hex!`) |

Doctests and `@doc` examples already show the correct shape; only the `@spec` lines disagree. Fix is surgical — update the four specs, no implementation change.

**Closeout (2026-04-28):** the four `@spec` lines plus the private `decode_hex_/1` were corrected as a drive-by in commit `8d4bc18` ("doctor, credo fixes", 2026-04-26) — `:error` → `:invalid_hex` on `decode_hex/1`, `decode_hex_number/1`, `decode_hex_/1`, and `from_hex/1`; `t() -> String.t()` → `t() -> t()` on `from_hex!/1`. Dialyzer has been clean on `hex.ex` since (verified post-`8d4bc18` and again 2026-04-28: 0 warnings filtered to the file, total `invalid_contract` count 8 — `hex.ex:93` no longer in the list). The 2026-04-28 closeout commit grounds the corrected specs with focused ExUnit assertions (`test/hex_test.exs` `describe "spec boundaries (Phase 1.4)"`) per the project memory `feedback_doctests_not_substitute_for_tests.md`, adds the missing failure-path doctests to `from_hex/1` and `from_hex!/1` (parity with `decode_hex/1` / `decode_hex!/1`), and bundles a small `deep_encode_binaries/1` coverage block (4 lines) that lifts `Cartouche.Hex` from 94.29% to 100% — clearing the ≥95% critical-tier gate prophylactically.


**Downstream impact once shipped in `0.1.x`:** onchain strips its `@dialyzer {:no_match, …}` blocks from `Onchain.Hex` and (via cascade through `Contract.call/5 → ABI.decode_response/2`) from the ABI / ERC / ENS / Multicall modules. Full downstream strip additionally needs the external `abi` fix tracked in Phase 10.

---

## Phase 2: `Cartouche.RPC.send_rpc/3` error-shape spec

**Why:** onchain carries `@dialyzer {:no_match, do_rpc: 3}` because the current spec promises `%{code: int, message: str}` for all errors, but `send_rpc/3` actually returns several other error shapes at runtime.

Confirmed runtime error shapes (`lib/cartouche/rpc.ex:84–203`, `lib/cartouche/http.ex` normalize_finch_result/1):

| Source | Returned shape |
|--------|----------------|
| Finch non-2xx | `{:error, %Finch.Response{}}` |
| Finch transport | `{:error, "[Cartouche] HTTP client error: …"}` (string) |
| Finch unknown | `{:error, "[Cartouche] Unknown error: …"}` (string) |
| Invalid JSON-RPC envelope | `{:error, %{code: -999, message: "…"}}` |
| Revert with decoded error (code 3) | `{:error, %{code:, message:, revert:, error_abi:, error_params:}}` (extra fields vs spec) |
| `decode: :hex` path with bad hex | bare `:invalid_hex` atom (not wrapped in `{:error, …}`) |
| Custom `decode:` fn raises | `{:error, "failed to decode `<method>` response: <inspect>"}` |
| **Non-JSON-encodable `method` or `params`** | **raises `Protocol.UndefinedError` / `Jason.EncodeError` — bypasses `{:ok,_}\|{:error,_}` contract entirely** (`rpc.ex:162`, `Jason.encode!(body)`). Same pattern in `lib/cartouche/solana/rpc.ex:68` (`Cartouche.Solana.RPC.send_rpc/3`). |

### Tasks

<!-- TASKS:BEGIN phase=2 -->
> 1 task. See [CHANGELOG.md](CHANGELOG.md#phase-2-cartouche-rpc-send-rpc-3-error-shape-spec).
<!-- TASKS:END -->

**Blast radius** (from `mix reach.impact Cartouche.RPC.send_rpc/3`, pre-rename): 6 direct callers break on signature change (`get_balance/2`, `get_transaction_count/2`, `eth_block_number/1`, `eth_chain_id/1`, `set_filter/1`, `Cartouche.Filter.handle_info/2`), 1 transitive (`Cartouche.Signer.init/1`), no return-value dependents. Behavior-preserving spec-widening is low-risk; a union-type split needs all 6 direct callers to still type-check.

---

## Phase 3: `Cartouche.Trace` + `Cartouche.TraceCall` deserialize specs ✅

**Why:** Dialyzer reports `trace.ex:408` and `trace_call.ex:124` as `invalid_contract`. The struct returned by `deserialize/1` has fields with union types (`nil | binary()`, `nil | <<_:160>>`, etc.) that the module's `@type t` declaration doesn't allow.

<!-- TASKS:BEGIN phase=3 -->
> 1 task. See [CHANGELOG.md](CHANGELOG.md#phase-3-cartouche-trace-cartouche-tracecall-deserialize-specs).
<!-- TASKS:END -->

---

## Phase 4: `Cartouche.Typed` internal-function specs

**Why:** Dialyzer reports `typed.ex:571` (`encode_value_map/3`) and `typed.ex:585` (`find_type/2`) as `invalid_contract`. Both specs completely disagree with the success typing — looks like copy-paste from a sibling function or a stale spec after a refactor.

- `encode_value_map/3`: original spec returned a map; impl now returns a `binary()`.
- `find_type/2`: spec returns `Typed.Type.t()`; impl returns a 2-tuple.

<!-- TASKS:BEGIN phase=4 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 19+20 `[CSR]` | ✅ | 🎁 **phase4_typed** · Phase 4 Typed internal-function specs — rewrite + visibility judgment [D:3/B:2/U:3 → Eff:0.83?] ⚠️ |
| Task 98 `[CSR]` | ✅ | 🎁 **phase4_typed** · Phase 4 follow-up — tighten Cartouche.Typed.encode_value_map/3 impl so dialyzer infers binary(), restore stricter @spec [D:2/B:2/U:2 → Eff:1.0?] 📋 |
| Task 45 `[CSR]` | ✅ | 🎁 **coverage_pushes** · Cartouche.Typed coverage push — exercise encode_value_map/3 and find_type/2 with representative inputs [D:2/B:2/U:3 → Eff:1.25?] 📋 |
<!-- TASKS:END -->

---

## Phase 5: VM / Erc20.Call `none()` cascade investigation ✅

**Closed 2026-05-06 — effectively resolved by INE-21 / Task 46 prior coverage work.** The four dialyzer `invalid_contract` warnings (`Cartouche.VM.exec/3`, `exec_call/3`, `Cartouche.Erc20.exec_trx/3`, `transfer/4`) no longer reproduce as of `5918e5a` (INE-21 / Task 46 landed 2026-05-05). PR #54 (INE-42) was a Cursor cloud-agent delegation that attempted `@dialyzer {:no_contracts, …}` suppressions on all four heads plus a spec narrowing on `Erc20.exec_trx/3`; local verification with `mix dialyzer.json --quiet` showed the suppressions were dead code (cascade no longer fires). PR #54 was merged for the spec narrowing (independently valuable — mirrors `Cartouche.RPC.execute_trx/3`'s contract); the four dead `@dialyzer` annotations + their cascade-root comment blocks were removed in the post-merge bookkeeping commit on `development`.

**Why the cascade collapsed:** Task 46's coverage push on `Cartouche.VM.Context`, `Cartouche.Erc20.Call`, and `Cartouche.VM.InvalidVm` exercised the previously-untyped paths well enough that dialyzer no longer narrows the public heads' success typing to `none()`. No targeted fix or suppression was needed.

<!-- TASKS:BEGIN phase=5 -->
> 1 task. See [CHANGELOG.md](CHANGELOG.md#phase-5-vm-erc20-call-none-cascade-investigation).
<!-- TASKS:END -->

---

## Phase 6: `Cartouche.VM.Context.init_from/2` spec ✅

**Closed 2026-05-06.** Task 46 cleared the coverage gate; Task 23 (PR #40 / INE-29) chose Option B (relax `init_from/2` to a concrete struct literal matching the actual initial-state construction). `Cartouche.VM.Context.@type t/0` stays broad to describe mutated runtime contexts. `vm.ex:104 invalid_contract` cleared.

<!-- TASKS:BEGIN phase=6 -->
> 2 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-6-cartouche-vm-context-init-from-2-spec).
<!-- TASKS:END -->

---

## Phase 7: Dependency freshness

Single-repo ownership simplifies this — we edit `mix.exs` and `mix.lock` directly, no dual-branch dance.

### 7.1 `google_api_cloud_kms` 0.38.1 → 0.43.0

`mix.exs` previously pinned `~> 0.38.1` (resolved `< 0.39`); now `~> 0.43.0` post-Tasks-24+25. Cartouche uses this in **two** signer modules — `lib/cartouche/signer/cloud_kms.ex` (Ethereum, secp256k1 `digest.sha256` sign) and `lib/cartouche/solana/signer/cloud_kms.ex` (Solana, `EC_SIGN_ED25519` raw-message sign) — both via `cloudkms_..._get_public_key` and `cloudkms_..._asymmetric_sign`, which collapsed at 0.40.0 from arity 6/7 (split path components) to arity 4 (`(connection, name, optional_params \\ [], opts \\ [])` with a single `name` resource path). Both modules are wrapped in `if Code.ensure_loaded?(GoogleApi.CloudKMS.V1.Api.Projects)` and gated as critical-tier (≥95% coverage gate per `critical-rules.md`) — current coverage 88% / 90% post-bump; Goth-path mocking (Task 73) is the deferred follow-up to clear the gate.

<!-- TASKS:BEGIN phase=7 -->
> 7 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-7-dependency-freshness).
<!-- TASKS:END -->

### 7.2 `ex_doc` 0.31.1 → 0.40

`mix.exs` already carries `~> 0.40` (kept from the `:reach` requirement — `reach` pulls `makeup_elixir ~> 1.0` which conflicted with upstream's `ex_doc 0.31.1 → ~> 0.14`). No additional action needed beyond Task 4 verifying `mix docs` produces clean output.

### 7.3 `finch` 0.19 → 0.21

`mix.exs` pinned `~> 0.19`; lockfile already on 0.21.0. Cartouche uses Finch across 4 callsites: `lib/cartouche/application.ex` (default pool start), `lib/cartouche/rpc.ex`, `lib/cartouche/solana/rpc.ex`, `lib/cartouche/open_chain.ex` (build/3 + request/3), and the error-normalizer at `lib/cartouche/http.ex` (formerly `util.ex` before the `Cartouche.HTTP` extraction). Two minors of HTTP/2 and pool improvements — audited; no API additions worth adopting.


### 7.4 Lockfile refresh

`ex_sha3`, `goth`: constraints already permit newer versions; `mix deps.update` and verify. `junit_formatter` and `bandit` need a small pin/lockfile dance — commit `860ac52` ("Tighten dep pins to match refreshed lockfile") rewrote `~> 3.3` to `~> 3.3.1`, which now blocks 3.4.0; `bandit` was never in roadmap. Tracked as Tasks 71 + 72 below. Bundle the lot into a single dep PR.


---

## Phase 8: `Cartouche.Transaction.V2.encode/1` duplication

**Why:** `mix ex_dna` surfaces one Type I (exact) clone in `lib/cartouche/transaction.ex`: both `encode/1` clauses of `Cartouche.Transaction.V2` (unsigned at line 394, signed at line 423) share 10 lines of identical struct destructuring and the same `<<0x02>> <> ExRLP.encode([...])` prefix. The signed clause differs only by appending the normalized `signature_y_parity` / `signature_r` / `signature_s` triple and applying `Enum.map/2` to the access list.

Natural extraction: a private helper returning the prefix list from the struct. Each clause either encodes that list as-is (unsigned) or concatenates the signature triple before encoding (signed).

<!-- TASKS:BEGIN phase=8 -->
> 2 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-8-cartouche-transaction-v2-encode-1-duplication).
<!-- TASKS:END -->

**Do not run `mix ex_dna --literal-mode abstract` for refactor targets.** It finds near-misses that are often intentional (EIP version pairs, opcode groupings). Type I / exact duplication only.

---

## Phase 9: New transaction types + raw decode

**Why:** The three features that genuinely require cartouche internals. Under fork ownership these ship when ready — no review-cadence gating.

<!-- TASKS:BEGIN phase=9 -->
> 4 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-9-new-transaction-types-raw-decode).
<!-- TASKS:END -->

---

## Phase 10: Upstream PR candidates (to `hayesgm/signet`)

**On-demand only.** We ship fixes in cartouche first. A task from a prior phase becomes an upstream-PR candidate once it's proven in cartouche and the PR would be clean, single-concern, and helpful to existing signet users.

### PR style (observed in signet's `git log`)

Narrow, single-concern, lowercase conventional-commit subject (`fix:`, `chore:`, `feat:`). One module, one behaviour per PR. Match the shape. Recent merged examples on signet: #119, #121, #126.

### Candidates

| Source | Nature | Upstream value |
|--------|--------|----------------|
| Phase 1.1 — `RecoveryBit` `:no_return` typo (landed here 2026-04-25 under Task 38) | `fix:` | Pure win; no runtime effect; one line. Port the spec fix only — `Cartouche.Util.RecoveryBit` still exists upstream |
| Phase 1.2 — `to_wei/1` narrow return | `chore:` | Pure win; one line |
| Phase 1.3 — `Signer.sign_direct/4` `mfa()` | `fix:` | Real type mismatch; one line + doctest |
| Phase 1.4 — `Cartouche.Hex` return specs | `fix:` | Four specs + doctests; evidence grounded in dialyzer output |
| Phase 2 — RPC error-shape widening | `fix:` | Evidence grounded; multiple shapes documented |
| Phase 3 — Trace/TraceCall deserialize specs | `fix:` | Evidence grounded |
| Phase 4 — Typed internal-function specs | `fix:` | Judgment call per Task 20 — pitch once we've decided direction |
| Phase 7.1 — `google_api_cloud_kms` constraint bump | `chore:` | Pitch only if it surfaces a concretely useful newer feature; otherwise maintainers refresh constraints on their own cycle |
| Phase 8 — V2 encode dedup | `refactor:` | Judgment call. Maintainer may prefer parallel clauses for EIP-1559 auditability. Disarming tone in PR body; happy-to-close framing |

### Not candidates

- Phase 0 (release mechanics — cartouche-specific)
- Phase 5 (cascade work — closed; resolved by INE-21 coverage push, no suppression needed)
- Phase 6 (VM-internal — low signet value)
- Phase 9 (new tx types — ship in cartouche first; reconsider upstream once production-tested, if signet is still active)

### Upstream PR checklist

Before opening any PR to `hayesgm/signet`:

1. Fix has landed in cartouche and survived at least one `0.1.x` release.
2. Port the fix to a branch off signet's `main` (separate working copy — our `development` branch has cartouche-specific tooling like `dialyxir`, `sobelow`, etc., that signet lacks).
3. Verify `mix format --check-formatted` + `mix test` pass on signet's vanilla setup.
4. PR body cites the cartouche commit / release where the fix has been running.
5. Include doctest evidence for any spec change.
6. No bundling. One concern per PR.

### External package — `ABI.decode/2` spec in `poanetwork/ex_abi`

<!-- TASKS:BEGIN phase=10 -->
| Task | Status | Notes |
|------|--------|-------|
| Task 34 | ⛔ | 🎁 **phase10_upstream** · ABI.decode/2 specced no_return() in poanetwork/ex_abi [D:3/B:5/U:5 → Eff:1.67?] 🚀 |
<!-- TASKS:END -->

---

## Phase 11: hieroglyph 1.0.0 → 1.4.0 adoption advisory

**Status:** ✅ complete — Phase 11 audits closed against hieroglyph 1.4.x.

**Context.** `hieroglyph` shipped four minor releases between 2026-04-24 and 2026-05-01: 1.0.0, 1.1.0, 1.2.0, 1.3.0, 1.4.0. The `{:hieroglyph, "~> 1.0"}` pin in `mix.exs` already accepts 1.4.0 — next `mix deps.update hieroglyph` pulls it. Full release notes in `../hieroglyph/CHANGELOG.md`; sibling roadmap at `../hieroglyph/ROADMAP.md` (now in maintenance posture). One change is BREAKING-on-opt-in-path; several silent bug fixes affect cartouche's existing decoded data; three new APIs are worth optional adoption.

### Tasks

<!-- TASKS:BEGIN phase=11 -->
> 3 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-11-hieroglyph-1-0-0-1-4-0-adoption-advisory).
<!-- TASKS:END -->

### Audit 1 — `decode_structs: true` and atom existence

Hieroglyph 1.4.0 hardened the `decode_structs: true` path: field-name atoms must already exist in the VM atom table (`String.to_existing_atom/1` instead of `String.to_atom/1`). Decoder raises `ArgumentError` with a migration hint otherwise. Closes a DoS surface (atom-table exhaustion via attacker-controlled ABI field names); behavior change on the opt-in path. Two cartouche call sites:

- `lib/mix/cartouche.gen.ex:607-610` — 🔧 fixed. The generator's `*_selector/0` template returns `Macro.escape(selector)` metadata whose return-field names remain strings (`%{name: "blockNumber"}` / `%{name: "cool"}`), not compile-time atom literals. Generated `exec_vm_*` wrappers now call a private `preintern_return_atoms!/1` helper before `ABI.decode(..., decode_structs: true)`, recursively covering tuple and array return types. Regenerated test-support bindings prove the emitted shape.
- `lib/cartouche/sleuth.ex:91-128` — 🔧 fixed. `query_v2/4` accepts runtime selectors and defaults `decode_structs: true`, so callers can supply selectors whose field atoms are not yet interned. `try_decode/3` now pre-interns the bounded selector return-field atoms before decode. Regression coverage uses `Code.loaded?/1` and a dynamically unique field name to prove raw Hieroglyph decode raises while the Cartouche boundary succeeds.

### Audit 2 — silent bug-fix windfall (1.0.0–1.2.0)

Cartouche flows may have been miscompiling/decoding without symptoms. Re-test:

- **Indexed reference-type event params** (1.0.0) — `lib/cartouche/filter.ex:114` calls `ABI.Event.decode_event/4`. Events with indexed `string` / `bytes` / `T[]` (fixed or dynamic) / tuple params previously returned wrong bytes; now return `{:indexed_hash, <<32 bytes>>}` per the Solidity spec rule for "all complex types."
- **`:string` decode NUL truncation** (1.2.0) — pre-existing in upstream since 2018. Any decoded string in cartouche flows that contained a NUL codepoint (`U+0000`) was silently truncated at the first NUL. Fix removes the helper entirely.
- **`encode_int/2` overflow guard** (1.1.0) — `int8`/`int16`/etc. were rejecting all valid values (including `0` for `int8`). If cartouche or any consumer was avoiding small int types because of this, that workaround can be dropped.
- **`dynamic?/1` crash on `T[0]`** (1.1.0) — zero-length fixed arrays no longer crash the layout query.

### Optional adoption — new hieroglyph public APIs

- `ABI.method_id/1` (1.1.0) — 🔧 adopted in `lib/mix/cartouche.gen.ex` for duplicate-function selector suffixes and generated selector pattern bytes. The generator still computes the full 32-byte keccak separately where event topic matching needs the complete signature hash.
- `ABI.decode_error/2` (1.2.0) — 🔧 adopted in `lib/cartouche/rpc.ex` for selector-prefixed revert payload decoding. Cartouche maps the decoded short error name back to the matching full ABI signature so existing RPC error maps stay unchanged.
- `ABI.encode_packed/2` (1.2.0) — ⚠️ no adoption opportunity found after searching `lib/**` for packed encoding and keccak patterns.
- `function` type encode/decode (1.3.0) — 24-byte external function pointer. Niche; only relevant if cartouche-generated bindings ever surface a `function` typed param.

**Acceptance:** the two `decode_structs` paths audited (with rationale recorded if no change made), bug-fix audit run for any production data that may have been silently miscompiled or truncated, optional new-API adoption taken or formally declined. Score is for the audit itself; if work is needed beyond verification, split into follow-up tasks here.

**Docs:** ROADMAP (this section's status); CHANGELOG `[Unreleased]` if any code change lands. No README/CLAUDE.md changes expected (cartouche public surface unchanged).

---

## Phase 12: Agent-economy descripex adoption

**Why:** Cartouche's API surface is well-documented for humans (most public functions have `@doc` + `@spec`) but invisible to AI agents — there is no machine-readable manifest, no MCP tool list, no progressive `describe()` discovery. Per the project's `agent-economy.md` include, libraries with ≥3 public modules should expose self-describing metadata via `descripex`. Cartouche has ~28 public modules (every `lib/cartouche/**.ex` not marked `@moduledoc false` and not under `lib/cartouche/contract/`); the cost is bounded (annotations are additive metadata) and the unlock is real: future MCP servers, agent frameworks, and EIP-8004 validators can introspect cartouche without scraping `@doc` strings.

`descripex 0.6.0` already resolves transitively via `hieroglyph 1.4`. Task 82 promotes it to a direct dep so consumer `mix.exs` files don't need to add it, stands up the `Cartouche` discoverable wrapper, and adds the validation test that polices annotated modules. Tasks 83-88 each pair a primary entry point with its natural co-domain helpers (e.g. RPC + the response decoders it returns; Solana Signer/Transaction + the instruction/PDA/ATA helpers they compose) — six `[P]`-eligible bundles spanning every public module in cartouche. Task 89 wires the static manifest export (`mix descripex.manifest`) and documents the discovery API in README. The phase ships as a complete annotation pass — no deferred tier; partial coverage would make `Cartouche.describe()` misleading.

**Coverage-gate exemption:** `api()` is metadata-only — it generates `@doc` (slot 4) + `@doc hints:` (slot 5) at compile time and adds `__api__/0,1` introspection functions. No runtime code path changes. Per `critical-rules.md` § "RAISE COVERAGE BEFORE MUTATING", this falls under the doc-only / metadata exemption. Each task body notes this explicitly so a future session does not get blocked unnecessarily on a tier coverage push that the work doesn't actually need.

**Excluded from scope:** generated modules under `lib/cartouche/contract/` (`Contract.IConsole`, generated `Contract.Sleuth`) are `@moduledoc false`. Annotating their generator template is the natural extension of existing **Task 50** (generator emits `@doc`/`@spec`); descripex annotations on generated bindings would ride along once Tasks 41/42/44/50 land. Not part of this phase.

<!-- TASKS:BEGIN phase=12 -->
> 13 tasks. See [CHANGELOG.md](CHANGELOG.md#phase-12-agent-economy-descripex-adoption).
<!-- TASKS:END -->

**Acceptance (phase-level):** Tasks 82-89 all land. `Cartouche.describe()` returns every public, non-`@moduledoc false` module (~28 total). `mix descripex.manifest --pretty` produces a non-empty `api_manifest.json`. README documents the discovery API. The validation test in Task 82 enforces no public function in any registered module is left unannotated.

**Docs:** ROADMAP (this section's status); CHANGELOG `[Unreleased]` per task; README ## API discovery section in Task 89. CLAUDE.md unchanged (no convention shifts; agent-economy.md include already documents the design pattern).

---

## Completed

_None yet beyond `0.0.1` placeholder (see [CHANGELOG.md](CHANGELOG.md))._

---

## Audit provenance

Findings that drive Phases 1–8:

- `mix dialyzer.json --quiet --output /tmp/cartouche-dialyzer.json` (2026-04-21, pre-rename) — 11 `invalid_contract` warnings drove Phases 1.3, 1.4, 3, 4, 5, 6.
- `mix hex.outdated` (2026-04-21) — drove Phase 7.
- `mix ex_dna` (2026-04-21) — one Type I clone drove Phase 8 (41 files analyzed, 1 clone, ~28 duplicated lines).
- `mix reach.hotspots` + `mix reach.coupling` + `mix reach.impact` (2026-04-21, reach 1.6.0) — confirmed Phase 2 blast radius (32 callers, 6 direct breakage points, MEDIUM risk); downgraded Phase 5 after discovering `VM.exec/3` and `Erc20.transfer/4` have 0 internal callers; identified pervasive `Cartouche.VM` submodule cycles likely feeding the cascade.
- Manual audit of `lib/cartouche/rpc.ex` + `lib/cartouche/util.ex` + `lib/cartouche/signer/cloud_kms.ex` — drove Phases 1.1, 1.2, 2, 7.1.

Before starting Phase 1 work, re-run `mix dialyzer.json --quiet --group-by-file` on the current `development` branch to catch any regressions introduced during the signet → cartouche rename.

---

## Consumer re-probe (onchain)

Once cartouche `0.1.0` is on hex and onchain flips `mix.exs` from `signet` to `cartouche`:

```bash
cd ../onchain
mix deps.update cartouche
mix dialyzer.json --quiet
# strip @dialyzer {:no_match, …} blocks from Onchain.Hex / ABI / Contract / ERC / ENS / Multicall
# as each of Phase 1.4 / Phase 2 fixes lands in a cartouche release
```

See `onchain/ROADMAP.md` for the full strip checklist.
