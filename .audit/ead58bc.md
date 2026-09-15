# Audit — ead58bc (range bc03614..ead58bc)

Date: 2026-09-15
Scope: 5 commits landed on `main`, all touching `packages/onchain_aerodrome`.

**Operator note:** finding 4 (task 9011) is about the gate, not this range — the
harness reviewer runs no tests at all for `onchain_aave`, `onchain_aerodrome` and
`onchain_evm`. Read that one first.

| Commit | Subject |
|---|---|
| `ead58bc` | roadmap: task 5007 -> done (shipped 78e1d3dceb62) |
| `78e1d3d` | onchain_aerodrome: derive TokenAmount drift names from ABI |
| `1313135` | harness: agent delivery — task 5007 veAERO structs, with ABI drift tests |
| `88d873c` | roadmap: task 4067 -> in_progress |
| `d5f407d` | roadmap: task 5007 -> in_progress |

## What was reviewed

The five new type modules (`Types.Vote`, `.VeNFT`, `.Relay` + `.Relay.AccountVeNFT`,
`.LpEpoch` + `.LpEpoch.TokenAmount`, `.Reward`), their five test files, the extended
`abi_drift_test.exs`, the `test/support/types_case.ex` changes, the `OnchainAerodrome`
module roster, and the doc updates in `CLAUDE.md` / `AGENTS.md` / `README.md`.

Checked for: dead code, missing or stale docs, CHANGELOG gaps, leftover debug output,
`@spec` / `@moduledoc` coverage, broken project conventions, inconsistent naming, and
tests that assert nothing.

**Clean on most axes.** The code is strong: every public `from_raw/1` carries a `@spec`
and a Descripex `api/3` declaration, every module has a substantive `@moduledoc` naming
its ABI source, the `# ABI order. Do not reorder for readability.` convention is applied
uniformly, and the drift tests read `priv/abis/*.json` rather than transcribing field
lists. `grep` over `lib/` and `test/` found no `IO.inspect`, `IO.puts`, `dbg(`, bare
`TODO`/`FIXME`, or `@tag :skip`. Doctor reports 100% moduledoc and 97.8% spec coverage;
Reach's architecture policy and cross-function smell passes are clean. The named
non-identity tests (`"LpEpoch TokenAmount is not Types.Reward"`, the `Vote`-defined-once
assertions that `refute` a re-declared `defstruct [:lp, :weight]`) are real
anti-regression tests, not tautologies.

`78e1d3d` was itself a good follow-up: it replaced a transcribed
`["token", "amount"]` literal with names derived from the ABI, and removed
`TypesCase.abi_address_fields/2`, which had become dead. No dead code remained.

## Findings

### 1. CHANGELOG gap — task 5007's entire surface was undocumented (fixed)

`packages/onchain_aerodrome/CHANGELOG.md` had **zero** mentions of `VeNFT`, `Vote`,
`Relay`, `LpEpoch` or `Reward`. The delivery commit touched `CLAUDE.md`, `AGENTS.md`
and `README.md` but not `CHANGELOG.md` — five new public modules (seven counting the
nested ones) would have shipped in the next `onchain_aerodrome` release with no
changelog record. The root `CLAUDE.md` names this explicitly under *After every task*.

**Fixed:** added an `[Unreleased] / Added` entry covering the five structs, the
once-only `Types.Vote` definition and the byte-identical-components assertion behind
it, the two deliberate non-identities (`LpEpoch.TokenAmount` ≠ `Types.Reward`,
`Relay.AccountVeNFT` ≠ `VeNFT`/`Vote`), the ABI-derived (never transcribed) drift
field names, and the integer-amounts / EIP-55-checksummed-addresses invariants.

### 2. Convention drift — the struct assertion was dropped in three `from_raw/1` bodies (fixed)

Eight of the eleven `Types.*` modules write
`%__MODULE__{} = Row.from_raw(__MODULE__, @fields, @address_fields, raw)`. The three
new modules that post-process nested rows — `VeNFT`, `Relay`, `LpEpoch` — bound the
result to a plain variable instead, dropping the assertion.

This matters slightly beyond style: `Row.from_raw/4` is specced to return `struct()`,
not `t()`, so the `%__MODULE__{}` match is what makes each module's
`@spec from_raw(tuple()) :: t()` self-checking at the one place the narrowing happens.
The subsequent `%{venft | ...}` map-update does not pin `__struct__`.

**Fixed:** restored the assertion in all three (`%__MODULE__{} = venft = ...` etc.).
Behaviour is unchanged — `Row.from_raw/4` already returns `struct!(module, values)`.

### 3. `TypesCase` resolves overloaded ABI entries by name alone — filed as task 9010

