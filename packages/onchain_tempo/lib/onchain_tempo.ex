defmodule OnchainTempo do
  @moduledoc """
  Tempo blockchain primitives for Elixir.

  Provides 0x76 transaction handling (deserialize, build, sign, co-sign),
  TIP-20 token calldata encoding, Tempo-specific RPC operations, and
  TransferWithMemo event log parsing.

  Built on the [onchain](https://hex.pm/packages/onchain) core library.

  ## Discovery

  Use `OnchainTempo.describe/0` for a module overview, `OnchainTempo.describe/1`
  for function listings, and `OnchainTempo.describe/2` for full function details.
  """
  use Descripex.Discoverable,
    modules: [
      Onchain.Tempo.TIP20,
      Onchain.Tempo.Transaction,
      Onchain.Tempo.Transaction.Builder,
      Onchain.Tempo.RPC,
      Onchain.Tempo.Transfer,
      Onchain.Tempo.Faucet
    ]
end
