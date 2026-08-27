---
name: abi-calldata
description: Encode and decode Ethereum/Solidity ABI calldata with the hieroglyph (`ABI`) library — intent → selector-prefixed transaction data, and revert/return/event data → values. Use when an agent task needs to build the `data` field of a transaction (e.g. "transfer 100 USDC to 0x…"), decode raw calldata or return values from a node, decode a custom-error revert, decode an event log, or parse a contract's `.abi.json`. Covers the encode/decode function-selection decision map, keyed-map vs tuple input shapes, the `:function`/`:constructor`/`:error`/`:event` `function_type` distinctions, and the documented gotchas (key shapes, NUL-safe string decode, indexed reference-type event hashing, `decode_structs` atom-interning). Points at `ABI.describe/__api__` for exact signatures instead of duplicating them.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Ships in the hieroglyph hex tarball (mix.exs package.files: skills/). Edit this file directly — it is NOT auto-synced from an include. -->

## ABI Calldata for Agents

You are an agent in a downstream repo (transaction builder, indexer, bot) that depends on `hieroglyph` (`{:hieroglyph, "~> 1.0"}`). The module namespace is `ABI.*`. Every function is pure — no processes, no config, no app to start. Goal: get from an *intent* to wire bytes (and back) without reading the library source.

This skill is recipes. For exact signatures, params, returns, and errors, introspect at runtime (see **Runtime introspection** below) — do not guess from memory.

### When to use

- Building the `data` field of a transaction from a function call (`transfer`, `approve`, `swapExactTokensForTokens`, …).
- Decoding raw transaction `data` (with its 4-byte selector) pulled from a node.
- Decoding a function's **return value** or a selector-routed payload.
- Decoding a Solidity **custom-error** revert (0.8.4+).
- Decoding an **event log** (`{data, topics}`) from `eth_getLogs` / a receipt.
- Parsing a whole contract `.abi.json` (solc / Foundry / Hardhat) into selectors.
- Producing `abi.encodePacked(...)` bytes for a Merkle leaf or a `keccak256(...)` hashing scheme.

### When NOT to use

- You need to **send** the transaction, sign it, manage nonces, or talk JSON-RPC — that is the caller's job; this library only shapes the `data`/return bytes. Hand the output to your signer / RPC client.
- You need RLP transaction encoding, EIP-712 typed-data hashing, or address checksumming — out of scope; use the dedicated library.
- `fixed<M>x<N>` / `ufixed<M>x<N>` — **rejected at parse time** (`ArgumentError`). Solidity itself can't assign them, so no contract emits them. `function` (24-byte pointer) IS supported.

## Worked recipe: intent → calldata (ERC-20 transfer)

Intent: *"transfer 100 USDC to `0xb2b7c1795f19fbc28fda77a95e59edbb8b3709c8`."*

Two facts the intent doesn't carry, that you must resolve first:
- **Address → 20-byte binary.** Strip `0x`, hex-decode. `ABI` wants the raw `<<…::160>>` binary, not the string.
- **Token amount → base units.** USDC has 6 decimals, so `100 USDC = 100 * 10**6 = 100_000_000`. (ETH/most ERC-20s use 18.)

```elixir
to     = Base.decode16!("b2b7c1795f19fbc28fda77a95e59edbb8b3709c8", case: :mixed)  # 20 bytes
amount = 100 * 1_000_000                                                          # 6 decimals

# Selector-prefixed calldata: keccak256("transfer(address,uint256)")[0..3] ++ encoded args
calldata = ABI.encode_call("transfer(address,uint256)", [to, amount])

# Hand `calldata` to your signer/RPC as the transaction `data` field.
"0x" <> Base.encode16(calldata, case: :lower)
#=> "0xa9059cbb000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c80000000000000000000000000000000000000000000000000000000005f5e100"
```

`a9059cbb` is the `transfer` selector; the two 32-byte words are the padded address and amount. Round-trips with `ABI.decode_call("transfer(address,uint256)", calldata) #=> {:ok, [to, amount]}`.

The signature string is the canonical Solidity form: `name(type,type,…)`, no spaces, no parameter names, `uint`/`int` mean `uint256`/`int256`.

## Decision map — which function?

### Encoding (values → bytes)

| You want | Function | Output |
|---|---|---|
| Transaction calldata (selector + args) | `ABI.encode_call/3` | `<<4-byte selector>> ++ args` |
| Just the encoded args (no selector) — e.g. a return value, or you'll prepend the selector yourself | `ABI.encode/2` | 32-byte-aligned head/tail bytes |
| `abi.encodePacked(...)` — Merkle leaf, `keccak256` hashing input | `ABI.encode_packed/2` | byte-tight, no padding (tuples/nested arrays raise) |
| Just the 4-byte selector (routing tables, topic matching) | `ABI.method_id/1` | 4 bytes |

`encode_call/3` == `method_id/1` ++ `encode/2`. Use `encode_call` for tx `data`; use `encode` for ABI-encoded return values or when something else owns the selector.

### Decoding (bytes → values)

| Your input | Function | Returns |
|---|---|---|
| Raw tx `data` **with** its 4-byte selector | `ABI.decode_call/3` | `{:ok, [args]}` \| `{:error, :selector_mismatch \| :calldata_too_short \| :no_function_name}` |
| A return value or selector-routed payload **without** a selector | `ABI.decode/3` | `[values]` (raises on malformed payload) |
| A custom-error revert blob (selector-prefixed) | `ABI.decode_error/2` | `{:ok, %{error: name, args: [...]}}` \| `{:error, :no_match \| :calldata_too_short}` |
| An event log `{data, topics}` | `ABI.decode_event/4` | `{:ok, name, args_map}` \| `{:error, {tag, _}}` |

