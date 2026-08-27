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
    {:onchain_js, "~> 0.3"}
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
mix test.json --quiet --include integration    # Integration tests (requires QuickBEAM)
```

## License

[MIT](LICENSE)
