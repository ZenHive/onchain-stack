# State reads: observed mainnet portability (2026-10-01)

Authority: [execution-apis v1.0.0-beta.7](https://github.com/ethereum/execution-apis/tree/v1.0.0-beta.7),
the vendored OpenRPC schema, [EIP-1186](https://eips.ethereum.org/EIPS/eip-1186),
and the live responses below. Spec residency does not guarantee historical availability.

DAI: `0x6b175474e89094c44da98b954eedeac495271d0f`, storage slot 1.
The archive endpoint was selected by `ETHEREUM_API_URL`; the hosted endpoint by
`ETHEREUM_ALCHEMY_URL`. URLs and credentials are deliberately omitted.
All recorded requests returned HTTP 200. Full request/response JSON, including
unaltered proof nodes, is in [`test/fixtures/state_reads`](../test/fixtures/state_reads).
Only JSON whitespace has been normalized.

| Request | Archive node | Alchemy mainnet |
| --- | --- | --- |
| `eth_getStorageAt`, block 18,000,000 (`0x112a880`) | Recorded word below | Same word |
| `eth_getStorageAt`, block 1 | Zero word | Zero word |
| `eth_getProof`, latest | DAI proof: balance 0, nonce 1, nonzero slot 1 | Same domain fields |
| `eth_getProof`, block 18,000,000 | Proof-window refusal below | Full account and slot proof |
| `eth_getProof`, block 1 | Proof-window refusal below | Non-existent account: balance/nonce/value zero, empty storage proof nodes |
| `eth_getStorageAt`, future block `0xffffffffffffffff` | Block-not-found below | Same refusal |
| `eth_getProof`, future block `0xffffffffffffffff` | Block-not-found below | Blocknumber-too-high below |

Historical storage result, verbatim:

```json
{"jsonrpc":"2.0","id":1,"result":"0x00000000000000000000000000000000000000000c989643a2d611a5d119644b"}
```

Refusals, verbatim:

```json
{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"distance to target block exceeds maximum proof window"}}
{"jsonrpc":"2.0","id":1,"error":{"code":-32001,"message":"block not found: 0xffffffffffffffff"}}
{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"invalid argument 2: blocknumber too high"}}
```

The shared transport preserves these answers as raw `%{code: ..., message: ...}`
error maps. A `-32001` code alone does not establish a provider-capability refusal.
Alchemy served deep history in this probe; it did not refuse or truncate the
block-18,000,000 proof. The archive node's historical proof window was more
restrictive. No universal hosted retention limit can be inferred from this run.
Empty storage proof nodes before contract deployment are not evidence of truncation.

Reproduce through the task-2136 seam (explicit configuration required):

```sh
export CARTOUCHE_LIVE_NODE_URL='http://127.0.0.1:8545'
export ETHEREUM_ALCHEMY_URL='https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY'
cd packages/onchain
mix test test/rpc_state_reads_live_test.exs --include integration
```

`Cartouche.RPC.eth_get_proof/3` replaces `Onchain.RPC.get_proof/3` and its bang
variant. Proof fields now use bytes and integers, with `Proof.StorageProof`
entries. `Cartouche.RPC.eth_get_storage_at/3` returns a 32-byte binary;
`Onchain.Trace.storage_at/3` retains its hex-string result through delegation.
Both accept `:block` (default `"latest"`) and shared transport options.
