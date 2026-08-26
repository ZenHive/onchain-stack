defmodule OnchainAerodrome do
  @moduledoc """
  Aerodrome Finance (Base, chain id 8453) bindings and analytics for Elixir.

  Aerodrome is a ve(3,3) exchange combining Solidly-style v2 pools (volatile
  and stable) with Slipstream concentrated-liquidity pools. This package
  provides the contract address registry, typed bindings, a Sugar-backed read
  API, and pure analytics over the returned structs. Built on the `onchain`
  core library.

  ## Layers

  Each layer is usable on its own and depends only on the ones below it —
  enforced by `.reach.exs`, not just documented:

  | Layer | Namespace | Needs |
  |-------|-----------|-------|
  | Registry / math | `Onchain.Aerodrome.Contracts`, `.Epoch`, `.Math` | nothing |
  | Types | `Onchain.Aerodrome.Types.*` | nothing |
  | Bindings | `Onchain.Aerodrome.Bindings.*` | an RPC endpoint |
  | Analytics | `Onchain.Aerodrome.Analytics.*` | structs only, no network |
  | Read API | `Onchain.Aerodrome.Sugar.*` | an RPC endpoint |
  | Writes | `Onchain.Aerodrome.Write.*` | calldata by default; a signer only if you opt in |

  ## Discovery

  Use `OnchainAerodrome.describe/0` for a module overview,
  `OnchainAerodrome.describe/1` for function listings, and
  `OnchainAerodrome.describe/2` for full function details.
  """

  use Descripex.Discoverable,
    modules: [
      Onchain.Aerodrome.Contracts
    ]
end
