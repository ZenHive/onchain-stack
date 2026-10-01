# Task 9031: production alloy ABI migration

The production backend is active. The former handwritten codecs survive only as
namespaced benchmark oracles in `legacy/`. `Onchain.ABI.TypeEncoder` and
`Onchain.ABI.TypeDecoder` retain their documented API facades, doctests and exception
contracts. The yecc/leex grammar sources are removed. `bench/abi.exs` exits
non-zero when any workload's mean is more than 2× the legacy mean.

## Production comparison

Measured 2026-09-29 on Linux / Intel Core Ultra 7 265, Elixir 1.20.4,
OTP 29.1, 20 schedulers, alloy-dyn-abi/alloy-json-abi 1.6.1, release Rust build.
Benchee: concurrency 1, warmup 1 second, runtime 3 seconds, memory 1 second.
Each job checks exact equality against the legacy output before timing. Both
sides receive pre-parsed selectors; production schema resources and signatures
are warm. Canonical decode payloads skip the declaration-order offset rewrite.

| Workload | Old ips | Alloy ips | Old bytes | Alloy bytes | Alloy / old time |
|---|---:|---:|---:|---:|---:|
| ERC-20 transfer encode | 354,746.41 | 355,983.55 | 4,392 | 576 | 0.997× |
| aggregate3 decode (500 results) | 3,013.10 | 2,283.34 | 656,912 | 708,776 | 1.320× |
| Transfer event decode (single log) | 372,659.57 | 508,921.21 | 2,688 | 1,704 | 0.732× |
| Transfer event decode (10000 logs) | 27.62 | 60.66 | 27,039,808 | 18,857,392 | 0.455× |
| nested tuple/array encode | 3,458.72 | 27,618.17 | 739,448 | 10,440 | 0.125× |

Memory is **BEAM process allocation**, excluding Rust heap allocation. Full
precision and deviations are in `results.json` and `benchmark-output.txt`.
The benchmark exited **0**. Means are the gate. This host is noisy (aggregate3
deviation ±68% alloy / ±165% old); aggregate3 medians are 374 µs versus 220 µs
(1.70×), still inside the gate.

The one-shot type-rendering + fresh NIF-resource compilation measurements were:
ERC-20 **861 µs**, Transfer **11 µs**, aggregate3 **5 µs**, nested **5 µs**.
These are single samples, include the dirty-scheduler handoff, and exclude
persistent-cache insertion. The ERC-20 sample is an outlier, not a median.

`prototype-results.json` / `prototype-output.txt` retain the earlier cached
prototype measurement. `compatibility-results.json` retains the production
measurement from before canonical payloads skipped the offset rewrite
(aggregate3 at 3.146×). The table above is the current code.

## Phase explanation

Separate diagnostic measurements average 1,000 instrumented native calls:

| Workload | Term decode µs | Alloy + preflight µs | Term encode µs |
|---|---:|---:|---:|
| ERC-20 transfer encode | 0.196 | 0.066 | 0.028 |
| Transfer event decode (single log) | 0.432 | 0.232 | 0.239 |
| aggregate3 decode (500 results) | 0.037 | 81.193 | 37.690 |
| nested tuple/array encode | 12.670 | 5.802 | 0.256 |

Aggregate3 is **1.320× slower** on the mean (438.0 µs versus 331.9 µs). Its
native phases sum to about **118.9 µs**. The rest is Elixir validation, result
rendering, cache lookup and the dirty-scheduler handoff. Instrumentation has
its own cost, so the phases are diagnostic rather than an exact decomposition
of Benchee's mean.

## Boundary and safety

The generic `Onchain.ABI.Native.abi/3` boundary accepts operation/type-or-resource/value;
`compile/2` creates an immutable resource with parsed types and topic0.
Bounded `:persistent_term` caches retain schemas and signatures. Normal-scheduler
execution is reserved for small static events (32 nodes, 256 type bytes,
four topics, 4,096 data bytes); dynamic/bulk work uses dirty CPU schedulers.
Inputs have byte, nesting, expanded-schema and traversal budgets. Allocation
preflight runs before alloy decoding to bound aliased offsets and nested lengths.
Improper lists are walked without Rustler's panicking list iterator. All exported
NIF operations contain unwinding panics and return tagged errors.

`Onchain.Filter` uses the real batch operation, grouping by topic and restoring
original log order. Batches return per-log outcomes. Facade validation retains
strict violations and legacy permissive offset behavior. Reference topics,
anonymous events, named structs, raw top-level encoding, zero-width arrays and
Solidity packed-array padding are covered by the existing tests.

## Oracle and differential checks

