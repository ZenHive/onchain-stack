# Onchain JS

JavaScript bridge for Ethereum — run npm packages on the BEAM via [QuickBEAM](https://hex.pm/packages/quickbeam). No Node.js required. Built on [onchain](https://github.com/ZenHive/onchain-stack/tree/main/packages/onchain).

## Package Family

| Package | Purpose | Native Deps |
|---------|---------|-------------|
| [onchain](https://github.com/ZenHive/onchain-stack/tree/main/packages/onchain) | Core Ethereum primitives, RPC, ABI, signing | None (pure Elixir) |
| [onchain_aave](https://github.com/ZenHive/onchain-stack/tree/main/packages/onchain_aave) | Aave V3 protocol wrappers | None (pure Elixir) |
| [onchain_evm](https://github.com/ZenHive/onchain-stack/tree/main/packages/onchain_evm) | Rust NIFs: revm simulation, Solidity parsing, codegen | Rustler |
| **onchain_js** (this) | JS bridge: npm packages on the BEAM | QuickBEAM (Zig NIF) |

Pick what you need — consumers who only need `eth_call` never compile Zig or Rust.

## Installation

```elixir
def deps do
  [
    {:onchain_js, "~> 0.5"}
  ]
end
```

## Use Cases

- **solc-js compilation** — `.sol` → ABI + bytecode without installing solc natively
- **Uniswap v3 SDK routing** — optimal swap paths, price impact via `@uniswap/v3-sdk`
- **DeFiSaver recipe builder** — flash loan recipes via `@defisaver/sdk`
- **Merkle proof construction** — airdrop claims, storage proofs via `merkletreejs`
- **Aave math cross-validation** — validate Elixir math against `@aave/math-utils`
- **1inch Fusion SDK** — DEX aggregation across protocols

## How It Works

QuickBEAM embeds QuickJS-NG as a Zig NIF. Each runtime is a GenServer with a persistent JavaScript context. npm_ex manages package installation without Node.js.

## Loading npm packages

npm packages are installed at **build time**, never at runtime. Nothing in this library contacts the npm registry.

1. Declare the packages in a `package.json` at your project root and install them with npm_ex. Commit `package.json` and `npm.lock`; `node_modules/` stays untracked.

   ```bash
   mix npm.install @noble/hashes@^2.4.0   # adds to package.json, writes npm.lock
   mix npm.ci                              # in every build: reproduce node_modules/ from npm.lock
   ```

   `mix npm.ci` installs exactly the locked versions. npm_ex 0.7.6 does not check that they still satisfy the ranges in `package.json`, and `mix npm.install` reports "Already up to date" for the same reason. After changing a range, run `mix npm.update <pkg>` to re-resolve, then commit the new `npm.lock`.

2. Write an entry script that imports from npm and puts what Elixir should call on `globalThis`:

   ```javascript
   // priv/js/keccak.js
   import { keccak_256 } from "@noble/hashes/sha3.js";
   import { bytesToHex, utf8ToBytes } from "@noble/hashes/utils.js";

   globalThis.keccak256Hex = (text) => bytesToHex(keccak_256(utf8ToBytes(text)));
   ```

3. Bundle and load it into a runtime, then call it:

   ```elixir
   {:ok, rt} = OnchainJs.Runtime.start_link()
   :ok = OnchainJs.Script.load(rt, "priv/js/keccak.js")
   {:ok, "4e03657a" <> _} = OnchainJs.Runtime.call(rt, "keccak256Hex", ["abc"])
   ```

`OnchainJs.Script.load/3` applies the browser stubs (`self`, `window`, `navigator`, `location`) before the bundle runs, which `Runtime.start_link(script: path)` cannot do. Bare imports resolve the way Node resolves them, by walking up from the importing file to the first ancestor directory with a matching `node_modules/<package>`, so `node_modules/` must sit in the entry script's directory or above it. There is no path override; `node_modules:` is rejected with `{:bundle_error, entry, {:unsupported_option, :node_modules}}`. In a Mix release the source tree is gone, so ship both under your app's `priv/`, as `priv/node_modules/` and `priv/js/app.js`, and load `Application.app_dir(:my_app, "priv/js/app.js")`. Failures come back tagged with the underlying message: `{:bundle_error, entry, reason}` (unreadable file, unresolved import, parse error) or `{:eval_error, entry, %QuickBEAM.JSError{}}` (the script threw, for example a missing browser global).

Hex does not ship this package's own `package.json`, `npm.lock` or `node_modules/`. Those exist only for its tests, so a consuming app always supplies its own.

## Discovery

The API describes itself, so an agent can learn how to call it without reading the source:

```elixir
OnchainJs.describe()                  # modules and namespaces
OnchainJs.describe(:runtime)          # function list with specs
OnchainJs.describe(:runtime, :eval)   # params, kinds, defaults, return shape
```

Parameters are tagged by kind: `:value` is something you supply, `:exchange_data` is something you must obtain first (the runtime handle names `start_link/1` as its source). `Descripex.Manifest.build/1` renders the whole surface as JSON and `Descripex.MCP.tools/1` renders it as MCP tool definitions.

## Testing

```bash
mix test.json --quiet                          # Unit tests
mix npm.ci                                     # Install node_modules/ from npm.lock (integration tests need it)
mix test.json --quiet --include integration    # Integration tests (requires QuickBEAM)
```

## License

[MIT](LICENSE)
