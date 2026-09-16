# Coming from ethers.js / viem

A translation table from the two JavaScript libraries most readers (human or
model) already know to the Cartouche calls that do the same job — and, in the
last column, where the semantics **differ**. Cartouche is not a port of either:
it is an idiomatic Elixir substrate that happens to cover the same ground. The
differences column is the part worth reading; the name mappings are the part
worth searching.

Verified against cartouche 0.9.1 (2026-09-16). ethers refers to v6, viem to 2.x.
ABI rows point into `hieroglyph`, Cartouche's ABI dependency, because that is
where the `ABI.*` modules live.

## Read this first — four rules that are not in the table

1. **Bytes, not hex strings.** Every address, hash, signature, calldata and
   return value is a raw binary (`<<_::160>>` for an address, `<<_::256>>` for
   a word). Hex strings exist only at the JSON-RPC boundary and in your own
   logs. `Cartouche.Hex.from_hex!/1` on the way in, `Cartouche.Hex.to_hex/1`
   on the way out — or `use Cartouche.Hex` and write `~h[0x…]`. Passing a
   `"0x…"` string where an address is expected does not error early; it
   produces a 42-byte binary and fails somewhere downstream.
2. **`Cartouche.Signer.sign/3` is not `signMessage`.** It keccaks the bytes it
   is given and signs that digest — **no EIP-191 prefix**, and `v` is
   EIP-155-encoded (`chain_id * 2 + 35 + recid`) by default, which can exceed
   one byte. To produce what a wallet or `verifyMessage` expects, prefix and
   force `v` to 27/28 yourself: `Cartouche.Signer.sign(Cartouche.Recover.prefix_eth(msg), signer, chain_id: 0)`.
3. **A signer is a process, not a value.** `new Wallet(pk)` becomes a supervised
   `Cartouche.Signer` GenServer (started from config or
   `Cartouche.Signer.start_link/1`), addressed by name or pid through the
   `signer:` option. `Cartouche.Signer.Curvy` is the raw-key backend if you
   need a function call without a process.
4. **Nothing validates an EIP-55 checksum.** `Cartouche.Hex.checksum_address/1`
   *produces* one; `Cartouche.Hex.decode_address!/1` checks length only. ethers'
   `getAddress` throws on a wrongly cased input — Cartouche accepts it.

Results are `{:ok, value} | {:error, reason}` tuples; `!`-suffixed functions
raise. Options are trailing keyword lists. Integers are native arbitrary
precision — there is no `BigNumber`/`bigint` distinction anywhere.

## Bytes and hex

| ethers v6 | viem | Cartouche | Difference |
|---|---|---|---|
| `getBytes("0x…")` | `hexToBytes` | `Cartouche.Hex.from_hex!/1`, or `~h[0x…]` | — |
| `hexlify(bytes)` | `bytesToHex` | `Cartouche.Hex.to_hex/1` | always lowercase, always `0x`-prefixed |
| `toQuantity(n)` | `numberToHex(n)` | `Cartouche.Hex.encode_quantity/1` | — (minimal hex, `"0x0"` for zero) |
| `toBigInt("0x…")` | `hexToBigInt` | `Cartouche.Hex.decode_hex_number!/1` | returns a plain integer |
| `zeroPadValue(v, 32)` | `pad(v, { size: 32 })` | `Cartouche.Hex.pad/2` | binaries only; raises if the input is already longer |
| `zeroPadBytes(v, 32)` | `pad(v, { dir: "right" })` | `Cartouche.Hex.pad_right/2` | — |
| `dataSlice`, `concat` | `slice`, `concat` | binary pattern matching, `<>` | no helpers — the language does it |
| `encodeBase58` / `decodeBase58` | — | `Cartouche.Base58.encode/1`, `decode/1`, `decode!/1` | `decode/1` returns `{:ok, bytes}` |

## Units

| ethers v6 | viem | Cartouche | Difference |
|---|---|---|---|
| `parseEther("1.5")` | `parseEther("1.5")` | `Cartouche.Wei.to_wei({Decimal.new("1.5"), :eth})` | input is `Decimal` or integer, never a string or float; the atom is `:eth` (`:ether` is rejected); a fraction finer than 1 wei **raises** — viem rounds, ethers throws |
| `parseUnits("5", "gwei")` | `parseGwei("5")` | `Cartouche.Wei.to_wei({5, :gwei})` | integer gwei only — there is no `{Decimal, :gwei}` clause |
| `parseUnits(x, decimals)` | `parseUnits(x, decimals)` | — | no arbitrary-decimals helper; multiply integers yourself |
| `formatEther`, `formatUnits` | `formatEther`, `formatUnits` | — | not in Cartouche; nothing renders wei back to a decimal string |
| a `bigint` amount | a `bigint` amount | an integer, or `{n, :wei \| :gwei \| :eth}` anywhere a fee or value is taken | the tagged tuple is accepted by every constructor and by `execute_trx/3` options |

