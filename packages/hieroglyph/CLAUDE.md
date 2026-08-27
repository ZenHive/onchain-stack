@~/.claude/includes/critical-rules.md
@~/.claude/includes/harness-workflow.md
@~/.claude/includes/onchain-workspace.md

<!--
  Selective-load (Opus 4.8): eager floor is `critical-rules`; `harness-workflow` is eager
  because internal roadmap work here is harness-driven (OTP dispatch→review→land loop).
  `onchain-workspace` is the harness workspace add-on (7-repo roster + dependency shape),
  eager family-wide. `upstream-pr-workflow` was demoted to skill-on-demand
  (workflow:upstream-pr-workflow) once upstream contribution was closed out — see
  "Upstream Divergence"; re-import only if we resume filing PRs to `exthereum/abi`.
  Everything else is skill-on-demand — task-prioritization → tasks:roadmap-planning,
  task-writing → tasks:task-writing, workflow-philosophy → workflow:workflow-philosophy,
  worktree-workflow → workflow:git-worktrees, web-command/ex-unit-json/dialyzer-json/code-style/
  development-commands/development-philosophy/elixir-setup/agent-economy → elixir:*.
  Delegation + across-instances intentionally omitted (work/library repo, no cloud-agent usage).
  Re-add an `@`-import only if Opus quality drops on that surface.
-->


# ABI

Pure Elixir library for encoding/decoding the Solidity ABI. No runtime processes — `ABI.encode/2`, `ABI.decode/2`, and the `TypeEncoder`/`TypeDecoder`/`FunctionSelector`/`Event` modules under `lib/abi/` are all stateless functions.

## Stack boundary — hieroglyph / cartouche / onchain

**Cut on what defines the bytes, not on who calls the node.** Canonical statement lives in
`cartouche/ROADMAP.md` § "Scope principle"; this is the binding summary.

| Layer | Owns |
|---|---|
| **hieroglyph** | The ABI codec. Pure functions over types and bytes. No I/O, no chain identity, no node. |
| **cartouche** | Everything defined by the **node's wire format**: the JSON-RPC transport, and one wrapper **plus one decoded struct** for every method in a **tagged release** of the `execution-apis` OpenRPC spec — plus transaction envelopes, signing, crypto, hex, and chain ids. |
| **onchain** (and `onchain_*` siblings) | Everything defined by a **contract, a standard, or an off-node protocol**: ERC-*, ENS, AA, MEV, DEX, Multicall, subscriptions, vendor/bundler/relay namespaces. It **re-presents** cartouche's structs; it never re-derives them. |

Routing, in one read:

- **New `eth_*` / `net_*` wrapper** → cartouche, iff the method is in a **tagged** OpenRPC
  release. Not in the spec → cartouche only with a `@doc` naming who serves it *and* a
  capability probe. Vendor/bundler/relay namespace (`eth_sendUserOperation`,
  `eth_sendBundle`, `eth_sendPrivateTransaction`) → onchain.
- **Response decoding** → cartouche, always, into a cartouche struct. onchain never
  re-derives a JSON shape the node emits.
- **ERC standard** → onchain, or a sibling when domain-heavy (`onchain_aave`).
- **Chain constants** → cartouche (`Cartouche.Chain`). A chain with a different tx envelope
  gets its own package (`onchain_tempo`).
- **Non-EVM chain** → its own package. Not cartouche, not onchain.

**Why the previous rule was reversed (2026-08-27).** The old rule sent "RPC method
wrappers" to onchain while leaving the transport and the response structs in cartouche.
That is not a separable cut — `send_rpc/3` takes a `:decode` function, so a wrapper is
*method string + param normalizer + pointer to a cartouche struct*, two of three parts
already cartouche's. onchain could not own the decode without owning the struct, so it
wrote its own. Measured cost: two mutually-incompatible `Block` representations
(`Cartouche.Block` → struct with raw binaries; `Onchain.RPC.Helpers.parse_block_response/1`
→ plain map with `0x` strings), ~500 LOC of duplicate decoders, twelve methods wrapped at
both layers, a `@dialyzer {:no_match, do_rpc: 3}` suppression as the receipt, and
`Onchain.HTTP` (34 LOC) existing only to escape cartouche's config key. No test can catch
that class, because no module consumes both. **The old rule did not prevent the
duplication — it caused it.**

**Migrate lazily, never as a campaign.** When a task ports a method down into cartouche,
the same task converts onchain's copy into a facade. Do not open a migration project.

## Toolchain & check commands (read before judging a build)