The unchanged fixture `test/support/fixtures/abi_before_alloy.etf` was imported
from `f19602a5` (only `packages/onchain` paths). It records **17,352 distinct
calls/outcomes**, including all four vendored ethers.js corpora, against the
pre-migration implementation. SHA-256:
`05292fe2d6247087ed582345004ec18fe2d53d5401ebf93d60ee9232f67ede2d`.
The production replay is green. Existing ABI tests were not modified.
The original fixture provenance/licenses remain under `test/support/fixtures/ethers`.

`legacy/` preserves pre-migration ABI, event, encoder and decoder bodies with
module/alias names changed (and alias formatting). It uses the unchanged
FunctionSelector representation; selector parsing is outside timed workloads.
The captured fixture, not recapture from the migrated backend, remains the oracle.
New malformed-input differentials compare truncated words, invalid bools, bad
offsets, oversized lengths, wrong-length packed addresses, and encoding arity
errors. Native properties exercise malformed types/values/payloads and resources.

## Verification

- Focused core suite, fixture replay, new properties, filter tests and shutdown
  probe pass: **571 checks** (152 doctests, 25 properties, 394 tests), with
  three pre-existing integration exclusions.
- An earlier consumer sweep (`consumer-exits.json`) exited 0: onchain 570,
  Aave 18, Aerodrome 77, EVM 133, JS 2, Solana 59, Tempo 16. Scoped verification,
  not full QA. The onchain count above is the later rerun.
- Aerodrome's existing types/decode fixture suites pass unchanged (77 checks).
- EVM's moved-infrastructure, Solidity and parameter checks pass (133 checks).
- `cargo clippy --locked --manifest-path native/onchain_abi/Cargo.toml --all-targets -- -D warnings`
  and `cargo fmt --check --manifest-path native/onchain_abi/Cargo.toml` pass.
- `mix compile --warnings-as-errors`, changed-file format checks,
  `mix onchain.manifest --check`, generated AGENTS freshness and diff checks pass.
- Five real cross-builds pass: aarch64/x86_64 Darwin, aarch64/x86_64 GNU/Linux,
  x86_64 musl. See `precompiled-build.json` for exact checksums/source hash.
  Only the host GNU/Linux artifact was executed here. The cross-builder used
  Zig 0.14.1 / cargo-zigbuild 0.23.4; musl requires `-crt-static` for a shared NIF.
- `ONCHAIN_PUBLISH=1 mix hex.build` exits 0, includes the five-target checksum
  file and Rust sources, and excludes no declared dependencies.
- A fresh project compiled the unpacked Hex tarball and encoded calldata with
  Cargo absent from PATH, using a local checksum-verified artifact cache; all
  three commands exit 0 (`cargo-free.json`). **No release assets were uploaded**;
  a fresh remote-download check must be repeated after the operator publishes
  those exact artifacts. Consumers cannot download an unpublished release.

Native artifacts are under `artifacts/precompiled/release/` (ignored build output).
Publish commands and the cargo-free consumer procedure are documented in
`../CLAUDE.md`.
No full suite, coverage or general analyzers were run; full post-merge QA remains
separate, and this repository has no automatic CI runner.

## Reproduction

From `packages/onchain`:

```sh
mix deps.get
ONCHAIN_BUILD=1 mix compile --force
mix run --no-start bench/abi.exs
ONCHAIN_BUILD=1 MIX_ENV=test mix compile --force
mix test test/abi test/abi_test.exs test/abi_regression_test.exs test/filter_test.exs bench/teardown_test.exs
cargo clippy --locked --manifest-path native/onchain_abi/Cargo.toml --all-targets -- -D warnings
```

After locally building precompiled artifacts, point
`RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH` at their directory when testing without
force-build. The release URL is not populated by this implementation session.

## Task 9032: alloy transactions and EIP-712

`transactions-before.json` records the handwritten encoder at
`2b2eb421a7fbe653737bfacaf25d39127638f8ee`, before deletion.
`transactions-after.json` records the replacement in this worktree;
`transactions-outcome.json` pins its source hashes and verification commands.
Both runs used the same machine/toolchain above, with Benchee concurrency 1,
1 s warmup, 3 s runtime and 1 s memory measurement. Ips below is the reciprocal
of median runtime. All four workloads regressed; performance is reporting-only
per the operator decision. BEAM memory excludes NIF allocations.

| Workload | Before median ips | After median ips | Before BEAM bytes | After BEAM bytes | Slowdown |
|---|---:|---:|---:|---:|---:|
| EIP-1559 encode + signing hash | 458,715.60 | 74,079.56 | 3,880 | 9,992 | 6.19× |
| EIP-712 permit hash | 129,651.24 | 53,341.87 | 10,488 | 18,296 | 2.43× |
| EIP-7702 encode + signing hash | 275,027.50 | 47,657.63 | 6,424 | 15,208 | 5.77× |
| raw-tx decode | 2,036,659.88 | 106,462.26 | 3,288 | 5,840 | 19.13× |