`TypesCase.abi_entry/2` selects an ABI function with
`&(&1["type"] == "function" and &1["name"] == abi_function)` — name only. The drift
test reading the same JSON disambiguates on input types too, and Relay's drift test
passes `["address"]` explicitly because `RelaySugar` overloads `all` upstream.

Verified against the capture: `priv/abis/relay_sugar.json` currently holds exactly one
`all` entry, so both readers agree today and **nothing is broken**. The defect is the
asymmetry — the drift test is hardened against a re-capture that adds an overload, the
shared helper is not, and after such a re-capture the two readers would silently
disagree (drift test green, one-to-one assertions grading against the wrong shape).
Secondary: an unresolvable name yields `nil` and then raises on the following
`Map.fetch!/2` instead of naming the file and signature it was looking for.

Not fixed inline — it changes a shared helper's call shape across roughly eight test
files, which is past the scope of a hygiene commit. **Filed as rmap task 9010**
(`onchain_aerodrome`, cursor / `cursor-grok-4.6-high`). The `[DD-8]` sibling gate
flagged 5006/5007/6039/4038; re-filed with `RMAP_SIBLING_CHECKED=1` because those
tasks define production structs and their drift assertions, whereas 9010 is the
one-resolution-rule invariant in test support — the class, not another instance.

### 4. `check.dispatch` runs no tests in three packages — filed as task 9011

Found by running the project's own dispatch gate cold and noticing the output carried
no test summary. Measured across all eight `mix.exs` files:

| `check.dispatch` has a test step | Packages |
|---|---|
| yes | cartouche, hieroglyph, onchain, onchain_js, onchain_tempo |
| **no** | **onchain_aave, onchain_aerodrome, onchain_evm** |

The three aliases without a test step are byte-identical to each other — one copied
template with the step dropped.

`check.dispatch` is the project's registered `check_command`: it is what the
cross-family reviewer runs, and under the harness contract the reviewer is the gate.
For three of eight packages that gate proves the code compiles, formats and passes
static analysis, and proves nothing about whether it works. Concretely for this range:
task 5007 landed 47 new `Types.*` tests and the reviewer worktree executed none of
them. This is the whole-surface class the root `CLAUDE.md` warns about — no per-task
reviewer can see it, because no single task's diff contains it.

Not fixed inline, and deliberately so. Adding `test.json` to onchain_aerodrome's alias
would turn every future dispatch of that package red on any node without Foundry (see
the cold-build witness below), so the right fix needs a decision — Foundry as a
documented dispatch-node prerequisite, or an exclusion tag that `check.dispatch` skips
while `mix ci` still runs. **Filed as rmap task 9011** (`onchain_stack`, codex /
`gpt-6-astra`), scored `d=4, b=9, u=8`.

## Reviewer feedback loop

No reviewer rejections are recorded for this project, so there is no false-rejection
candidate in this range.

## Cold-build witness

The audit worktree was un-warmed. `mix deps.get` was required first — a bare
`mix check.dispatch` aborts on unfetched deps.

**Command: `cd packages/onchain_aerodrome && mix deps.get && mix check.dispatch` —
passed** (exit 0), cold, and passed again after the fixes in this commit. That covers
`format --check-formatted`, `compile --warnings-as-errors`, `credo --strict`,
`doctor --raise` (100% moduledoc, 97.8% spec), `ex_dna --max-clones 0`,
`reach.check --arch --smells` and `sobelow --skip --exit low`.

It does **not** cover tests — that is finding 4. Because the gate is silent there, the
suite was run separately as part of this audit:

- `mix test.json test/onchain/aerodrome/types/` — **47 passed**, covering every module in
  this range including the three I edited.
- `mix test` (whole package) — **156/159 passed, 3 failed**. All three failures are in
  `test/onchain/aerodrome/calldata_fixture_test.exs`, all with
  `Foundry cast is required on PATH; never a skip`; `cast` is absent on this node.
  Those tests landed earlier under task 5026 (`fe6faa0` / `6af0864`), are outside the
  audited range, and their refusal to skip is deliberate and correct. Environmental,
  pre-existing, not caused by this range or by my fixes.

## Summary

4 findings, 2 fixed here, 2 filed as tasks 9010 and 9011.

The landed code itself is high quality — the veAERO structs are well documented,
well specced and genuinely well tested, and the `78e1d3d` follow-up had already
removed the one piece of dead code. The only omission in the range proper was the
CHANGELOG.

The more consequential finding is 9011, which the range did not cause but did
expose: the dispatch gate that graded this work never ran its tests. Worth flagging
to the operator ahead of the others.