Key fork: **does the blob still carry its 4-byte selector?** Node transaction `data` and revert data do (→ `decode_call` / `decode_error`); `eth_call` return values do not (→ `decode`). `decode/3` raises on a malformed payload; `decode_call`/`decode_error` return `{:error, …}` for the *selector* mismatch but still raise if the selector matches and the *payload* is malformed — pattern-match the error tag, wrap the call in `try` only if you must tolerate corrupt payloads.

## Input shapes — keyed-map vs tuple

A Solidity **tuple/struct** parameter accepts two equivalent input shapes in `ABI.encode/2`:

- **Tuple** — positional, always works: `{<<1::160>>, 1_000}`
- **Keyed map** — only when the selector's tuple components carry `:name` (i.e. parsed from a JSON ABI, or a `FunctionSelector` literal with named components): `%{recipient: <<1::160>>, amount: 1_000}`

Both produce identical bytes. Map keys may be **atoms or strings**, and camelCase ABI names auto-map to snake_case atoms (`"toAddress"` / `:to_address` both resolve). Reach for the map shape when your values came from a prior `ABI.decode(..., decode_structs: true)` or a Jason-decoded request payload; reach for the tuple shape for hand-built one-offs. Flat (non-tuple) argument lists are always positional lists regardless.

## function_type — filtering a parsed ABI

`ABI.parse_specification/1` takes the **string-keyed** maps from a decoded `.abi.json` and returns one `ABI.FunctionSelector` per entry — *including* non-function entries. Filter by `.function_type`:

```elixir
selectors =
  File.read!("contract.abi.json") |> Jason.decode!() |> ABI.parse_specification()

funcs  = Enum.filter(selectors, &(&1.function_type == :function))
errors = Enum.filter(selectors, &(&1.function_type == :error))    # custom-error defs for decode_error/2
events = Enum.filter(selectors, &(&1.function_type == :event))    # event defs for decode_event/4
```

`function_type` ∈ `:function | :constructor | :fallback | :receive | :event | :error`. `:constructor`/`:fallback`/`:receive` have `function: nil`. A parsed `FunctionSelector` can be passed anywhere a signature string can (`encode/2`, `encode_call/3`, `decode_call/3`, `decode_error/2`, `decode_event/4`) — pre-parse once, reuse, skip re-hashing the signature.

## Gotchas (each one has bitten a real consumer)

- **Decoded key shape is strings by default.** `decode_event/4` returns `%{"from" => …, "amount" => …}` (string keys). `parse_specification/1` keeps component `:name`s as strings inside the `types` list. Pattern-match accordingly, or opt into atoms (next item).
- **`decode_structs: true` requires pre-interned atoms.** `ABI.decode(sig, data, decode_structs: true)` returns a snake_case **atom-keyed** map — but it calls `String.to_existing_atom/1` and **raises `ArgumentError`** if a field-name atom was never created. This is deliberate: it closes the `String.to_atom/1` DoS surface for consumers ingesting ABIs from block explorers / user JSON. Fix: reference the atoms once at compile time so they're interned —
  ```elixir
  @field_atoms [:from, :to, :value, :owner, :spender]   # forces interning
  ```
  Code that already pattern-matches the decoded map (`%{value: v} = decoded`) interns them for free. Unnamed fields fall through to the tuple form (atom lookup skipped).
- **Indexed reference-type event params are hashes, not values.** Solidity stores `string`, `bytes`, arrays (fixed or dynamic), and tuples that are `indexed` as `keccak256(value)` in the topic — the preimage is unrecoverable. `decode_event/4` returns these as `{:indexed_hash, <<32 bytes>>}` rather than a decoded value. Don't treat that 32-byte hash as the data; match `topics`/use the hash for equality only. (Broader than the head/tail "dynamic" rule — it's the spec's "all complex types" indexing rule.)
- **`:string` decode is NUL-safe.** Solidity strings are length-prefixed UTF-8 and may legitimately contain `<<0>>` codepoints. This library decodes the full length (an earlier upstream bug truncated at the first NUL, C-string style). You get the whole string back — don't re-truncate.
- **`encode_packed/2` ≠ `encode/2`.** Packed mode is byte-tight (no 32-byte alignment) and rejects tuples/nested arrays. It's for hashing inputs (Merkle leaves, signature schemes), never for transaction calldata. Inside an array, scalar elements *are* padded to 32 bytes so boundaries stay recoverable; the top level is tight.
- **Addresses are 20-byte binaries, amounts are base-unit integers.** The library never sees `"0x…"` strings or decimal token amounts — convert at the boundary (hex-decode the address, multiply by `10**decimals`).
- **`fixed`/`ufixed` raise at parse time.** If a signature you were handed contains them, that's an `ArgumentError`, not a bug here — Solidity can't use those types either.

## Runtime introspection — don't memorize signatures

`hieroglyph` is `descripex`-annotated. Get exact params/returns/errors from the running VM instead of guessing:

```elixir
ABI.describe()                  # all annotated modules
ABI.describe(:abi)              # function list for the top-level ABI module
ABI.describe(:abi, :encode)     # full hints for one function — params, returns, errors, spec
ABI.__api__()                   # raw [%{name, arity, hints, spec, …}] entries
ABI.__api__(:encode_call)       # one entry by name
```

Static, CI-diffable form: `mix hieroglyph.manifest` writes `api_manifest.json` (every annotated function as JSON) — use it to detect contract drift across version bumps. When unsure of an arg order or an error tag, introspect; this skill won't drift, but it also won't enumerate every signature on purpose.