Reproduce with `ONCHAIN_BUILD=1 MIX_ENV=test mix run --no-start
bench/transactions.exs after`. Run `mix deps.compile benchee deep_merge statistex`
in the dev environment first; the script loads only those benchmark dependencies
from the dev build. The before run used the same workloads and frozen external
transaction vectors. Its first measurement completed but failed to write JSON
because of an outdated Benchee field name; the recorded baseline is the corrected
rerun, still before encoder deletion.

`capture_transactions.exs` is only for the old revision. It captured 3,614 calls
from the transaction, typed-data, vector/property and signing tests. The replay
checks 1,775 codec calls: 536 unchanged outcomes and 1,239 explicit new negative
cases (618 oversized encode/hash inputs, 620 decode rejections including
noncanonical scalars, and one EIP-4844 empty destination). It also checks bytes,
hashes and round trips for the captured encode calls. No frozen record was
deleted. The property suite now exercises u64/u128 field boundaries and rejects
negative/oversized values without truncation. EIP-7702 authorization chain IDs
and transaction amounts retain their protocol-defined U256 width.

Focused signer coverage is 96% with the same source-line accounting as
`ExUnitJSON.Coverage`; see `transaction-signer-coverage.json` and
`signing_coverage.exs`. Four live Sepolia tests passed, including two successful
self-transfers; the compact result is in `transaction-live-signing.json`. Full
post-merge QA has not run.

Alloy's typed-data resolver requires acyclic schemas for hashing. The existing
`encode_type/2` formatter still supports recursive schema descriptions, but
finite recursive-value hashing remains a follow-up compatibility issue. The
existing Mail, bytesN, signed-integer and array-of-struct conformance tests pass.

## Task 9048: transaction and EIP-712 term boundary

The consensus NIF now accepts BEAM maps/lists and returns decoded maps directly.
The bounded converter in `native/onchain_abi/src/consensus_term.rs` creates alloy's
serde values without encoding or parsing JSON text. RPC-shaped field normalization
and alloy's transaction/EIP-712 codecs remain unchanged. Signed-envelope decoding
also avoids serializing an unused transaction hash. Recursive hashing is unchanged.

Conversion stays on dirty CPU schedulers and inside the panic boundary, with limits
of 64 nesting levels, 100,000 nodes (including map keys), and 16 MiB of aggregate
string bytes (including keys). Invalid terms return error tuples. Wide EVM integers
still cross as lossless decimal/hex strings.

Both runs below used this session's machine: Intel Core Ultra 7 265, Linux x86_64,
Elixir 1.20.4 / OTP 29.1, 20 schedulers, Rust 1.98.0 release builds, MIX_ENV=dev,
Benchee 1.5.1 with concurrency 1, 1 s warmup, 3 s runtime, and 1 s memory time.
The baseline is the JSON boundary at `3c01c00f0960096cf9d80632238749d8e82130fc`.

| Workload | JSON median ips | Term median ips | JSON BEAM bytes | Term BEAM bytes | Speedup |
|---|---:|---:|---:|---:|---:|
| EIP-1559 encode + signing hash | 74,085 | 90,514 | 10,160 | 4,032 | 1.22× |
| EIP-712 permit hash | 48,709 | 53,519 | 18,296 | 10,152 | 1.10× |
| EIP-7702 encode + signing hash | 47,762 | 60,419 | 15,488 | 6,000 | 1.26× |
| raw-tx decode | 109,613 | 120,192 | 5,840 | 4,896 | 1.10× |

Performance remains reporting-only. BEAM memory does not include native allocations,
and these gains do not recover the historical pre-alloy throughput. The raw records
are `transactions-boundary-before.json` and `transactions-boundary-after.json`;
`transactions-outcome.json` → `boundary_replacement` records source hashes, commands,
limits, and verification. The original task 9032 evidence is retained separately.

To reproduce, compile each corresponding source revision with
`ONCHAIN_BUILD=1 mix compile --warnings-as-errors`, then run:

```sh
ONCHAIN_BUILD=1 mix run --no-compile --no-start bench/transactions.exs boundary-before
ONCHAIN_BUILD=1 mix run --no-compile --no-start bench/transactions.exs boundary-after
```

The baseline uses the updated benchmark script with the original JSON NIF sources;
both labels run identical native workloads. The `before` label remains reserved for
the old handwritten implementation. Focused verification passed 357 checks, including
the unchanged frozen fixture, integer-bound error contracts, malformed-term limits,
signing and VM shutdown; four live Sepolia integration tests also passed. Full QA
and coverage remain separate post-merge work.
