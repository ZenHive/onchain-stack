# Base fee consolidation — Task 2127

## Decision (2026-10-01)

Keep `Cartouche.RPC.base_fee/1`, implemented with
`eth_feeHistory("0x1", "latest", [])`, taking the final `baseFeePerGas` entry
through the existing `Cartouche.FeeHistory` decoder and shared transport.
Remove `Onchain.RPC.base_fee/1` and its bang wrapper. Callers wanting a mined
or historical block's fee should read that block's `base_fee_per_gas`.
The surviving wrapper always returns the next block's fee.

This is preferable to the pending header because providers may refuse `pending`
or treat it as `latest`. Both probed hosted providers currently returned a real
pending header, but fee history avoids depending on that behavior. `eth_baseFee`
is refused by both providers, so it cannot be the portable implementation.

The [tagged v1.0.0-beta.7 fee-market schema](https://github.com/ethereum/execution-apis/blob/v1.0.0-beta.7/src/eth/fee_market.yaml)
was read during implementation: its `baseFeePerGas` array includes the fee for
the next block after the newest returned block. `eth_baseFee` merged to
[main on 2026-06-15 (#795)](https://github.com/ethereum/execution-apis/pull/795)
and is in no tagged release per the task's release audit (latest beta.7).
The attempt to independently refresh GitHub's latest-release metadata returned
HTTP 404; the release-status statement relies on that supplied audit.

## Live observations

Read-only JSON-RPC batches on 2026-10-01 used the existing environment URLs;
no credentials are recorded here. Every endpoint returned `eth_chainId = "0x1"`.

`ETHEREUM_ALCHEMY_URL`, exact `eth_baseFee` error:

```json
{"code":-32600,"message":"eth_baseFee is not available on the ETH_MAINNET. For more information see our docs: https://docs.alchemy.com/alchemy/documentation/apis/ethereum"}
```

`ETHEREUM_INFURA_URL`, exact `eth_baseFee` error:

```json
{"code":-32601,"message":"The method eth_baseFee does not exist/is not available"}
```

For both providers, fee history returned `oldestBlock = "0x18e2a28"` and
`baseFeePerGas = ["0x42043a9", "0x4001897"]`; the pending header returned
`number = "0x18e2a29"`, `baseFeePerGas = "0x4001897"`.

On the archive endpoint (`ETHEREUM_API_URL`), one batch containing all three
constructions returned `eth_baseFee = "0x4001897"`, fee history's final entry
`"0x4001897"`, and pending header `baseFeePerGas = "0x4001897"`.
The batch checks agreement without comparing independent HTTP requests across
heads. JSON-RPC batching itself does not guarantee an atomic snapshot on every
server; an actual differing head will fail the equality assertion visibly.

## Regression checks

`rpc_portability_test.exs` pins both exact refusals through `send_rpc/3` and
requires the portable wrapper to succeed on archive, Alchemy and Infura. The
existing named-endpoint helper flunks with export instructions when a hosted
URL is missing. `rpc_integration_test.exs` compares fee history and
`eth_baseFee` in one batch and checks the wrapper against the EIP-1559 update
rule. Unit tests pin the fixed wire parameters, final-entry selection, zero,
incomplete windows, and upstream error propagation. The old guessed Infura
fixture is now backed by the observation above and exercises the raw method.

```sh
cd packages/onchain
mix test test/rpc_test.exs test/onchain/rpc_test.exs test/live_test.exs
CARTOUCHE_LIVE_NODE_URL="$ETHEREUM_API_URL" mix test --include integration test/rpc_portability_test.exs
CARTOUCHE_LIVE_NODE_URL="$ETHEREUM_API_URL" mix test --only base_fee_portability test/rpc_integration_test.exs
mix check.dispatch
```

Harness prohibits changelog edits in implementer worktrees. This note carries
the decision and evidence for the release changelog without editing that file.

Verification on the implementation revision:

- Focused unit suite above: 261 passed (73 doctests, 188 tests), exit 0.
- Hosted portability suite: 2 passed, exit 0; archive, Alchemy and Infura exercised.
- Tagged batch/calculation tests: 2 passed, 36 unrelated tests excluded, exit 0.
- `mix check.dispatch`: exit 0 (format check and compile with warnings as errors).
- `git diff --check`: exit 0.

Initial live-test failures exposed a raw-hex/integer expectation mismatch and
an incorrect batch function name in the new tests; both were corrected before
the passing runs above. No full `mix ci` was run; it belongs to post-merge QA.