Canonical gate: **`mix ci`** (= `precommit.full`) — `precommit` (format `--check-formatted` + compile `--warnings-as-errors` + `credo --strict` + `doctor --raise` + a **95%** coverage gate via `test.json --cover --cover-threshold 95 --exclude integration` + `sobelow --skip`), then `ex_dna --max-clones 0`, `reach.check --arch --smells`, `deps.audit.gated`, `dialyzer.json --quiet`, `agents.check`, `hieroglyph.manifest --check`. A clean `mix ci` is the merge bar. (`mix precommit` = the base steps only, no dialyzer/ex_dna/reach/audit. `mix check.fast` = format + compile + credo only.) Coverage is 95%, not 85% — this is a wire-format/crypto encoder (critical business logic). The commit hook does **not** run `precommit`; per-edit hooks grade touched files.

**Releases are manual: `mix hex.publish`, then `git tag v<version> && git push origin v<version>` (the tag is cut *after* a successful publish).** Before publishing, check by hand that `CHANGELOG.md` has no entries left under `[Unreleased]`, that its newest `# X.Y.Z` section matches the `mix.exs` version, that the tree is clean and `HEAD` is pushed, and that `v<version>` does not already exist. There is no hosted CI in this repo — `a3a1d14` removed the GitHub Actions workflows, and two `mix ci` steps (`deps.audit.gated`, `agents.check`) shell out to scripts outside the repo, so the canonical gate only runs on a developer host.

**Nothing runs `mix ci` automatically — this repo has no CI.** The GitHub Actions
workflows were deleted in `a3a1d14`; `.github/` now holds only `dependabot.yml`, and
the `.circleci/config.yml` in the tree is inherited from the `exthereum/abi` fork
parent (last touched upstream in 2018, `working_directory: ~/abi`, installs
libsecp256k1 build deps this fork does not use) — treat it as an unconnected
artifact, not a gate. `mix ci` is therefore enforced by whoever runs it: the
developer host and the harness reviewer agent in its run worktree. Two of its steps
cannot run anywhere else at all — `deps.audit.gated` shells out to
`bin/advisory-freshness.sh` in the sibling `onchain-stack` checkout, and
`agents.check` shells out to `~/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh`
— so both are developer-host-only by construction. A reviewer that cannot reach those
paths is running a strictly smaller gate than the one described above and should say
so rather than report a clean `mix ci`.

**The `.json` mix tasks emit JSON BY DESIGN — that is expected output, never an error or a broken setup:**

- **`mix test.json`** (from the `ex_unit_json` dep) — ExUnit results as a JSON document for machine parsing; identical run to `mix test`. Parse it for failures; the JSON envelope itself is never a failure signal. `--cover` can emit a large per-module coverage blob — pipe to a file (`--output /tmp/cov.json`) and `jq` the summary, don't dump it to the transcript.
- **`mix dialyzer.json`** (from the `dialyzer_json` dep) — dialyzer warnings as JSON. Read the JSON array for *real* warnings; do NOT flag the JSON output as a problem. If the encoder cannot serialize a warning shape, plain `mix dialyzer` (MIX_ENV=dev) is the authoritative dialyzer check. Zero real warnings = pass.

The other gate tools are plain-text: `mix credo --strict`, `mix doctor --raise`, `mix sobelow --skip` (the `--skip` honors `.sobelow-skips`; inline `# sobelow_skip` comments are NOT honored by the commit hook — see § Sobelow in `~/.claude/CLAUDE.md`).

