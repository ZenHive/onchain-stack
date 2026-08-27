# ABI verification ledger

Record of the independent-oracle and planted-mutant verification for the ABI
wire format (roadmap task 44). This file is the audit trail: what was asserted,
against which authority, and what the mutation run proved about it.

Last full run: **2026-08-22**.

---

## 1. Why round-tripping was not enough

The suite that existed before this task was dominated by
`decode(encode(x)) == x` properties (`test/abi/roundtrip_property_test.exs`,
28 properties, composite depth 5) plus ~30 hand-pinned hex/selector fixtures.

Two blind spots survive an arbitrarily thorough round trip:

**Offset arithmetic is invisible by non-use.** `ABI.TypeEncoder` writes a
head-slot offset for every dynamic element (`encode_tuple_element/2`).
`ABI.TypeDecoder` parses that word into `{:dynamic, type, tail_position}` and
then *discards* it — `{:dynamic, type, _tail_position} -> decode_type(...)` —
consuming the tail sequentially in declaration order instead. The decoder
therefore never reads the number the encoder wrote, and a wrong offset survives
every round trip while corrupting every external reader.

**Self-verification.** `ABI.method_id/1` computes the selector on the encode
side and again on the decode side; `ABI.Event.event_signature/1` likewise. The
same deterministic bug produces both sides of the comparison.

Not blind spots, contrary to an earlier framing of this task: `ABI.Math.pad/4`
and `unpad/3` are two independently written implementations, and
`TypeDecoder.decode_int/2` uses the BEAM's native signed bit syntax rather than
re-deriving two's complement — a padding-direction flip or sign-extension bug
*does* break the round trip.

---

## 2. Authorities

| Authority | Version / date | Used for |
|---|---|---|
| Solidity ABI specification, https://docs.soliditylang.org/en/latest/abi-spec.html | fetched 2026-08-22 | §`formal-specification-of-the-encoding` (head/tail offsets, length words, padding direction), §`function-selector`, §`events`, §`encoding-of-indexed-event-parameters` |
| `@ethersproject/testcases` 5.8.0 (MIT) | fetched 2026-08-22 | 1,601 vendored vectors recorded from `solc`-compiled contract output |
| Foundry `cast` (`cast abi-encode`, `cast keccak`) | local, 2026-08-22 | independent cross-check of every hand-derived expectation in `test/abi/abi_spec_test.exs` |
| `solc` | 0.8.10+commit.fc410830 (local) | available for generating fixtures; not needed — the vendored corpus covered every shape |

Vendored corpus provenance, license and filter criteria:
`test/support/fixtures/ethers/PROVENANCE.md`.

---

## 3. What this task added

### 3.1 Independent vectors — `test/abi/ethers_corpus_test.exs`

Eight tests over 1,601 vendored vectors. No assertion path contains a
`decode(encode(x))` step: every expectation is a byte string ethers.js recorded
from a real contract.

| Assertion | Vectors | Surface |
|---|---|---|
| `ABI.encode/2` output equals the contract's returned encoding | 443 + 368 | head/tail offsets, length words, padding, nested tuples and arrays |
| `ABI.decode/3` of the recorded encoding equals the recorded arguments | 443 + 368 | the decode direction, against bytes this library did not produce |
| `ABI.method_id/1` equals `solc`'s selector | 376 | selector derivation, independently of the encode path |
| `ABI.encode_event_topics/2` equals the emitted topic list | 414 | topic0 derivation, indexed value packing, indexed reference hashing |
| non-indexed parameters encode to the emitted log `data` | 414 | event data payload |
| `ABI.decode_event/4` recovers the emitted parameter values | 414 | log decoding, including `{:indexed_hash, _}` for hashed topics |

### 3.2 Spec-anchored assertions — `test/abi/abi_spec_test.exs`

19 tests, each citing the spec section it encodes, closing the three concerns
the round-trip suite left open:

- **Offset value** — five tests pinning the exact head word: one static word
  before a dynamic argument (`0x40`), a static `T[k]` inlined into the head
  (`0x80` for `(bytes,address[3])`), a nested static array (`0xa0`), an inlined
  static tuple (`0x60`), and offsets inside a dynamic array measured from the
  element area rather than the count word.
- **Length word** — byte length for `bytes`, UTF-8 *byte* length (not codepoint
  count) for `string`, element count for a dynamic array, and the absence of a
  length word for a fixed-size array.
