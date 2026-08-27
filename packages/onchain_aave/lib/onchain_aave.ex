defmodule OnchainAave do
  @moduledoc """
  Aave V3 and V4 protocol wrappers for Elixir.

  Provides pool reads/writes, oracle price feeds, math conversions,
  typed response structs, and Aave V4 Hub, Spoke, oracle, Tokenization
  Spoke, and Position Manager wrappers. Built on the `onchain` core library.

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
      Onchain.Aave.Math.V4,
      Onchain.Aave.V4.Hub,
      Onchain.Aave.V4.Oracle,
      Onchain.Aave.V4.PositionManager,
      Onchain.Aave.V4.Spoke,
      Onchain.Aave.V4.TokenizationSpoke,
      Onchain.Aave.Types.UserAccountData,
      Onchain.Aave.Types.AggregatedReserveData,
      Onchain.Aave.Types.BaseCurrencyInfo,
      Onchain.Aave.Types.UserReserveData,
      Onchain.Aave.V4.Hub.Asset,
      Onchain.Aave.V4.Hub.AssetConfig,
      Onchain.Aave.V4.Hub.SpokeConfig,
      Onchain.Aave.V4.Hub.SpokeData,
      Onchain.Aave.V4.Types.SpokeDynamicReserveConfig,
      Onchain.Aave.V4.Types.SpokeLiquidationConfig,
      Onchain.Aave.V4.Types.SpokeReserveConfig,
      Onchain.Aave.V4.Types.SpokeReserveData,
      Onchain.Aave.V4.Types.SpokeUserData,
      Onchain.Aave.V4.Types.SpokeUserPosition
    ]
end