## Hashing and addresses

| ethers v6 | viem | Cartouche | Difference |
|---|---|---|---|
| `keccak256(bytes)` | `keccak256(bytes)` | `Cartouche.Hash.keccak/1` | returns 32 raw bytes |
| `id("Transfer(address,uint256)")` | `toEventSelector` / `keccak256(toBytes(s))` | `Cartouche.Hash.keccak/1` on the string, or `ABI.Event.event_signature/1` from a selector | — |
| `getAddress("0x…")` | `getAddress` | `Cartouche.Hex.checksum_address/1` (string → string) or `Cartouche.Hex.to_address/1` (bytes → string) | **produces** EIP-55 but never **validates** it — see rule 4 |
| `isAddress` | `isAddress` | `Cartouche.Hex.decode_address!/1` (raises otherwise) | length check only, no checksum check |
| `computeAddress(pubkey)` | `publicKeyToAddress` | `Cartouche.Address.from_public_key/1` | SEC1 uncompressed `0x04‖X‖Y` (65 bytes) only; compressed keys are not accepted |
| `getCreateAddress`, `getCreate2Address` | `getContractAddress` | — | not in Cartouche |

## Keys and signers

| ethers v6 | viem | Cartouche | Difference |
|---|---|---|---|
| `Wallet.createRandom()` | `generatePrivateKey()` + `privateKeyToAccount` | `Cartouche.Keys.generate_keypair/0` → `{address, private_key}` | 32 random bytes, no mnemonic (BIP-39/32 is roadmap task 9015) |
| `new Wallet(pk)` | `privateKeyToAccount(pk)` | config `signer: [default: {:priv_key, "0x…"}]`, or `Cartouche.Signer.start_link(mfa: {Cartouche.Signer.Curvy, :sign, [pk]}, name: MySigner)` | a **process** — see rule 3; the `:default` entry registers as `Cartouche.Signer.Default` and is what every `signer:`-less call uses |
| `wallet.address` | `account.address` | `Cartouche.Signer.address/1` | 20 raw bytes, fetched from the process |
| — (address from a key, no object) | `privateKeyToAddress` | `Cartouche.Signer.Curvy.get_address/1` | — |
| `wallet.signingKey.publicKey` | `privateKeyToAccount(pk).publicKey` | `Cartouche.Signer.Curvy.public_key/1` | — |
| `signingKey.sign(digest)` | `sign({ hash, privateKey })` | `Cartouche.Signer.Curvy.sign_digest/2` | returns `%Curvy.Signature{}` **without a recovery id**; `Cartouche.Recover.find_recid_from_digest/3` recovers it against the expected address |
| a KMS signer (third-party plugins) | `toAccount` with a custom `sign` | `{:cloud_kms, credentials, key_path, version}` signer spec | GCP Cloud KMS is a first-class backend; KMS emits no recovery bit, so Cartouche tries all four |

## Messages and typed data

| ethers v6 | viem | Cartouche | Difference |
|---|---|---|---|
| `signer.signMessage(msg)` | `signMessage` | `Cartouche.Signer.sign(Cartouche.Recover.prefix_eth(msg), signer, chain_id: 0)` | **two divergences** — no automatic EIP-191 prefix, and `v` is EIP-155 unless `chain_id: 0`; see rule 2 |
| `hashMessage(msg)` | `hashMessage` | `Cartouche.Hash.keccak(Cartouche.Recover.prefix_eth(msg))` | — |
| `verifyMessage(msg, sig)` | `recoverMessageAddress` / `verifyMessage` | `Cartouche.Recover.recover_personal_sign/2` | returns the 20-byte address — compare it yourself; accepts packed `r‖s‖v` with `v` in `{0, 1, 27, 28, EIP-155}` or a `%Curvy.Signature{}` |
| `recoverAddress(digest, sig)` | `recoverAddress` | `Cartouche.Recover.recover_eth_from_digest/2` | — |
| — | — | `Cartouche.Recover.recover_eth/2` | keccaks the message first and applies **no** prefix — the inverse of `Cartouche.Signer.sign/3`, with no ethers equivalent |
| `TypedDataEncoder.encode(d, t, v)` | — | `Cartouche.Typed.encode/1` | same `0x1901 ‖ domainSeparator ‖ hashStruct` bytes |
| `TypedDataEncoder.hash(d, t, v)` | `hashTypedData` | `Cartouche.Hash.keccak(Cartouche.Typed.encode(typed))` | — |
| `signer.signTypedData(d, t, v)` | `signTypedData` | `Cartouche.Signer.sign(Cartouche.Typed.encode(typed), signer, chain_id: 0)` | plain `sign/3` is right here (no prefix wanted) — still pass `chain_id: 0` for a 27/28 `v` |
| `verifyTypedData` | `recoverTypedDataAddress` | `Cartouche.Recover.recover_eth(Cartouche.Typed.encode(typed), sig)` | — |
| `TypedDataEncoder.hashStruct` | `hashStruct` | `Cartouche.Typed.hash_struct/3` | — |
| `TypedDataEncoder.hashDomain` | `hashDomain` | `Cartouche.Typed.domain_seperator/1` | note the spelling |
| `eth_signTypedData_v4` JSON payload | same | `Cartouche.Typed.deserialize/1` | expects `domain` / `types` / **`value`** keys — a wallet payload's `message` must be renamed; `primaryType` is not read (inferred from `value`'s field names) |

