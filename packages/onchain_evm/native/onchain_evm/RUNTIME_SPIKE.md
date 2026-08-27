# Tokio per-call runtime construction spike

Date: 2026-08-22

**Decision: not worth doing.** Keep building a `current_thread` runtime per
`build_fork` call. Do not lazy-init or share one.

This spike changed no simulation behavior. `build_current_thread_runtime` is
the same `Builder::new_current_thread().enable_all().build()` sequence
`build_fork` already ran inline.

## Measurement

Archive node: `ETHEREUM_API_URL=http://localhost:8545` (tunneled reth), fork
block 20_000_000. Wall times are `Onchain.EVM.simulate_call/3` via the release
NIF, 5 samples after one warmup. Runtime construction is the exact helper
`build_fork` calls, 10_000 samples after 1_000 warmups, plus one cold first
build in a fresh process.

| Step | Profile | n | median | p99 | max | cold (first) |
|---|---|---|---|---|---|---|
| `build_current_thread_runtime` | release (NIF) | 10_000 | **1.0 µs** | 1.25 µs | 19 µs | 148 µs |
| `build_current_thread_runtime` | debug | 10_000 | 6.0 µs | 7.7 µs | 51 µs | 442 µs |

| `simulate_call` | calldata | median wall | min | max |
|---|---|---|---|---|
| Cheap | USDC `totalSupply()` | **2.906 s** | 2.519 s | 3.095 s |
| Expensive | Aave V3 `getUserAccountData` of `0x28C6c06298d514Db089934071355E5743bf21d60` | **4.079 s** | 3.689 s | 4.267 s |

Share of wall time, release-profile construction:

| Numerator | Cheap share | Expensive share |
|---|---|---|
| median 1.0 µs | **0.000034%** (1.0 µs / 2.906 s) | **0.000025%** (1.0 µs / 4.079 s) |
| cold 148 µs | 0.0051% | 0.0036% |
| 1 ms ceiling (the rust test's bound) | 0.034% | 0.025% |

The cheap/expensive gap is the extra JSON-RPC reads the Aave view issues.
Runtime construction does not grow with call cost.

A 100× faster node (no SSH tunnel, ~29 ms cheap call) would still see a
median share of 0.0034%. Construction is not a visible part of wall time.

## Why not share a runtime anyway

`WrapDatabaseAsync::with_runtime` **owns** the `tokio::runtime::Runtime`.
Every AlloyDB read then calls `Runtime::block_on` on that owned runtime
(`revm-database-interface` 42 `HandleOrRuntime::Runtime`).

The NIFs are `DirtyIo`, so concurrent `simulate_call`s run on different dirty
scheduler threads. Sharing one `current_thread` runtime across those threads
means several of them drive the same single-threaded reactor via `block_on`.
Tokio's current-thread runtime is not a concurrent executor: that either
serializes the simulations or panics when a second thread tries to enter.
A microsecond save is not worth a throughput regression.

A design that would *not* serialize is a different proposal: a
`new_multi_thread` runtime plus `WrapDatabaseAsync::with_handle` on cloned
`Handle`s. The measurement says that work is not justified.

## Reproduction

```text
cargo test --release --manifest-path native/onchain_evm/Cargo.toml \
  current_thread_runtime_construction_is_sub_millisecond -- --nocapture

mix test.json --only tokio_runtime test/onchain/evm_integration_test.exs
```
