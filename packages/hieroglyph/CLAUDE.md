@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md
@~/.claude/includes/onchain-workspace.md

<!--
  Selective-load (Opus 4.8): eager floor is `critical-rules`; `harness-workflow` is eager
  because internal roadmap work here is harness-driven (OTP dispatch→review→land loop).
  `onchain-workspace` is the harness workspace add-on (monorepo layout + sibling/3 +
  dependency shape), eager family-wide. `upstream-pr-workflow` was demoted to skill-on-demand
  (workflow:upstream-pr-workflow) once upstream contribution was closed out — see
  "Upstream Divergence"; re-import only if we resume filing PRs to `exthereum/abi`.
  Everything else is skill-on-demand — task-prioritization → tasks:roadmap-planning,
  task-writing → tasks:task-writing, workflow-philosophy → workflow:workflow-philosophy,
  worktree-workflow → workflow:git-worktrees, web-command/ex-unit-json/dialyzer-json/code-style/
  development-commands/development-philosophy/elixir-setup/agent-economy → elixir:*.
  Delegation + across-instances intentionally omitted (work/library package, no cloud-agent usage).
  Re-add an `@`-import only if Opus quality drops on that surface.
-->

# hieroglyph

Pure Elixir library for encoding/decoding the Solidity ABI. No runtime processes — `ABI.encode/2`, `ABI.decode/2`, and the `TypeEncoder`/`TypeDecoder`/`FunctionSelector`/`Event` modules under `lib/abi/` are all stateless functions.