- **Padding direction** — left/zero for `uint`, left/`0xff` for negative `int`,
  left for `address` and `bool`, right for `bytes<M>` and the `string` tail.

Plus indexed-event-parameter hashing (an indexed tuple and an indexed *static*
array are both hashed, which the head/tail `dynamic?` predicate would not
predict), anonymous events on both directions, and the "first four bytes, in
digest order" selector rule.

### 3.3 Planted mutants — `test/support/mutants/mutants.exs`

Eight single-site edits to `lib/`, applied and reverted by
`MIX_ENV=test mix hieroglyph.mutants`. The runner asserts each anchor matches
its file exactly once (a moved site fails loudly rather than silently disarming
the mutant), refuses to grade a mutant whose `replace` leaves the file
byte-identical, and verifies the SHA-256 of every touched file after the
revert — aborting the whole run if a file does not come back byte-exact,
rather than mutating the next file on top of a tree that is already wrong.

Two properties of that guarantee are worth stating precisely, because the
earlier wording overstated them:

* **The revert covers exceptions, not signals.** `try/after` restores the file
  when anything raises, but Ctrl-C reaches the BEAM break handler and
  `erlang:halt` unwinds nothing — and essentially all of a run's wall-clock
  time is spent inside `mix test` with `lib/` mutated. The original bytes are
  therefore also written to a `.hieroglyph-mutants.orig` sidecar before each
  mutation and removed only once the restore is verified. A leftover sidecar
  means a run was killed mid-mutation, and the task refuses to start until it
  is cleared (`git checkout -- lib/ && rm lib/**/*.hieroglyph-mutants.orig`).
* **A control run precedes the corpus.** Every mutant is graded by "did the
  vector files go non-zero", so vector files that are already failing would
  make every mutant read as `:killed` and report a perfect score against a
  broken oracle. The runner asserts they pass on unmutated `lib/` first. This
  matters most for `--only`, which otherwise selects away the single
  `:survivor` mutant whose expectation would have caught the same breakage.

Two runs are recorded per mutant and kept apart: **vectors** (only the two
files added by this task) and **suite** (the whole `mix test` run). Only the
vectors column counts as a kill. A mutant that fails to compile is reported
`invalid`, never as a kill — static analysis is a different oracle.

---

## 4. Mutant table

Run of 2026-08-22, `MIX_ENV=test mix hieroglyph.mutants`.

| # | Mutant id | Site | Mutation | Vectors | Suite | Verdict | Killing assertion |
|---|---|---|---|---|---|---|---|
| 1 | `offset-word-zeroed` | `type_encoder.ex` `encode_tuple_element/2` head slot | write constant `0` instead of `tail_position` | failed | failed | **killed** | corpus encode (`contract-interface`); spec `head/tail offset value` |
| 2 | `offset-never-advances` | `type_encoder.ex` `encode_tuple_element/2` accumulator | drop `+ byte_size(el)` | failed | failed | **killed** | corpus encode; spec `offsets inside a dynamic array` |
| 3 | `tail-start-off-by-one-word` | `type_encoder.ex` `encode_type/2` `{:tuple, _}` | `count(types) * 32 + 32` | failed | failed | **killed** | corpus encode; spec `a single static word before a dynamic argument` |
| 4 | `selector-slice-shifted` | `abi.ex` `method_id/1` | take digest bytes 1..4 | failed | failed | **killed** | corpus `contract-signatures`; spec `function selector` |
| 5 | `keccak-digest-reversed` | `math.ex` `kec/1` | return the digest byte-reversed | failed | failed | **killed** | corpus `contract-signatures` and event topic0 |
| 6 | `event-signature-annotates-indexed` | `event.ex` `event_signature/1` | hash the signature with the `indexed` keyword rendered | failed | failed | **killed** | corpus `encode_event_topics/2` (topic0) |
| 7 | `indexed-tuple-not-hashed` | `event.ex` `reference_type?/1` | delete the `{:tuple, _}` clause | failed | failed | **killed** | spec `an indexed tuple is stored as the keccak256 of its in-place encoding` |
| 8 | `mod-negative-branch` | `math.ex` `mod/2` | return `rem/2` (sign-preserving) for negative dividends | passed | failed | **survivor** | — see §5 |

**7 of 8 killed by assertions added in this task.** The suite column shows all
eight are caught by *something*, but for mutant 8 that something is only the
pre-existing `ABI.Math.mod/2` doctest, which per this task's definition makes it
a survivor, not a kill.

