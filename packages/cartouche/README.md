# Cartouche

[![Hex.pm](https://img.shields.io/hexpm/v/cartouche.svg)](https://hex.pm/packages/cartouche)

Lightweight Ethereum and Solana RPC client for Elixir. Cartouche is an **attributed fork** of [hayesgm/signet](https://github.com/hayesgm/signet) maintained by [ZenHive](https://github.com/ZenHive).

It bundles four capabilities into one library:

- **JSON-RPC clients** for Ethereum and Solana (`Cartouche.RPC`, `Cartouche.Solana.RPC`).
- **Signers** as supervised GenServers — local secp256k1 / Ed25519 seeds, or GCP Cloud KMS — exposing a uniform `sign/3` API.
- **Transaction builders** for every Ethereum envelope — legacy (V1), EIP-2930 (V_2930), EIP-1559 (V2), EIP-4844 blob (V3) and EIP-7702 set-code (V4) — plus Solana legacy transactions.
- **Contract codegen** — `mix cartouche.gen` turns Foundry / Hardhat artifacts into typed Elixir modules with `encode_*` / `call_*` / `execute_*` helpers backed by the RPC client.

## Release

Current release: **`0.8.0`** (2026-08-23). See [CHANGELOG.md](CHANGELOG.md) for the
full release history, including the EIP-2930 access-list encoding fix that changes
serialized bytes for the bare-address shorthand.

## Installation

```elixir
def deps do
  [
    {:cartouche, "~> 0.8"}
  ]
end
```

## Configuration

Cartouche is an OTP application — its supervisor starts on boot and reads `config :cartouche, ...`. A typical mainnet setup:

```elixir
# config/runtime.exs
import Config

config :cartouche,
  chain_id: 1,
  ethereum_node: "https://mainnet.infura.io/v3/" <> System.fetch_env!("INFURA_KEY"),
  signer: [
    default: {:priv_key, System.fetch_env!("ETH_PRIVATE_KEY")}
  ]
```

Each entry under `:signer` becomes a supervised `Cartouche.Signer` GenServer; the `:default` name is special — it's registered as `Cartouche.Signer.Default` and used when a caller doesn't pass `:signer` explicitly. Solana mirrors this with `:solana_node` and `:solana_signer`.

> **Production tip — direct cartouche use:** if you're embedding cartouche directly to operate a server-side hot wallet (relayer, fee payer, treasury, oracle), prefer the `:cloud_kms` signer spec over `:priv_key` in production — `Cartouche.Signer.Curvy` keeps the key in BEAM memory, while Cloud KMS keeps it in GCP HSM and gives you per-call audit logs. Consumers reaching cartouche through the `onchain` wrapper inherit whatever signer that layer configures.

| Key | Default | Purpose |
| --- | --- | --- |
| `:chain_id` | `1` | Default Ethereum chain ID for signers and transactions |
| `:ethereum_node` | `"https://mainnet.infura.io"` | Ethereum JSON-RPC endpoint |
| `:signer` | `[]` | List of `{name, signer_spec}` for Ethereum signers |
| `:solana_node` | `nil` | Solana JSON-RPC endpoint (required for any Solana RPC call) |
| `:solana_signer` | `[]` | List of `{name, signer_spec}` for Solana signers |
| `:contracts` | `[]` | Named contract address registry — see `Cartouche.get_contract_address/1` |
| `:req_options` | `[]` | Global [Req](https://hex.pm/packages/req) options merged into every HTTP request (see HTTP transport below) |
| `:timeout` | `30_000` | Ethereum RPC request timeout (ms) — compile-time |
| `:solana_timeout` | `30_000` | Solana RPC request timeout (ms) — compile-time |
| `:open_chain_base_url` | `"https://api.4byte.sourcify.dev"` | OpenChain base URL |

### HTTP transport

Cartouche issues all JSON-RPC and OpenChain requests through [Req](https://hex.pm/packages/req); it does **not** start an HTTP connection pool of its own. Three layers of [Req options](https://hexdocs.pm/req/Req.html#new/1) are merged into every request, lowest to highest precedence:

1. **Global** — `config :cartouche, :req_options, [...]`
2. **Per-transport** — `config :cartouche, Cartouche.RPC | Cartouche.Solana.RPC | Cartouche.OpenChain.API, <req options>`
3. **Per-call** — `req_options: [...]` in the opts keyword passed to any RPC function

```elixir
# Reuse your own supervised Finch pool instead of Req's default (start MyFinch yourself):
config :cartouche, :req_options, finch: MyFinch

# Or scope it to one transport:
config :cartouche, Cartouche.Solana.RPC, finch: MyFinch
```

A connection-level failure is returned as `{:error, "[Cartouche] HTTP client error: #{inspect(reason)}"}` (mapped from `%Req.TransportError{}`).

**Testing** — stub the transport with [`Req.Test`](https://hexdocs.pm/req/Req.Test.html) or a plain function plug. A function plug runs in the calling process, so no ownership/`allow` ceremony is needed:

```elixir
# config/test.exs
config :cartouche, Cartouche.RPC, plug: &MyApp.RPCStub.call/1

# or per-call: Cartouche.RPC.send_rpc("eth_blockNumber", [], req_options: [plug: &MyApp.RPCStub.call/1])

defmodule MyApp.RPCStub do
  def call(conn) do
    %{"id" => id} = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
    Req.Test.json(conn, %{"jsonrpc" => "2.0", "result" => "0x10", "id" => id})
  end
end
```

Signer specs:

```elixir
# Local secp256k1 key (Ethereum)
{:priv_key, "0xdeadbeef..."}

# GCP Cloud KMS (Ethereum)
{:cloud_kms, kms_credentials, "projects/P/locations/L/keyRings/R/cryptoKeys/K", "1"}

# Local Ed25519 seed (Solana) — accepts raw 32-byte binary, hex, or Base58
{:ed25519, "0x..."}

# GCP Cloud KMS (Solana, Ed25519)
{:cloud_kms, kms_credentials, "projects/P/locations/L/keyRings/R/cryptoKeys/K", "1"}
```

## Node compatibility

Cartouche talks to whatever JSON-RPC endpoint you configure. The transaction, balance,
block, log, receipt, call and fee-history methods work against any mainstream Ethereum
node — Alchemy, Infura, QuickNode, a self-hosted Geth/reth/Erigon, pruned or archive
alike. The tracing surface does not, and one fee method does not.

Three caveats worth knowing before you pick an endpoint:

| Surface | Requirement | Symptom without it |
| --- | --- | --- |
| `Cartouche.RPC.base_fee/1` | `eth_baseFee` — an **Erigon-origin method**, since adopted by reth, Nethermind and go-ethereum (v1.17.4) and merged into `ethereum/execution-apis` `main` on 2026-06-15, but carried by **no tagged spec release** and documented by neither Alchemy nor Infura | Alchemy mainnet answers `-32600 "eth_baseFee is not available on the ETH_MAINNET"` (observed 2026-08-25). Other hosted providers have not been probed; expect a refusal, but the exact code and message will vary |
| `Cartouche.RPC.trace_trx/2`, `trace_call/2`, `trace_call_many/2`, `debug_trace_call/2` | the `trace_*` namespace (OpenEthereum-origin; served by Erigon and reth) and `debug_traceCall` — **none of them in `ethereum/execution-apis`** | hosted endpoints that do not expose the tracing namespaces reject the call; the exact code and message vary by provider and have not been probed |
| Historical-state reads (a `block` parameter older than ~128 blocks) | an **archive** node, or a hosted plan that retains history | `-32001 Unable to complete request`, or a "missing trie node" error, depending on client |

For the base fee specifically, the portable construction is to read `baseFeePerGas` from
the **pending** block header — every EIP-1559 node serves it, and it carries the same
"next block" semantics that `eth_baseFee` does. `Onchain.RPC.base_fee/1` in the
[`onchain`](https://github.com/ZenHive/onchain) package does exactly that if you'd rather
not hand-roll it.

Note that the `:ethereum_node` default (`https://mainnet.infura.io`) is a placeholder, not
a recommendation — it carries no API key and will not serve real traffic. Always set
`:ethereum_node` explicitly, or pass `rpc_url:` per call.

## Quick start: send your first transaction

With the configuration above (a `:default` signer registered), `Cartouche.RPC.execute_trx/3` looks up the nonce, signs, and sends in one call:

```elixir
{:ok, tx_hash} =
  Cartouche.RPC.execute_trx(
    <<1::160>>,                                                # contract address (20 bytes)
    {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]},
    base_fee: {1, :gwei},
    priority_fee: {3, :gwei},
    value: 0
  )
```

`execute_trx/3` accepts:

- `:gas_price` — V1 (legacy) path. Mutually exclusive with the V2 fee fields.
- `:base_fee` and `:priority_fee` — V2 (EIP-1559) path. If both are omitted, V2 is the default and `eth_gasPrice` is consulted for the base fee.
- `:gas_limit` — defaults to `eth_estimateGas` × `:gas_buffer` (1.5).
- `:nonce` — defaults to `eth_getTransactionCount`.
- `:value` — wei (default `0`). Accepts `{n, :gwei}` or a bare integer.
- `:verify` — runs `eth_call` first to surface revert reasons before broadcasting (default `true`).
- `:trx_type` — `:v1`, `:v2`, or `nil` (auto-detect).
- `:signer`, `:chain_id` — override the configured defaults.

`Cartouche.RPC.prepare_trx/3` has the same option surface but returns the signed `%V1{}` or `%V2{}` struct without broadcasting — useful for offline signing or batch submission.

## Ethereum

### RPC calls

`Cartouche.RPC` exposes the JSON-RPC surface and a small set of higher-level wrappers. The transport is `send_rpc/3`; everything else is convenience:

```elixir
{:ok, balance_wei}    = Cartouche.RPC.get_balance(<<1::160>>)
{:ok, nonce}          = Cartouche.RPC.get_nonce(<<1::160>>)
{:ok, chain_id}       = Cartouche.RPC.eth_chain_id()
{:ok, block_number}   = Cartouche.RPC.eth_block_number()
{:ok, %Cartouche.Block{}}   = Cartouche.RPC.get_block_by_number(block_number)
{:ok, %Cartouche.Block{}}   = Cartouche.RPC.get_block_by_number("latest")
{:ok, %Cartouche.Receipt{}} = Cartouche.RPC.get_trx_receipt(tx_hash)

# Read-only contract call (eth_call)
{:ok, return_data} =
  Cartouche.RPC.call_trx(%Cartouche.Transaction.V2{
    destination: contract,
    data: call_data
  })
```

Every RPC function takes a final `opts` keyword list — `:ethereum_node`, `:block_number`, `:timeout`, `:headers` — letting you target multiple nodes from one process tree.

### Signing

A signer process knows its own address and signs on demand. With a `:default` entry in config, callers don't need to pass anything:

```elixir
{:ok, signature} = Cartouche.Signer.sign("hello world")
address          = Cartouche.Signer.address()  # 20-byte binary
```

To start a signer manually (e.g. in a test):

```elixir
{:ok, pid} =
  Cartouche.Signer.start_link(
    mfa: {Cartouche.Signer.Curvy, :sign, [private_key_bytes]},
    name: MySigner
  )

{:ok, sig} = Cartouche.Signer.sign("hello", MySigner)
```

Each signer process keeps its own public key, and signatures are verified against it before they're returned. Cloud KMS doesn't emit a recovery bit, so Cartouche tries all four and picks the one that recovers to the registered address.

### Operator keys vs. end-user wallets

The `Cartouche.Signer` GenServer is for **keys you operate** — relayers, fee payers, treasury wallets, attestation oracles. It is **not** a place to plug in end-user wallets; users on-chain sign in their own wallet (MetaMask, Phantom, Ledger, WalletConnect) and your backend's job is to **verify** what they sent. The relevant primitives:

- **EIP-712 typed data** (`eth_signTypedData_v4`) — `Cartouche.Typed` for domain / type encoding and the digest a wallet would have produced.
- **`personal_sign` / raw signature recovery** — `Cartouche.Recover.recover_eth/2` (with `prefix_eth/1` for the `\x19Ethereum Signed Message:\n` envelope) and `Cartouche.Recover.find_recid/3` when only `(r, s)` arrived.
- **Recovery-bit normalisation** — `Cartouche.RecoveryBit` between `:base` / `:ethereum` / `:eip155` representations.

Solana mirrors this with `Cartouche.Solana.Keys` for Phantom-signed payload verification on the user side and `Cartouche.Solana.Signer` (Ed25519 / Cloud KMS) for the operator side.

### Transactions

Build, sign, and encode a **V1 (legacy)** transaction:

```elixir
{:ok, signed_trx} =
  Cartouche.Transaction.build_signed_trx(
    contract,         # 20-byte address
    nonce,            # integer
    {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]},
    {50, :gwei},      # gas price
    100_000,          # gas limit
    0,                # value
    chain_id: :goerli
  )

raw = Cartouche.Transaction.V1.encode(signed_trx)
{:ok, tx_hash} = Cartouche.RPC.send_rpc("eth_sendRawTransaction", [Cartouche.Hex.to_hex(raw)])
```

Build, sign, and encode a **V2 (EIP-1559)** transaction:

```elixir
{:ok, signed_trx} =
  Cartouche.Transaction.build_signed_trx_v2(
    contract,
    nonce,
    {"baz(uint,address)", [50, :binary.decode_unsigned(<<1::160>>)]},
    {50, :gwei},      # max priority fee per gas
    {10, :gwei},      # max fee per gas
    100_000,          # gas limit
    0,                # value
    [],               # access list
    chain_id: :goerli
  )

raw = Cartouche.Transaction.V2.encode(signed_trx)
```

Both builders accept a `:callback` option — a `fn trx -> {:ok, trx} | {:error, reason}` run after construction and before signing — useful for last-mile mutations (nonce reservation, gas overrides). `V1.recover_signer/2` and `V2.recover_signer/1` round-trip the encoded form back to the signing address.

## Contract bindings

`mix cartouche.gen` turns Solidity build artifacts into Elixir modules:

```bash
mix cartouche.gen "out/**/*.json" --prefix my_app/contracts
```

Flags:

- `--prefix` — module + path prefix. `my_app/contracts` produces `MyApp.Contracts.SomeContract` in `lib/my_app/contracts/some_contract.ex`.
- `--out` — output root (default `lib/`).

The generator accepts both raw ABI JSON arrays and full Foundry / Hardhat artifacts (with `"abi"` and `"bytecode"`). For each ABI entry it emits:

- `encode_<fn>/N` — ABI-encodes the call data
- `selector_<fn>/0` — returns the `%ABI.FunctionSelector{}`
- `call_<fn>(contract, args, opts)` — wraps `Cartouche.RPC.call_trx/2`
- `execute_<fn>(contract, args, opts)` — wraps `Cartouche.RPC.execute_trx/3`
- `prepare_<fn>(contract, args, opts)` — wraps `Cartouche.RPC.prepare_trx/3`
- `estimate_gas_<fn>(contract, args, opts)`
- `decode_call/1`, `decode_event/2`, `decode_error/1` dispatchers
- For pure functions with bytecode: `exec_vm_<fn>` (local EVM execution via `Cartouche.VM`)

Each generated public function carries an ABI-derived `@doc` (function name + signature) and a `@spec` (typed via the ABI-type → Elixir-type mapping; `decode_*_call/1` is `binary() :: <decoded inputs>`, tuple ABI returns render as Elixir tuples, `exec_vm_*` returns reflect the multi-clause unwrap), so HexDocs renders cleanly and IDE/editor introspection works against the generated bindings.

Once generated, callsites read like any other Elixir module:

```elixir
{:ok, tx_hash} =
  MyApp.Contracts.SomeContract.execute_some_function(addr, 55, priority_fee: {55, :gwei})
```

## Solana

Solana support mirrors the Ethereum surface. With `:solana_node` and a `:solana_signer` configured:

```elixir
fee_payer  = Cartouche.Solana.Signer.address()  # 32-byte pubkey from configured signer
recipient  = Cartouche.Base58.decode!("RecipientPublicKeyInBase58...")
{:ok, %{blockhash: blockhash}} = Cartouche.Solana.RPC.get_latest_blockhash()

instruction = Cartouche.Solana.SystemProgram.transfer(fee_payer, recipient, 1_000_000_000)
message     = Cartouche.Solana.Transaction.build_message(fee_payer, [instruction], blockhash)

# Sign via the configured GenServer signer (no raw seed handling in app code)
msg_bytes  = Cartouche.Solana.Transaction.serialize_message(message)
{:ok, sig} = Cartouche.Solana.Signer.sign(msg_bytes)
signed     = %Cartouche.Solana.Transaction{signatures: [sig], message: message}

{:ok, signature} = Cartouche.Solana.RPC.send_and_confirm(signed, commitment: :confirmed)
```

For offline signing (no GenServer), pass raw 32-byte Ed25519 seeds directly: `Cartouche.Solana.Transaction.sign(message, [fee_payer_seed])`. For sponsored transactions (one party pays fees for another), see `Cartouche.Solana.Transaction.sign_partial/2` and `add_signature/3`.

`Cartouche.Solana.RPC` covers the standard JSON-RPC surface (`get_balance/2`, `get_account_info/2`, `simulate_transaction/2`, `request_airdrop/3`, plus the SPL token and fee queries). `Cartouche.Solana.Keys` handles keypair generation, seed loading, and Base58 conversion; `Cartouche.Solana.Signer` is the GenServer parallel to `Cartouche.Signer` for both Ed25519 and Cloud KMS backends.

## Hex utilities

`use Cartouche.Hex` brings in the `~h` sigil for compile-time hex literals plus the common encoders:

```elixir
defmodule MyApp.Calls do
  use Cartouche.Hex

  @selector ~h[0xa9059cbb]                 # decoded at compile time

  def is_transfer?(<<@selector::binary, _rest::binary>>), do: true
  def is_transfer?(_), do: false
end
```

Module-level helpers:

```elixir
Cartouche.Hex.decode_hex!("0xaabb")            # <<0xaa, 0xbb>>
Cartouche.Hex.to_hex(<<0xaa, 0xbb>>)           # "0xaabb"
Cartouche.Hex.to_address(<<1::160>>)           # "0x0000...0001" (EIP-55 checksummed)
Cartouche.Hash.keccak("hello")                 # 32-byte digest
Cartouche.Wei.to_wei({2, :gwei})               # 2_000_000_000
```

## Modules at a glance

| Module | What it does |
| --- | --- |
| `Cartouche.RPC` | Ethereum JSON-RPC client; high-level `execute_trx` / `prepare_trx` / `call_trx` |
| `Cartouche.Signer` | GenServer signer (secp256k1, Cloud KMS) — `sign/3`, `address/1` |
| `Cartouche.Transaction` | V1, V_2930, V2, V3 (blob) and V4 (set-code) builders, encoders, signature recovery |
| `Cartouche.Filter` | Supervised log / block / pending-transaction filter GenServer — `start_link/1` |
| `Cartouche.Erc20` | ERC-20 call and calldata helpers |
| `Cartouche.VM` | In-process EVM interpreter for local execution and tracing |
| `Cartouche.Sleuth` | Batched read-only contract queries via a deployed Sleuth contract |
| `Cartouche.OpenChain` | Selector lookup against the OpenChain signature database |
| `Cartouche.Typed` | EIP-712 typed-data domain / type encoder, digest builder |
| `Cartouche.Recover` | EIP-191 `personal_sign` recovery — `recover_eth/2`, `recover_public_key/2`, `find_recid/3` |
| `Cartouche.RecoveryBit` | Convert `v` between `:base` (`0/1`), `:ethereum` (`27/28`), `:eip155` |
| `Cartouche.Hex` / `Cartouche.Hash` | `~h` sigil, encode/decode helpers, keccak digests |
| `Cartouche.Wei` | `to_wei/1` — accepts integers or `{n, :gwei}` |
| `Cartouche.Solana.RPC` | Solana JSON-RPC client |
| `Cartouche.Solana.Transaction` | Build / sign / serialize Solana legacy transactions |
| `Cartouche.Solana.Token` / `TokenProgram` / `ATA` / `PDA` | SPL-token instructions, associated-token and program-derived addresses |
| `Cartouche.Solana.Signer` | GenServer Ed25519 signer (local seed, Cloud KMS) |
| `Mix.Tasks.Cartouche.Gen` | Codegen from Solidity artifacts — `mix cartouche.gen` |

## API discovery

Every public Cartouche module is annotated with [`descripex`](https://hexdocs.pm/descripex) `api(...)` blocks, so the surface is machine-readable for AI agents and introspection tooling. The top-level `Cartouche` module exposes a three-level progressive-disclosure API:

```elixir
Cartouche.describe()                            # Level 1: all modules + namespaces
Cartouche.describe(:rpc)                        # Level 2: function list for one module
Cartouche.describe(:rpc, :get_block_by_number)  # Level 3: full param/return detail
```

For build-time and HTTP / MCP consumers there are two equivalent shapes of the same manifest:

- `mix manifest` — regenerates `api_manifest.json` at the project root (pretty-printed JSON, gitignored). Run at release time the same way you'd run `mix docs`.
- `Cartouche.Manifest.build/0` — returns the manifest map at runtime, so a live Erlang VM can serve `/manifest.json` or feed an MCP tool list without an out-of-band artifact.

`api_manifest.json` is intentionally **not** shipped in the hex package — consumers regenerate it from source against the installed dep, or call `Cartouche.Manifest.build/0` directly.

## Documentation

Full API reference: [hexdocs.pm/cartouche](https://hexdocs.pm/cartouche). Release history: [CHANGELOG.md](CHANGELOG.md).

## Relationship to upstream

Cartouche is a fork of `hayesgm/signet`. We upstream fixes where it makes sense. Attribution to the original maintainer (Geoffrey Hayes, Compound Labs) is preserved in `LICENSE` and `CHANGELOG.md`.

## License

MIT. See `LICENSE`.