Root of the family's dependency cascade (below `descripex`). See the root
`CLAUDE.md` for the stack-boundary routing rule between hieroglyph / cartouche
/ onchain, the sibling/3 mechanism, and the shared gate adjudications
(reach #36, cowlib/gun, sobelow) — this file carries only what's specific to
this package.

## Toolchain & check commands (read before judging a build)

Canonical gate: **`mix ci`** (= `precommit.full`), same shape as every other
package in the monorepo (see root `CLAUDE.md` § Gates) with one difference
worth calling out: **coverage is a 95% floor, not the family's usual
70–85%**, folded directly into the `precommit` alias (not a separate step) —
this is a wire-format/crypto encoder, critical business logic, and the
tighter bar is deliberate. `mix precommit` = format + compile
`--warnings-as-errors` + `credo --strict` + `doctor --raise` + the 95%
coverage gate (`test.json --cover --cover-threshold 95 --exclude integration`)
+ `sobelow --skip`. `mix ci` adds `ex_dna --max-clones 0`, `reach.check --arch
--smells`, `deps.audit.gated`, `dialyzer.json --quiet`, `agents.check`, and
**`hieroglyph.manifest --check`** (below). `mix check.fast` = format + compile
+ credo only, for a quick loop.

- **`mix hieroglyph.manifest [path]`** (`lib/mix/tasks/hieroglyph.manifest.ex`)
  emits `api_manifest.json` from `ABI.__descripex_modules__/0`; `--check`
  regenerates in memory and fails on drift (ignoring `generated_at`).
  Downstream cartouche/onchain treat this as a contract-stability artifact —
  it is a `mix ci` step here specifically because this package is the one
  that would silently break that contract.
- **`mix hieroglyph.mutants` is NOT part of `mix ci`** — it mutates `lib/` in
  place and spawns a full `mix test` per mutant. Run
  `MIX_ENV=test mix hieroglyph.mutants` when the encoder, decoder, selector or
  event paths change, and update the mutant table in
  `docs/abi-verification-ledger.md`. It runs a control pass over the vector
  files on unmutated `lib/` first (otherwise an already-failing vector suite
  makes every mutant read as killed), reverts every file byte-exactly, and
  exits non-zero on a surprise (a mutant that should die and didn't, a
  survivor that unexpectedly died, an anchor that no longer matches its site
  exactly once, or a file that didn't come back byte-exact). The `after`
  clause covers exceptions but not signals, so the original bytes also go to
  a `.hieroglyph-mutants.orig` sidecar; a leftover sidecar means an
  interrupted run and the task refuses to start until cleared
  (`git checkout -- lib/ && rm lib/**/*.hieroglyph-mutants.orig`).
- **`reach.check --arch --smells` needs `.reach.exs` scoped to
  `source_paths: ["lib", "test/support"]`** — this package is one of the two
  reach #36 workarounds (root `CLAUDE.md` § Adjudicated findings): without
  the scope, reach's smell pass crashes on the yecc/leex-generated Erlang
  under `src/`, which is unfixable-by-definition anyway.
- **`.sobelow-skips` here has only 2 lines and suppresses nothing** (this
  package sits at zero sobelow findings even without `--skip`) — it's
  vestigial; deleting it is the cheaper fix if you're ever touching it,
  per root `CLAUDE.md`'s open item on the drift-check replacement.
- This package's dep tree audits clean — no `.mix_audit_ignore` needed here
  (hieroglyph doesn't pull `gun`).

(Claude-family agents with the user's global skills can invoke
`elixir:ex-unit-json` and `elixir:dialyzer-json` for the full flag/jq
reference. For every other agent — the cross-family harness reviewers — the
notes above are self-contained.)

## Layout

- `lib/abi.ex` — public surface (`encode/2`, `decode/3`, `decode_call/3`, `decode_event/4`, `method_id/1`, `event_signature/1`, `parse_specification/1`). Also the `Descripex.Discoverable` module — wires `ABI.describe/0..2` and `ABI.__descripex_modules__/0` for agent-side introspection.
- `lib/abi/type_encoder.ex` / `type_decoder.ex` — head/tail packing for static and dynamic Solidity types
- `lib/abi/function_selector.ex` — parses `"foo(uint256,address)"` strings; uses generated yecc/leex parsers in `src/`
- `lib/abi/event.ex` — log decoding (indexed vs non-indexed args, topic hashing)
- `lib/abi/parser.ex` — `@moduledoc false` walker; wraps `:ethereum_abi_parser.parse/1`, normalizes the AST, and rejects unsupported types (`fixed`/`ufixed`) at parse time (`:function` rejection lifted in 1.3.0 — it now encodes/decodes as a 24-byte payload)
- `lib/abi/math.ex` — shared 32-byte padding helpers (`pad/4`, `unpad/3`) plus `mod/2` and `kec/1` (keccak256). Encoder/decoder delegate here instead of duplicating the byte-domain padding formula.
- `src/*.xrl` / `src/*.yrl` — leex/yecc grammar; compiled by the `:yecc, :leex` Mix compilers (see `mix.exs:18`). Edit the `.xrl`/`.yrl`, never the generated `.erl`.
- `lib/mix/tasks/hieroglyph.manifest.ex` — see above.
- `test/support/fixtures/ethers/` — vendored `@ethersproject/testcases` 5.8.0 vectors (MIT), recorded from `solc` output. The **independent oracle**: `test/abi/ethers_corpus_test.exs` asserts against them byte-for-byte with no `decode(encode(x))` step. Provenance + filter criteria in `PROVENANCE.md`; re-vendor with `vendor.py`.
- `test/abi/abi_spec_test.exs` — spec-anchored assertions, each citing its ABI-spec section: the head/tail offset VALUE (which the decoder never reads back), the length word, and padding direction.
- `test/support/mutants/` + `test/support/mix/tasks/hieroglyph.mutants.ex` — the planted-mutant corpus and its runner. Deliberately under `test/support/` (not `lib/`) so the runner stays out of the 95% coverage gate.
- `docs/abi-verification-ledger.md` — authorities with fetch dates, the mutant table, and the survivor review. Read it before touching the encoder, decoder, selector or event paths.

## Gotchas

- `parse_specification/2` accepts `:string_keys` to keep ABI JSON keys as strings rather than atoms — preserve this when touching selector parsing.
- `TypeEncoder` recently grew integer- and string-key support (commits `a43e9d5`, `46accc8`); when adding new type paths, mirror both keyed-map and tuple input shapes.
- This library is consumed downstream by transaction builders. Breaking the public encode/decode shape is a major-version event — bump `version` in `mix.exs` accordingly.

## Open Work

See [ROADMAP.md](../../ROADMAP.md) (root, task IDs offset +1000 for this package) for the current punch list (bugs, test debt, feature gaps).

## Package Identity

Published on hex.pm as [`hieroglyph`](https://hex.pm/packages/hieroglyph) (fork-of `exthereum/abi`); repo history lives at `github.com/ZenHive/hieroglyph` (archived — the live checkout is `packages/hieroglyph/` in this monorepo). The module namespace is unchanged — consumers still call `ABI.encode/2`, `ABI.decode/2`, etc. Only the hex dep name differs (`{:hieroglyph, "~> 1.0"}`). Name chosen to mirror the `signet → cartouche` Egyptian-naming pattern (a cartouche literally contains hieroglyphs); the `ABI` module name was kept deliberately because Solidity's own term is the correct one — renaming it would hurt callsite discoverability. See CHANGELOG entry for 1.0.0 (2026-04-24) for the version-reset rationale.

## Upstream Divergence (reference — not a work queue)

**Upstream is dormant; we do not track it.** `exthereum/abi` has had no maintainer activity on our filings — issues #53/#54/#55 and PR #52 sit open with zero comments since 2026-04/05, alongside unanswered third-party issues dating to 2018. Contributing back was attempted and is now closed out: **no further upstream issues or PRs are planned, and there is no session-start status check.** Ship fixes here; if maintainers ever land something, reconcile on their merge — not before.

The list below is a **reference map** of where this fork diverges from upstream and why — useful when reading `ABI.Event`/`ABI.Parser`/`TypeEncoder` and wondering why they don't match `exthereum/abi`. It is not a to-do list.

| Divergence | Fork fix |
|---|---|
| Indexed reference-type event params decoded from raw topic bytes ([#53](https://github.com/exthereum/abi/issues/53)) | `{:indexed_hash, <<32 bytes>>}` for **all** reference types (arrays fixed or dynamic, tuples, `string`, `bytes`) via `reference_type?/1` in `ABI.Event`. Broader than the head/tail "dynamic" rule by design — matches the spec's "all complex types" event-indexing rule. |
| `fixed`/`ufixed`/`function` parse but don't encode; `@type type` gaps ([#54](https://github.com/exthereum/abi/issues/54)) | 1.0.0: parse-time rejection in `ABI.Parser` + `{:bytes, N}` added to `@type type`. 1.3.0: `function` rejection lifted — full encode/decode/packed (24-byte external pointer = 20-byte address ++ 4-byte selector). `fixed`/`ufixed` stay rejected; Solidity itself doesn't fully support them (README "Why `fixed<M>x<N>` … are deferred"). |
| Lexer: single `x` in `fixed<M>x<N>` shadowed by the LETTERS rule (sub-bug of #54, never filed) | 1.2.0: dedicated `fixed_typename`/`ufixed_typename` terminals + `'x'`-rule reorder + `identifier_part` extension. |
| `TypeEncoder.encode_int/2` overflow guard mixed bytes and bits, rejecting every `int8` (incl. `0`) ([#55](https://github.com/exthereum/abi/issues/55)) | 68ab658: numeric range check against `Bitwise.bsl(1, N - 1)` replaces the `byte_size > bytes - 1` guard. Upstream's own `"int overflow raises data overflow"` test passed against the broken encoder for the wrong reason. |
| `:string` decode truncated at the first NUL byte (upstream since `bdceb719`, 2018; never filed) | 1.2.0: `nul_terminate_string/1` deleted — Solidity strings are length-prefixed UTF-8 and may contain NUL codepoints; decode delegates to `decode_bytes(rest, length, :right)`. |
| `decode_structs: true` interned atoms from contract-supplied field names (never filed) | 1.4.0: `ABI.TypeDecoder.tuple_value/3` and `ABI.TypeEncoder.fetch_by_name/2` route through `String.to_existing_atom/1`; decoder requires field atoms pre-interned (raises `ArgumentError` with a migration hint). Rejected `:strict`/`:strings` knobs as API-surface bloat. |

Fork-only additions with no upstream counterpart: `ABI.decode_error/2` (Solidity 0.8.4+ custom errors), `ABI.encode_packed/2` (non-standard packed encoding), the narrowed `decode_event/4` error contract (`{:error, {:malformed_data, _}}` instead of raising), and `encode_bytes/1` demoted to `defp`.
