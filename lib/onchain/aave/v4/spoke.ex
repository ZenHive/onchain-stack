defmodule Onchain.Aave.V4.Spoke do
  @moduledoc """
  Aave V4 Spoke read operations.

  Reads are scoped to a caller-supplied Spoke contract. Reserve and user
  structs are decoded into `Onchain.Aave.V4.Types` structs; numeric values
  remain in their contract units (asset units, BPS, WAD, or RAY).

  Errors pass through from address validation and `Onchain.Contract.call/5`.
  """

  use Descripex, namespace: "/aave/v4/spoke"

  alias Onchain.Aave.V4.Types.SpokeDynamicReserveConfig
  alias Onchain.Aave.V4.Types.SpokeLiquidationConfig
  alias Onchain.Aave.V4.Types.SpokeReserveConfig
  alias Onchain.Aave.V4.Types.SpokeReserveData
  alias Onchain.Aave.V4.Types.SpokeUserData
  alias Onchain.Aave.V4.Types.SpokeUserPosition
  alias Onchain.Address
  alias Onchain.Contract

  @type address :: String.t() | binary()
  @type result(value) :: {:ok, value} | {:error, term()}

  @reserve_response "((address,address,uint16,uint8,uint24,uint8,uint32))"
  @reserve_config_response "((uint24,bool,bool,bool,bool))"
  @dynamic_reserve_config_response "((uint16,uint32,uint16))"
  @liquidation_config_response "((uint128,uint64,uint16))"
  @user_position_response "((uint120,uint120,int200,uint120,uint32))"
  @user_data_response "((uint256,uint256,uint256,uint256,uint256,uint256,uint256))"

  @spoke_desc "Spoke contract address"
  @reserve_id_desc "Spoke-local reserve identifier"
  @user_desc "User address"
  @opts_desc "Options: :rpc_url, :timeout, :block"

  api(:get_liquidation_config, "Fetch the Spoke liquidation thresholds and bonus factor.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, SpokeLiquidationConfig.t()} | {:error, term()}"}
  )

  @spec get_liquidation_config(address(), keyword()) :: result(SpokeLiquidationConfig.t())
  def get_liquidation_config(spoke, opts \\ []) do
    spoke
    |> Contract.call("getLiquidationConfig()", [], @liquidation_config_response, opts)
    |> unwrap_struct(SpokeLiquidationConfig)
  end

  api(:get_reserve_count, "Fetch the number of reserves listed on the Spoke.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}"}
  )

  @spec get_reserve_count(address(), keyword()) :: result(non_neg_integer())
  def get_reserve_count(spoke, opts \\ []), do: call_uint(spoke, "getReserveCount()", [], opts)

  api(:get_reserve_supplied_assets, "Fetch the total supplied assets for a Spoke reserve.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}"}
  )

  @spec get_reserve_supplied_assets(address(), non_neg_integer(), keyword()) :: result(non_neg_integer())
  def get_reserve_supplied_assets(spoke, reserve_id, opts \\ []) when is_integer(reserve_id) and reserve_id >= 0 do
    call_uint(spoke, "getReserveSuppliedAssets(uint256)", [reserve_id], opts)
  end

  api(:get_reserve_supplied_shares, "Fetch the total supplied shares for a Spoke reserve.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}"}
  )

  @spec get_reserve_supplied_shares(address(), non_neg_integer(), keyword()) :: result(non_neg_integer())
  def get_reserve_supplied_shares(spoke, reserve_id, opts \\ []) when is_integer(reserve_id) and reserve_id >= 0 do
    call_uint(spoke, "getReserveSuppliedShares(uint256)", [reserve_id], opts)
  end

  api(:get_reserve_total_debt, "Fetch the total reserve debt for a Spoke reserve.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}"}
  )

  @spec get_reserve_total_debt(address(), non_neg_integer(), keyword()) :: result(non_neg_integer())
  def get_reserve_total_debt(spoke, reserve_id, opts \\ []) when is_integer(reserve_id) and reserve_id >= 0 do
    call_uint(spoke, "getReserveTotalDebt(uint256)", [reserve_id], opts)
  end

  api(:get_reserve_debt, "Fetch drawn and premium debt for a Spoke reserve.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, {non_neg_integer(), non_neg_integer()}} | {:error, term()}"}
  )

  @spec get_reserve_debt(address(), non_neg_integer(), keyword()) ::
          result({non_neg_integer(), non_neg_integer()})
  def get_reserve_debt(spoke, reserve_id, opts \\ []) when is_integer(reserve_id) and reserve_id >= 0 do
    spoke
    |> Contract.call("getReserveDebt(uint256)", [reserve_id], "(uint256,uint256)", opts)
    |> unwrap_pair()
  end

  api(:get_reserve_id, "Resolve a Hub asset to its Spoke-local reserve id.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      hub: [kind: :value, description: "Hub contract address"],
      asset_id: [kind: :value, description: "Hub-local asset identifier"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}"}
  )

  @spec get_reserve_id(address(), address(), non_neg_integer(), keyword()) :: result(non_neg_integer())
  def get_reserve_id(spoke, hub, asset_id, opts \\ []) when is_integer(asset_id) and asset_id >= 0 do
    with {:ok, hub_bin} <- Address.validate(hub) do
      call_uint(spoke, "getReserveId(address,uint256)", [hub_bin, asset_id], opts)
    end
  end

  api(:get_reserve, "Fetch typed metadata and flags for a Spoke reserve.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, SpokeReserveData.t()} | {:error, term()}"}
  )

  @spec get_reserve(address(), non_neg_integer(), keyword()) :: result(SpokeReserveData.t())
  def get_reserve(spoke, reserve_id, opts \\ []) when is_integer(reserve_id) and reserve_id >= 0 do
    spoke
    |> Contract.call("getReserve(uint256)", [reserve_id], @reserve_response, opts)
    |> unwrap_struct(SpokeReserveData)
  end

  api(:get_reserve_config, "Fetch typed static configuration for a Spoke reserve.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, SpokeReserveConfig.t()} | {:error, term()}"}
  )

  @spec get_reserve_config(address(), non_neg_integer(), keyword()) :: result(SpokeReserveConfig.t())
  def get_reserve_config(spoke, reserve_id, opts \\ []) when is_integer(reserve_id) and reserve_id >= 0 do
    spoke
    |> Contract.call("getReserveConfig(uint256)", [reserve_id], @reserve_config_response, opts)
    |> unwrap_struct(SpokeReserveConfig)
  end

  api(:get_dynamic_reserve_config, "Fetch a typed dynamic configuration version for a Spoke reserve.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      dynamic_config_key: [kind: :value, description: "Dynamic configuration version key"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, SpokeDynamicReserveConfig.t()} | {:error, term()}"}
  )

  @spec get_dynamic_reserve_config(address(), non_neg_integer(), non_neg_integer(), keyword()) ::
          result(SpokeDynamicReserveConfig.t())
  def get_dynamic_reserve_config(spoke, reserve_id, dynamic_config_key, opts \\ [])
      when is_integer(reserve_id) and reserve_id >= 0 and is_integer(dynamic_config_key) and dynamic_config_key >= 0 do
    spoke
    |> Contract.call(
      "getDynamicReserveConfig(uint256,uint32)",
      [reserve_id, dynamic_config_key],
      @dynamic_reserve_config_response,
      opts
    )
    |> unwrap_struct(SpokeDynamicReserveConfig)
  end

  api(:get_user_reserve_status, "Fetch whether a user uses a reserve as collateral and borrows it.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      user: [kind: :value, description: @user_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, {boolean(), boolean()}} | {:error, term()}"}
  )

  @spec get_user_reserve_status(address(), non_neg_integer(), address(), keyword()) ::
          result({boolean(), boolean()})
  def get_user_reserve_status(spoke, reserve_id, user, opts \\ []) when is_integer(reserve_id) and reserve_id >= 0 do
    spoke
    |> call_with_address("getUserReserveStatus(uint256,address)", [reserve_id], user, "(bool,bool)", opts)
    |> unwrap_bool_pair()
  end

  api(:get_user_supplied_assets, "Fetch a user's supplied assets for a Spoke reserve.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      user: [kind: :value, description: @user_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}"}
  )

  @spec get_user_supplied_assets(address(), non_neg_integer(), address(), keyword()) :: result(non_neg_integer())
  def get_user_supplied_assets(spoke, reserve_id, user, opts \\ []) when is_integer(reserve_id) and reserve_id >= 0 do
    spoke
    |> call_with_address("getUserSuppliedAssets(uint256,address)", [reserve_id], user, "(uint256)", opts)
    |> unwrap_uint()
  end

  api(:get_user_supplied_shares, "Fetch a user's supplied shares for a Spoke reserve.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      user: [kind: :value, description: @user_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}"}
  )

  @spec get_user_supplied_shares(address(), non_neg_integer(), address(), keyword()) :: result(non_neg_integer())
  def get_user_supplied_shares(spoke, reserve_id, user, opts \\ []) when is_integer(reserve_id) and reserve_id >= 0 do
    spoke
    |> call_with_address("getUserSuppliedShares(uint256,address)", [reserve_id], user, "(uint256)", opts)
    |> unwrap_uint()
  end

  api(:get_user_total_debt, "Fetch a user's total debt for a Spoke reserve.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      user: [kind: :value, description: @user_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}"}
  )

  @spec get_user_total_debt(address(), non_neg_integer(), address(), keyword()) :: result(non_neg_integer())
  def get_user_total_debt(spoke, reserve_id, user, opts \\ []) when is_integer(reserve_id) and reserve_id >= 0 do
    spoke
    |> call_with_address("getUserTotalDebt(uint256,address)", [reserve_id], user, "(uint256)", opts)
    |> unwrap_uint()
  end

  api(:get_user_premium_debt_ray, "Fetch a user's RAY-scaled premium debt for a Spoke reserve.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      user: [kind: :value, description: @user_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}"}
  )

  @spec get_user_premium_debt_ray(address(), non_neg_integer(), address(), keyword()) :: result(non_neg_integer())
  def get_user_premium_debt_ray(spoke, reserve_id, user, opts \\ []) when is_integer(reserve_id) and reserve_id >= 0 do
    spoke
    |> call_with_address("getUserPremiumDebtRay(uint256,address)", [reserve_id], user, "(uint256)", opts)
    |> unwrap_uint()
  end

  api(:get_user_debt, "Fetch a user's drawn and premium debt for a Spoke reserve.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      user: [kind: :value, description: @user_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, {non_neg_integer(), non_neg_integer()}} | {:error, term()}"}
  )

  @spec get_user_debt(address(), non_neg_integer(), address(), keyword()) ::
          result({non_neg_integer(), non_neg_integer()})
  def get_user_debt(spoke, reserve_id, user, opts \\ []) when is_integer(reserve_id) and reserve_id >= 0 do
    spoke
    |> call_with_address("getUserDebt(uint256,address)", [reserve_id], user, "(uint256,uint256)", opts)
    |> unwrap_pair()
  end

  api(:get_user_position, "Fetch a user's typed position for one Spoke reserve.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      user: [kind: :value, description: @user_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, SpokeUserPosition.t()} | {:error, term()}"}
  )

  @spec get_user_position(address(), non_neg_integer(), address(), keyword()) :: result(SpokeUserPosition.t())
  def get_user_position(spoke, reserve_id, user, opts \\ []) when is_integer(reserve_id) and reserve_id >= 0 do
    spoke
    |> call_with_address("getUserPosition(uint256,address)", [reserve_id], user, @user_position_response, opts)
    |> unwrap_struct(SpokeUserPosition)
  end

  api(:get_user_account_data, "Fetch a user's typed per-Spoke health and account summary.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      user: [kind: :value, description: @user_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, SpokeUserData.t()} | {:error, term()}"}
  )

  @spec get_user_account_data(address(), address(), keyword()) :: result(SpokeUserData.t())
  def get_user_account_data(spoke, user, opts \\ []) do
    spoke
    |> call_with_address("getUserAccountData(address)", [], user, @user_data_response, opts)
    |> unwrap_struct(SpokeUserData)
  end

  api(:get_user_last_risk_premium, "Fetch the risk premium from a user's last position update.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      user: [kind: :value, description: @user_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}"}
  )

  @spec get_user_last_risk_premium(address(), address(), keyword()) :: result(non_neg_integer())
  def get_user_last_risk_premium(spoke, user, opts \\ []) do
    spoke
    |> call_with_address("getUserLastRiskPremium(address)", [], user, "(uint256)", opts)
    |> unwrap_uint()
  end

  api(:get_liquidation_bonus, "Fetch the liquidation bonus for a user's reserve at a health factor.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      user: [kind: :value, description: @user_desc],
      health_factor: [kind: :value, description: "Health factor in WAD"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}"}
  )

  @spec get_liquidation_bonus(address(), non_neg_integer(), address(), non_neg_integer(), keyword()) ::
          result(non_neg_integer())
  def get_liquidation_bonus(spoke, reserve_id, user, health_factor, opts \\ [])
      when is_integer(reserve_id) and reserve_id >= 0 and is_integer(health_factor) and health_factor >= 0 do
    spoke
    |> call_with_address(
      "getLiquidationBonus(uint256,address,uint256)",
      [reserve_id],
      user,
      health_factor,
      "(uint256)",
      opts
    )
    |> unwrap_uint()
  end

  api(:position_manager_active?, "Fetch whether governance has activated a position manager.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      position_manager: [kind: :value, description: "Position manager address"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, boolean()} | {:error, term()}"}
  )

  @spec position_manager_active?(address(), address(), keyword()) :: result(boolean())
  def position_manager_active?(spoke, position_manager, opts \\ []) do
    spoke
    |> call_with_address("isPositionManagerActive(address)", [], position_manager, "(bool)", opts)
    |> unwrap_bool()
  end

  api(:position_manager?, "Fetch whether a position manager is active and approved by a user.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      user: [kind: :value, description: @user_desc],
      position_manager: [kind: :value, description: "Position manager address"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, boolean()} | {:error, term()}"}
  )

  @spec position_manager?(address(), address(), address(), keyword()) :: result(boolean())
  def position_manager?(spoke, user, position_manager, opts \\ []) do
    with {:ok, user_bin} <- Address.validate(user),
         {:ok, manager_bin} <- Address.validate(position_manager) do
      spoke
      |> Contract.call("isPositionManager(address,address)", [user_bin, manager_bin], "(bool)", opts)
      |> unwrap_bool()
    end
  end

  api(:get_liquidation_logic, "Fetch the liquidation logic library address.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}"}
  )

  @spec get_liquidation_logic(address(), keyword()) :: result(String.t())
  def get_liquidation_logic(spoke, opts \\ []) do
    spoke
    |> Contract.call("getLiquidationLogic()", [], "(address)", opts)
    |> unwrap_address()
  end

  api(:oracle, "Fetch the Spoke oracle address.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}"}
  )

  @spec oracle(address(), keyword()) :: result(String.t())
  def oracle(spoke, opts \\ []) do
    spoke
    |> Contract.call("ORACLE()", [], "(address)", opts)
    |> unwrap_address()
  end

  api(:max_user_reserves_limit, "Fetch the maximum collateral and borrow reserve count per user.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}"}
  )

  @spec max_user_reserves_limit(address(), keyword()) :: result(non_neg_integer())
  def max_user_reserves_limit(spoke, opts \\ []) do
    spoke
    |> Contract.call("MAX_USER_RESERVES_LIMIT()", [], "(uint16)", opts)
    |> unwrap_uint()
  end

  @spec call_uint(address(), String.t(), list(), keyword()) :: result(non_neg_integer())
  defp call_uint(spoke, signature, params, opts) do
    spoke
    |> Contract.call(signature, params, "(uint256)", opts)
    |> unwrap_uint()
  end

  @spec call_with_address(address(), String.t(), list(), address(), String.t(), keyword()) :: result(list())
  defp call_with_address(spoke, signature, params, address, return_type, opts) do
    with {:ok, address_bin} <- Address.validate(address) do
      Contract.call(spoke, signature, params ++ [address_bin], return_type, opts)
    end
  end

  @spec call_with_address(address(), String.t(), list(), address(), non_neg_integer(), String.t(), keyword()) ::
          result(list())
  defp call_with_address(spoke, signature, params, address, trailing_param, return_type, opts) do
    with {:ok, address_bin} <- Address.validate(address) do
      Contract.call(spoke, signature, params ++ [address_bin, trailing_param], return_type, opts)
    end
  end

  @spec unwrap_uint(result(list())) :: result(non_neg_integer())
  defp unwrap_uint({:ok, [value]}) when is_integer(value) and value >= 0, do: {:ok, value}
  defp unwrap_uint({:error, _} = error), do: error

  @spec unwrap_pair(result(list())) :: result({non_neg_integer(), non_neg_integer()})
  defp unwrap_pair({:ok, [first, second]}) when is_integer(first) and first >= 0 and is_integer(second) and second >= 0,
    do: {:ok, {first, second}}

  defp unwrap_pair({:error, _} = error), do: error

  @spec unwrap_bool(result(list())) :: result(boolean())
  defp unwrap_bool({:ok, [value]}) when is_boolean(value), do: {:ok, value}
  defp unwrap_bool({:error, _} = error), do: error

  @spec unwrap_bool_pair(result(list())) :: result({boolean(), boolean()})
  defp unwrap_bool_pair({:ok, [first, second]}) when is_boolean(first) and is_boolean(second), do: {:ok, {first, second}}

  defp unwrap_bool_pair({:error, _} = error), do: error

  @spec unwrap_address(result(list())) :: result(String.t())
  defp unwrap_address({:ok, [address]}) when is_binary(address), do: Address.checksum(address)
  defp unwrap_address({:error, _} = error), do: error

  @spec unwrap_struct(result(list()), module()) :: result(struct())
  defp unwrap_struct({:ok, [fields]}, module) when is_tuple(fields), do: {:ok, module.from_raw(fields)}
  defp unwrap_struct({:error, _} = error, _module), do: error
end
