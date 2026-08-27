# Hieroglyph — Ethereum ABI for Elixir

[![Hex.pm](https://img.shields.io/hexpm/v/hieroglyph.svg)](https://hex.pm/packages/hieroglyph)
[![HexDocs](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/hieroglyph)

The [Application Binary Interface](https://docs.soliditylang.org/en/latest/abi-spec.html) (ABI) of Solidity describes how to transform binary data to types which the Solidity programming language understands. For instance, if we want to call a function `bark(uint32,bool)` on a Solidity-created contract `contract Dog`, what `data` parameter do we pass into our Ethereum transaction? This project allows us to encode such function calls.

## About this package

`hieroglyph` is a maintained fork of [exthereum/abi](https://github.com/exthereum/abi) that ships bugfixes and Elixir 1.19+ compatibility ahead of upstream. **The module namespace is unchanged:** consumers still call `ABI.encode/2`, `ABI.decode/2`, `ABI.parse_specification/1`, etc. Only the hex package name differs. See [exthereum/abi#53](https://github.com/exthereum/abi/issues/53), [#54](https://github.com/exthereum/abi/issues/54), and [#55](https://github.com/exthereum/abi/issues/55) for the fork-motivating bug reports filed upstream.

## Installation

The package can be installed by adding `hieroglyph` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:hieroglyph, "~> 1.7"}
  ]
end
```

Docs are published on [HexDocs](https://hexdocs.pm/hieroglyph).

## Usage

### Encoding

To encode a function call, pass the ABI spec and the data to pass in to `ABI.encode/2`.

```elixir
iex> ABI.encode("baz(uint,address)", [50, <<1::160>> |> :binary.decode_unsigned])
<<162, 145, 173, 214, 0, 0, 0, 0, 0, 0, 0, 0, ...>
```

Then, you can construct an Ethereum transaction with that data, e.g.

```elixir
# Blockchain comes from `Exthereum.Blockchain`, see below.
iex> %Blockchain.Transaction{
...> # ...
...> data: <<162, 145, 173, 214, 0, 0, 0, 0, 0, 0, 0, 0, ...>
...> }
```

That transaction can then be sent via JSON-RPC or DevP2P to execute the given function.

### Decoding

Decode is generally the opposite of encoding, though we generally leave off the function signature from the start of the data. E.g. from above:

```elixir
iex> ABI.decode("baz(uint,address)", "000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000320000000000000000000000000000000000000000000000000000000000000001" |> Base.decode16!(case: :lower))
[50, <<1::160>> |> :binary.decode_unsigned]
```

Security note: decoding remains permissive by default for backwards compatibility. For adversarial calldata, pass `strict: true` to `ABI.decode/3`, `ABI.decode_call/3`, `ABI.decode_event/4`, or `ABI.decode_error/3` to reject non-canonical integer/bool padding, trailing bytes after the declared payload, and string/bytes length prefixes that exceed the available data. Strict failures return `{:error, {:strict_violation, detail}}`.

#### Pre-interning atoms for `decode_structs: true`

When the ABI carries field names, you can opt into a map-shaped result keyed by snake_case atoms:

```elixir
iex> ABI.decode("(uint256 a,bool b)", "000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000001" |> Base.decode16!(case: :lower), decode_structs: true)
%{a: 10, b: true}
```

Each field-name atom must already exist in the VM atom table — `decode_structs: true` calls `String.to_existing_atom/1` and raises `ArgumentError` if the atom has not been interned. This bounds atom creation to the set of names you have explicitly referenced in your code, closing the [`String.to_atom/1` DoS surface](https://hexdocs.pm/elixir/String.html#to_atom/1) for consumers that ingest ABIs from arbitrary sources (block explorers, user-submitted JSON, indexer feeds).

The migration is a one-liner per consumer — reference the snake_case atoms once at compile time. Code that already pattern-matches the decoded map (`%{a: a, b: b} = decoded`) interns them automatically. For ABIs loaded dynamically:

```elixir
defmodule MyApp.Erc20 do
  @field_atoms [:from, :to, :value, :owner, :spender]
  # …
end
```

Fields with empty `:name` (or any missing names) fall through to the tuple form — atom lookup is skipped entirely.

### Computing method IDs and decoding selector-prefixed calldata

`ABI.method_id/1` returns the 4-byte function selector (`keccak256(canonical_signature)[0..3]`) — useful for selector-table routing, log-topic matching, or pre-validating calldata without decoding args. Accepts a signature string or a `FunctionSelector` struct.

```elixir
iex> ABI.method_id("transfer(address,uint256)") |> Base.encode16(case: :lower)
"a9059cbb"

iex> ABI.method_id("deposit()") |> Base.encode16(case: :lower)
"d0e30db0"
```

`ABI.encode_call/3` and `ABI.decode_call/3` are the selector-prefixed calldata helpers: `encode_call/3` builds the 4-byte-prefixed blob, while `decode_call/3` strips and verifies the 4-byte prefix before decoding the payload. `ABI.decode/3` remains payload-only — use `decode_call/3` when the input still has its method-ID prefix (raw transaction `data` from a node), and `decode/3` for return values or selector-routed payloads.

```elixir
iex> ABI.encode_call("transfer(address,uint256)", [<<1::160>>, 100])
...> |> Base.encode16(case: :lower)
"a9059cbb00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000064"

iex> calldata = ABI.encode_call("transfer(address,uint256)", [<<1::160>>, 100])
iex> ABI.decode_call("transfer(address,uint256)", calldata)
{:ok, [<<1::160>>, 100]}

iex> ABI.decode_call("transfer(address,uint256)", <<0xde, 0xad, 0xbe, 0xef>>)
{:error, :selector_mismatch}

iex> ABI.decode_call("transfer(address,uint256)", <<0xa9, 0x05>>)
{:error, :calldata_too_short}
```

Returns `{:ok, decoded}` on selector match, or `{:error, :calldata_too_short | :selector_mismatch | :no_function_name}`. A malformed payload after a valid selector still raises — same contract as `decode/3`.

### Encoding and decoding custom errors (Solidity 0.8.4+)

Solidity 0.8.4 introduced [custom errors](https://soliditylang.org/blog/2021/04/21/custom-errors/) — the revert data is selector-prefixed exactly like calldata, with the selector being `keccak256("ErrorName(types...)")[0..3]`. `ABI.decode_error/2` matches the first 4 bytes of `revert_data` against a list of known error definitions and decodes the payload of whichever matches first. Definition order is the disambiguation lever — the first matching selector wins. `ABI.encode_error/3` is the encode-side counterpart (test harnesses, RPC mocks, contract fuzzers) — it builds the selector-prefixed revert blob and raises `ArgumentError` for an unnamed selector.

```elixir
iex> revert = ABI.encode_error("InsufficientBalance(uint256,uint256)", [10, 100])
iex> ABI.decode_error(revert, [
...>   "Unauthorized(address)",
...>   "InsufficientBalance(uint256,uint256)",
...>   "NotFound()"
...> ])
{:ok, %{error: "InsufficientBalance", args: [10, 100]}}
```

Returns `{:ok, %{error: name, args: [...]}}` on a hit, or `{:error, :no_match | :calldata_too_short}`. Like `decode_call/3`, a malformed payload after a successful selector match still raises. Each definition in the list can be a signature string or a pre-parsed `FunctionSelector` struct (mixed accepted).

The two Solidity **built-in** errors are recognized implicitly — `Error(string)` (selector `0x08c379a0`, the standard `require`/`revert` reason string) and `Panic(uint256)` (selector `0x4e487b71`, the 0.8.x `assert`/arithmetic panic) decode even when `error_definitions` is `[]`, so you don't hand-define them. A user definition whose selector collides with a built-in still wins — `error_definitions` is consulted first.

```elixir
iex> ABI.decode_error(ABI.encode("Error(string)", ["insufficient balance"]), [])
{:ok, %{error: "Error", args: ["insufficient balance"]}}

iex> ABI.decode_error(ABI.encode("Panic(uint256)", [0x11]), [])
{:ok, %{error: "Panic", args: [17]}}  # 0x11 = overflow/underflow
```

### Packed encoding (`abi.encodePacked`)

`ABI.encode_packed/2` produces Solidity's [non-standard packed encoding](https://docs.soliditylang.org/en/stable/abi-spec.html#non-standard-packed-mode) — used for Merkle airdrop leaves, `keccak256(abi.encodePacked(...))` signature schemes, and any context where you need the byte-tight concatenation rather than the standard 32-byte-aligned head/tail layout.

```elixir
# Canonical spec example: int16(-1), bytes1(0x42), uint16(0x03), string("Hello, world!")
iex> ABI.encode_packed(
...>   "spec(int16,bytes1,uint16,string)",
...>   [-1, <<0x42>>, 3, "Hello, world!"]
...> )
<<0xff, 0xff, 0x42, 0x00, 0x03>> <> "Hello, world!"

# Merkle airdrop leaf: address ++ uint256 → 52 bytes pre-hash
iex> account = <<0xb2b7c1795f19fbc28fda77a95e59edbb8b3709c8::160>>
iex> packed = ABI.encode_packed("leaf(address,uint256)", [account, 100])
iex> byte_size(packed)
52
```

Tuples/structs and nested arrays are not supported by Solidity's packed mode and raise `ArgumentError`. Inside an array, scalar elements are padded to 32 bytes (per the spec) so element boundaries are recoverable; at the top level the encoding is byte-tight with no padding. Standard ABI encoding (`ABI.encode/2`) is the inverse — use `encode/2` for transaction calldata, `encode_packed/2` for hashing inputs.

### Deploy encoding (constructor arguments)

`ABI.encode_constructor/2` encodes constructor arguments for a contract deployment. Constructors have no selector, so it returns the ABI-encoded args with **no** 4-byte prefix — the deploy calldata is `contract_bytecode <> encoded_args`. It only accepts a `%ABI.FunctionSelector{function_type: :constructor}` (the `:constructor` entry from `parse_specification/1`); a non-constructor selector raises `ArgumentError`. Mirrors viem's `encodeDeployData`, scoped to just the args blob.

```elixir
iex> [constructor] =
...>   ABI.parse_specification([%{
...>     "type" => "constructor",
...>     "stateMutability" => "nonpayable",
...>     "inputs" => [%{"name" => "supply", "type" => "uint256"}]
...>   }])
iex> encoded_args = ABI.encode_constructor(constructor, [1000])
iex> deploy_calldata = contract_bytecode <> encoded_args
```

An empty-args constructor returns `<<>>`. The args round-trip through `ABI.decode/3` against the constructor's parsed types.

### Parsing a JSON ABI file

Full contract ABIs from `solc` / Foundry / Hardhat can be fed straight into `ABI.parse_specification/1` after decoding the JSON. Non-function entries (constructors) are skipped; function, fallback, receive, event, and custom-error entries are all returned as `ABI.FunctionSelector` structs.

```elixir
iex> File.read!("priv/dog.abi.json")
...> |> Jason.decode!()
...> |> ABI.parse_specification()
...> |> Enum.find(&(&1.function == "bark"))
%ABI.FunctionSelector{function: "bark", function_type: :function, ...}
```

Each returned selector carries its `function_type` (`:function`, `:constructor`, `:fallback`, `:receive`, `:event`, or `:error`), so you can filter the parsed list by shape when a single ABI mixes all of them.

### Looking up and formatting ABI fragments

`ABI.get_abi_item/3` finds a fragment by name in a parsed specification (the list from `parse_specification/1`). For overloaded names, pass `arg_types` — a list of internal type atoms aligned with each input's `type` field — to select the intended overload; pass `nil` when the name is unique or to surface `{:error, {:ambiguous, _}}`. Mirrors viem's `getAbiItem`.

```elixir
iex> abi = ABI.parse_specification([
...>   %{"type" => "function", "name" => "pick", "inputs" => [%{"type" => "uint256"}]},
...>   %{"type" => "function", "name" => "pick", "inputs" => [%{"type" => "uint256"}, %{"type" => "address"}]}
...> ])
iex> {:error, {:ambiguous, _}} = ABI.get_abi_item(abi, "pick", nil)
iex> {:ok, %ABI.FunctionSelector{}} = ABI.get_abi_item(abi, "pick", [{:uint, 256}, :address])
iex> ABI.get_abi_item(abi, "missing", nil)
{:error, :not_found}
```

`ABI.format_abi_item/1` is the inverse of parsing — it renders any `FunctionSelector` (function, error, event, constructor) back to its canonical `"name(type1,type2,...)"` signature string, with tuples expanded to parenthesized member lists and arrays rendered `[]` / `[N]`. It delegates to the same canonical sig-builder that `method_id/1` and `event_signature/1` hash, so the human-readable string can never drift from what gets hashed. Mirrors viem's `formatAbiItem`.

```elixir
iex> ABI.parse_specification([%{"type" => "function", "name" => "transfer", "inputs" => [%{"type" => "address"}, %{"type" => "uint256"}]}])
...> |> hd()
...> |> ABI.format_abi_item()
"transfer(address,uint256)"
```

### Decoding event logs

Event logs arrive as `{data, topics}` pairs from the JSON-RPC node. `ABI.decode_event/4` (or the lower-level `ABI.Event.decode_event/4`) splits indexed parameters out of the topics and decodes non-indexed parameters from the data blob. By default it verifies that `topics[0]` matches the keccak256 of the event signature. An event parsed from a JSON ABI with `"anonymous": true` is handled natively — no `topics[0]` slot is expected and no signature check runs. Pass `check_event_signature: false` when the event is given as a signature string (which cannot express anonymity) or when `topics` intentionally omits the signature slot.

Errors come back as a closed atom-tagged set — `{:error, {:event_signature_mismatch, %{expected: _, got: _}}}` when `topics[0]` doesn't match the expected signature, `{:error, {:topics_length_mismatch, _}}` when the topic count is wrong for the indexed-parameter count, and `{:error, {:malformed_data, _}}` when the non-indexed payload fails to decode. Pattern-match the tag rather than parsing strings.

To build a matching `eth_getLogs` topic filter, pass indexed argument values to `ABI.encode_event_topics/2` in event order. Use `:any` for an unfiltered indexed slot.

```elixir
iex> hex = &Base.decode16!(&1, case: :lower)
iex> ABI.encode_event_topics(
...>   "Transfer(address indexed from,address indexed to,uint256 amount)",
...>   [hex.("b2b7c1795f19fbc28fda77a95e59edbb8b3709c8"), :any]
...> )
[
  hex.("ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"),
  hex.("000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8"),
  :any
]
```

```elixir
iex> hex = &Base.decode16!(&1, case: :lower)
iex> ABI.decode_event(
...>   "Transfer(address indexed from, address indexed to, uint256 amount)",
...>   hex.("00000000000000000000000000000000000000000000000000000004a817c800"),
...>   [
...>     hex.("ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"),
...>     hex.("000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8"),
...>     hex.("0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea")
...>   ]
...> )
{:ok, "Transfer",
 %{
   "amount" => 20_000_000_000,
   "from" => <<0xb2, 0xb7, 0xc1, 0x79, 0x5f, 0x19, 0xfb, 0xc2, 0x8f, 0xda, 0x77, 0xa9, 0x5e, 0x59, 0xed, 0xbb, 0x8b, 0x37, 0x09, 0xc8>>,
   "to"   => <<0x77, 0x95, 0x12, 0x6b, 0x3a, 0xe4, 0x68, 0xf4, 0x4c, 0x90, 0x12, 0x87, 0xde, 0x98, 0x59, 0x41, 0x98, 0xce, 0x38, 0xea>>
 }}
```

### Map and struct input to `encode/2`

For tuple/struct parameters whose `:name` is known (i.e. parsed from a JSON ABI, or declared in a `FunctionSelector` literal), `ABI.encode/2` accepts a plain `Map` in place of the raw tuple. Both atom keys and string keys are resolved, with camelCase ABI names auto-mapped to their snake_case atom form. The output is identical to the tuple-shaped input — useful when the encoded parameters originated from a prior `ABI.decode/3` call with `decode_structs: true`, or from Jason-decoded request payloads.

```elixir
iex> selector = %ABI.FunctionSelector{
...>   function: nil,
...>   types: [%{type: {:tuple, [
...>     %{name: "recipient", type: :address},
...>     %{name: "amount",    type: {:uint, 256}}
...>   ]}}]
...> }
iex> ABI.encode(selector, [%{recipient: <<1::160>>, amount: 1_000}])
...> ==
...>   ABI.encode(selector, [{<<1::160>>, 1_000}])
true
```

## Agent Integration

`hieroglyph` is annotated with [`descripex`](https://hex.pm/packages/descripex) so its public surface is discoverable at runtime and emittable as a static manifest. The intended consumer is downstream codegen / agent tooling — `cartouche`-generated contract bindings, `onchain*` packages, and any catalog that needs to verify or list ABI primitives — not human readers (use the regular hexdocs for that).

Progressive discovery via `ABI.describe/0..2`:

```elixir
ABI.describe()                 # Level 1: all annotated modules with namespaces
ABI.describe(:abi)             # Level 2: function list for the top-level ABI module
ABI.describe(:abi, :encode)    # Level 3: full hints — params, returns, errors, spec
```

Direct module introspection:

```elixir
ABI.__api__()                  # list of %{name, arity, hints, spec, ...} entries
ABI.__api__(:encode)           # one entry by name
```

Static manifest emission (JSON-serializable representation of every annotated function — params, returns, errors, specs, descriptions):

```bash
mix hieroglyph.manifest                    # writes api_manifest.json in project root
mix hieroglyph.manifest /path/to/out.json  # custom output path
mix hieroglyph.manifest --check            # fail if committed file drifted (ignores generated_at)

# Equivalent direct invocation of the descripex builtin:
mix descripex.manifest --app hieroglyph --pretty --output api_manifest.json
```

The manifest is suitable for downstream CI (cartouche-generated bindings, onchain consumers) to diff across `hieroglyph` version bumps as a contract-stability check — silent contract drift in this library propagates as compile errors three layers down through generated bindings into every onchain_<protocol> package.

## Support

Currently supports:

  * [X] `uint<M>`
  * [X] `int<M>`
  * [X] `address`
  * [X] `uint`
  * [X] `bool`
  * [ ] `fixed<M>x<N>`
  * [ ] `ufixed<M>x<N>`
  * [ ] `fixed`
  * [X] `bytes<M>`
  * [X] `function`
  * [X] `<type>[M]`
  * [X] `bytes`
  * [X] `string`
  * [X] `<type>[]`
  * [X] `(T1,T2,...,Tn)`

Round-trip safety — `decode(encode(x)) == x` — is property-tested with `stream_data` across every supported type above, including recursively nested tuples and fixed/dynamic arrays.

`function` is the 24-byte external function pointer (20-byte address ++ 4-byte selector); supplied to `ABI.encode/2` as a 24-byte binary, returned by `ABI.decode/3` in the same shape. Encoded as a 32-byte right-padded slot in standard mode, or 24 bytes tight in `ABI.encode_packed/2`.

### Why `fixed<M>x<N>` / `ufixed<M>x<N>` are deferred

Solidity itself does not fully support fixed-point types — quoting the [Solidity language docs](https://docs.soliditylang.org/en/latest/types.html): *"Fixed point numbers are not fully supported by Solidity yet. They can be declared, but cannot be assigned to or from."* Because no real contracts emit them, there is nothing to encode/decode in the wild; the cost of implementing a full encoder/decoder + range validation against a type the language itself can't use would be all build, no payoff. `ABI.FunctionSelector.decode/1`, `ABI.FunctionSelector.decode_type/1`, and `ABI.parse_specification/1` raise `ArgumentError` at parse time when a signature contains `fixed`/`ufixed` (bare or explicit-`M`x`N`, including nested in arrays or tuples), pointing at [exthereum/abi#54](https://github.com/exthereum/abi/issues/54) for tracking.

# Docs

* [Solidity ABI](https://docs.soliditylang.org/en/latest/abi-spec.html)
* [Solidity Docs](https://docs.soliditylang.org/)
* [Solidity Grammar](https://github.com/ethereum/solidity/blob/develop/docs/grammar.txt)
* [Exthereum Blockchain](https://github.com/exthereum/blockchain)

# Collaboration

MIT-licensed. Issues and PRs welcome at [ZenHive/onchain-stack](https://github.com/ZenHive/onchain-stack/issues). Upstream bugs affecting Solidity ABI semantics are also filed at [exthereum/abi](https://github.com/exthereum/abi/issues) — see `CHANGELOG.md` for cross-references.