## Transactions

Cartouche has one struct per envelope type and no field-based type inference:
`Cartouche.Transaction.V1` (legacy), `V_2930` (type 1), `V2` (EIP-1559),
`V3` (EIP-4844), `V4` (EIP-7702).

| ethers v6 | viem | Cartouche | Difference |
|---|---|---|---|
| `Transaction.from({ to, value, … })` | `prepareTransactionRequest` | `Cartouche.Transaction.V2.new(nonce, max_priority_fee, max_fee, gas_limit, to, value, data, access_list, chain_id)` | positional constructor per type, not a request object; pick the struct yourself |
| `Transaction.from(serialized)` | `parseTransaction` | `Cartouche.Transaction.decode/1` | dispatches on the envelope byte; `{:ok, struct}` |
| `tx.serialized` | `serializeTransaction` | `Cartouche.Transaction.encode/1` | raw bytes — `to_hex/1` before JSON |
| `tx.from` | `recoverTransactionAddress` | `Cartouche.Transaction.V2.recover_signer/1`, `V1.recover_signer/2` | V1 needs the chain id passed in |
| `tx.hash` | `keccak256(serialized)` | `V3.hash/1`, `V4.hash/1`; for V1/V2 `Cartouche.Hash.keccak(Cartouche.Transaction.encode(tx))` | no `hash/1` on V1 and V2 |
| `wallet.signTransaction(tx)` | `signTransaction` | `Cartouche.Transaction.build_signed_trx_v2/9` (builds **and** signs), `build_signed_trx/7` for legacy; `V3.sign/2`, `V4.sign/2` on an existing struct | V1/V2 have no `sign/2` — the builder is the signing path; its `:callback` option runs between construction and signing |
| `wallet.sendTransaction(tx)` | `sendTransaction` / `writeContract` | `Cartouche.RPC.execute_trx(to, calldata, opts)` | fetches nonce, fees and gas, **runs `eth_call` first** (`verify: true` is the default), signs, broadcasts — `simulateContract` + `writeContract` in one call; `Cartouche.RPC.prepare_trx/3` is the same without the broadcast |
| `provider.broadcastTransaction(raw)` | `sendRawTransaction` | `Cartouche.RPC.send_trx/2` on a signed V1/V2 struct | V3/V4 go through `Cartouche.RPC.send_rpc("eth_sendRawTransaction", [to_hex(raw)])` |
| `authorization` signing (7702) | `signAuthorization` | `Cartouche.Transaction.V4.sign_authorization/2` on `{chain_id, address, nonce}` | — |
| an RPC transaction object | same | `Cartouche.Transaction.V2.from_json/1` (and per type) | — |

## RPC reads

There is no provider or client value: every function takes `ethereum_node: url`
in its trailing `opts` (defaulting to `config :cartouche, :ethereum_node`). A
client struct is roadmap task 9017 in `onchain`.

