defmodule OnchainEvm do
  @moduledoc """
  EVM simulation, Solidity parsing, debug/trace APIs, and contract codegen for Elixir.

  Provides Rust NIF-powered local EVM execution (revm), Solidity ABI parsing (Alloy),
  debug/trace APIs, and compile-time contract code generation. Built on the `onchain` core library.

  ## Discovery

  Use `OnchainEvm.describe/0` for a module overview, `OnchainEvm.describe/1` for
  function listings, and `OnchainEvm.describe/2` for full function details.
  """

  use Descripex.Discoverable,
    modules: [
      Onchain.EVM,
      Onchain.Solidity,
      Onchain.Trace,
      Onchain.Contract.Generator
    ]
end
