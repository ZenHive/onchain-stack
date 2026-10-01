# Core ABI NIF boundary

Rules for `ABI.Native` (`packages/onchain/native/onchain_abi`) and the
`ABI.*` facades over it, as shipped by task 9031. Every rule holds on `main`
today and has an existing test. Each rule's source follows it.

NIF-1: Every entry into the core ABI NIF catches unwinding panics; malformed types, values or payloads return an error tuple and never crash the VM.
  Source: task 9031 (acceptance criteria, "Safety"); packages/onchain/CLAUDE.md § Core ABI native build.

NIF-2: Inputs are bounded before alloy allocates: type strings to 4,096 bytes and 64 nesting markers, payloads to 16 MiB, traversal and conversion to 100,000 nodes, and batches to 10,000 logs sharing one output-node budget.
  Source: packages/onchain/CLAUDE.md § Core ABI native build.

NIF-3: Normal-scheduler NIF work is limited to events with static schemas of at most 32 nodes and 256 type bytes, four topics and 4,096 data bytes; all other work runs on dirty CPU schedulers.
  Source: task 9031 body; packages/onchain/CLAUDE.md § Core ABI native build.

NIF-4: The alloy-backed `ABI.*` API reproduces the pre-migration implementation over the committed oracle fixture `test/support/fixtures/abi_before_alloy.etf` (identical return values and exception reasons), and no `ABI.*` public signature changed.
  Source: task 9031 (acceptance criteria 1-2).

NIF-5: `strict: true` returns `{:error, {:strict_violation, _}}` or raises `ABI.TypeDecoder.StrictViolation` for dirty padding, trailing bytes and over-long length prefixes, with the same accept/reject outcome as the pre-alloy strict decoder, non-canonical offsets included.
  Source: task 9031 (acceptance criterion on strict); packages/onchain/CLAUDE.md (`ABI.Validation`).

NIF-6: `fixed`/`ufixed` types, bare, `MxN` and nested, are rejected with an explicit error.
  Source: task 9031 (acceptance criterion on fixed/ufixed); packages/onchain/CLAUDE.md.

NIF-7: Parsed schemas and signature hashes are cached under separate `:persistent_term` keys, each cache holding at most 1,024 entries; misses beyond the bound compile without retention.
  Source: packages/onchain/lib/abi/alloy.ex (commit 66af428); packages/onchain/CLAUDE.md.
  Tests: `packages/onchain/test/abi/alloy_cache_test.exs` covers separate keys, concurrent inserts (including event schemas), and the signature cache's 1,024-entry cap with continued answers after overflow.
