# Post-merge audit: cbf4b4fe

## Scope and judgment

- Integrated revision: `cbf4b4feaccfbecfaf125aa5aea19a8d289b0907`.
- Audited range: `b7aba76f07f4e29c17a597342e9f7d9f81e5d2ba..cbf4b4feaccfbecfaf125aa5aea19a8d289b0907`.
- Configured command: `mix ci`.
- Original-revision QA: **failed**. All configured steps were attempted and completed; no missing prerequisite remains. This audit does not gate landing or deployment.

Reviewed the landed consolidation, native ABI/transaction/EIP-712 and Tempo changes, shared RPC/log/signer surfaces, codegen, cache synchronization, node introspection and fee-history base-fee decision. Fixed five documentation/generated-instruction hygiene groups. All 3,727 configured package tests and coverage floors passed. Original QA failed on core Reach, two known core Dialyzer warnings and six AGENTS freshness checks; regeneration repaired every freshness failure. No runtime changes or new tasks proposed.

Reviewed the range inventory, prior landed audit evidence and representative code/diffs: namespace-preserving consolidation and Solana extraction; ABI NIF bounds and scheduling, BEAM consensus terms, recursive typed values, transaction adapters; cache locking and regression tests; common RPC transport, refusal classification, log and signer migration; generator/Sleuth integration and orphaned decoder removal; Tempo native mutation scratch isolation; shared Rust gates and alias separation. Inspected the latest node-introspection and base-fee changes in detail, including tests and the committed probe evidence. This is a best-effort hygiene review, not a line-by-line security review of the entire range. No leftover debug call or additional runtime defect was established. Material removals and the base-fee decision already have changelog entries. Roadmap and changelog files were not edited.

## Findings and fixes

Five fixed groups and two retained analyzer groups (seven findings):

1. **Native architecture and operational instructions — fixed.** Root/core instructions still described the removed yecc/leex parser; the package table omitted Tempo's Rust crate, and EVM claimed to be the only native package. Corrected these descriptions, the shared audit-ignore symlink count, and the core endpoint-requirements paragraph. Root gate documentation now describes actual environments: core/EVM/Solana use test; Aave/Aerodrome/JS/Tempo use dev for analyzers with explicit test coverage subprocesses. No aliases or analysis scopes changed.
2. **Core package overview — fixed.** The README family table omitted Aerodrome and Solana, and its opening omitted the core alloy NIF. Added the missing package rows and native-codec description without changing dependency bounds.
3. **Historical consumer guides — fixed.** Marked the relocated Hieroglyph guide as historical and linked current installation/native-build instructions. The already-historical Cartouche guide has a current node-compatibility section; clarified this distinction, removed its obsolete keyless Infura default, and corrected its documented Req option precedence to match `Cartouche.HTTP.req_options/3` (per-transport, global, per-call).
4. **NIF-7 evidence — fixed.** The spec note incorrectly said no test covered the cache cap. It now names `test/abi/alloy_cache_test.exs` and accurately distinguishes separate-key/concurrent-insert coverage from the signature-cache 1,024-entry overflow test. No normative rule or test changed.
5. **Generated instructions — fixed.** Six package freshness checks failed because the imported stack-choice paragraph had drifted. Regenerated root and all package AGENTS files with the installed renderer, including the source-document repairs above. All eight freshness checks now pass. No host include was edited.
6. **Core Reach — retained.** The strict smell pass recommends extracting a behaviour for `Cartouche.SignerTest.Ed25519Backend`, `Cartouche.SignerTest.HighSBackend` and `Cartouche.Test.HighSSignerBackend`. All three already declare `@behaviour Cartouche.Signer.Backend` and `@impl true` for the named callbacks (`test/support/signer_test_backends.ex`). This is the previously recorded behaviour-candidate finding; adding an ignore, removing a test backend or changing callbacks solely to evade it would not repair behavior. No dependency was patched and the failing outcome remains visible.
7. **Core Dialyzer — retained.** The two unsuppressed warnings at `Cartouche.Signer.safe_get_address/2` and `Onchain.AA` reproduce the prior audits. `ExSecp256k1.create_public_key/1` declares `{:ok, binary()} | atom()` while the local backend contract and runtime error handling use tagged errors. Did not delete error branches or suppress warnings. This is the existing upstream-spec mismatch recorded in `.audit/6492c934.md`, not a newly discovered defect.