- **`mix reach.check --arch --smells` gates from `.reach.exs`** (`smells: [strict: true]`).
  Smell findings must be fixed, never added to an ignore list. `deps/reach` here carries a
  deliberate local 3-line patch (filed upstream as elixir-vibe/reach#36) without which
  `--smells` crashes on this repo's yecc/leex-generated Erlang — never touch `deps/`.
- **`deps.audit.gated`** runs `bin/advisory-freshness.sh` (in `onchain-stack`) before
  `mix deps.audit` — `mix_audit` discards its own sync exit status, so a frozen advisory DB
  would otherwise still report green. This repo carries no `.mix_audit_ignore` (audit is clean).

**`mix hieroglyph.mutants` is NOT part of `mix ci`** — it mutates `lib/` in place and spawns a full `mix test` per mutant, which does not belong in a per-commit gate. Run `MIX_ENV=test mix hieroglyph.mutants` when the encoder, decoder, selector or event paths change, and update the mutant table in `docs/abi-verification-ledger.md`. It runs a control pass over the vector files on unmutated `lib/` first (without it a already-failing vector suite makes every mutant read as killed), reverts every file byte-exactly, and exits non-zero on a surprise (a mutant that should die and didn't, a survivor that unexpectedly died, an anchor that no longer matches its site exactly once, or a file that did not come back byte-exact). The `after` clause covers exceptions but not signals, so the original bytes also go to a `.hieroglyph-mutants.orig` sidecar; a leftover sidecar means an interrupted run and the task refuses to start until it is cleared (`git checkout -- lib/ && rm lib/**/*.hieroglyph-mutants.orig`).

(Claude-family agents with the user's global skills can invoke `elixir:ex-unit-json` and `elixir:dialyzer-json` for the full flag/jq reference. For every other agent — the cross-family harness reviewers — the notes above are self-contained.)

## Layout

- `lib/abi.ex` — public surface (`encode/2`, `decode/3`, `decode_call/3`, `decode_event/4`, `method_id/1`, `event_signature/1`, `parse_specification/1`). Also the `Descripex.Discoverable` module — wires `ABI.describe/0..2` and `ABI.__descripex_modules__/0` for agent-side introspection.
- `lib/abi/type_encoder.ex` / `type_decoder.ex` — head/tail packing for static and dynamic Solidity types
- `lib/abi/function_selector.ex` — parses `"foo(uint256,address)"` strings; uses generated yecc/leex parsers in `src/`
- `lib/abi/event.ex` — log decoding (indexed vs non-indexed args, topic hashing)
- `lib/abi/parser.ex` — `@moduledoc false` walker; wraps `:ethereum_abi_parser.parse/1`, normalizes the AST, and rejects unsupported types (`fixed`/`ufixed`) at parse time (`:function` rejection lifted in 1.3.0 — it now encodes/decodes as a 24-byte payload)
- `lib/abi/math.ex` — shared 32-byte padding helpers (`pad/4`, `unpad/3`) plus `mod/2` and `kec/1` (keccak256). Encoder/decoder delegate here instead of duplicating the byte-domain padding formula.
- `src/*.xrl` / `src/*.yrl` — leex/yecc grammar; compiled by the `:yecc, :leex` Mix compilers (see `mix.exs:18`). Edit the `.xrl`/`.yrl`, never the generated `.erl`.
- `lib/mix/tasks/hieroglyph.manifest.ex` — `mix hieroglyph.manifest [path]` task that emits `api_manifest.json` from `ABI.__descripex_modules__/0`; `--check` regenerates in memory and fails on drift (ignoring `generated_at`). Consumed by downstream cartouche/onchain CI as a contract-stability artifact; the check is a `mix ci` step.
- `test/support/fixtures/ethers/` — vendored `@ethersproject/testcases` 5.8.0 vectors (MIT), recorded from `solc` output. The **independent oracle**: `test/abi/ethers_corpus_test.exs` asserts against them byte-for-byte with no `decode(encode(x))` step. Provenance + filter criteria in `PROVENANCE.md`; re-vendor with `vendor.py`.
- `test/abi/abi_spec_test.exs` — spec-anchored assertions, each citing its ABI-spec section: the head/tail offset VALUE (which the decoder never reads back), the length word, and padding direction.
- `test/support/mutants/` + `test/support/mix/tasks/hieroglyph.mutants.ex` — the planted-mutant corpus and its runner. Deliberately under `test/support/` (not `lib/`) so the runner stays out of the 95% coverage gate.
- `docs/abi-verification-ledger.md` — authorities with fetch dates, the mutant table, and the survivor review. Read it before touching the encoder, decoder, selector or event paths.

## Gotchas

- `parse_specification/2` accepts `:string_keys` to keep ABI JSON keys as strings rather than atoms — preserve this when touching selector parsing.
- `TypeEncoder` recently grew integer- and string-key support (commits `a43e9d5`, `46accc8`); when adding new type paths, mirror both keyed-map and tuple input shapes.
- This library is consumed downstream by transaction builders. Breaking the public encode/decode shape is a major-version event — bump `version` in `mix.exs` accordingly.

## Open Work

See [ROADMAP.md](ROADMAP.md) for the current punch list (bugs, test debt, feature gaps).

## Package Identity

Published on hex.pm as [`hieroglyph`](https://hex.pm/packages/hieroglyph) (fork-of `exthereum/abi`); repo lives at `github.com/ZenHive/hieroglyph`. The module namespace is unchanged — consumers still call `ABI.encode/2`, `ABI.decode/2`, etc. Only the hex dep name differs (`{:hieroglyph, "~> 1.0"}`). Name chosen to mirror the `signet → cartouche` Egyptian-naming pattern (a cartouche literally contains hieroglyphs); the `ABI` module name was kept deliberately because Solidity's own term is the correct one — renaming it would hurt callsite discoverability. See CHANGELOG entry for 1.0.0 (2026-04-24) for the version-reset rationale.

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
