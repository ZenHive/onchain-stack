# RPC consolidation for 0.16.0 (Task 9035)

`Cartouche.RPC` owns the implementations. `Onchain.RPC` contains only
`defdelegate` compatibility aliases; Task 9036 can remove that file before
renaming the owner. `Onchain.RPC.Helpers`, `.Specs`, and `.Codegen` retain
their namespaces until that migration. All runtime callers in `packages/*/lib`
use the owner directly.

## Breaking release notes for the harness changelog writer

Harness owns changelog updates. The following is the complete 0.16.0 entry
for this task; no changelog or roadmap file is edited here.

The implementations of these `Onchain.RPC` functions are removed (their
aliases remain temporarily). Default-option arities and every `!` variant
move with them:

| Former function | Owner / implementation |
| --- | --- |
| `eth_call/2,3` | `Cartouche.RPC.eth_call/2,3` adapts to `call_trx/1,2` |
| `eth_estimate_gas/1,2` | `Cartouche.RPC.eth_estimate_gas/1,2` adapts to `estimate_gas/1,2` |
| `eth_send_raw_transaction/1,2` | `Cartouche.RPC.eth_send_raw_transaction/1,2` adapts to `send_trx/1,2` |
| `get_balance/1,2` | `Cartouche.RPC.get_balance/1,2` |
| `block_number/0,1` | `Cartouche.RPC.block_number/0,1` aliases `eth_block_number/0,1` |
| `chain_id/0,1` | `Cartouche.RPC.chain_id/0,1` aliases `eth_chain_id/0,1` |
| `get_block_by_number/1,2` | `Cartouche.RPC.get_block_by_number/1,2` |
| `get_transaction_receipt/1,2` | `Cartouche.RPC.get_transaction_receipt/1,2` adapts to `get_trx_receipt/1,2` |
| `get_transaction_count/1,2` | `Cartouche.RPC.get_transaction_count/1,2`; `get_nonce/1,2` also delegates here |
| `eth_get_code/1,2` | `Cartouche.RPC.eth_get_code/1,2` adapts to `get_code/1,2` |
| `fee_history/1,2` | `Cartouche.RPC.fee_history/1,2`; count/options forms share the options implementation |
| `blob_base_fee/0,1` | `Cartouche.RPC.blob_base_fee/0,1` |

`get_block_access_list/1,2` and its bang variant, `call/2,3` and its bang
variant, and `batch/1,2` move unchanged. Those aliases also remain in
`Onchain.RPC`. There are no other function bodies there.

Return changes:

- Block reads return `%Cartouche.Block{}` instead of an atom-keyed map.
  Hashes, roots, bloom, miner, extra data, and uncle hashes are binary;
  nonce is an integer. Withdrawals are `%Cartouche.Block.Withdrawal{}` with
  binary addresses. Transaction hashes remain hex strings; requested full
  transactions use Cartouche transaction structs. `requests_hash` is retained.
- Receipt reads return `%Cartouche.Receipt{}` instead of a map. Hashes and
  addresses are binary; the richer shape includes `logs_bloom`, `blob_gas_used`,
  and `blob_gas_price`. Pending/unknown receipts still return `{:ok, nil}`.
- Receipt and subscription logs now share `%Cartouche.Filter.Log{}` with
  filter queries. Addresses, data, hashes, and topics are binary. Block hash
  and `extra_data` are present. Missing `removed` is nil (formerly false);
  pending location fields may be absent or null and decode to nil.
- Shared direct wrappers (`get_balance`, `block_number`, `chain_id`,
  `get_transaction_count`, `get_block_by_number`, `blob_base_fee`) retain
  Cartouche's native unclassified error shapes instead of the former Onchain
  `{:rpc_error, map}` envelope. Classified node refusals remain tagged.
  Hex-input adapters keep their previous error envelopes and hex outputs.
- Fee-history integer counts are encoded as JSON-RPC hex quantities; the
  Cartouche options form retains its empty-percentile default and accepts
  existing hex counts. The count/options adapter retains its `[50]` default
  and validation.

`Cartouche.RPC.DSL.defrpc/3` is removed. Every declaration now uses
`Onchain.RPC.Codegen.defrpc/2` with `method: ...`, checked against
`lib/onchain/rpc/specs.ex`. Optional documentation metadata preserves the
former Cartouche Descripex entries. `defrpc_bang/2` remains the single bang
convention: unwrap success, including nil; raise `RuntimeError` with the
function name and inspected error on failure.