Tempo's dev Dialyzer reports one unnecessary skip for the existing ExRLP test-support ignore. It is documented for the test environment, so a dev-only run is not evidence that the test-support ignore can be deleted. EVM's seven and core's three existing Dialyzer suppressions remain visible in the output; no new suppressions were added.

## Reviewer feedback

The two rejected task-9031 attempts truthfully followed their then-current benchmark stop condition. Later landed work uses compiled schema resources/batched decoding and the operator changed performance to reporting-only. Sound later work does not make those earlier stop-rule rejections false. No false rejection is established.

## Original-revision QA

Every configured check below finished before tracked edits. The first cold root `mix ci` exited 1: test dependencies `styler`, `ex_slop`, `sobelow`, `doctor` and `credo` were unavailable (`Can't continue due to errors on dependencies`). Ran `mix deps.get` at root and in all seven packages; dependency resolution completed without a tracked lock change. Retried `mix ci`: eight sibling bounds and 16 root alias tests passed; core compile, formatting, Credo, all three Doctor policies and clone detection passed, then Reach failed with one behaviour candidate (root exit 1).

Read each alias using the repository's `test/alias_graph.exs`. Executed all 86 remaining expanded steps independently and serially, continuing after failures. The directory/environment and actual command for every continuation are recorded below. Function captures were invoked through the unchanged shared helper using `Mix.start()` and `Code.require_file`; they were not substituted with weaker checks. This covers all 94 package steps including the first eight executed by root `mix ci`.

### Tests, coverage and native checks

| Package | Passed | Failed | Coverage / floor |
|---|---:|---:|---|
| onchain | 2353 | 0 | ABI 95.71 / 95; Cartouche 92.69 / 85; Onchain 78.85 / 70; signers 98.56 / 95 |
| onchain_aave | 408 | 0 | 100 / 65 |
| onchain_aerodrome | 172 | 0 | 82.25 / 65 |
| onchain_evm | 303 | 0 | 94.20 / 85 |
| onchain_js | 14 | 0 | 35.00 / 25 |
| onchain_solana | 300 | 0 | 98.12 / 95 |
| onchain_tempo | 177 | 0 | 96.69 / 90 |
| **Total** | **3727** | **0** | All configured floors met |

No retries/flaky array or skipped tests were reported by these test summaries. Configured exclusions stayed active (core 253; Aave 85; Aerodrome 2; EVM 37; JS 6; Solana 0; Tempo 9). This does not claim live hosted/archive, bundler, wallet, relay or mutation-campaign verification. The committed base-fee probe evidence was reviewed, not re-measured. No operator server/database was used. All seven coverage subprocesses exited 0 without a VM-halt crash; this is one host run, not resolution of the cross-host investigation in task 9023.

Cargo audits completed for all configured crates. Core Rust: 1 passed; EVM Rust: 28 + 7 passed. Both configured Clippy steps passed. Tempo configures Cargo audit but no Cargo test/Clippy step. No missing-Cargo/clippy skip occurred. Full configured Credo, Doctor, clone, Sobelow and mirror-based dependency checks passed across the packages. Downstream Reach and Dialyzer passed; core failures are detailed below.

Supplemental commands on the original revision:

- `elixir test/consolidated_coverage_test.exs`: 5 passed.
- `bash -n bin/advisory-freshness.sh bin/publish-prep.sh bin/fleet-health.sh packages/onchain/scripts/build-precompiled.sh`: passed.
- Root `/home/harness/_DATA/code/claude-marketplace/scripts/sync-agents-md.sh --check`: passed.
- Root `mix hex.audit`: exit 0 with the host's existing ignored gun/cowlib advisory family explicitly listed. This is distinct from the mirror-based configured audits and is not a claim of no advisories. No host ignore or dependency was changed; no new private security finding was identified.
- `git diff --check b7aba76f..HEAD`: reported whitespace in historical captured analyzer/benchmark output. Those evidence artifacts were preserved; this audit's own diff passes.

### Continuation ledger

`agents_check` exit 1 means stale rendered instructions; all other nonzero results are expanded below. Test commands explicitly selecting `MIX_ENV=test` retain that inner environment even when the outer alias uses dev.

| Directory | Env | Command | Exit |
|---|---|---|---:|
| `packages/onchain` | `test` | `mix sobelow --skip --exit low` | 0 |
| `packages/onchain` | `test` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.advisory_freshness([])"` | 0 |
| `packages/onchain` | `test` | `mix deps.audit --ignore-file .mix_audit_ignore` | 0 |
| `packages/onchain` | `test` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.cargo_audit([])"` | 0 |
| `packages/onchain` | `test` | `mix cmd env MIX_ENV=test mix onchain.coverage` | 0 |
| `packages/onchain` | `test` | `mix hieroglyph.manifest --check` | 0 |
| `packages/onchain` | `test` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.cargo_test([])"` | 0 |
| `packages/onchain` | `test` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.cargo_clippy([])"` | 0 |
| `packages/onchain` | `test` | `mix dialyzer` | 2 |
| `packages/onchain` | `test` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.agents_check([])"` | 1 |
| `packages/onchain_aave` | `dev` | `mix compile --warnings-as-errors` | 0 |
| `packages/onchain_aave` | `dev` | `mix format --check-formatted` | 0 |
| `packages/onchain_aave` | `dev` | `mix credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME` | 0 |
| `packages/onchain_aave` | `dev` | `mix doctor --raise` | 0 |
| `packages/onchain_aave` | `dev` | `mix ex_dna --max-clones 0` | 0 |
| `packages/onchain_aave` | `dev` | `mix reach.check --dead-code --arch --smells` | 0 |
| `packages/onchain_aave` | `dev` | `mix sobelow --skip --exit low` | 0 |
| `packages/onchain_aave` | `dev` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.advisory_freshness([])"` | 0 |
| `packages/onchain_aave` | `dev` | `mix deps.audit --ignore-file .mix_audit_ignore` | 0 |
| `packages/onchain_aave` | `dev` | `mix cmd env MIX_ENV=test mix test.json --cover --cover-threshold 65 --exclude integration` | 0 |
| `packages/onchain_aave` | `dev` | `mix dialyzer` | 0 |
| `packages/onchain_aave` | `dev` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.agents_check([])"` | 1 |
| `packages/onchain_aerodrome` | `dev` | `mix compile --warnings-as-errors` | 0 |
| `packages/onchain_aerodrome` | `dev` | `mix format --check-formatted` | 0 |
| `packages/onchain_aerodrome` | `dev` | `mix credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME` | 0 |
| `packages/onchain_aerodrome` | `dev` | `mix doctor --raise` | 0 |
| `packages/onchain_aerodrome` | `dev` | `mix ex_dna --max-clones 0` | 0 |
| `packages/onchain_aerodrome` | `dev` | `mix reach.check --dead-code --arch --smells` | 0 |
| `packages/onchain_aerodrome` | `dev` | `mix sobelow --skip --exit low` | 0 |
| `packages/onchain_aerodrome` | `dev` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.advisory_freshness([])"` | 0 |
| `packages/onchain_aerodrome` | `dev` | `mix deps.audit --ignore-file .mix_audit_ignore` | 0 |
| `packages/onchain_aerodrome` | `dev` | `mix cmd env MIX_ENV=test sh -c 'PATH="$HOME/.foundry/bin:$PATH" exec mix test.json --cover --cover-threshold 65 --exclude integration'` | 0 |
| `packages/onchain_aerodrome` | `dev` | `mix dialyzer` | 0 |
| `packages/onchain_aerodrome` | `dev` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.agents_check([])"` | 1 |
| `packages/onchain_evm` | `test` | `mix compile --warnings-as-errors` | 0 |
| `packages/onchain_evm` | `test` | `mix format --check-formatted` | 0 |
| `packages/onchain_evm` | `test` | `mix credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME` | 0 |
| `packages/onchain_evm` | `test` | `mix doctor --raise` | 0 |
| `packages/onchain_evm` | `test` | `mix ex_dna --max-clones 0` | 0 |
| `packages/onchain_evm` | `test` | `mix reach.check --dead-code --arch --smells` | 0 |
| `packages/onchain_evm` | `test` | `mix sobelow --skip --exit low` | 0 |
| `packages/onchain_evm` | `test` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.advisory_freshness([])"` | 0 |
| `packages/onchain_evm` | `test` | `mix deps.audit --ignore-file .mix_audit_ignore` | 0 |
| `packages/onchain_evm` | `test` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.cargo_audit([])"` | 0 |
| `packages/onchain_evm` | `test` | `mix test.json --cover --cover-threshold 85 --exclude integration` | 0 |
| `packages/onchain_evm` | `test` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.cargo_test([])"` | 0 |
| `packages/onchain_evm` | `test` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.cargo_clippy([])"` | 0 |
| `packages/onchain_evm` | `test` | `mix dialyzer` | 0 |
| `packages/onchain_evm` | `test` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.agents_check([])"` | 1 |
| `packages/onchain_js` | `dev` | `mix compile --warnings-as-errors` | 0 |
| `packages/onchain_js` | `dev` | `mix format --check-formatted` | 0 |
| `packages/onchain_js` | `dev` | `mix credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME` | 0 |
| `packages/onchain_js` | `dev` | `mix doctor --raise` | 0 |
| `packages/onchain_js` | `dev` | `mix ex_dna --max-clones 0` | 0 |
| `packages/onchain_js` | `dev` | `mix reach.check --dead-code --arch --smells` | 0 |
| `packages/onchain_js` | `dev` | `mix sobelow --skip --exit low` | 0 |
| `packages/onchain_js` | `dev` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.advisory_freshness([])"` | 0 |
| `packages/onchain_js` | `dev` | `mix deps.audit --ignore-file .mix_audit_ignore` | 0 |
| `packages/onchain_js` | `dev` | `mix cmd env MIX_ENV=test mix test.json --cover --cover-threshold 25 --exclude integration` | 0 |
| `packages/onchain_js` | `dev` | `mix dialyzer` | 0 |
| `packages/onchain_js` | `dev` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.agents_check([])"` | 1 |
| `packages/onchain_solana` | `test` | `mix compile --warnings-as-errors` | 0 |
| `packages/onchain_solana` | `test` | `mix format --check-formatted` | 0 |
| `packages/onchain_solana` | `test` | `mix credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME` | 0 |
| `packages/onchain_solana` | `test` | `mix doctor --raise` | 0 |
| `packages/onchain_solana` | `test` | `mix ex_dna --max-clones 0` | 0 |
| `packages/onchain_solana` | `test` | `mix reach.check --dead-code --arch --smells` | 0 |
| `packages/onchain_solana` | `test` | `mix sobelow --config` | 0 |
| `packages/onchain_solana` | `test` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.advisory_freshness([])"` | 0 |
| `packages/onchain_solana` | `test` | `mix deps.audit --ignore-file .mix_audit_ignore` | 0 |
| `packages/onchain_solana` | `test` | `mix test.json --cover --cover-threshold 95` | 0 |
| `packages/onchain_solana` | `test` | `mix dialyzer` | 0 |
| `packages/onchain_solana` | `test` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.agents_check([])"` | 0 |
| `packages/onchain_tempo` | `dev` | `mix compile --warnings-as-errors` | 0 |
| `packages/onchain_tempo` | `dev` | `mix format --check-formatted` | 0 |
| `packages/onchain_tempo` | `dev` | `mix credo --strict --ignore Credo.Check.Design.TagTODO,Credo.Check.Design.TagFIXME` | 0 |
| `packages/onchain_tempo` | `dev` | `mix doctor --raise` | 0 |
| `packages/onchain_tempo` | `dev` | `mix ex_dna --max-clones 0` | 0 |
| `packages/onchain_tempo` | `dev` | `mix reach.check --dead-code --arch --smells` | 0 |
| `packages/onchain_tempo` | `dev` | `mix sobelow --skip --exit low` | 0 |
| `packages/onchain_tempo` | `dev` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.advisory_freshness([])"` | 0 |
| `packages/onchain_tempo` | `dev` | `mix deps.audit --ignore-file .mix_audit_ignore` | 0 |
| `packages/onchain_tempo` | `dev` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.cargo_audit([])"` | 0 |
| `packages/onchain_tempo` | `dev` | `mix cmd env MIX_ENV=test mix test.json --cover --cover-threshold 90 --exclude integration` | 0 |
| `packages/onchain_tempo` | `dev` | `mix dialyzer` | 0 |
| `packages/onchain_tempo` | `dev` | `elixir -e "Mix.start(); Code.require_file(\"../../shared/mix_helpers.exs\"); OnchainMonorepo.MixHelpers.agents_check([])"` | 1 |