---

## 5. Survivor review

### `mod-negative-branch` — classified **unreachable from the ABI wire path**

`ABI.Math.mod/2`'s negative-dividend clause is dead code for every
encoder/decoder call site. Evidence — the complete set of `mod/2` call sites in
`lib/`, and the sign of the first argument at each:

| Call site | Expression | First argument |
|---|---|---|
| `math.ex` `pad/4` | `mod(32 - mod(size_in_bytes, 32), 32)` | inner `mod` yields `0..31`, so the outer sees `1..32` |
| `math.ex` `unpad/3` | same shape | `1..32` |
| `type_encoder.ex` `pack_*` | `Math.mod(32 - Math.mod(size, 32), 32)` | `1..32` |
| `type_decoder.ex` `decode_uint/2`, `decode_int/2` | `Math.mod(@word_size_bits - size_in_bits, @word_size_bits)` | `size_in_bits <= 256` (the grammar rejects wider), so `0..248` |
| `type_decoder.ex` `decode_bytes/3` | `Math.mod(@word_size_bytes - Math.mod(size_in_bytes, 32), 32)` | `0..32` |

No wire-format assertion can reach the mutated branch, so no wire-format
assertion should be expected to kill it. The branch is still live for direct
callers of the public `ABI.Math.mod/2`, and the existing doctest
(`ABI.Math.mod(-7, 5) == 3`) is its correct guard. Adding a duplicate of that
doctest to the new files would manufacture a kill without adding coverage, so
the mutant is recorded here instead of papered over.

The dependency worth knowing: this classification holds only while the type
grammar rejects integer widths above 256 bits. If that ever changes,
`@word_size_bits - size_in_bits` goes negative and the branch becomes live on
the decode path — re-run the mutant corpus at that point.

No other mutant survived. No mutant was dropped, silently or otherwise.

---

## 6. Defects the oracle found

Both were introduced by this task's oracle, not by its code changes, and both
were invisible to the pre-existing round-trip suite exactly as §1 predicts.

### 6.1 `TypeEncoder` — a static `T[k]` was counted as one head slot

`do_count/1` accounted for inlined static *tuples* but not for fixed-size
*arrays*. A static `T[k]` is inlined into the head as `enc(X[0]) … enc(X[k-1])`
and occupies `k` times the head size of its element type; counting it as one
word understated `tail_start` for every dynamic sibling.

`ABI.encode("(bytes,address[3])", …)` wrote offset `0x40` where Solidity writes
`0x80`. The decoder never read the offset, so the round trip was green;
79 of the 811 vendored interface vectors failed. Fixed in
`lib/abi/type_encoder.ex`; regression pinned by
`test/abi/abi_spec_test.exs` "a static `T[k]` is inlined into the head".

### 6.2 `Event` — anonymous events could not be decoded

`Event.event_topic0/1` already omitted `topics[0]` for anonymous events on the
encode side, but `do_decode_event/4` unconditionally reserved a topic0 slot, so
every anonymous log failed with `{:error, {:topics_length_mismatch, _}}`.
194 of the 414 vendored event vectors are anonymous and all failed. Fixed in
`lib/abi/event.ex` by folding `anonymous_event?/1` into `check_event_signature`,
which makes both the slot count and the signature verification anonymity-aware
in one place. Regression pinned by `test/abi/abi_spec_test.exs` "an anonymous
event has no `topics[0]`, on both the encode and decode side".

Both fixes change encode/decode *output* for the affected shapes, which the
task's `out_of_scope` nominally excluded. They are wire-format corrections
against the provider-owned spec, they are the whole point of introducing an
independent oracle, and leaving them unfixed would have landed a red suite.
Recorded in `CHANGELOG.md` as fixes.

---

## 7. Re-running

    MIX_ENV=test mix test.json test/abi/ethers_corpus_test.exs test/abi/abi_spec_test.exs
    MIX_ENV=test mix hieroglyph.mutants          # both columns, exits non-zero on a surprise
    MIX_ENV=test mix hieroglyph.mutants --vectors --only offset-word-zeroed
    python3 test/support/fixtures/ethers/vendor.py   # re-vendor from upstream

`mix hieroglyph.mutants` is deliberately **not** wired into `mix ci`: it mutates
`lib/` in place and spawns a full `mix test` per mutant, which does not belong
in a gate that runs on every commit. Run it when the encoder, decoder, selector
or event paths change — and update the table above when it does.
