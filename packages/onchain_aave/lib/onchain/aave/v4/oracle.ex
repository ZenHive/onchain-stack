defmodule Onchain.Aave.V4.Oracle do
  @moduledoc """
  Aave V4 Spoke-scoped oracle reads.

  V4 has no protocol-wide oracle. Each Spoke owns an `IAaveOracle` (resolved
  via `ISpoke.ORACLE()`), and prices are keyed by Spoke **reserve id**, not
  underlying asset address. Pass a Spoke address instead of a network.

  V3 `BASE_CURRENCY` / `BASE_CURRENCY_UNIT` / `getFallbackOracle` have no
  V4 equivalent — `decimals/2` is the price scale (V4 oracles are 8 decimals).
  Direct Chainlink / `IPriceFeed` reads take a feed address, not a Spoke.

  ## Error Format

  Errors pass through from the underlying module that failed:

  | Source | Error Shape |
  |--------|-------------|
  | `Onchain.Address.validate/1` | `{:error, {:invalid_address, input}}` |
  | `Onchain.Contract.call/5` | `{:error, {:encode_error, ...}}`, `{:error, {:rpc_error, ...}}`, `{:error, {:decode_error, ...}}` |

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `oracle_address/2` | Spoke's `IAaveOracle` via `ISpoke.ORACLE()` |
  | `get_reserve_price/3` | Price of one reserve (`getReservePrice`) |
  | `get_reserve_prices/3` | Batch prices (`getReservesPrices`) |
  | `get_reserve_source/3` | `IPriceFeed` for a reserve (`getReserveSource`) |
  | `decimals/2` | Oracle price decimals |
  | `get_spoke/2` | Spoke this oracle is bound to (`spoke()`) |
  | `get_asset_price/3` | V3-shaped alias of `get_reserve_price/3` |
  | `get_asset_prices/3` | V3-shaped alias of `get_reserve_prices/3` |
  | `get_source_of_asset/3` | V3-shaped alias of `get_reserve_source/3` |
  | `get_latest_round_data/2` | Chainlink aggregator `latestRoundData` |
  | `get_latest_answer/2` | `IPriceFeed.latestAnswer` (what V4 AaveOracle reads) |
  """

  use Descripex, namespace: "/aave/v4/oracle"

  alias Onchain.Aave.Opts
  alias Onchain.Aave.Oracle, as: V3Oracle
  alias Onchain.Address
  alias Onchain.Contract

  @opts_desc "Options: :rpc_url, :timeout, :block"
  @spoke_desc "Spoke address as 0x hex string or 20-byte binary"
  @reserve_id_desc "Spoke reserve identifier"
  @reserve_ids_desc "List of Spoke reserve identifiers"

  api(:oracle_address, "Resolve a Spoke's IAaveOracle via ISpoke.ORACLE().",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Checksummed IAaveOracle address"
    }
  )

  @spec oracle_address(String.t() | binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def oracle_address(spoke, opts \\ []) do
    {_network_opts, rpc_opts} = Opts.split_network(opts)

    spoke
    |> Contract.call("ORACLE()", [], "(address)", rpc_opts)
    |> unwrap_address()
  end

  api(:oracle_address!, "Resolve a Spoke's IAaveOracle. Raises on error.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: :string, description: "Checksummed IAaveOracle address"}
  )

  @spec oracle_address!(String.t() | binary(), keyword()) :: String.t()
  def oracle_address!(spoke, opts \\ []), do: bang!(oracle_address(spoke, opts), "oracle_address")

  api(:get_reserve_price, "Price of a Spoke reserve in oracle base units.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Price in oracle decimals (8 for V4)"
    }
  )

  @spec get_reserve_price(String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_reserve_price(spoke, reserve_id, opts \\ []) when is_integer(reserve_id) and reserve_id >= 0 do
    spoke
    |> call_oracle("getReservePrice(uint256)", [reserve_id], "(uint256)", opts)
    |> unwrap_uint()
  end

  api(:get_reserve_price!, "Price of a Spoke reserve. Raises on error.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: :non_neg_integer, description: "Price in oracle decimals"}
  )

  @spec get_reserve_price!(String.t() | binary(), non_neg_integer(), keyword()) :: non_neg_integer()
  def get_reserve_price!(spoke, reserve_id, opts \\ []),
    do: bang!(get_reserve_price(spoke, reserve_id, opts), "get_reserve_price")

  api(:get_reserve_prices, "Prices for multiple Spoke reserves in one call.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_ids: [kind: :value, description: @reserve_ids_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, [non_neg_integer()]} | {:error, term()}",
      description: "Prices in oracle decimals, same order as reserve_ids"
    }
  )

  @spec get_reserve_prices(String.t() | binary(), [non_neg_integer()], keyword()) ::
          {:ok, [non_neg_integer()]} | {:error, term()}
  def get_reserve_prices(spoke, reserve_ids, opts \\ []) when is_list(reserve_ids) do
    spoke
    |> call_oracle("getReservesPrices(uint256[])", [reserve_ids], "(uint256[])", opts)
    |> unwrap_uints()
  end

  api(:get_reserve_prices!, "Prices for multiple Spoke reserves. Raises on error.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_ids: [kind: :value, description: @reserve_ids_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "[non_neg_integer()]", description: "List of prices"}
  )

  @spec get_reserve_prices!(String.t() | binary(), [non_neg_integer()], keyword()) ::
          [non_neg_integer()]
  def get_reserve_prices!(spoke, reserve_ids, opts \\ []),
    do: bang!(get_reserve_prices(spoke, reserve_ids, opts), "get_reserve_prices")

  api(:get_reserve_source, "IPriceFeed (Chainlink-style) address for a Spoke reserve.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Checksummed price-feed address"
    }
  )

  @spec get_reserve_source(String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def get_reserve_source(spoke, reserve_id, opts \\ []) when is_integer(reserve_id) and reserve_id >= 0 do
    spoke
    |> call_oracle("getReserveSource(uint256)", [reserve_id], "(address)", opts)
    |> unwrap_address()
  end

  api(:get_reserve_source!, "IPriceFeed address for a Spoke reserve. Raises on error.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: :string, description: "Checksummed price-feed address"}
  )

  @spec get_reserve_source!(String.t() | binary(), non_neg_integer(), keyword()) :: String.t()
  def get_reserve_source!(spoke, reserve_id, opts \\ []),
    do: bang!(get_reserve_source(spoke, reserve_id, opts), "get_reserve_source")

  api(:decimals, "Number of decimals used to return Spoke oracle prices.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Price decimals (8 on V4)"
    }
  )

  @spec decimals(String.t() | binary(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def decimals(spoke, opts \\ []) do
    spoke
    |> call_oracle("decimals()", [], "(uint8)", opts)
    |> unwrap_uint()
  end

  api(:decimals!, "Oracle price decimals. Raises on error.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: :non_neg_integer, description: "Price decimals"}
  )

  @spec decimals!(String.t() | binary(), keyword()) :: non_neg_integer()
  def decimals!(spoke, opts \\ []), do: bang!(decimals(spoke, opts), "decimals")

  api(:get_spoke, "Spoke address this IAaveOracle is bound to.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Checksummed Spoke address from IPriceOracle.spoke()"
    }
  )

  @spec get_spoke(String.t() | binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def get_spoke(spoke, opts \\ []) do
    spoke
    |> call_oracle("spoke()", [], "(address)", opts)
    |> unwrap_address()
  end

  api(:get_spoke!, "Spoke this oracle is bound to. Raises on error.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: :string, description: "Checksummed Spoke address"}
  )

  @spec get_spoke!(String.t() | binary(), keyword()) :: String.t()
  def get_spoke!(spoke, opts \\ []), do: bang!(get_spoke(spoke, opts), "get_spoke")

  api(
    :get_asset_price,
    "V3-shaped alias of get_reserve_price/3. The second argument is a Spoke reserve id, not an asset address.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Price in oracle decimals"
    }
  )

  @spec get_asset_price(String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_asset_price(spoke, reserve_id, opts \\ []), do: get_reserve_price(spoke, reserve_id, opts)

  api(:get_asset_price!, "V3-shaped alias of get_reserve_price!/3. Raises on error.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: :non_neg_integer, description: "Price in oracle decimals"}
  )

  @spec get_asset_price!(String.t() | binary(), non_neg_integer(), keyword()) :: non_neg_integer()
  def get_asset_price!(spoke, reserve_id, opts \\ []), do: get_reserve_price!(spoke, reserve_id, opts)

  api(
    :get_asset_prices,
    "V3-shaped alias of get_reserve_prices/3. Arguments are Spoke reserve ids, not asset addresses.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_ids: [kind: :value, description: @reserve_ids_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, [non_neg_integer()]} | {:error, term()}",
      description: "List of prices"
    }
  )

  @spec get_asset_prices(String.t() | binary(), [non_neg_integer()], keyword()) ::
          {:ok, [non_neg_integer()]} | {:error, term()}
  def get_asset_prices(spoke, reserve_ids, opts \\ []), do: get_reserve_prices(spoke, reserve_ids, opts)

  api(:get_asset_prices!, "V3-shaped alias of get_reserve_prices!/3. Raises on error.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_ids: [kind: :value, description: @reserve_ids_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "[non_neg_integer()]", description: "List of prices"}
  )

  @spec get_asset_prices!(String.t() | binary(), [non_neg_integer()], keyword()) ::
          [non_neg_integer()]
  def get_asset_prices!(spoke, reserve_ids, opts \\ []), do: get_reserve_prices!(spoke, reserve_ids, opts)

  api(
    :get_source_of_asset,
    "V3-shaped alias of get_reserve_source/3. The second argument is a Spoke reserve id, not an asset address.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Checksummed price-feed address"
    }
  )

  @spec get_source_of_asset(String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def get_source_of_asset(spoke, reserve_id, opts \\ []), do: get_reserve_source(spoke, reserve_id, opts)

  api(:get_source_of_asset!, "V3-shaped alias of get_reserve_source!/3. Raises on error.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: :string, description: "Checksummed price-feed address"}
  )

  @spec get_source_of_asset!(String.t() | binary(), non_neg_integer(), keyword()) :: String.t()
  def get_source_of_asset!(spoke, reserve_id, opts \\ []), do: get_reserve_source!(spoke, reserve_id, opts)

  api(:get_latest_round_data, "Latest round data from a Chainlink aggregator.",
    params: [
      aggregator: [kind: :value, description: "Chainlink aggregator / IPriceFeed address"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, map()} | {:error, term()}",
      description: "Map with :round_id, :answer, :started_at, :updated_at, :answered_in_round"
    }
  )

  @spec get_latest_round_data(String.t() | binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_latest_round_data(aggregator, opts \\ []) do
    {_network_opts, rpc_opts} = Opts.split_network(opts)
    V3Oracle.get_latest_round_data(aggregator, rpc_opts)
  end

  api(:get_latest_round_data!, "Latest Chainlink round data. Raises on error.",
    params: [
      aggregator: [kind: :value, description: "Chainlink aggregator / IPriceFeed address"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: :map, description: "Round data map"}
  )

  @spec get_latest_round_data!(String.t() | binary(), keyword()) :: map()
  def get_latest_round_data!(aggregator, opts \\ []),
    do: bang!(get_latest_round_data(aggregator, opts), "get_latest_round_data")

  api(:get_latest_answer, "Latest IPriceFeed answer (the call V4 AaveOracle uses).",
    params: [
      feed: [kind: :value, description: "IPriceFeed / Chainlink aggregator address"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, integer()} | {:error, term()}",
      description: "Signed price answer in feed decimals"
    }
  )

  @spec get_latest_answer(String.t() | binary(), keyword()) :: {:ok, integer()} | {:error, term()}
  def get_latest_answer(feed, opts \\ []) do
    {_network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, [answer]} <- Contract.call(feed, "latestAnswer()", [], "(int256)", rpc_opts) do
      {:ok, answer}
    end
  end

  api(:get_latest_answer!, "Latest IPriceFeed answer. Raises on error.",
    params: [
      feed: [kind: :value, description: "IPriceFeed / Chainlink aggregator address"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: :integer, description: "Signed price answer"}
  )

  @spec get_latest_answer!(String.t() | binary(), keyword()) :: integer()
  def get_latest_answer!(feed, opts \\ []), do: bang!(get_latest_answer(feed, opts), "get_latest_answer")

  @spec call_oracle(String.t() | binary(), String.t(), list(), String.t(), keyword()) ::
          {:ok, list()} | {:error, term()}
  defp call_oracle(spoke, signature, params, return_type, opts) do
    {_network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, oracle} <- oracle_address(spoke, rpc_opts) do
      Contract.call(oracle, signature, params, return_type, rpc_opts)
    end
  end

  @spec unwrap_uint({:ok, list()} | {:error, term()}) :: {:ok, non_neg_integer()} | {:error, term()}
  defp unwrap_uint({:ok, [value]}) when is_integer(value) and value >= 0, do: {:ok, value}
  defp unwrap_uint({:error, _} = error), do: error

  @spec unwrap_uints({:ok, list()} | {:error, term()}) ::
          {:ok, [non_neg_integer()]} | {:error, term()}
  defp unwrap_uints({:ok, [values]}) when is_list(values), do: {:ok, values}
  defp unwrap_uints({:error, _} = error), do: error

  @spec unwrap_address({:ok, list()} | {:error, term()}) :: {:ok, String.t()} | {:error, term()}
  defp unwrap_address({:ok, [bin]}) when is_binary(bin), do: Address.checksum(bin)
  defp unwrap_address({:error, _} = error), do: error

  @spec bang!({:ok, term()} | {:error, term()}, String.t()) :: term()
  defp bang!({:ok, value}, _name), do: value
  defp bang!({:error, reason}, name), do: raise("#{name} failed: #{inspect(reason)}")
end