### Core failure output

Reach (after architecture reported OK):

```text
Behaviour candidates
────────────────────
  test/support/signer_test_backends.ex:57
    3 modules expose the same 3 public callbacks; consider extracting a behaviour if these modules are interchangeable implementations
    modules=Cartouche.SignerTest.Ed25519Backend, Cartouche.SignerTest.HighSBackend, Cartouche.Test.HighSSignerBackend
    callbacks=algorithm/1, public_key/1, sign_payload/2

  1 finding(s)
** (Mix) Smell check failed: 1 finding(s)
** (Mix) mix ci failed in packages/onchain (exited 1)
```

Dialyzer:

```text
Total errors: 5, Skipped: 3, Unnecessary Skips: 0
done in 0m2.18s
lib/cartouche/signer.ex:817:16:pattern_match
The pattern can never match the type.

Pattern:
{:error, _}

Type:
{:ok, <<_::160>>}

________________________________________________________________________________
lib/onchain/aa.ex:622:16:pattern_match
The pattern can never match the type.

Pattern:
{:error, _}

Type:
{:ok, <<_::160>>}

________________________________________________________________________________
done (warnings were emitted)
Halting VM with exit status 2
```

Freshness failures (onchain, Aave, Aerodrome, EVM, JS, Tempo) each reported:

```text
STALE: ./AGENTS.md has drifted from CLAUDE.md (+@-imports) — run sync-agents-md.sh
AGENTS.md freshness check failed (sync-agents-md.sh exited 1)
```

Core's renderer also printed `printf: write error: Broken pipe` while its comparison exited on stale content. Solana and root freshness passed on the original revision. All eight pass after regeneration.

## Repair verification

Only Markdown/inlined instructions changed; runtime code, tests, aliases, dependencies, thresholds and suppressions are untouched. After edits:

- Ran the installed `sync-agents-md.sh` renderer at root and all seven packages, then `--check` in each: all eight printed `OK: ./AGENTS.md is up to date`.
- `rmap validate`: `valid`; roadmap files unchanged.
- `git diff --check`: passed.
- Reviewed the final diff and new local documentation links against the files/code they describe.

No code-suite rerun was needed for these documentation-only repairs. Original full QA remains **failed** because of the two retained analyzer groups, even though freshness is repaired. No automatic CI runner is claimed.

## Proposed tasks

None. Retained analyzer findings are deduplicated against prior QA evidence; this pass established no new shipping-blocking correctness or security defect requiring a separate task.
