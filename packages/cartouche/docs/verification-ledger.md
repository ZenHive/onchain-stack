# Transaction Verification Ledger

Task 113 establishes these invariants for Cartouche's Ethereum transaction surface:

| ID | Claim | Evidence |
|---|---|---|
| `INV-TX-ENVELOPE` | Every encodable V1, V_2930, V2, V3, and V4 envelope round-trips and a generated signature recovers its signer. | StreamData properties and independent golden vectors. |
| `INV-TX-DOMAIN` | Changing the chain ID changes the recovered signer; legacy `v` follows `2 * chain_id + 35 + y_parity`. | StreamData properties. |
| `INV-SIGN-LOW-S` | Every 65-byte signing route emits `s <= secp256k1n/2`, including a backend that returns high-s. | StreamData property with pure-backend, legacy-MFA, direct, and forced-high-s routes. |
| `INV-TX-VECTORS` | Cartouche's decoded field meaning, bytes, hashes, signer recovery, and EIP-7702 authority recovery match independent implementations. | Committed ethers and viem vectors. |

## Authorities

| Specification | Authoritative claim used |
|---|---|
| [EIP-2](https://eips.ethereum.org/EIPS/eip-2) | Transaction signatures require `s <= secp256k1n/2`. |
| [EIP-155](https://eips.ethereum.org/EIPS/eip-155) | Legacy signing payload and `v = 2 * chain_id + 35 + y_parity`. |
| [EIP-2718](https://eips.ethereum.org/EIPS/eip-2718) | Typed envelope is `TransactionType || TransactionPayload`. |
| [EIP-2930](https://eips.ethereum.org/EIPS/eip-2930) | Type `0x01`, field order, access-list shape, and signed preimage. |
| [EIP-1559](https://eips.ethereum.org/EIPS/eip-1559) | Type `0x02`, field order, and signed preimage. |
| [EIP-4844](https://eips.ethereum.org/EIPS/eip-4844) | Type `0x03`, field order, signed preimage, and versioned-hash shape. |
| [EIP-7702](https://eips.ethereum.org/EIPS/eip-7702) | Type `0x04`, field order, non-empty authorization list, and authorization signing domain. |

The exercised wire behavior is explicit in those EIPs. No vector overrides an EIP interpretation, and no discrepancy was observed. ethers and viem agree byte-for-byte on all signed payloads, unsigned payloads, hashes, recovered senders, and the EIP-7702 authorization. The V1 vector is the EIP-155 worked example (signing data, signing hash, and signed transaction).

## Vector provenance

| Fixture | Source implementation | Exact version | Coverage |
|---|---|---:|---|
| `test/fixtures/vectors/ethers-6.17.0.json` | [ethers](https://github.com/ethers-io/ethers.js) | 6.17.0 | V1, V_2930, V2, V3, V4, and EIP-7702 authorization. |
| `test/fixtures/vectors/viem-2.55.19.json` | [viem](https://github.com/wevm/viem) | 2.55.19 | V1, V_2930, V2, V3, V4, and EIP-7702 authorization. |

Each JSON fixture embeds its source, exact version, and generation command. The committed generator is `test/fixtures/vectors/generate.cjs`; its command installs pinned packages into an isolated npm prefix and regenerates both files.

Toolchain used for this ledger: Node.js 26.7.0, npm 11.19.0, ethers 6.17.0, viem 2.55.19, Elixir 1.20.2, Erlang/OTP 29, and StreamData 1.4.0.

## Mutation adequacy

Task 113 shows the suite *passes* on the transaction and signing surface. Task 114 asks
the harder question: would it *fail* if the code were wrong?

**That question is not answered here.** The campaign ran to completion, but the tool
cannot report a surviving mutant on this Elixir, so the adequacy claim the task exists for
has no evidence behind it. What the run *did* establish — which lines no test reaches, and
which mutants are provably unkillable — is recorded below, along with the tests written to
close the gaps it found. The measurement itself is deferred to task 119.

Tool: [muex](https://hex.pm/packages/muex) 0.8.2, on Elixir 1.20.2 / Erlang.OTP 29.
`muzak` was rejected by the task and not used: its last release is 1.1.1 (December 2022)
and its free tier caps a run at 25 randomly chosen mutations, which cannot support an
adequacy claim.

### Configuration

```
mix muex --files <surface> --test-paths test \
  --mutators arithmetic,boolean,case_clause,comparison,cond_clause,conditional,\
enum_semantics,extended_math,function_call,guard,invert_negatives,literal,\
map_semantics,negate_conditionals,pipe,return_value,statement_deletion,with_clause \
  --no-filter --no-optimize --coverage-guided \
  --concurrency 8 --timeout 60000 --fail-at 0 --format json
```

All 18 mutators, and the run is **exhaustive by construction**. Two flags carry that:

* `--no-optimize` disables muex's default sampling. Left on, `--max-per-function 20` and
  `--min-complexity 2` would silently reduce the surface to a sample — reintroducing the
  very property that disqualified muzak.
* `--no-filter` disables intelligent file filtering, so no file is skipped on a heuristic.

`--coverage-guided` narrows only *which existing tests run against a given mutant*; it
never drops a mutant, and a line no test reaches is reported as `no_coverage` rather than
being quietly omitted. It is a wall-clock optimization, not a scope reduction.

One invocation covers the whole surface. Per-module invocations are not equivalent in
cost: `Muex.Coverage.collect/3` rebuilds its line index by running `mix test.json <file>
--cover` once per test file, serially and without a cache, so every extra invocation pays
a full-suite pass. Splitting this campaign by module is what exhausted an earlier
dispatched attempt's time budget.

### Surface

`lib/cartouche/transaction.ex` (V1 and V2 live there), `lib/cartouche/transaction/*.ex`,
`lib/cartouche/signer.ex`, `lib/cartouche/signer/*.ex`, `lib/cartouche/recover.ex`, and
`lib/cartouche/recovery_bit.ex` — 13 files, 4,599 lines. Generated contract wrappers under
`lib/cartouche/contract/` are out of scope.

### Why `killed` and `survived` are not reported here

muex 0.8.2 parses the human-readable summary line that `mix test` prints, and matches the
wording Elixir used up to 1.19. `Muex.TestRunner.Port`:

```elixir
defp count_failures(output, _exit_code) do
  case Regex.run(~r/(\d+) failures?/, output) do
    [_, count] -> String.to_integer(count)
    nil ->
      if String.contains?(output, "0 failures") do
        0
      else
        # No ExUnit output at all — something crashed. Treat as killed.
        1
      end
  end
end
```

Elixir 1.20 no longer prints `20 tests, 0 failures`. It prints `Result: 20 passed (11
doctests, 9 tests)` for a green run, and `Result: 0/1 passed` followed by `Failed: 1 test`
for a red one. Neither wording contains `N failures`, and neither contains the substring
`0 failures`, so the regex misses and the fallback returns 1. The comment states the
assumption that fails: there *is* ExUnit output, it is merely worded differently. Since
`classify_test_result({:ok, %{failures: 0}})` is the only path to `:survived`, that class
is unreachable — **a mutant no test notices is reported as `killed`.**

Verified against a four-file project outside this repo: one module `def add(a, b), do: a +
b`, one test asserting only `is_integer(Demo.add(1, 2))`. Mutating `+` to `-` by hand
leaves the test green, so the mutant demonstrably survives. muex reports
`killed / killed`, `survived: 0`, `mutation_score: 100.0`. Filed upstream as
[Oeditus/muex#20](https://github.com/Oeditus/muex/issues/20) with that reproduction and a
patch.

The same stale patterns make `has_exunit_summary?/1` always false, which collapses
`compile_error?/1` to "does the output contain `** (SomethingError)`" — true whenever a
test fails by raising rather than by a plain assertion. So the reported class depends on
*how* a test fails, not on whether it fails:

| Real outcome | muex reports |
|---|---|
| every test passes — a genuine survivor | `killed` |
| a test fails by assertion | `killed` |
| a test fails by raising | `invalid` |

That also explains the churn. Between the baseline campaign and the verification pass
`lib/` was byte-identical — only test files were added — yet **337 of the 1,379 distinct
mutants re-measured changed class**: 246 `killed` → `invalid` and 91 the reverse, driven
purely by coverage guidance selecting a different set of tests. Timing corroborates that
`invalid` is not a compile failure: those mutants ran a p50 of 6.6 s, essentially the same
as `killed` (7.0 s), while the classes that genuinely skip the test subprocess are three
orders of magnitude faster — `equivalent` 21–45 ms, `no_coverage` 0 ms. Only 3 of 842
carried an `error` field, i.e. were real `Sandbox.apply_mutation` failures.

### What the run still measured

Two classes are decided **before or without** running any test, so the defect above does
not touch them:

* `no_coverage` — `select_tests/2` consults the coverage index and returns `:no_coverage`
  for a line no test executes, before a subprocess is ever spawned.
* `equivalent` — Trivial Compiler Equivalence compares the mutant's BEAM bytecode against
  the original under a shared throwaway module name (`Muex.Tce`), reporting equivalence
  only on an exact instruction-stream match and treating any compile failure as *not*
  equivalent. No test runs.

| Module | Mutants | Equivalent | Not executed | Killed\* | Invalid\* |
|---|---:|---:|---:|---:|---:|
| `recover` | 217 | 0 | 0 | 105 | 112 |
| `recovery_bit` | 217 | 12 | 35 | 74 | 96 |
| `signer` | 414 | 0 | 0 | 189 | 225 |
| `signer/backend` | 20 | 0 | 0 | 12 | 8 |
| `signer/cloud_kms` | 134 | 0 | 0 | 62 | 72 |
| `signer/curvy` | 66 | 0 | 0 | 29 | 37 |
| `transaction` | 1881 | 1227 | 0 | 209 | 445 |
| `transaction/call` | 31 | 2 | 0 | 13 | 16 |
| `transaction/signature` | 151 | 12 | 0 | 63 | 76 |
| `transaction/typed_decode` | 198 | 0 | 0 | 94 | 104 |
| `transaction/v3` | 455 | 0 | 8 | 223 | 224 |
| `transaction/v4` | 764 | 0 | 12 | 387 | 365 |
| `transaction/v_2930` | 357 | 0 | 0 | 173 | 184 |
| **total** | **4905** | **1253** | **55** | **1633** | **1964** |

Wall clock 98 minutes. **\* `Killed` and `Invalid` are recorded for provenance only and
carry no information** — per the section above, every mutant that ran lands in one of the
two according to how its tests failed, and a survivor lands in `killed`. Do not read a
mutation score from this table.

The 1,227 equivalents concentrated in `transaction.ex` are explained by that file's
shape — 1,999 lines dense with `api(...)` declarations, `@doc`/`@spec` attributes and long
doctests, all of which the compiler erases. Mutating documentation cannot change
transaction semantics.

**Not executed — 55** is the campaign's real finding. These are mutants on lines no test
in `test/` reaches, and they are *weaker* than survivors, not better: the suite was never
given the chance to fail. They are dispositioned below.

### Disposition of the 55 unexecuted mutants

Every unexecuted mutant traces to one of six sites. Four of the six are default-argument
heads or defensive clauses that no call site in the suite reached.

| Site | Mutants | Disposition |
|---|---:|---|
| `recovery_bit.ex:51` — `normalize/2` head, `rec_type \\ :eip155` | 12 | **Killed by new tests.** Every existing call site, doctests included, passed `rec_type` explicitly, so nothing pinned the `:eip155` default or the `rec_type in @rec_types` guard. `test/recovery_bit_test.exs` now calls `normalize/1` and asserts an unknown convention raises instead of falling through. |
| `recovery_bit.ex:100` — `normalize_signature/2` head, same default | 23 | **Killed by new tests.** Same gap, same fix, plus a case pinning the 65-byte signature guard. |
| `transaction/v3.ex:204` — `sign/2` head, `signer \\ Default` | 8 | **Killed by new tests.** `V3.sign/1` — the default-signer route — was never exercised. `test/cartouche/transaction/mutation_gap_test.exs` signs through it and asserts the recovered address matches the default signer, and that the implicit and explicit routes encode identically. |
| `transaction/v4.ex:370` — `encode_access_list(nil)` | 4 | **Killed by new tests.** `V4.new/10` never yields a nil access list, but `encode/1` accepts a struct carrying one. The new test asserts nil encodes exactly as `[]` and round-trips back to `[]`. |
| `transaction/v4.ex:589` — `decode_uint/2` error clause | 5 | **Killed by new tests.** Reached by a wire-level 13-field envelope whose y-parity field is two bytes wide. The same test file also pins the neighbouring `decode_word/1` behaviour: RLP encodes scalars minimally, so a short signature word is left-padded to 32 bytes and only an oversized one is rejected. |
| `transaction/v4.ex:574` — `decode_y_parity(nil)` | 3 | **Accepted gap: unreachable clause.** `decode_fields/1` is only ever fed by the RLP decoder, which yields binaries and lists but never `nil`; the unsigned 10-field clause passes `{nil, nil, nil}` straight to `decode_transaction_fields/2` and bypasses `decode_y_parity/1` entirely. The clause is dead defensive code that mirrors the `binary() \| nil` spec. No test can reach it without calling a private function, so it is recorded rather than covered. |

Note that "killed by new tests" above means *the line is now executed by a test that
asserts its behaviour* — established by reading the tests and by the coverage movement
below, not by muex's `killed` verdict, which carries no information.

### Verification pass

The three files that carried all 55 unexecuted mutants were re-measured with the new tests
in place, same flags, 1,436 mutants, wall clock 79 minutes.

| | Baseline | Verification | Change |
|---|---:|---:|---|
| Not executed | 55 | **3** | −52 |
| Equivalent | 12 | 15 | +3 |

**52 of the 55 previously-unexecuted mutants are now under test.** Of those, 49 ran the
suite and 3 turned out to be provably equivalent — a mutant with no coverage never reaches
the TCE check, because `select_tests/2` short-circuits first, so gaining coverage is what
exposed them as unkillable.

The 3 that remain unexecuted are all at `v4.ex:574`, the dead `decode_y_parity(nil)`
clause dispositioned above as an accepted gap. That is the predicted outcome and the one
result of this campaign that is both meaningful and unaffected by the tool defect.

### Deliberate-fault canaries

A mutation score is only worth what the fault detection behind it is worth — and here the
score is worth nothing, which makes these the only positive evidence in the section.
`test/cartouche/mutation_canary_test.exs` reconstructs specific faults by hand and pins
which invariant kills each — and, deliberately, which plausible invariant does not. These
are ordinary ExUnit tests and depend on muex in no way.

| Canary | Fault | Killed by | Does *not* kill it |
|---|---|---|---|
| Low-s deleted | `Signer.emit_signature/4` without `Recover.normalize_low_s/1`, driven by a high-s backend | `INV-SIGN-LOW-S` (`s <= n/2`) | Address recovery. Both `(r, s)` and `(r, n - s)` are valid over the same digest, so the recid search finds the matching bit and recovery succeeds. |
| Wrong chain id in `v` | `Signer.encode_eip155/3` packing `v` from `chain_id + 1` | The EIP-155 formula assertion, `v - (2 * chain_id + 35) in [0, 1]` | Raw-signature recovery. `Recover.decode_signature/1` reduces `v` to `rem(v + 1, 2)`, and shifting the chain id by one shifts `v` by two, so the parity — and the recovered address — is unchanged. |
| Wrong chain id in the hash domain | `V1.recover_signer/2` re-encoding the EIP-155 payload under a neighbouring chain | `INV-TX-DOMAIN` (recovery yields a stranger) | — the chain id is inside the digest here, so recovery is the detector. |

The two chain-id canaries are the useful pair: the same nominal fault is caught by
opposite assertions depending on whether the chain id sits in the signed digest or in the
`v` byte. An adequacy claim resting on recovery alone would have missed the second.

### Caveats

* **No adequacy claim is made by this section.** The suite may well be strong against the
  faults muex generates — this campaign simply cannot say so, in either direction. Task
  119 re-runs the measurement once an upstream release reports survivors *and* applies the
  mutations it reports; see the attempt recorded below for why #20 alone is not that
  release.
* **`Killed` and `Invalid` in the result table are provenance, not measurement.** They are
  retained so the re-run can be diffed against this baseline, and for no other purpose.
* **Two-minute contamination window.** The canary file was briefly created under `test/`
  while the baseline campaign was running (muex symlinks the project's `test/` into each
  worker sandbox), and was moved out ~2 minutes later. This is moot for the classes this
  section relies on: `no_coverage` is decided from a coverage index built before the file
  existed, and `equivalent` never runs a test at all.
* **Not a CI gate.** This is a one-off measurement plus the tests it produced. muex is a
  `:dev`/`:test` dependency and no `mix ci` step runs it. A future scoped check is cheap
  (`mix muex --since main` mutates only changed lines); a recurring exhaustive run is not.

### 2026-08-24 re-measurement attempt on muex 0.8.3 — run and discarded

muex 0.8.3 closes [#20](https://github.com/Oeditus/muex/issues/20): its reproduction now
reports `survived: 2`, `mutation_score: 0.0%`, where 0.8.2 reported `killed / killed`,
100%. The campaign above was therefore re-run with the same flags: 4,905 mutants, 88
minutes, 1,308 `killed` / 111 `survived` / 2,227 `invalid` / 1,256 `equivalent` / 3
`no_coverage`.

**Those survivors are not test gaps, and the run was discarded.** The first survivor
checked before triage was `transaction.ex:222`, `:binary` → `:mutated_atom`, on a line
`V1.decode/1` covers with 13 assertions. It is killed by the existing suite at
`test/transaction_test.exs:1213`, and killed again when driven through muex's own
`Sandbox.apply_mutation/4` + `TestRunner.Port.run_tests/2` (`failures=1`). It was scored
`survived` because the mutation never reached the beam.

Two upstream defects, both open against 0.8.3, produce that:

* [#23](https://github.com/Oeditus/muex/issues/23) — `Sandbox.detect_app_from_build/2`
  resolves the app name only when `_build/<env>/lib/*/.mix/compile.elixir` has exactly one
  match. cartouche has 45, one per dependency, so it returns `nil`,
  `ensure_build_copy_for_file/2` makes no copy, and every sandbox's
  `_build/test/lib/cartouche` stays a **symlink into the real project build directory** —
  measured directly, unchanged before and after `apply_mutation/4`. Parallel workers then
  share one `ebin` and one compile manifest: when a sibling recompiles the file between a
  worker's mutant write and its own test run, Mix reads the source as up to date and the
  mutation is silently dropped. This is also the likeliest explanation for the 337-of-1,379
  class churn recorded above over a byte-identical `lib/`, which was attributed to #20.
* [#24](https://github.com/Oeditus/muex/issues/24) — mutations are matched by their
  *reported* line, which for two mutators is deliberately not the matched node's line. So
  `StatementDeletion` is a 100% no-op and bare-boolean flips are ~70%: 383 of these 4,905
  mutants, and 8 of the 111 survivors, were graded against unmodified source. Scheduling
  does not affect this one.

`#22` and `#25` do not reach this campaign: `--no-filter` bypasses the file filter, and
`--test-paths test` links the whole test root rather than a narrowed subset.

`--concurrency 1` removes #23's race — `.mutation/run.sh` is pinned to it, with the
reasoning in its header — but nothing available today removes #24, so a serial re-run was
started and then stopped rather than carried to a partly-invalid result. Task 119 is
blocked on a muex release carrying both fixes, and its pre-campaign gate is now per defect
rather than #20's reproduction alone.

What this attempt does **not** change: `no_coverage` is decided before any mutation is
applied — `select_tests/2` consults the coverage index and returns `:no_coverage` first —
so the 55-unexecuted finding, its disposition table, and the verification pass above stand
as recorded.

**`equivalent` is not in that position, and the sentence above originally claimed it was.**
Trivial Compiler Equivalence does not run a test, but it does run *after* the mutation is
applied: `Muex.WorkerPool.run_mutation_worker/4` calls `Compiler.compile_to_source/3` —
the line-keyed `transform/5` that #24 breaks — and hands the resulting **source** to
`Tce.equivalent_source?(file_entry.ast, mutated_source)`. A mutation that #24 turns into a
no-op therefore produces source byte-identical to the original, TCE reports an exact
instruction-stream match, and the mutant is classified `equivalent` without ever reaching
a sandbox. `--no-optimize` does not disable this: `Muex.Config.resolve_tce/1` reads only
`--tce` / `--no-tce`, and the campaign passed neither.

So the `equivalent` counts recorded above — task 114's 1,227 and this attempt's 1,256 —
are an **upper bound** contaminated by mutations that were never applied, not a measured
equivalence class. How much of each count is real is unknown and not derivable from the
recorded artifacts; task 119's re-run has to re-derive `equivalent` alongside the rest.
`no_coverage` is unaffected, and the #20-scoped claim in the task 114 section above
("Two classes are decided before or without running any test") remains true of #20 and
only of #20.
