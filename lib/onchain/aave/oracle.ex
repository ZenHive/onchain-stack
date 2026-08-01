defmodule Onchain.Aave.Oracle do
  @moduledoc """
  Aave V3 Oracle and Chainlink price feed reads.

  Composes `Contracts`, `Contract`, and `Address` into single-call functions
  for fetching asset prices, Chainlink aggregator addresses, and base currency info.

  ## Chainlink Direct Read

  `get_latest_round_data/2` reads directly from a Chainlink aggregator contract
  (obtained via `get_source_of_asset/2`), bypassing the Aave oracle.

  ## Error Format

  Errors pass through from the underlying module that failed:

  | Source | Error Shape |
  |--------|-------------|
  | `Onchain.Address.validate/1` | `{:error, {:invalid_address, input}}` |
  | `Onchain.Aave.Contracts.address/2` | `{:error, {:unsupported_network, network}}` |
  | `Onchain.Contract.call/5` | `{:error, {:encode_error, ...}}`, `{:error, {:rpc_error, ...}}`, `{:error, {:decode_error, ...}}` |

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `get_asset_price/2` | Price of one asset in base currency units |
  | `get_asset_price!/2` | Same, raises on error |
  | `get_asset_prices/2` | Batch prices for multiple assets |
  | `get_asset_prices!/2` | Same, raises on error |
  | `get_source_of_asset/2` | Chainlink aggregator address for an asset |
  | `get_source_of_asset!/2` | Same, raises on error |
  | `get_base_currency/1` | Base currency token address |
  | `get_base_currency!/1` | Same, raises on error |
  | `get_base_currency_unit/1` | Base currency unit (10^decimals) |
  | `get_base_currency_unit!/1` | Same, raises on error |
  | `get_fallback_oracle/1` | Fallback oracle address |
  | `get_fallback_oracle!/1` | Same, raises on error |
  | `get_latest_round_data/2` | Chainlink aggregator latest round |
  | `get_latest_round_data!/2` | Same, raises on error |
  """

  use Descripex, namespace: "/aave/oracle"

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.Opts
  alias Onchain.Address
  alias Onchain.Contract

  # --- get_asset_price ---

  api(:get_asset_price, "Get the price of an asset in base currency units.",
    params: [
      asset: [kind: :value, description: "Asset address as 0x hex string or 20-byte binary"],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :network (default :ethereum), :rpc_url, :timeout, :block"
      ]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Price in base currency units (8 decimals for Aave V3 USD)"
    }
  )

  @spec get_asset_price(String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_asset_price(asset, opts \\ []) do
    {network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, asset_bin} <- Address.validate(asset),
         {:ok, oracle_addr} <- Contracts.address(:oracle, network_opts),
         {:ok, [price]} <-
           Contract.call(oracle_addr, "getAssetPrice(address)", [asset_bin], "(uint256)", rpc_opts) do
      {:ok, price}
    end
  end

  # --- get_asset_price! ---

  api(:get_asset_price!, "Get the price of an asset. Raises on error.",
    params: [
      asset: [kind: :value, description: "Asset address"],
      opts: [kind: :value, default: [], description: "Options: :network, :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :non_neg_integer, description: "Price in base currency units"}
  )

  @spec get_asset_price!(String.t() | binary(), keyword()) :: non_neg_integer()
  def get_asset_price!(asset, opts \\ []) do
    case get_asset_price(asset, opts) do
      {:ok, price} -> price
      {:error, reason} -> raise "get_asset_price failed: #{inspect(reason)}"
    end
  end

  # --- get_asset_prices ---

  api(:get_asset_prices, "Get prices for multiple assets in one call.",
    params: [
      assets: [kind: :value, description: "List of asset addresses"],
      opts: [kind: :value, default: [], description: "Options: :network, :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, [non_neg_integer()]} | {:error, term()}",
      description: "List of prices in base currency units"
    }
  )

  @spec get_asset_prices([String.t() | binary()], keyword()) ::
          {:ok, [non_neg_integer()]} | {:error, term()}
  def get_asset_prices(assets, opts \\ []) when is_list(assets) do
    {network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, asset_bins} <- Opts.validate_addresses(assets),
         {:ok, oracle_addr} <- Contracts.address(:oracle, network_opts),
         {:ok, [prices]} <-
           Contract.call(
             oracle_addr,
             "getAssetsPrices(address[])",
             [asset_bins],
             "(uint256[])",
             rpc_opts
           ) do
      {:ok, prices}
    end
  end

  # --- get_asset_prices! ---

  api(:get_asset_prices!, "Get prices for multiple assets. Raises on error.",
    params: [
      assets: [kind: :value, description: "List of asset addresses"],
      opts: [kind: :value, default: [], description: "Options: :network, :rpc_url, :timeout, :block"]
    ],
    returns: %{type: "[non_neg_integer()]", description: "List of prices"}
  )

  @spec get_asset_prices!([String.t() | binary()], keyword()) :: [non_neg_integer()]
  def get_asset_prices!(assets, opts \\ []) do
    case get_asset_prices(assets, opts) do
      {:ok, prices} -> prices
      {:error, reason} -> raise "get_asset_prices failed: #{inspect(reason)}"
    end
  end

  # --- get_source_of_asset ---

  api(:get_source_of_asset, "Get the Chainlink aggregator address for an asset.",
    params: [
      asset: [kind: :value, description: "Asset address"],
      opts: [kind: :value, default: [], description: "Options: :network, :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Checksummed Chainlink aggregator address"
    }
  )

  @spec get_source_of_asset(String.t() | binary(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def get_source_of_asset(asset, opts \\ []) do
    {network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, asset_bin} <- Address.validate(asset),
         {:ok, oracle_addr} <- Contracts.address(:oracle, network_opts),
         {:ok, [source_bin]} <-
           Contract.call(oracle_addr, "getSourceOfAsset(address)", [asset_bin], "(address)", rpc_opts) do
      Address.checksum(source_bin)
    end
  end

  # --- get_source_of_asset! ---

  api(:get_source_of_asset!, "Get the Chainlink aggregator address. Raises on error.",
    params: [
      asset: [kind: :value, description: "Asset address"],
      opts: [kind: :value, default: [], description: "Options: :network, :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :string, description: "Checksummed Chainlink aggregator address"}
  )

  @spec get_source_of_asset!(String.t() | binary(), keyword()) :: String.t()
  def get_source_of_asset!(asset, opts \\ []) do
    case get_source_of_asset(asset, opts) do
      {:ok, addr} -> addr
      {:error, reason} -> raise "get_source_of_asset failed: #{inspect(reason)}"
    end
  end

  # --- get_base_currency ---

  api(:get_base_currency, "Get the base currency token address.",
    params: [
      opts: [kind: :value, default: [], description: "Options: :network, :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Checksummed base currency address"
    }
  )

  @spec get_base_currency(keyword()) :: {:ok, String.t()} | {:error, term()}
  def get_base_currency(opts \\ []) do
    {network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, oracle_addr} <- Contracts.address(:oracle, network_opts),
         {:ok, [currency_bin]} <-
           Contract.call(oracle_addr, "BASE_CURRENCY()", [], "(address)", rpc_opts) do
      Address.checksum(currency_bin)
    end
  end

  # --- get_base_currency! ---

  api(:get_base_currency!, "Get the base currency token address. Raises on error.",
    params: [
      opts: [kind: :value, default: [], description: "Options: :network, :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :string, description: "Checksummed base currency address"}
  )

  @spec get_base_currency!(keyword()) :: String.t()
  def get_base_currency!(opts \\ []) do
    case get_base_currency(opts) do
      {:ok, addr} -> addr
      {:error, reason} -> raise "get_base_currency failed: #{inspect(reason)}"
    end
  end

  # --- get_base_currency_unit ---

  api(:get_base_currency_unit, "Get the base currency unit (10^decimals).",
    params: [
      opts: [kind: :value, default: [], description: "Options: :network, :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Base currency unit (e.g. 100000000 for 8-decimal USD)"
    }
  )

  @spec get_base_currency_unit(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def get_base_currency_unit(opts \\ []) do
    {network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, oracle_addr} <- Contracts.address(:oracle, network_opts),
         {:ok, [unit]} <-
           Contract.call(oracle_addr, "BASE_CURRENCY_UNIT()", [], "(uint256)", rpc_opts) do
      {:ok, unit}
    end
  end

  # --- get_base_currency_unit! ---

  api(:get_base_currency_unit!, "Get the base currency unit. Raises on error.",
    params: [
      opts: [kind: :value, default: [], description: "Options: :network, :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :non_neg_integer, description: "Base currency unit"}
  )

  @spec get_base_currency_unit!(keyword()) :: non_neg_integer()
  def get_base_currency_unit!(opts \\ []) do
    case get_base_currency_unit(opts) do
      {:ok, unit} -> unit
      {:error, reason} -> raise "get_base_currency_unit failed: #{inspect(reason)}"
    end
  end

  # --- get_fallback_oracle ---

  api(:get_fallback_oracle, "Get the fallback oracle address.",
    params: [
      opts: [kind: :value, default: [], description: "Options: :network, :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Checksummed fallback oracle address"
    }
  )

  @spec get_fallback_oracle(keyword()) :: {:ok, String.t()} | {:error, term()}
  def get_fallback_oracle(opts \\ []) do
    {network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, oracle_addr} <- Contracts.address(:oracle, network_opts),
         {:ok, [fallback_bin]} <-
           Contract.call(oracle_addr, "getFallbackOracle()", [], "(address)", rpc_opts) do
      Address.checksum(fallback_bin)
    end
  end

  # --- get_fallback_oracle! ---

  api(:get_fallback_oracle!, "Get the fallback oracle address. Raises on error.",
    params: [
      opts: [kind: :value, default: [], description: "Options: :network, :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :string, description: "Checksummed fallback oracle address"}
  )

  @spec get_fallback_oracle!(keyword()) :: String.t()
  def get_fallback_oracle!(opts \\ []) do
    case get_fallback_oracle(opts) do
      {:ok, addr} -> addr
      {:error, reason} -> raise "get_fallback_oracle failed: #{inspect(reason)}"
    end
  end

  # --- get_latest_round_data ---

  api(:get_latest_round_data, "Get the latest round data from a Chainlink aggregator.",
    params: [
      aggregator: [kind: :value, description: "Chainlink aggregator address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, map()} | {:error, term()}",
      description: "Map with :round_id, :answer, :started_at, :updated_at, :answered_in_round"
    }
  )

  @spec get_latest_round_data(String.t() | binary(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def get_latest_round_data(aggregator, opts \\ []) do
    with {:ok, [round_id, answer, started_at, updated_at, answered_in_round]} <-
           Contract.call(
             aggregator,
             "latestRoundData()",
             [],
             "(uint80,int256,uint256,uint256,uint80)",
             opts
           ) do
      {:ok,
       %{
         round_id: round_id,
         answer: answer,
         started_at: started_at,
         updated_at: updated_at,
         answered_in_round: answered_in_round
       }}
    end
  end

  # --- get_latest_round_data! ---

  api(:get_latest_round_data!, "Get the latest Chainlink round data. Raises on error.",
    params: [
      aggregator: [kind: :value, description: "Chainlink aggregator address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :map, description: "Round data map"}
  )

  @spec get_latest_round_data!(String.t() | binary(), keyword()) :: map()
  def get_latest_round_data!(aggregator, opts \\ []) do
    case get_latest_round_data(aggregator, opts) do
      {:ok, data} -> data
      {:error, reason} -> raise "get_latest_round_data failed: #{inspect(reason)}"
    end
  end
end
