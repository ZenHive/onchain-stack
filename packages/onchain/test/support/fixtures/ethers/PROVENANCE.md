# Vendored vector corpus — provenance

## Source

| | |
|---|---|
| Package | `@ethersproject/testcases` |
| Version | 5.8.0 |
| Tarball | `https://registry.npmjs.org/@ethersproject/testcases/-/testcases-5.8.0.tgz` |
| Integrity | `sha512-Jx/g2GoLwW0nv3/QpB9/Yfla1TPaqTop2lfa4HTOSGHKk4Q++aGoMUkZG/KrsuNdbHnROrXogjLTMqq6TauQNQ==` |
| License | MIT (ethers.js, © 2019 Richard Moore) — full text in `LICENSE.ethers.md` |
| Upstream repo | https://github.com/ethers-io/ethers.js |
| Fetched | 2026-08-22 |
| Files taken | `package/testcases/{contract-interface,contract-interface-abi2,contract-signatures,contract-events}.json.gz` |

The corpus is derived from `solc`-compiled contracts: each vector records the
contract source, its compiled bytecode, the values passed in, and the bytes the
contract actually returned or the log it actually emitted. Nothing in it was
produced by hieroglyph, which is what makes it usable as an **independent
oracle** — see `docs/abi-verification-ledger.md`.

Only `@ethersproject/testcases` was usable this way. `eth-abi`, `viem` and
`alloy` keep their vectors inline in test code rather than in a machine-readable
corpus, and `ethereum/tests` `ABITests/basic_abi_tests.json` holds three vectors.

## Regeneration

    python3 test/support/fixtures/ethers/vendor.py

The script downloads the tarball, **verifies it against the `Integrity` hash
above and aborts on a mismatch**, slims each corpus, applies the filter below,
and rewrites the four JSON files in place. It is deterministic: re-running it
leaves the working tree unchanged.

The integrity pin is what makes the corpus usable as an oracle. These vectors
define what "correct" means for the entire wire-format suite, so they are
verified rather than trusted: a registry compromise, a caching proxy that
rewrites the response, or a truncated transfer would otherwise regenerate a
corpus that silently redefines the expectations it exists to enforce.

## Filter criteria

The four upstream files hold ~7,800 vectors and ~42 MB uncompressed. The
vendored subset is 1,601 vectors and ~1.1 MB, produced by applying these rules
**in this order** (the order is part of the criterion — a later rule sees only
what earlier rules kept):

1. **Slim to the asserted fields.** Contract source, bytecode and runtime
   bytecode are dropped; only the type list, the input values, and the recorded
   expectation (`result`, `sigHash`, or `topics`/`data`) are kept, plus the
   event's own ABI item for `contract-events`.
   - `contract-interface` / `contract-interface-abi2` take `normalizedValues`
     when the upstream vector has them: the generator feeds values wider than
     the declared type and the contract truncates before returning, so
     `normalizedValues` is what `result` actually encodes.
   - `contract-events` takes `values`, **not** `normalizedValues` — the latter
     substitutes the topic hash for hashed indexed reference types, making it
     the decode-side expectation rather than an encodable input.
2. **Drop vectors carrying unpaired UTF-16 surrogates** in a string value.
   These do not survive a round trip through UTF-8 JSON and are a property of
   the corpus's random generator, not of the ABI.
3. **Drop any slimmed record over 4,096 bytes.** These are long-payload
   repetitions of shapes the smaller vectors already cover; the cap is what
   keeps the vendored files small.
4. **Keep every hand-written vector; take every 5th generated one.** Vectors
   named `random-*` are machine-generated; the rest (`sol-*`, `simple-*`,
   `string-indexed`, `array-2d`, …) are hand-written for a specific ABI feature
   and are all kept. Generated vectors are kept at `index rem 5 == 0` counting
   only generated vectors, in upstream corpus order.

No filtering is done on Solidity type: every type in all four upstream corpora
already lies inside hieroglyph's supported grammar (verified 2026-08-22 — the
corpora contain no `fixed`/`ufixed` and no `function` type).

## Vendored contents

| File | Vectors | Asserts |
|---|---|---|
| `contract-interface.json` | 443 | `ABI.encode/2` and `ABI.decode/3` vs the contract's returned ABI encoding |
| `contract-interface-abi2.json` | 368 | same, for ABI-coder-v2 shapes (nested tuples, `bytes[]`, `string[k]`) |
| `contract-signatures.json` | 376 | `ABI.method_id/1` vs `solc`'s 4-byte selector |
| `contract-events.json` | 414 | `ABI.encode_event_topics/2`, event `data`, and `ABI.decode_event/4` vs emitted logs |
