# Cartouche contract development

Run commands from `packages/onchain`. Contract bindings now use the shared
`Onchain.Contract.Generator` at compile time; `mix cartouche.gen` and
`Cartouche.Contract.IConsole` were removed.

For a raw ABI JSON file:

```elixir
defmodule MyApp.Contract do
  use Onchain.Contract.Generator, abi_file: "priv/abis/contract.json"
end
```

For a Foundry artifact with init and runtime bytecode, use `artifact_file:`
with a path relative to the module source file. See the generator's module docs
for the generated read/write functions and Sleuth helpers.

`Cartouche.Contract.Sleuth` reads the vendored `priv/Sleuth.json` artifact and
marks its query functions as view calls, since they run inside `eth_call`.
Its source is [compound-finance/sleuth](https://github.com/compound-finance/sleuth).
Recompile after changing the artifact; its module declares it as an external resource.
