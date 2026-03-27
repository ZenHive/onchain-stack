defmodule OnchainJs do
  @moduledoc """
  JavaScript bridge for Ethereum — run npm packages on the BEAM via QuickBEAM.

  Provides supervised QuickBEAM runtimes for loading and executing JavaScript
  libraries (solc-js, Uniswap SDK, DeFiSaver, merkletreejs) without Node.js.

  ## Portfolio

  | Package | Purpose |
  |---------|---------|
  | `onchain` | Core Ethereum primitives, RPC, ABI, signing |
  | `onchain_aave` | Aave V3 protocol wrappers |
  | `onchain_evm` | Rust NIFs: revm simulation, Solidity parsing, codegen |
  | **`onchain_js`** | JS bridge: npm packages on the BEAM via QuickBEAM |
  """
end
