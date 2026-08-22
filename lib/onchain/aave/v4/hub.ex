defmodule Onchain.Aave.V4.Hub do
  @moduledoc """
  Aave V4 Hub read operations.

  One module for all three Hubs (Core, Prime, Plus). Wraps Hub-level reads:
  member Spokes, credit-line inventory and caps, the Hub rate environment /
  utilization, IHubBase share-to-asset preview converters, and IHub bound
  constants. Amounts stay raw integers (token units, RAY, BPS) — conversion
  is the caller's job given per-asset decimals.

  ## Error Format

  Errors pass through from the underlying module that failed:

  | Source | Error Shape |
  |--------|-------------|
  | Hub atom | `{:error, {:unknown_hub, hub}}` |
  | `Onchain.Address.validate/1` | `{:error, {:invalid_address, input}}` |
  | `Onchain.Aave.Contracts.address/2` | `{:error, {:unsupported_network, network}}`, `{:error, {:unknown_contract, key}}` |
  | `Onchain.Contract.call/5` | `{:error, {:encode_error, ...}}`, `{:error, {:rpc_error, ...}}`, `{:error, {:decode_error, ...}}` |

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `hub_address/2` | Resolve `:core` / `:prime` / `:plus` to the Hub contract |
  | `get_spoke_count/3` | Member Spokes listed for an asset |
  | `is_spoke_listed/4` | Whether a Spoke is listed for an asset |
  | `get_spoke_address/4` | Spoke address at a list index |
  | `get_spoke/4` | Credit-line inventory + caps (`SpokeData`) |
  | `get_spoke_config/4` | Caps / threshold / active / halted |
  | `get_spoke_added_assets/4` | Assets added by a Spoke |
  | `get_spoke_added_shares/4` | Shares added by a Spoke |
  | `get_spoke_drawn_shares/4` | Drawn shares (credit line drawn) |
  | `get_spoke_owed/4` | Drawn + premium owed by a Spoke |
  | `get_spoke_total_owed/4` | Total owed by a Spoke |
  | `get_spoke_premium_ray/4` | Premium owed by a Spoke (RAY) |
  | `get_spoke_premium_data/4` | Premium shares + offset for a Spoke |
  | `get_spoke_deficit_ray/4` | Spoke deficit (RAY) |
  | `underlying_listed?/3` | Whether an underlying is listed |
  | `get_asset_count/2` | Listed assets on the Hub |
  | `get_asset/3` | Full `Asset` (liquidity, rates, shares) |
  | `get_asset_config/3` | Fee receiver, fee, strategy, controller |
  | `get_added_assets/3` | Total assets added across Spokes |
  | `get_added_shares/3` | Total shares added across Spokes |
  | `get_asset_liquidity/3` | Available liquidity |
  | `get_asset_owed/3` | Hub-wide drawn + premium owed |
  | `get_asset_total_owed/3` | Hub-wide total owed |
  | `get_asset_premium_ray/3` | Hub-wide premium owed (RAY) |
  | `get_asset_drawn_shares/3` | Hub-wide drawn shares |
  | `get_asset_premium_data/3` | Hub-wide premium shares + offset |
  | `get_asset_deficit_ray/3` | Hub-wide deficit (RAY) |
  | `get_asset_accrued_fees/3` | Accrued fees not yet minted |
  | `get_asset_swept/3` | Liquidity held by the reinvestment controller |
  | `get_asset_drawn_rate/3` | Current drawn rate (RAY) |
  | `get_asset_drawn_index/3` | Current drawn index (RAY) |
  | `get_asset_id/3` | Asset id for an underlying |
  | `get_asset_underlying_and_decimals/3` | Underlying token + decimals |
  | `preview_add_by_assets/4` | Shares added for assets (round down) |
  | `preview_add_by_shares/4` | Assets added for shares (round up) |
  | `preview_remove_by_assets/4` | Shares removed for assets (round up) |
  | `preview_remove_by_shares/4` | Assets removed for shares (round down) |
  | `preview_draw_by_assets/4` | Shares drawn for assets (round up) |
  | `preview_draw_by_shares/4` | Assets drawn for shares (round down) |
  | `preview_restore_by_assets/4` | Shares restored for assets (round down) |
  | `preview_restore_by_shares/4` | Assets restored for shares (round up) |
  | `max_allowed_underlying_decimals/2` | Inclusive max underlying decimals |
  | `min_allowed_underlying_decimals/2` | Inclusive min underlying decimals |
  | `max_allowed_spoke_cap/2` | SpokeConfig add/draw cap sentinel (no cap) |
  | `max_risk_premium_threshold/2` | SpokeConfig risk-premium sentinel (no threshold) |
  """

  use Descripex, namespace: "/aave/v4/hub"

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.Opts
  alias Onchain.Aave.V4.Hub.Asset
  alias Onchain.Aave.V4.Hub.AssetConfig
  alias Onchain.Aave.V4.Hub.SpokeConfig
  alias Onchain.Aave.V4.Hub.SpokeData
  alias Onchain.Address
  alias Onchain.Contract

  @type hub :: :core | :prime | :plus

  @hub_contracts %{core: :v4_core_hub, prime: :v4_prime_hub, plus: :v4_plus_hub}

  @asset_response "((uint120,uint120,uint8,uint120,uint120,int200,uint120,uint120,uint16,uint120,uint96,uint40,address,address,address,address,uint200))"
  @asset_config_response "((address,uint16,address,address))"
  @spoke_data_response "((uint120,uint120,int200,uint120,uint40,uint40,uint24,bool,bool,uint200))"
  @spoke_config_response "((uint40,uint40,uint24,bool,bool))"

  @opts_desc "Options: :network (default :ethereum), :rpc_url, :timeout, :block"
  @hub_desc "Hub atom: :core, :prime, or :plus"
  @asset_id_desc "Hub asset identifier"
  @spoke_desc "Spoke address as 0x hex string or 20-byte binary"
  @assets_desc "Asset amount in token units"
  @shares_desc "Share amount"

  # --- hub_address ---

  api(:hub_address, "Resolve a V4 Hub atom to its checksummed contract address.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      opts: [kind: :value, default: [], description: "Options: [network: :ethereum]"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Checksummed Hub address",
      example: "0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9"
    }
  )

  @spec hub_address(atom(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def hub_address(hub, opts \\ []) do
    case Map.fetch(@hub_contracts, hub) do
      {:ok, key} -> Contracts.address(key, opts)
      :error -> {:error, {:unknown_hub, hub}}
    end
  end

  # --- get_spoke_count ---

  api(:get_spoke_count, "Number of Spokes listed for an asset on the Hub.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Listed spoke count"}
  )

  @spec get_spoke_count(hub(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_spoke_count(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_uint(hub, "getSpokeCount(uint256)", [asset_id], opts)
  end

  # --- is_spoke_listed ---

  api(:is_spoke_listed, "Whether a Spoke is listed for an asset on the Hub.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, boolean()} | {:error, term()}", description: "true if the Spoke is listed"}
  )

  @spec is_spoke_listed(hub(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, boolean()} | {:error, term()}
  def is_spoke_listed(hub, asset_id, spoke, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    hub
    |> call_spoke("isSpokeListed(uint256,address)", "(bool)", asset_id, spoke, opts)
    |> unwrap_bool()
  end

  # --- get_spoke_address ---

  api(:get_spoke_address, "Spoke address for an asset at the given list index.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      index: [kind: :value, description: "Zero-based index into the Hub's spoke list"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: "Checksummed Spoke address"}
  )

  @spec get_spoke_address(hub(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def get_spoke_address(hub, asset_id, index, opts \\ [])
      when is_integer(asset_id) and asset_id >= 0 and is_integer(index) and index >= 0 do
    hub
    |> call_hub("getSpokeAddress(uint256,uint256)", [asset_id, index], "(address)", opts)
    |> unwrap_address()
  end

  # --- get_spoke ---

  api(:get_spoke, "Spoke credit-line inventory and caps for an asset.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, SpokeData.t()} | {:error, term()}", description: "SpokeData struct"}
  )

  @spec get_spoke(hub(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, SpokeData.t()} | {:error, term()}
  def get_spoke(hub, asset_id, spoke, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    hub
    |> call_spoke("getSpoke(uint256,address)", @spoke_data_response, asset_id, spoke, opts)
    |> unwrap_spoke_data()
  end

  # --- get_spoke_config ---

  api(:get_spoke_config, "Spoke caps, risk-premium threshold, and active/halted flags.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, SpokeConfig.t()} | {:error, term()}", description: "SpokeConfig struct"}
  )

  @spec get_spoke_config(hub(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, SpokeConfig.t()} | {:error, term()}
  def get_spoke_config(hub, asset_id, spoke, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    hub
    |> call_spoke("getSpokeConfig(uint256,address)", @spoke_config_response, asset_id, spoke, opts)
    |> unwrap_spoke_config()
  end

  # --- get_spoke_added_assets ---

  api(:get_spoke_added_assets, "Assets added to the Hub by a Spoke.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Added assets (token units)"}
  )

  @spec get_spoke_added_assets(hub(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_spoke_added_assets(hub, asset_id, spoke, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_spoke_uint(hub, "getSpokeAddedAssets(uint256,address)", asset_id, spoke, opts)
  end

  # --- get_spoke_added_shares ---

  api(:get_spoke_added_shares, "Shares added to the Hub by a Spoke.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Added shares"}
  )

  @spec get_spoke_added_shares(hub(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_spoke_added_shares(hub, asset_id, spoke, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_spoke_uint(hub, "getSpokeAddedShares(uint256,address)", asset_id, spoke, opts)
  end

  # --- get_spoke_drawn_shares ---

  api(:get_spoke_drawn_shares, "Drawn shares of an asset for a Spoke.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Drawn shares"}
  )

  @spec get_spoke_drawn_shares(hub(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_spoke_drawn_shares(hub, asset_id, spoke, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_spoke_uint(hub, "getSpokeDrawnShares(uint256,address)", asset_id, spoke, opts)
  end

  # --- get_spoke_owed ---

  api(:get_spoke_owed, "Drawn and premium amounts a Spoke owes the Hub.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, {non_neg_integer(), non_neg_integer()}} | {:error, term()}",
      description: "{drawn, premium} in token units"
    }
  )

  @spec get_spoke_owed(hub(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, {non_neg_integer(), non_neg_integer()}} | {:error, term()}
  def get_spoke_owed(hub, asset_id, spoke, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    hub
    |> call_spoke("getSpokeOwed(uint256,address)", "(uint256,uint256)", asset_id, spoke, opts)
    |> unwrap_pair()
  end

  # --- get_spoke_total_owed ---

  api(:get_spoke_total_owed, "Total amount a Spoke owes the Hub for an asset.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Total owed (token units)"}
  )

  @spec get_spoke_total_owed(hub(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_spoke_total_owed(hub, asset_id, spoke, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_spoke_uint(hub, "getSpokeTotalOwed(uint256,address)", asset_id, spoke, opts)
  end

  # --- get_spoke_premium_ray ---

  api(:get_spoke_premium_ray, "Premium a Spoke owes the Hub, RAY-scaled.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Premium owed, RAY-scaled"}
  )

  @spec get_spoke_premium_ray(hub(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_spoke_premium_ray(hub, asset_id, spoke, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_spoke_uint(hub, "getSpokePremiumRay(uint256,address)", asset_id, spoke, opts)
  end

  # --- get_spoke_premium_data ---

  api(:get_spoke_premium_data, "Premium shares and offset for a Spoke.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, {non_neg_integer(), integer()}} | {:error, term()}",
      description: "{premium shares, premium offset RAY}"
    }
  )

  @spec get_spoke_premium_data(hub(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, {non_neg_integer(), integer()}} | {:error, term()}
  def get_spoke_premium_data(hub, asset_id, spoke, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    hub
    |> call_spoke("getSpokePremiumData(uint256,address)", "(uint256,int256)", asset_id, spoke, opts)
    |> unwrap_premium_data()
  end

  # --- get_spoke_deficit_ray ---

  api(:get_spoke_deficit_ray, "Spoke deficit for an asset, RAY-scaled.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Deficit in asset units, RAY-scaled"}
  )

  @spec get_spoke_deficit_ray(hub(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_spoke_deficit_ray(hub, asset_id, spoke, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_spoke_uint(hub, "getSpokeDeficitRay(uint256,address)", asset_id, spoke, opts)
  end

  # --- underlying_listed? ---

  api(:underlying_listed?, "Whether an underlying token is listed on the Hub.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      underlying: [kind: :value, description: "Underlying asset address as 0x hex or 20-byte binary"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, boolean()} | {:error, term()}", description: "true if the underlying is listed"}
  )

  @spec underlying_listed?(hub(), String.t() | binary(), keyword()) ::
          {:ok, boolean()} | {:error, term()}
  def underlying_listed?(hub, underlying, opts \\ []) do
    with {:ok, underlying_bin} <- Address.validate(underlying) do
      hub
      |> call_hub("isUnderlyingListed(address)", [underlying_bin], "(bool)", opts)
      |> unwrap_bool()
    end
  end

  # --- get_asset_count ---

  api(:get_asset_count, "Number of assets listed on the Hub.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Listed asset count"}
  )

  @spec get_asset_count(hub(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def get_asset_count(hub, opts \\ []) do
    call_uint(hub, "getAssetCount()", [], opts)
  end

  # --- get_asset ---

  api(:get_asset, "Full Hub asset position, including liquidity and drawn rate/index.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, Asset.t()} | {:error, term()}", description: "Asset struct"}
  )

  @spec get_asset(hub(), non_neg_integer(), keyword()) :: {:ok, Asset.t()} | {:error, term()}
  def get_asset(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    hub
    |> call_hub("getAsset(uint256)", [asset_id], @asset_response, opts)
    |> unwrap_asset()
  end

  # --- get_asset_config ---

  api(:get_asset_config, "Hub asset fee and interest-rate configuration.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, AssetConfig.t()} | {:error, term()}", description: "AssetConfig struct"}
  )

  @spec get_asset_config(hub(), non_neg_integer(), keyword()) ::
          {:ok, AssetConfig.t()} | {:error, term()}
  def get_asset_config(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    hub
    |> call_hub("getAssetConfig(uint256)", [asset_id], @asset_config_response, opts)
    |> unwrap_asset_config()
  end

  # --- get_asset_accrued_fees ---

  api(:get_asset_accrued_fees, "Accrued asset fees not yet minted as shares.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Accrued fees in asset units"}
  )

  @spec get_asset_accrued_fees(hub(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_asset_accrued_fees(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_uint(hub, "getAssetAccruedFees(uint256)", [asset_id], opts)
  end

  # --- get_asset_swept ---

  api(:get_asset_swept, "Liquidity held by the asset's reinvestment controller.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Swept liquidity in asset units"}
  )

  @spec get_asset_swept(hub(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_asset_swept(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_uint(hub, "getAssetSwept(uint256)", [asset_id], opts)
  end

  # --- get_added_assets ---

  api(:get_added_assets, "Total assets added to the Hub across all Spokes.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Added assets in token units"}
  )

  @spec get_added_assets(hub(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_added_assets(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_uint(hub, "getAddedAssets(uint256)", [asset_id], opts)
  end

  # --- get_added_shares ---

  api(:get_added_shares, "Total added shares on the Hub across all Spokes.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Added shares"}
  )

  @spec get_added_shares(hub(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_added_shares(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_uint(hub, "getAddedShares(uint256)", [asset_id], opts)
  end

  # --- get_asset_liquidity ---

  api(:get_asset_liquidity, "Available Hub liquidity for an asset.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Available liquidity (token units)"}
  )

  @spec get_asset_liquidity(hub(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_asset_liquidity(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_uint(hub, "getAssetLiquidity(uint256)", [asset_id], opts)
  end

  # --- get_asset_owed ---

  api(:get_asset_owed, "Hub-wide drawn and premium amounts owed for an asset.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, {non_neg_integer(), non_neg_integer()}} | {:error, term()}",
      description: "{drawn, premium} in token units"
    }
  )

  @spec get_asset_owed(hub(), non_neg_integer(), keyword()) ::
          {:ok, {non_neg_integer(), non_neg_integer()}} | {:error, term()}
  def get_asset_owed(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    hub
    |> call_hub("getAssetOwed(uint256)", [asset_id], "(uint256,uint256)", opts)
    |> unwrap_pair()
  end

  # --- get_asset_total_owed ---

  api(:get_asset_total_owed, "Hub-wide total amount owed for an asset.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Total owed (token units)"}
  )

  @spec get_asset_total_owed(hub(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_asset_total_owed(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_uint(hub, "getAssetTotalOwed(uint256)", [asset_id], opts)
  end

  # --- get_asset_premium_ray ---

  api(:get_asset_premium_ray, "Hub-wide premium owed for an asset, RAY-scaled.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Premium owed, RAY-scaled"}
  )

  @spec get_asset_premium_ray(hub(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_asset_premium_ray(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_uint(hub, "getAssetPremiumRay(uint256)", [asset_id], opts)
  end

  # --- get_asset_drawn_shares ---

  api(:get_asset_drawn_shares, "Hub-wide drawn shares for an asset.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Drawn shares"}
  )

  @spec get_asset_drawn_shares(hub(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_asset_drawn_shares(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_uint(hub, "getAssetDrawnShares(uint256)", [asset_id], opts)
  end

  # --- get_asset_premium_data ---

  api(:get_asset_premium_data, "Hub-wide premium shares and offset for an asset.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, {non_neg_integer(), integer()}} | {:error, term()}",
      description: "{premium shares, premium offset RAY}"
    }
  )

  @spec get_asset_premium_data(hub(), non_neg_integer(), keyword()) ::
          {:ok, {non_neg_integer(), integer()}} | {:error, term()}
  def get_asset_premium_data(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    hub
    |> call_hub("getAssetPremiumData(uint256)", [asset_id], "(uint256,int256)", opts)
    |> unwrap_premium_data()
  end

  # --- get_asset_deficit_ray ---

  api(:get_asset_deficit_ray, "Hub-wide deficit for an asset, RAY-scaled.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Deficit in asset units, RAY-scaled"}
  )

  @spec get_asset_deficit_ray(hub(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_asset_deficit_ray(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_uint(hub, "getAssetDeficitRay(uint256)", [asset_id], opts)
  end

  # --- get_asset_drawn_rate ---

  api(:get_asset_drawn_rate, "Current drawn rate for an asset, RAY-scaled.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Drawn rate (RAY)"}
  )

  @spec get_asset_drawn_rate(hub(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_asset_drawn_rate(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_uint(hub, "getAssetDrawnRate(uint256)", [asset_id], opts)
  end

  # --- get_asset_drawn_index ---

  api(:get_asset_drawn_index, "Current drawn index for an asset, RAY-scaled.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Drawn index (RAY)"}
  )

  @spec get_asset_drawn_index(hub(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_asset_drawn_index(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    call_uint(hub, "getAssetDrawnIndex(uint256)", [asset_id], opts)
  end

  # --- get_asset_id ---

  api(:get_asset_id, "Hub asset identifier for an underlying token.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      underlying: [kind: :value, description: "Underlying asset address as 0x hex or 20-byte binary"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Asset identifier"}
  )

  @spec get_asset_id(hub(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def get_asset_id(hub, underlying, opts \\ []) do
    with {:ok, underlying_bin} <- Address.validate(underlying) do
      call_uint(hub, "getAssetId(address)", [underlying_bin], opts)
    end
  end

  # --- get_asset_underlying_and_decimals ---

  api(:get_asset_underlying_and_decimals, "Underlying token address and decimals for a Hub asset.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, {String.t(), non_neg_integer()}} | {:error, term()}",
      description: "{checksummed underlying, decimals}"
    }
  )

  @spec get_asset_underlying_and_decimals(hub(), non_neg_integer(), keyword()) ::
          {:ok, {String.t(), non_neg_integer()}} | {:error, term()}
  def get_asset_underlying_and_decimals(hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    with {:ok, [underlying, decimals]} <-
           call_hub(hub, "getAssetUnderlyingAndDecimals(uint256)", [asset_id], "(address,uint8)", opts),
         {:ok, checksummed} <- Address.checksum(underlying) do
      {:ok, {checksummed, decimals}}
    end
  end

  # --- preview_add_by_assets ---

  api(:preview_add_by_assets, "Shares that would be added for the given assets. Rounds down.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      assets: [kind: :value, description: @assets_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Shares added (rounded down)"}
  )

  @spec preview_add_by_assets(hub(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def preview_add_by_assets(hub, asset_id, assets, opts \\ [])
      when is_integer(asset_id) and asset_id >= 0 and is_integer(assets) and assets >= 0 do
    call_uint(hub, "previewAddByAssets(uint256,uint256)", [asset_id, assets], opts)
  end

  # --- preview_add_by_shares ---

  api(:preview_add_by_shares, "Assets that would be added for the given shares. Rounds up.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      shares: [kind: :value, description: @shares_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Assets added (rounded up)"}
  )

  @spec preview_add_by_shares(hub(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def preview_add_by_shares(hub, asset_id, shares, opts \\ [])
      when is_integer(asset_id) and asset_id >= 0 and is_integer(shares) and shares >= 0 do
    call_uint(hub, "previewAddByShares(uint256,uint256)", [asset_id, shares], opts)
  end

  # --- preview_remove_by_assets ---

  api(:preview_remove_by_assets, "Shares that would be removed for the given assets. Rounds up.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      assets: [kind: :value, description: @assets_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Shares removed (rounded up)"}
  )

  @spec preview_remove_by_assets(hub(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def preview_remove_by_assets(hub, asset_id, assets, opts \\ [])
      when is_integer(asset_id) and asset_id >= 0 and is_integer(assets) and assets >= 0 do
    call_uint(hub, "previewRemoveByAssets(uint256,uint256)", [asset_id, assets], opts)
  end

  # --- preview_remove_by_shares ---

  api(:preview_remove_by_shares, "Assets that would be removed for the given shares. Rounds down.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      shares: [kind: :value, description: @shares_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Assets removed (rounded down)"}
  )

  @spec preview_remove_by_shares(hub(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def preview_remove_by_shares(hub, asset_id, shares, opts \\ [])
      when is_integer(asset_id) and asset_id >= 0 and is_integer(shares) and shares >= 0 do
    call_uint(hub, "previewRemoveByShares(uint256,uint256)", [asset_id, shares], opts)
  end

  # --- preview_draw_by_assets ---

  api(:preview_draw_by_assets, "Shares that would be drawn for the given assets. Rounds up.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      assets: [kind: :value, description: @assets_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Shares drawn (rounded up)"}
  )

  @spec preview_draw_by_assets(hub(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def preview_draw_by_assets(hub, asset_id, assets, opts \\ [])
      when is_integer(asset_id) and asset_id >= 0 and is_integer(assets) and assets >= 0 do
    call_uint(hub, "previewDrawByAssets(uint256,uint256)", [asset_id, assets], opts)
  end

  # --- preview_draw_by_shares ---

  api(:preview_draw_by_shares, "Assets that would be drawn for the given shares. Rounds down.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      shares: [kind: :value, description: @shares_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Assets drawn (rounded down)"}
  )

  @spec preview_draw_by_shares(hub(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def preview_draw_by_shares(hub, asset_id, shares, opts \\ [])
      when is_integer(asset_id) and asset_id >= 0 and is_integer(shares) and shares >= 0 do
    call_uint(hub, "previewDrawByShares(uint256,uint256)", [asset_id, shares], opts)
  end

  # --- preview_restore_by_assets ---

  api(:preview_restore_by_assets, "Shares that would be restored for the given assets. Rounds down.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      assets: [kind: :value, description: @assets_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Shares restored (rounded down)"}
  )

  @spec preview_restore_by_assets(hub(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def preview_restore_by_assets(hub, asset_id, assets, opts \\ [])
      when is_integer(asset_id) and asset_id >= 0 and is_integer(assets) and assets >= 0 do
    call_uint(hub, "previewRestoreByAssets(uint256,uint256)", [asset_id, assets], opts)
  end

  # --- preview_restore_by_shares ---

  api(:preview_restore_by_shares, "Assets that would be restored for the given shares. Rounds up.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset_id: [kind: :value, description: @asset_id_desc],
      shares: [kind: :value, description: @shares_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Assets restored (rounded up)"}
  )

  @spec preview_restore_by_shares(hub(), non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def preview_restore_by_shares(hub, asset_id, shares, opts \\ [])
      when is_integer(asset_id) and asset_id >= 0 and is_integer(shares) and shares >= 0 do
    call_uint(hub, "previewRestoreByShares(uint256,uint256)", [asset_id, shares], opts)
  end

  # --- max_allowed_underlying_decimals ---

  api(:max_allowed_underlying_decimals, "Inclusive maximum allowed underlying-asset decimals.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Max decimals (inclusive, uint8)"}
  )

  @spec max_allowed_underlying_decimals(hub(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def max_allowed_underlying_decimals(hub, opts \\ []) do
    call_uint(hub, "MAX_ALLOWED_UNDERLYING_DECIMALS()", [], opts)
  end

  # --- min_allowed_underlying_decimals ---

  api(:min_allowed_underlying_decimals, "Inclusive minimum allowed underlying-asset decimals.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Min decimals (inclusive, uint8)"}
  )

  @spec min_allowed_underlying_decimals(hub(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def min_allowed_underlying_decimals(hub, opts \\ []) do
    call_uint(hub, "MIN_ALLOWED_UNDERLYING_DECIMALS()", [], opts)
  end

  # --- max_allowed_spoke_cap ---

  api(
    :max_allowed_spoke_cap,
    "Maximum Spoke add/draw cap. Using this value on SpokeConfig means no cap.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Cap bound (uint40 whole assets; max means no cap)"
    }
  )

  @spec max_allowed_spoke_cap(hub(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def max_allowed_spoke_cap(hub, opts \\ []) do
    call_uint(hub, "MAX_ALLOWED_SPOKE_CAP()", [], opts)
  end

  # --- max_risk_premium_threshold ---

  api(
    :max_risk_premium_threshold,
    "Maximum Spoke risk-premium threshold. Using this value on SpokeConfig means no threshold.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Threshold bound (uint24 BPS; max means no threshold)"
    }
  )

  @spec max_risk_premium_threshold(hub(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def max_risk_premium_threshold(hub, opts \\ []) do
    call_uint(hub, "MAX_RISK_PREMIUM_THRESHOLD()", [], opts)
  end

  @spec call_hub(atom(), String.t(), list(), String.t(), keyword()) ::
          {:ok, list()} | {:error, term()}
  defp call_hub(hub, signature, params, return_type, opts) do
    {network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, hub_addr} <- hub_address(hub, network_opts) do
      Contract.call(hub_addr, signature, params, return_type, rpc_opts)
    end
  end

  @spec call_uint(atom(), String.t(), list(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp call_uint(hub, signature, params, opts) do
    hub
    |> call_hub(signature, params, "(uint256)", opts)
    |> unwrap_uint()
  end

  @spec call_spoke(atom(), String.t(), String.t(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, list()} | {:error, term()}
  defp call_spoke(hub, signature, return_type, asset_id, spoke, opts) do
    with {:ok, spoke_bin} <- Address.validate(spoke) do
      call_hub(hub, signature, [asset_id, spoke_bin], return_type, opts)
    end
  end

  @spec call_spoke_uint(atom(), String.t(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp call_spoke_uint(hub, signature, asset_id, spoke, opts) do
    hub
    |> call_spoke(signature, "(uint256)", asset_id, spoke, opts)
    |> unwrap_uint()
  end

  @spec unwrap_uint({:ok, list()} | {:error, term()}) :: {:ok, non_neg_integer()} | {:error, term()}
  defp unwrap_uint({:ok, [value]}) when is_integer(value) and value >= 0, do: {:ok, value}
  defp unwrap_uint({:error, _} = error), do: error

  @spec unwrap_bool({:ok, list()} | {:error, term()}) :: {:ok, boolean()} | {:error, term()}
  defp unwrap_bool({:ok, [value]}) when is_boolean(value), do: {:ok, value}
  defp unwrap_bool({:error, _} = error), do: error

  @spec unwrap_address({:ok, list()} | {:error, term()}) :: {:ok, String.t()} | {:error, term()}
  defp unwrap_address({:ok, [bin]}) when is_binary(bin), do: Address.checksum(bin)
  defp unwrap_address({:error, _} = error), do: error

  @spec unwrap_pair({:ok, list()} | {:error, term()}) ::
          {:ok, {non_neg_integer(), non_neg_integer()}} | {:error, term()}
  defp unwrap_pair({:ok, [a, b]}) when is_integer(a) and is_integer(b), do: {:ok, {a, b}}
  defp unwrap_pair({:error, _} = error), do: error

  @spec unwrap_premium_data({:ok, list()} | {:error, term()}) ::
          {:ok, {non_neg_integer(), integer()}} | {:error, term()}
  defp unwrap_premium_data({:ok, [shares, offset]}) when is_integer(shares) and shares >= 0 and is_integer(offset),
    do: {:ok, {shares, offset}}

  defp unwrap_premium_data({:error, _} = error), do: error

  @spec unwrap_asset({:ok, list()} | {:error, term()}) :: {:ok, Asset.t()} | {:error, term()}
  defp unwrap_asset({:ok, [fields]}) when is_tuple(fields), do: {:ok, Asset.from_raw(fields)}
  defp unwrap_asset({:error, _} = error), do: error

  @spec unwrap_asset_config({:ok, list()} | {:error, term()}) ::
          {:ok, AssetConfig.t()} | {:error, term()}
  defp unwrap_asset_config({:ok, [fields]}) when is_tuple(fields), do: {:ok, AssetConfig.from_raw(fields)}
  defp unwrap_asset_config({:error, _} = error), do: error

  @spec unwrap_spoke_data({:ok, list()} | {:error, term()}) :: {:ok, SpokeData.t()} | {:error, term()}
  defp unwrap_spoke_data({:ok, [fields]}) when is_tuple(fields), do: {:ok, SpokeData.from_raw(fields)}
  defp unwrap_spoke_data({:error, _} = error), do: error

  @spec unwrap_spoke_config({:ok, list()} | {:error, term()}) ::
          {:ok, SpokeConfig.t()} | {:error, term()}
  defp unwrap_spoke_config({:ok, [fields]}) when is_tuple(fields), do: {:ok, SpokeConfig.from_raw(fields)}
  defp unwrap_spoke_config({:error, _} = error), do: error
end

defmodule Onchain.Aave.V4.Hub.Asset do
  @moduledoc """
  Typed `IHub.Asset` — Hub-level liquidity, shares, and drawn-rate environment.

  Amounts are raw integers. RAY-scaled fields keep the `_ray` / rate / index
  suffix rather than converting to `Decimal`.
  """

  use Descripex, namespace: "/aave/v4/hub/asset"

  alias Onchain.Address

  @enforce_keys [
    :liquidity,
    :realized_fees,
    :decimals,
    :added_shares,
    :swept,
    :premium_offset_ray,
    :drawn_shares,
    :premium_shares,
    :liquidity_fee,
    :drawn_index,
    :drawn_rate,
    :last_update_timestamp,
    :underlying,
    :ir_strategy,
    :reinvestment_controller,
    :fee_receiver,
    :deficit_ray
  ]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          liquidity: non_neg_integer(),
          realized_fees: non_neg_integer(),
          decimals: non_neg_integer(),
          added_shares: non_neg_integer(),
          swept: non_neg_integer(),
          premium_offset_ray: integer(),
          drawn_shares: non_neg_integer(),
          premium_shares: non_neg_integer(),
          liquidity_fee: non_neg_integer(),
          drawn_index: non_neg_integer(),
          drawn_rate: non_neg_integer(),
          last_update_timestamp: non_neg_integer(),
          underlying: String.t(),
          ir_strategy: String.t(),
          reinvestment_controller: String.t(),
          fee_receiver: String.t(),
          deficit_ray: non_neg_integer()
        }

  api(:from_raw, "Convert a decoded IHub.Asset tuple into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "17-element tuple from getAsset",
        source: "Onchain.Aave.V4.Hub.get_asset/3"
      ]
    ],
    returns: %{type: :struct, description: "%Onchain.Aave.V4.Hub.Asset{}"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw(
        {liquidity, realized_fees, decimals, added_shares, swept, premium_offset_ray, drawn_shares, premium_shares,
         liquidity_fee, drawn_index, drawn_rate, last_update_ts, underlying, ir_strategy, reinvestment, fee_receiver,
         deficit_ray}
      ) do
    %__MODULE__{
      liquidity: liquidity,
      realized_fees: realized_fees,
      decimals: decimals,
      added_shares: added_shares,
      swept: swept,
      premium_offset_ray: premium_offset_ray,
      drawn_shares: drawn_shares,
      premium_shares: premium_shares,
      liquidity_fee: liquidity_fee,
      drawn_index: drawn_index,
      drawn_rate: drawn_rate,
      last_update_timestamp: last_update_ts,
      underlying: Address.checksum!(underlying),
      ir_strategy: Address.checksum!(ir_strategy),
      reinvestment_controller: Address.checksum!(reinvestment),
      fee_receiver: Address.checksum!(fee_receiver),
      deficit_ray: deficit_ray
    }
  end
end

defmodule Onchain.Aave.V4.Hub.AssetConfig do
  @moduledoc """
  Typed `IHub.AssetConfig` — fee and interest-rate configuration for a Hub asset.
  """

  use Descripex, namespace: "/aave/v4/hub/asset-config"

  alias Onchain.Address

  @enforce_keys [:fee_receiver, :liquidity_fee, :ir_strategy, :reinvestment_controller]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          fee_receiver: String.t(),
          liquidity_fee: non_neg_integer(),
          ir_strategy: String.t(),
          reinvestment_controller: String.t()
        }

  api(:from_raw, "Convert a decoded IHub.AssetConfig tuple into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "4-element tuple from getAssetConfig",
        source: "Onchain.Aave.V4.Hub.get_asset_config/3"
      ]
    ],
    returns: %{type: :struct, description: "%Onchain.Aave.V4.Hub.AssetConfig{}"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw({fee_receiver, liquidity_fee, ir_strategy, reinvestment_controller}) do
    %__MODULE__{
      fee_receiver: Address.checksum!(fee_receiver),
      liquidity_fee: liquidity_fee,
      ir_strategy: Address.checksum!(ir_strategy),
      reinvestment_controller: Address.checksum!(reinvestment_controller)
    }
  end
end

defmodule Onchain.Aave.V4.Hub.SpokeData do
  @moduledoc """
  Typed `IHub.SpokeData` — per-Spoke credit-line inventory and caps.
  """

  use Descripex, namespace: "/aave/v4/hub/spoke-data"

  @enforce_keys [
    :drawn_shares,
    :premium_shares,
    :premium_offset_ray,
    :added_shares,
    :add_cap,
    :draw_cap,
    :risk_premium_threshold,
    :active,
    :halted,
    :deficit_ray
  ]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          drawn_shares: non_neg_integer(),
          premium_shares: non_neg_integer(),
          premium_offset_ray: integer(),
          added_shares: non_neg_integer(),
          add_cap: non_neg_integer(),
          draw_cap: non_neg_integer(),
          risk_premium_threshold: non_neg_integer(),
          active: boolean(),
          halted: boolean(),
          deficit_ray: non_neg_integer()
        }

  api(:from_raw, "Convert a decoded IHub.SpokeData tuple into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "10-element tuple from getSpoke",
        source: "Onchain.Aave.V4.Hub.get_spoke/4"
      ]
    ],
    returns: %{type: :struct, description: "%Onchain.Aave.V4.Hub.SpokeData{}"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw(
        {drawn_shares, premium_shares, premium_offset_ray, added_shares, add_cap, draw_cap, risk_premium_threshold,
         active, halted, deficit_ray}
      ) do
    %__MODULE__{
      drawn_shares: drawn_shares,
      premium_shares: premium_shares,
      premium_offset_ray: premium_offset_ray,
      added_shares: added_shares,
      add_cap: add_cap,
      draw_cap: draw_cap,
      risk_premium_threshold: risk_premium_threshold,
      active: active,
      halted: halted,
      deficit_ray: deficit_ray
    }
  end
end

defmodule Onchain.Aave.V4.Hub.SpokeConfig do
  @moduledoc """
  Typed `IHub.SpokeConfig` — add/draw caps, risk-premium threshold, and flags.
  """

  use Descripex, namespace: "/aave/v4/hub/spoke-config"

  @enforce_keys [:add_cap, :draw_cap, :risk_premium_threshold, :active, :halted]

  defstruct @enforce_keys

  @type t :: %__MODULE__{
          add_cap: non_neg_integer(),
          draw_cap: non_neg_integer(),
          risk_premium_threshold: non_neg_integer(),
          active: boolean(),
          halted: boolean()
        }

  api(:from_raw, "Convert a decoded IHub.SpokeConfig tuple into a typed struct.",
    params: [
      raw: [
        kind: :exchange_data,
        description: "5-element tuple from getSpokeConfig",
        source: "Onchain.Aave.V4.Hub.get_spoke_config/4"
      ]
    ],
    returns: %{type: :struct, description: "%Onchain.Aave.V4.Hub.SpokeConfig{}"}
  )

  @spec from_raw(tuple()) :: t()
  def from_raw({add_cap, draw_cap, risk_premium_threshold, active, halted}) do
    %__MODULE__{
      add_cap: add_cap,
      draw_cap: draw_cap,
      risk_premium_threshold: risk_premium_threshold,
      active: active,
      halted: halted
    }
  end
end