| ethers v6 | viem | Cartouche | Difference |
|---|---|---|---|
| `new JsonRpcProvider(url)` | `createPublicClient({ transport: http(url) })` | — | `ethereum_node:` option per call, or application config |
| `provider.send(method, params)` | `client.request({ method, params })` | `Cartouche.RPC.send_rpc/3` | returns the raw JSON value unless `decode: :hex \| :hex_unsigned \| fun` |
| `getBalance(addr)` | `getBalance` | `Cartouche.RPC.get_balance/2` | integer wei |
| `getTransactionCount(addr)` | `getTransactionCount` | `Cartouche.RPC.get_nonce/2` | `block_number: "pending"` for the pending nonce |
| `getCode(addr)` | `getCode` / `getBytecode` | `Cartouche.RPC.get_code/2` | raw bytes |
| `getStorage(addr, slot)` | `getStorageAt` | — | roadmap task 2130; `send_rpc("eth_getStorageAt", …)` until then |
| `getBlockNumber()` | `getBlockNumber` | `Cartouche.RPC.eth_block_number/1` | — |
| `getNetwork().chainId` | `getChainId` | `Cartouche.RPC.eth_chain_id/1` | — |
| `getBlock(tag, prefetchTxs)` | `getBlock` | `Cartouche.RPC.get_block_by_number/2`, `get_block_by_hash/2` → `%Cartouche.Block{}` | `include_transaction_details: true` for full transactions |
| `getTransactionReceipt(hash)` | `getTransactionReceipt` | `Cartouche.RPC.get_trx_receipt/2` → `%Cartouche.Receipt{} \| nil` | — |
| `getTransaction(hash)` | `getTransaction` | — | roadmap task 2129; `send_rpc("eth_getTransactionByHash", …)` until then |
| `waitForTransaction(hash)` | `waitForTransactionReceipt` | — | roadmap task 9017 |
| `getFeeData()` | `estimateFeesPerGas` | `Cartouche.RPC.gas_price/1`, `max_priority_fee_per_gas/1`, `base_fee/1`, `fee_history/1` → `%Cartouche.FeeHistory{}` | no combined fee struct; `execute_trx/3` derives fees itself (`base_fee_buffer`, `priority_fee` options) |
| `estimateGas(tx)` | `estimateGas` | `Cartouche.RPC.estimate_gas/2` | takes a V1/V2/`%Cartouche.Transaction.Call{}` struct |
| `call(tx)` | `call` | `Cartouche.RPC.call_trx/2` | returns raw return bytes; a revert is `{:error, %{code: 3, message: _, revert: bytes}}`, decoded when `errors: ["MyError(uint256)"]` is passed |
| — | `createAccessList` | `Cartouche.RPC.create_access_list/2` | — |
| `getLogs(filter)` | `getLogs` | — | roadmap task 2128; node-side filters only (below), or `send_rpc`, until then |
| `FallbackProvider` | `fallback([...])` | — | roadmap task 9014 |
| — | — | `Cartouche.RPC.debug_trace_call/2`, `trace_call/2`, `trace_call_many/2`, `trace_trx/2` | typed tracing wrappers, first-class |

## Contract calls (ABI lives in hieroglyph)

| ethers v6 | viem | Cartouche / hieroglyph | Difference |
|---|---|---|---|
| `new Interface(abiJson)` | `abi` array | `ABI.parse_specification/1` | — |
| `Fragment.from("function transfer(address,uint256)")` | `parseAbiItem` | `ABI.FunctionSelector.decode/1` | one item per call — no whole-ABI human-readable list |
| `iface.encodeFunctionData(fn, args)` | `encodeFunctionData` | `ABI.encode_call/3`, e.g. `ABI.encode_call("transfer(address,uint256)", [to, amount])` | positional arg list; the address arg is 20 bytes |
| `iface.decodeFunctionData(data)` | `decodeFunctionData` | `ABI.decode_call/3` | — |
| `iface.decodeFunctionResult(fn, data)` | `decodeFunctionResult` | `ABI.decode("(uint256)", return_data)` | pass the **return tuple type**, not the function signature |
| `AbiCoder.encode(types, values)` | `encodeAbiParameters` | `ABI.encode("(uint256,address)", [{n, addr}])` | tuple type string, values as one tuple; no selector |
| `iface.getFunction(fn).selector` | `toFunctionSelector` | `ABI.method_id/1` | 4 raw bytes |
| `iface.parseError(data)` | `decodeErrorResult` | `ABI.decode_error/3`, or `errors:` on `call_trx/2` / `execute_trx/3` | — |
| `solidityPacked(types, values)` | `encodePacked` | `ABI.encode_packed/2` | — |
| `new Contract(addr, abi, runner)` | `getContract` | none — inline `{"sig(types)", args}` calldata, or a module generated by `mix cartouche.gen` (`call_<fn>`, `execute_<fn>`, `prepare_<fn>`, `decode_event/2`) | no contract object; the generated module is the closest thing and is compile-time, not runtime |
| `contract.fn.staticCall(args)` | `readContract` | `Cartouche.RPC.call_trx(%Cartouche.Transaction.Call{destination: addr, data: calldata})` then `ABI.decode/3` | two steps unless you use generated bindings |
| `contract.fn(args)` | `writeContract` | `Cartouche.RPC.execute_trx(addr, {"fn(types)", args}, opts)` | see Transactions — simulates first by default |
| — | `simulateContract` | `execute_trx/3` with `verify: true` (default), or `call_trx/2` with `from:` | simulation is **on by default** — the opposite of ethers, which never simulates |
| — | `erc20Abi` | `Cartouche.ERC20.balance_of/3`, `Cartouche.ERC20.transfer/4` | — |

