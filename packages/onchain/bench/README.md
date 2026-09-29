# Task 9031: production alloy ABI migration

Benchmarks are reporting only, per the operator's correction. There is no
performance stop condition. The production backend is active; the former
handwritten codecs survive only as namespaced benchmark oracles in `legacy/`.
`ABI.TypeEncoder` and `ABI.TypeDecoder` retain their documented API facades,
doctests and exception contracts. The yecc/leex grammar sources are removed.

## Production comparison

Measured 2026-09-29 on Linux / Intel Core Ultra 7 265, Elixir 1.20.4,
OTP 29.1, 20 schedulers, alloy-dyn-abi/alloy-json-abi 1.6.1, release Rust build.
Benchee: concurrency 1, warmup 1 second, runtime 3 seconds, memory 1 second.
No other tests/builds from this invocation ran during timing. Each job checks
exact equality against the legacy output before timing. Both sides receive
pre-parsed selectors; production schema resources and signatures are warm.

| Workload | Old ips | Alloy ips | Old bytes | Alloy bytes | Alloy / old time |
|---|---:|---:|---:|---:|---:|
| ERC-20 transfer encode | 421,009.87 | 405,604.02 | 4,392 | 576 | 1.038× |
| aggregate3 decode (500 results) | 4,012.62 | 1,275.66 | 656,912 | 1,841,818 | 3.146× |
| Transfer event decode (single log) | 665,166.14 | 708,264.17 | 2,688 | 2,360 | 0.939× |
| Transfer event decode (10000 logs) | 64.10 | 66.76 | 27,039,808 | 24,781,408 | 0.960× |
| nested tuple/array encode | 3,389.22 | 32,689.28 | 739,448 | 10,440 | 0.104× |

Memory is **BEAM process allocation**, excluding Rust heap allocation. Full
precision and deviations are in `results.json` and `benchmark-output.txt`.
The benchmark exited **0**. Timings have substantial variance on this shared host;
see the raw deviations rather than treating these means as universal speedups.

The one-shot type-rendering + fresh NIF-resource compilation measurements were:
ERC-20 **8 µs**, Transfer **12 µs**, aggregate3 **187 µs**, nested **9 µs**.
These wall-clock samples include the dirty-scheduler handoff, are not medians,
and exclude persistent-cache insertion/signature-cache population. The aggregate3
sample is reported unchanged rather than rerun to discard an outlier.

`prototype-results.json` / `prototype-output.txt` retain the earlier cached
prototype measurement (all workloads faster than legacy). The production
comparison above includes the compatibility checks that prototype lacked.

## Phase explanation

Separate diagnostic measurements average 1,000 instrumented native calls:

| Workload | Term decode µs | Alloy + preflight µs | Term encode µs |
|---|---:|---:|---:|
| ERC-20 transfer encode | 0.191 | 0.062 | 0.021 |
| Transfer event decode (single log) | 0.121 | 0.228 | 0.134 |
| aggregate3 decode (500 results) | 0.032 | 78.456 | 38.119 |
| nested tuple/array encode | 12.403 | 5.336 | 0.181 |

The aggregate3 workload is **3.146× slower** overall (783.9 µs versus 249.2 µs).
Its native phases sum to about **116.6 µs**: term input is negligible, alloy
plus allocation preflight takes 78.5 µs, and result conversion takes 38.1 µs.
Most total time therefore lies outside those native phases: Elixir's legacy
padding/length checks, offset normalization, shape rendering, cache lookup and
scheduler crossings. The 1.84 MB BEAM allocation supports the compatibility
walks/copies as the main optimization target; it is not evidence that alloy
itself costs 783.9 µs.

ERC-20 encoding is **1.038× slower** (2.465 µs versus 2.375 µs).
Its native phases are 0.191 µs input, 0.062 µs alloy and 0.021 µs output;
the rest includes facade normalization, cache lookup and dirty-scheduler handoff.
The 90 ns mean difference is small relative to the benchmark's variation.
The other three workloads are faster in this run. Instrumentation has its own
cost, so the phases are diagnostic rather than an exact decomposition of
Benchee's mean.

`compatibility-results.json` preserves an earlier production measurement.
The final run follows fixes preserving a body field named `__abi__topic` and
selecting the event scheduler from cached schema metadata, so dynamic events
also use one NIF crossing. It was rerun for code changes, not to seek a passing
performance threshold.
A useful follow-up is to consolidate compatibility validation/normalization
walks without changing strict errors or the captured oracle.

## Boundary and safety

The generic `ABI.Native.abi/3` boundary accepts operation/type-or-resource/value;
`compile/2` creates an immutable resource with parsed types and topic0.
Bounded `:persistent_term` caches retain schemas and signatures. Normal-scheduler
execution is reserved for small static events (32 nodes, 256 type bytes,
four topics, 4,096 data bytes); dynamic/bulk work uses dirty CPU schedulers.
Inputs have byte, nesting, expanded-schema and traversal budgets. Allocation
preflight runs before alloy decoding to bound aliased offsets and nested lengths.
Improper lists are walked without Rustler's panicking list iterator. All exported
NIF operations contain unwinding panics and return tagged errors.

`Cartouche.Filter` uses the real batch operation, grouping by topic and restoring
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
  probe pass: **570 checks** (152 doctests, 25 properties, 393 tests), with
  three pre-existing integration exclusions.
- All seven package VMs exit **0** after their focused tests and the common
  `bench/teardown_test.exs` resource-retention probe. Commands are recorded in
  `consumer-exits.json`. Counts: onchain 570, Aave 18, Aerodrome 77, EVM 133,
  JS 2, Solana 59, Tempo 16. This is scoped verification, not a claim of full QA.
- Aerodrome's existing types/decode fixture suites pass unchanged (77 checks).
- EVM's moved-infrastructure, Solidity and parameter checks pass (133 checks).
- `cargo clippy --locked --manifest-path native/onchain_abi/Cargo.toml --all-targets -- -D warnings`
  and `cargo fmt --check --manifest-path native/onchain_abi/Cargo.toml` pass.
- `mix compile --warnings-as-errors`, changed-file format checks,
  `mix hieroglyph.manifest --check`, generated AGENTS freshness and diff checks pass.
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
`../CLAUDE.md`. The changelog is deliberately untouched under harness policy.
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
