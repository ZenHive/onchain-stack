defmodule Onchain do
  @moduledoc """
  Shared Ethereum/blockchain library providing read and write capabilities.

  Uses `cartouche` as the sole Ethereum dependency for RPC calls, ABI encoding,
  transaction signing, and cryptographic operations.

  ## Discovery

  Use `Onchain.describe/0` for a module overview, `Onchain.describe/1` for
  function listings, and `Onchain.describe/2` for full function details.

  """

  use Descripex.Discoverable,
    modules: [
      Cartouche.Hex,
      ABI,
      Onchain.Address,
      Onchain.Decimal,
      Cartouche.RPC,
      Cartouche.Block,
      Onchain.Contract,
      Onchain.DEX.Router,
      Onchain.ERC20,
      Onchain.ERC721,
      Onchain.ERC1155,
      Onchain.ENS,
      Onchain.Multicall,
      Cartouche.Signer,
      Onchain.Subscription,
      Onchain.Transfer,
      Onchain.Wallet,
      Onchain.AA
    ]
end