## Events and filters

| ethers v6 | viem | Cartouche | Difference |
|---|---|---|---|
| `contract.on(event, cb)` | `watchContractEvent` / `watchEvent` | `Cartouche.Filter.start_link(kind: :log, address: addr, topics: [...], events: [...])` + `Cartouche.Filter.listen/1` | a supervised GenServer polling `eth_getFilterChanges` every `check_delay` ms (default 3000); delivers `%Cartouche.Filter.Log{}` **messages** to the listening pid — no callback |
| `provider.on("block", cb)` | `watchBlocks` | `Cartouche.Filter.start_link(kind: :block)` | delivers `{:hashes, [hash]}` |
| `provider.on("pending", cb)` | `watchPendingTransactions` | `Cartouche.Filter.start_link(kind: :pending)` | same shape |
| `iface.encodeFilterTopics` | `encodeEventTopics` | `ABI.Event.encode_event_topics/2` | — |
| `iface.parseLog(log)` | `decodeEventLog` | `ABI.Event.decode_event/4` | — |
| `eth_newBlockFilter` & co. | `createBlockFilter` & co. | `Cartouche.RPC.new_block_filter/1`, `new_pending_transaction_filter/1`, `get_filter_logs/2` | — |

## Node-managed accounts

The ethers `JsonRpcSigner` / viem "JSON-RPC account" path — the node holds the
key and signs.

| ethers v6 | viem | Cartouche | Difference |
|---|---|---|---|
| `provider.getSigner().sendTransaction(tx)` | `sendTransaction` with a JSON-RPC account | `Cartouche.RPC.send_transaction/2` | `eth_sendTransaction` — the node signs |
| `provider.listAccounts()` | `getAddresses` | `Cartouche.RPC.accounts/1` | — |
| `eth_sign` via node | — | `Cartouche.RPC.sign/3` | distinct from `Cartouche.Signer.sign/3`; this is the node's key |
| `eth_signTransaction` | — | `Cartouche.RPC.sign_transaction/2`, `fill_transaction/2` | — |

## Chains

| ethers v6 | viem | Cartouche | Difference |
|---|---|---|---|
| `Network.from("sepolia")` | `sepolia` chain object | `Cartouche.Chain.parse_id(:sepolia)` → `11155111` | an atom → id map only; no currency, RPC URLs, explorers or contract addresses (roadmap task 9013) |

## Cartouche extras with no ethers/viem counterpart

`Cartouche.OpenChain.lookup/3` (selector → signature lookup),
`Cartouche.Sleuth` (bytecode queries), `Cartouche.VM` (in-process EVM subset
for pure functions), `Cartouche.RPC.eth_config/1` and `eth_capabilities/1`,
the Cloud KMS backends, and the whole `Cartouche.Solana.*` tree.

## Not in Cartouche — and where it is instead

| ethers / viem | Where |
|---|---|
| ENS (`resolveName`, `lookupAddress`, `namehash`) | `onchain` — `Onchain.ENS` |
| Multicall (`multicall`) | `onchain` — `Onchain.Multicall` |
| `HDNodeWallet`, `Mnemonic`, keystore JSON | roadmap task 9015 |
| `waitForTransactionReceipt`, a client struct | roadmap task 9017 (`onchain`) |
| `FallbackProvider` / `fallback` transport | roadmap task 9014 |
| chain objects | roadmap task 9013 |
| test client (`setBalance`, `impersonateAccount`, `mine`, `snapshot`) | roadmap task 9016 |
| SIWE (`siwe`) | roadmap task 9018 (`onchain`) |
| `getLogs`, `getTransaction`, `getStorage` | roadmap tasks 2128, 2129, 2130 (bundle `cartouche_rpc_read_surface`, behind the 2137 transport move) |
| `formatUnits`, `getCreate2Address`, checksum validation | no wrapper and no task today — a few lines of Elixir |
