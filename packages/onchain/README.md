# Onchain

Pure Elixir Ethereum library. Provides read (`eth_call`) and write (transaction signing) capabilities using [`cartouche`](https://hex.pm/packages/cartouche) as the sole Ethereum dependency. No native deps, no Rustler.

## Package Family

| Package | Purpose | Deps |
|---------|---------|------|
| **onchain** (this) | Core Ethereum primitives, RPC, ABI, signing | cartouche |
| [onchain_aave](https://github.com/ZenHive/onchain_aave) | Aave V3 protocol wrappers | onchain |
| [onchain_evm](https://github.com/ZenHive/onchain_evm) | Rust NIFs: revm simulation, Solidity parsing, codegen | onchain + rustler |
| [onchain_js](https://github.com/ZenHive/onchain_js) | JS bridge: npm packages on the BEAM via QuickBEAM | onchain + quickbeam |
| [onchain_tempo](https://github.com/ZenHive/onchain_tempo) | Tempo chain primitives: 0x76 transactions, TIP-20 encoding | onchain |

Pick what you need — consumers who only need `eth_call` never compile Rust or Zig.

## Installation

```elixir
def deps do
  [
    {:onchain, "~> 0.7"},
    # Add if you need Aave:
    {:onchain_aave, "~> 0.1"},
    # Add if you need EVM simulation / Solidity parsing:
    {:onchain_evm, "~> 0.1"},
    # Add if you need JS bridge (solc-js, Uniswap SDK, etc.):
    {:onchain_js, "~> 0.1"},
    # Add if you need Tempo chain (0x76 transactions, TIP-20 tokens):
    {:onchain_tempo, "~> 0.1"}
  ]
end
```

Requires an Ethereum JSON-RPC endpoint. Configure via:

```elixir
# config/config.exs
config :cartouche, :ethereum_node, "https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
```

Or pass the URL per-call to `Onchain.RPC` functions.

## Node compatibility

Onchain is built to run against **any** mainstream Ethereum JSON-RPC endpoint — Alchemy,
Infura, QuickNode, a self-hosted Geth/reth/Erigon, pruned or archive. That portability is
a deliberate constraint, not an accident: the maintainers develop against a full archive
node, and anything that only works there is treated as a bug.

Everything in `Onchain.RPC`, `Onchain.ERC20`, `Onchain.ERC721`, `Onchain.ERC1155`,
`Onchain.Contract`, `Onchain.Log`, `Onchain.Block`, `Onchain.Multicall` and `Onchain.ENS`
uses standard methods and needs no special endpoint. These surfaces depend on what
your provider serves:

| Surface | Requirement | Symptom without it |
| --- | --- | --- |
| Historical reads — any `block` parameter older than ~128 blocks (`eth_call`, `eth_getBalance`, `eth_getProof`, `eth_feeHistory` at an old block) | an **archive** node, or a hosted plan that retains history | `{:error, {:unavailable, map}}` (`-32001 Unable to complete request` on Alchemy), or a "missing trie node" error, depending on client |
| `Onchain.Subscription` (`eth_subscribe`) | a **WebSocket** endpoint (`wss://`), which not every plan includes | connection refused, or `{:error, {:method_not_found, map}}` over HTTP |
| `trace_*` / `debug_*` on a free hosted plan | a plan that serves that namespace | `{:error, {:namespace_unavailable, map}}` (Alchemy: `-32600` "...not available on the Free tier") |
| Methods the node does not implement (`eth_getBlockAccessList`, `eth_baseFee`, …) | a node that serves them, or a portable construction (`base_fee/1` reads the block header instead of `eth_baseFee`) | `{:error, {:method_not_found, map}}` |

Each of those error terms is classified on the shared `Onchain.RPC` result path
so a codegen'd wrapper, a hand-written wrapper, `call/3` and `batch/2` apply the
same rules to the same wire response. Note that a provider may not send the same
wire response in both modes — Alchemy reports pruned history as `-32001` to a
single call but as a generic `-32000 "Internal error"` inside an array batch, so
a batched capability probe can come back unclassified. Unrecognized JSON-RPC codes still arrive as `{:error, {:rpc_error, map}}`.
See `Onchain.RPC`'s moduledoc § "Node-capability refusals" for the pinned
message shapes and for the finding that `-32001` is **not** uniquely pruned
history (Alchemy answers it for some unimplemented methods too).

Notably *not* on that list: `Onchain.RPC.base_fee/1` and `blob_base_fee/1`. Both read
from the block header rather than calling the client-specific `eth_baseFee` /
`eth_blobBaseFee` extensions, so they work on any EIP-1559 (resp. EIP-4844) node. See the
`NOTE (portability)` comment in `lib/onchain/rpc.ex` for the equivalence check.

If you hit a method that works on your node but not on a common hosted provider, that's a
portability bug worth reporting.

## Quick Start

```elixir
# Read an ERC-20 token balance (USDC on mainnet)
usdc = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
{:ok, balance} = Onchain.ERC20.balance_of(usdc, "0xYourAddress")

# Resolve an ENS name (UTS-46/ENSIP-15 normalized before namehash)
{:ok, address} = Onchain.ENS.resolve("vitalik.eth")

# Multi-coin / wildcard / CCIP-Read resolution: walks parent labels for a
# wildcard resolver (ENSIP-10) and follows EIP-3668 OffchainLookup reverts.
{:ok, eth_bytes} = Onchain.ENS.address("vitalik.eth", 60)
{:ok, op_bytes} = Onchain.ENS.address("name.eth", Onchain.ENS.evm_coin_type(10))

# Generic contract call (encode -> eth_call -> decode)
{:ok, [name]} = Onchain.Contract.call(usdc, "name()", [], "(string)")

# All functions have bang variants that raise on error
balance = Onchain.ERC20.balance_of!(usdc, "0xYourAddress")

# EIP-1559 fee suggestion: fetch history, compute base/priority/max in one go.
# `:reward_percentiles` is required — non-empty, monotonically non-decreasing list of integers in 0..100.
{:ok, history} = Onchain.RPC.fee_history(20, reward_percentiles: [50])
{:ok, {base_fee, max_priority, max_fee}} = Onchain.Fees.suggest_fees(history)

# Gas-limit estimation (eth_estimateGas) over a tx-params map
{:ok, gas} = Onchain.RPC.eth_estimate_gas(%{from: from, to: token, data: calldata})

# send_transaction auto-estimates the gas limit (with 1.25x headroom) when :gas_limit
# is omitted — so stale hardcoded limits can't OOG-revert. Pass :gas_limit to opt out.
{:ok, tx_hash} =
  Onchain.ERC20.transfer(token, recipient, amount,
    private_key: key, nonce: nonce, chain_id: 1, rpc_url: url
  )

# Decode a Solidity 0.8.4+ custom-error revert against a list of candidate signatures
{:ok, %{error: "OwnableUnauthorizedAccount", args: [_addr]}} =
  Onchain.ABI.decode_error(
    "0x118cdaa7000000000000000000000000d8da6bf26964af9d7eed9e03e53415d37aa96045",
    ["OwnableUnauthorizedAccount(address)"]
  )

# After an eth_call that reverts with a custom error, use :data from the rpc_error map:
# {:error, {:rpc_error, %{data: revert_hex}}} -> Onchain.ABI.decode_error(revert_hex, [...])
```

## Modules

### Core

| Module | Purpose |
|--------|---------|
| `Onchain.Hex` | Hex encoding/decoding (hex<->binary, hex<->integer, 0x prefix) |
| `Onchain.ABI` | ABI encoding/decoding for contract calls (`encode_call/2`, `decode_response/3`, `decode_types/3`, `decode_call/3` for selector-prefixed calldata, `decode_error/3` for Solidity 0.8.4+ custom-error revert data). Optional trailing keyword is forwarded to hieroglyph; `strict: true` rejects non-canonical payloads as `{:error, {:decode_error, {:strict_violation, detail}}}` |
| `Onchain.Address` | Address validation, EIP-55 checksum, normalization |
| `Onchain.Decimal` | Decimal precision helpers (to_decimal, div_pow10, to_basis_points) |
| `Onchain.Fees` | EIP-1559 fee recommendation (`suggest_fees/2`) over `Cartouche.FeeHistory.t()` — pure function, returns `{base_fee, max_priority, max_fee}` |
| `Onchain.RPC` | Ethereum JSON-RPC wrapper (eth_call, `eth_estimate_gas`, eth_getLogs, receipts, nonces, balances, block_number, chain_id, **decoded** `get_block_by_number`, `get_transaction_by_hash`, block-level receipt/count/by-index reads, EIP-7928 block access lists, eth_get_code, eth_send_raw_transaction, syncing, fee_history, `base_fee`, `blob_base_fee`, get_proof; `call/3` for any other method; `batch/2` for JSON-RPC array batching). Opt-in `retry: [max_retries: n, backoff_ms: ms]` on single-call paths retries transport failures only (default: no retry). Block receipts reuse the single-receipt parsed map; by-index transactions reuse the transaction map; block access lists preserve the node's raw camelCase response. `get_block_by_number/2` returns atom-keyed maps (quantities as integers — aligned with `get_transaction_by_hash/2`). `eth_get_logs/2` accepts atom keys or canonical camelCase string aliases (`"fromBlock"`, `"toBlock"`, `"blockHash"`, `"address"`, `"topics"`); `:block_hash` is mutually exclusive with `:from_block`/`:to_block` per EIP-1474 |
| `Onchain.RPC.Helpers` | Shared RPC helpers (hex normalization, block tags, tx hash validation; `parse_block_response/1`, `parse_transaction_map/1`; execution-revert maps get `:data` hex for `decode_error/2`) |
| `Onchain.Block` | Block fetching with parsed fields, timestamp-based binary search |
| `Onchain.Contract` | Generic contract call (encode -> eth_call -> decode in one function) |
| `Onchain.Multicall` | Batch multiple eth_call via Multicall3 |
| `Onchain.Sleuth` | Deploy-as-call: ship creation bytecode in one eth_call, decode returned bytes |
| `Onchain.Log` | Event log parsing against ABI signatures |
| `Onchain.Signer` | Key management and transaction signing |
| `Onchain.ERC20` | ERC-20 read (balanceOf, allowance, decimals, symbol, totalSupply) and write (transfer, approve) |
| `Onchain.ERC721` | ERC-721 NFT reads (owner_of, token_uri, balance_of, name, symbol, get_approved, approved_for_all?) |
| `Onchain.ERC1155` | ERC-1155 multi-token reads (balance_of, balance_of_batch, uri, approved_for_all?) |
| `Onchain.ERC7730` | ERC-7730 clear-signing: load a descriptor (`load/1`), bind it to calldata / EIP-712 / UserOp and render human-readable display fields (`format/2`, `format!/2`) |

### Chain Intelligence

| Module | Purpose |
|--------|---------|
| `Onchain.Wallet` | Classify address (EOA/contract), native ETH balance |
| `Onchain.Transfer` | Parse ERC-20/721/1155 Transfer events into normalized structs |
| `Onchain.MEV` | MEV protection — submit signed txs/bundles to a Flashbots-style private relay (`send_private_transaction/2`, `send_bundle/2`); caller-supplied `:endpoint` (no public-node fallback) + `:headers` auth |
| `Onchain.ENS` | ENS name resolution: forward (`resolve/2`), multi-coin + wildcard + CCIP-Read (`address/3`, ENSIP-9/10 + EIP-3668), reverse, text records, contenthash, ABI, pubkey; UTS-46/ENSIP-15 `normalize/1`, ENSIP-10 `dns_encode/1`, ENSIP-11 `evm_coin_type/1` |
| `Onchain.ENS.Normalize` | UTS-46 / ENSIP-15 name normalization (deterministic subset: case-fold + NFC + ignored/disallowed code points; not the confusable/script-mixing security filters) |
| `Onchain.ENS.CCIP` | EIP-3668 CCIP-Read pure helpers (OffchainLookup parse, gateway-request shaping, callback calldata) + bounded gateway round-trip loop |
| `Onchain.Subscription` | Real-time streaming via eth_subscribe (newHeads, pendingTx, logs) |
| `Onchain.Subscription.Parser` | Pure parsing for eth_subscribe notification payloads (newHeads, pendingTx, logs) |

### DeFi

| Module | Purpose |
|--------|---------|
| `Onchain.DEX.Router` | Optimal swap-path routing across Uniswap v2/v3-style pools — pure-Elixir constant-product math for v2, on-chain QuoterV2 `eth_call` for v3 (`route/5`, `quote_pool/4`, `amount_out_v2/4`) |

### Account Abstraction (ERC-4337)

| Module | Purpose |
|--------|---------|
| `Onchain.AA` | ERC-4337 UserOperation hashing (`user_op_hash/4`), signing (`sign_user_operation/5` — `:eip191`/`:raw`), and bundler JSON-RPC (`send_user_operation/3`, `estimate_user_operation_gas/3`, `get_user_operation_by_hash/2`, `get_user_operation_receipt/2`, `supported_entry_points/1`). Handles both v0.6 and v0.7 EntryPoint wire formats; `user_op_hash` verified against viem reference vectors |
| `Onchain.AA.UserOperation` | Version-agnostic UserOperation struct (numeric fields as integers, byte fields as `0x` hex, optional v0.7 `factory`/`paymaster` fields). Build with `Onchain.AA.new/1` |

Most read functions (`Onchain.RPC`, `Onchain.ERC20`/`ERC721`/`ERC1155`, `Onchain.Block`, `Onchain.DEX.Router.amount_out_v2`, …) expose a `function!/1` bang variant that raises on error instead of returning `{:error, reason}`. Newer composite modules (`Onchain.MEV`, `Onchain.AA`, `Onchain.ERC7730`, `Onchain.DEX.Router.route`/`quote_pool`) return tagged tuples only — no bang variant.

## Real-time Subscriptions

Stream new blocks, pending transactions, and event logs via WebSocket:

```elixir
# Connect to a WebSocket endpoint
{:ok, sub} = Onchain.Subscription.connect("wss://eth-mainnet.g.alchemy.com/v2/KEY")

# Subscribe to new block headers
{:ok, sub_id} = Onchain.Subscription.subscribe(sub, :new_heads)

# Events arrive as messages to the calling process
receive do
  {:subscription, {:new_heads, ^sub_id, head}} ->
    IO.inspect(head.number, label: "new block")
end

# Or provide a custom handler
{:ok, sub} = Onchain.Subscription.connect("wss://...",
  handler: fn {:new_heads, _id, head} -> Logger.info("Block #{head.number}") end
)

# Subscribe to filtered event logs
{:ok, _} = Onchain.Subscription.subscribe(sub, {:logs, %{
  address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  topics: [Onchain.Transfer.transfer_topics()]
}})

# Clean up
Onchain.Subscription.unsubscribe(sub, sub_id)
Onchain.Subscription.close(sub)
```

Requires a WebSocket-capable endpoint (`wss://` or `ws://`), separate from the HTTP RPC URL.

## Discovery

All modules use [descripex](https://hex.pm/packages/descripex) for self-describing APIs:

```elixir
Onchain.describe()                  # List of all annotated modules (one summary per module)
Onchain.describe(:hex)              # Function summary list for a module
Onchain.describe(:hex, :decode)     # Function detail map (params, errors, returns)
```

## Testing

```bash
mix test.json --quiet                          # Unit tests (no RPC needed)
mix test.json --quiet --include integration    # Integration tests (requires RPC)
```

Differential tests compare `Onchain.RPC` against `Cartouche.RPC` on the same node (opt-in, requires mainnet RPC):

```bash
export ONCHAIN_DIFFERENTIAL_TESTS=1
export ETHEREUM_API_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
mix test.json --quiet --include differential test/onchain/differential
```

Integration tests require an Ethereum RPC endpoint:

```bash
export ETHEREUM_API_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
```

WebSocket subscription tests require a WebSocket endpoint:

```bash
export ETHEREUM_WS_URL="wss://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
```

Sepolia write tests additionally require `ETH_SEPOLIA_RPC_URL` and `SIGNER_PRIVATE_KEY`.

## License

[MIT](LICENSE)
