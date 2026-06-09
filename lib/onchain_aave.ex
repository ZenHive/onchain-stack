defmodule OnchainAave do
  @moduledoc """
  Aave V3 protocol wrappers for Elixir.

  Provides pool reads/writes, oracle price feeds, math conversions,
  and typed response structs. Built on the `onchain` core library.

  ## Discovery

  Use `OnchainAave.describe/0` for a module overview, `OnchainAave.describe/1` for
  function listings, and `OnchainAave.describe/2` for full function details.
  """

  use Descripex.Discoverable,
    modules: [
      Onchain.Aave.Contracts,
      Onchain.Aave.Math,
      Onchain.Aave.Oracle,
      Onchain.Aave.Pool,
      Onchain.Aave.DebtToken,
      Onchain.Aave.UiPoolDataProvider,
      Onchain.Aave.Faucet,
      Onchain.Aave.Types.UserAccountData,
      Onchain.Aave.Types.AggregatedReserveData,
      Onchain.Aave.Types.BaseCurrencyInfo,
      Onchain.Aave.Types.UserReserveData
    ]
end