The duplicate receipt parser and `Onchain.RPC.Helpers.parse_log/1` are
removed. Tests from both RPC surfaces exercise the owner, with the old test
paths retained to preserve their history. Live differential tests compare
against independently decoded wire responses rather than a second wrapper.

## Review handoff and verification

Acceptance coverage: all twelve RPC operations have one wire implementation
in Cartouche; callers and both former test surfaces target that owner. There
is one spec-checked `defrpc/2`; bang behavior is documented and tested.
Onchain contains delegates only. Logs share the canonical decoder, including
pending locations. Breaking release notes are above for harness to copy into
the changelog. The namespace rename is not performed.

Checks run on 2026-10-01 from each named package directory:

| Package | Command | Result |
| --- | --- | --- |
| onchain | Focused `mix test` command below | 532 passed, 3 integration tests excluded by the existing default |
| onchain | `mix test test/descripex_validation_test.exs test/onchain/rpc_codegen_test.exs test/onchain/rpc_merge_test.exs` | 16 passed |
| onchain_aave | `mix test test/onchain/aave/pool_test.exs test/onchain/aave/debt_token_test.exs test/onchain/aave/ui_pool_data_provider_test.exs` | 98 passed |
| onchain_aerodrome | `mix test test/onchain/aerodrome/bindings/lp_sugar_test.exs test/onchain/aerodrome/bindings/abi_test.exs` | 27 passed |
| onchain_tempo | `mix test test/onchain/tempo/transaction/builder_test.exs test/onchain/tempo/rpc_test.exs` | 46 passed |
| onchain_evm | `mix test test/onchain/trace_test.exs test/onchain/evm/params_test.exs` | 77 passed |
| onchain_solana | `mix test test/solana/rpc_test.exs test/solana/token_test.exs` | 60 passed |
| onchain_js | `mix test test/onchain_js/runtime_test.exs --include integration` | 6 passed |

`mix check.dispatch` passed in every touched package: onchain, onchain_aave,
onchain_aerodrome, and onchain_tempo. These aliases were inspected: they run
format verification and compilation with warnings as errors, not full QA.
Changed files were formatted, with final format checks passing. `mix deps.get`
restored the locked local dependencies; no lockfiles changed.

The core focused command was:

```sh
mix test test/rpc_test.exs test/rpc_transport_test.exs \
  test/rpc_transaction_reads_test.exs test/rpc_state_reads_test.exs \
  test/rpc_node_introspection_test.exs test/onchain/rpc_test.exs \
  test/onchain/rpc_merge_test.exs test/onchain/rpc_block_reads_test.exs \
  test/onchain/rpc_estimate_gas_test.exs test/onchain/rpc_codegen_test.exs \
  test/onchain/rpc_batch_test.exs test/onchain/rpc_revert_test.exs \
  test/onchain/rpc_retry_test.exs test/onchain/rpc_telemetry_test.exs \
  test/onchain/rpc_node_refusal_test.exs \
  test/onchain/subscription/parser_test.exs test/onchain/subscription_test.exs \
  test/block_test.exs test/receipt_test.exs test/filter_test.exs \
  test/onchain/fees_test.exs test/onchain/wallet_test.exs \
  test/onchain/contract_test.exs test/onchain/ens_test.exs \
  test/onchain/rpc/helpers_test.exs test/onchain/rpc/specs_test.exs
```

Live archive verification:

```sh
ONCHAIN_DIFFERENTIAL_TESTS=1 mix test \
  test/onchain/differential/rpc_cartouche_test.exs --include differential
```

All 15 passed against the configured archive endpoint, using independently
decoded wire results. No live transactions were submitted.

The hosted Alchemy run of that differential file plus
`rpc/receipt_integration_test.exs`, `rpc/transaction_count_integration_test.exs`,
and `rpc/code_integration_test.exs` used `--include integration --include
differential`, with `ETHEREUM_API_URL` set to `ETHEREUM_ALCHEMY_URL`.
It passed 29 of 31: historical fee history returned the documented
`{:unavailable, %{code: -32001, ...}}`, and one historical balance comparison
mismatched. A targeted repeat of the balance test passed; its initial mismatch
is not treated as a clean first run. The archive differential run above passed
both cases. No tests were skipped or weakened to accommodate hosted refusals.

Full `mix ci`, coverage, and analyzers were not run: they remain the separate
post-merge QA responsibility. No automatic QA result is implied.
