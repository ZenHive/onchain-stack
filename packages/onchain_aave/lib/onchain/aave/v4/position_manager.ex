defmodule Onchain.Aave.V4.PositionManager do
  @moduledoc """
  Aave V4 Giver, Taker, and Config Position Manager write wrappers, plus
  Spoke position-manager authorization.

  V4 has no Pool. Supply and repay go through the Giver Position Manager
  (`:v4_giver_position_manager`); borrow and withdraw go through the Taker
  (`:v4_taker_position_manager`); collateral and risk-premium configuration
  go through the Config Position Manager (`:v4_config_position_manager`) or
  the Spoke itself. Reserves are addressed by a Spoke-scoped `reserve_id`
  (from `Onchain.Aave.V4.Spoke`), not by asset address.

  Every `*OnBehalfOf` and allowance-gated entrypoint takes the position owner
  as an explicit required argument. The wrappers never default the owner to
  the signer address. `approve_borrow/5`, `approve_withdraw/5`,
  `set_user_position_manager/4`, and the Config permission setters have no owner argument because the on-chain
  functions grant from `msg.sender`.

  Config updates require the matching permission even when owner and signer are
  the same address. Authorize Config on the Spoke, then grant risk-premium or
  dynamic-config permission with its corresponding setter. Collateral permission
  does not authorize either update. Passing `false` revokes a permission.

  ## Error Format

  | Source | Error Shape |
  |--------|-------------|
  | `Onchain.Address.validate/1` | `{:error, {:invalid_address, input}}` |
  | Amount / reserve id / flag | `{:error, {:invalid_amount, input}}`, `{:error, {:invalid_reserve_id, input}}`, `{:error, {:invalid_flag, input}}` |
  | `Onchain.Aave.Contracts.address/2` | `{:error, {:unsupported_network, network}}`, `{:error, {:unknown_contract, key}}` |
  | Taker allowance reverts | `{:error, {:insufficient_borrow_allowance, allowance, required}}`, `{:error, {:insufficient_withdraw_allowance, allowance, required}}` |
  | `Onchain.ABI.encode_call/2` | `{:error, {:encode_error, reason}}` |
  | `Onchain.Contract.call/5` | `{:error, {:rpc_error, map}}`, `{:error, {:decode_error, reason}}` |
  | `Onchain.Signer.send_transaction/3` | `{:error, {:missing_option, ...}}`, `{:error, {:sign_error, ...}}`, etc. |

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `supply/5` | Giver `supplyOnBehalfOf` |
  | `repay/5` | Giver `repayOnBehalfOf` |
  | `borrow/5` | Taker `borrowOnBehalfOf` |
  | `withdraw/5` | Taker `withdrawOnBehalfOf` |
  | `approve_borrow/5` | Taker `approveBorrow` |
  | `approve_withdraw/5` | Taker `approveWithdraw` |
  | `renounce_borrow_allowance/4` | Taker `renounceBorrowAllowance` |
  | `renounce_withdraw_allowance/4` | Taker `renounceWithdrawAllowance` |
  | `borrow_allowance/5` | Taker `borrowAllowance` |
  | `withdraw_allowance/5` | Taker `withdrawAllowance` |
  | `set_user_position_manager/4` | Spoke `setUserPositionManager` |
  | `set_using_as_collateral/5` | Spoke `setUsingAsCollateral` |
  | `set_using_as_collateral_on_behalf_of/5` | Config `setUsingAsCollateralOnBehalfOf` |
  | `update_user_risk_premium_on_behalf_of/3` | Config `updateUserRiskPremiumOnBehalfOf` |
  | `update_user_dynamic_config_on_behalf_of/3` | Config `updateUserDynamicConfigOnBehalfOf` |
  | `set_can_set_using_as_collateral_permission/4` | Config `setCanSetUsingAsCollateralPermission` |
  | `set_can_update_user_risk_premium_permission/4` | Config risk-premium permission grant/revoke |
  | `set_can_update_user_dynamic_config_permission/4` | Config dynamic-config permission grant/revoke |
  | `decode_revert/1` | Decode Taker allowance custom-error revert data |
  """

  use Descripex, namespace: "/aave/v4/position_manager"

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.Opts
  alias Onchain.ABI
  alias Onchain.Address
  alias Onchain.Contract
  alias Onchain.Hex
  alias Onchain.Signer

  @type address :: String.t() | binary()
  @type result(value) :: {:ok, value} | {:error, term()}

  @giver :v4_giver_position_manager
  @taker :v4_taker_position_manager
  @config :v4_config_position_manager

  @supply_sig "supplyOnBehalfOf(address,uint256,uint256,address)"
  @repay_sig "repayOnBehalfOf(address,uint256,uint256,address)"
  @borrow_sig "borrowOnBehalfOf(address,uint256,uint256,address)"
  @withdraw_sig "withdrawOnBehalfOf(address,uint256,uint256,address)"
  @approve_borrow_sig "approveBorrow(address,uint256,address,uint256)"
  @approve_withdraw_sig "approveWithdraw(address,uint256,address,uint256)"
  @renounce_borrow_sig "renounceBorrowAllowance(address,uint256,address)"
  @renounce_withdraw_sig "renounceWithdrawAllowance(address,uint256,address)"
  @borrow_allowance_sig "borrowAllowance(address,uint256,address,address)"
  @withdraw_allowance_sig "withdrawAllowance(address,uint256,address,address)"
  @set_user_position_manager_sig "setUserPositionManager(address,bool)"
  @set_using_as_collateral_sig "setUsingAsCollateral(uint256,bool,address)"
  @set_using_as_collateral_obo_sig "setUsingAsCollateralOnBehalfOf(address,uint256,bool,address)"
  @update_risk_premium_sig "updateUserRiskPremiumOnBehalfOf(address,address)"
  @update_dynamic_config_sig "updateUserDynamicConfigOnBehalfOf(address,address)"
  @set_can_update_risk_permission_sig "setCanUpdateUserRiskPremiumPermission(address,address,bool)"
  @set_can_update_dynamic_permission_sig "setCanUpdateUserDynamicConfigPermission(address,address,bool)"
  @set_can_set_collateral_permission_sig "setCanSetUsingAsCollateralPermission(address,address,bool)"

  @borrow_allowance_error "InsufficientBorrowAllowance(uint256,uint256)"
  @withdraw_allowance_error "InsufficientWithdrawAllowance(uint256,uint256)"
  @allowance_errors [@borrow_allowance_error, @withdraw_allowance_error]

  @spoke_desc "Spoke contract address as 0x hex string or 20-byte binary"
  @reserve_id_desc "Spoke-local reserve identifier (not an asset address)"
  @amount_desc "Raw integer amount in underlying token units"
  @owner_desc "Position owner. Required; never defaulted to the signer"
  @spender_desc "Address receiving (or holding) the Taker allowance"
  @manager_desc "Position manager address to authorize or revoke"
  @delegatee_desc "Address receiving (or holding) a Config permission"
  @flag_desc "Boolean flag; rejected unless it is exactly true or false"
  @write_opts_desc "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :network (default :ethereum), :gas_limit"
  @read_opts_desc "Options: :network (default :ethereum), :rpc_url, :timeout, :block"
  @tx_hash_desc "Transaction hash hex string"

  # --- supply ---

  api(:supply, "Supply underlying to a Spoke reserve on behalf of a position owner via the Giver.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      amount: [kind: :value, description: @amount_desc],
      on_behalf_of: [kind: :value, description: @owner_desc],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec supply(address(), non_neg_integer(), non_neg_integer(), address(), keyword()) :: result(String.t())
  def supply(spoke, reserve_id, amount, on_behalf_of, opts) do
    on_behalf_of_tx(@giver, @supply_sig, spoke, reserve_id, amount, on_behalf_of, opts)
  end

  # --- repay ---

  api(:repay, "Repay a Spoke reserve debt on behalf of a position owner via the Giver.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      amount: [kind: :value, description: @amount_desc],
      on_behalf_of: [kind: :value, description: @owner_desc],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec repay(address(), non_neg_integer(), non_neg_integer(), address(), keyword()) :: result(String.t())
  def repay(spoke, reserve_id, amount, on_behalf_of, opts) do
    on_behalf_of_tx(@giver, @repay_sig, spoke, reserve_id, amount, on_behalf_of, opts)
  end

  # --- borrow ---

  api(:borrow, "Borrow from a Spoke reserve on behalf of a position owner via the Taker.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      amount: [kind: :value, description: @amount_desc],
      on_behalf_of: [kind: :value, description: @owner_desc],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec borrow(address(), non_neg_integer(), non_neg_integer(), address(), keyword()) :: result(String.t())
  def borrow(spoke, reserve_id, amount, on_behalf_of, opts) do
    on_behalf_of_tx(@taker, @borrow_sig, spoke, reserve_id, amount, on_behalf_of, opts)
  end

  # --- withdraw ---

  api(:withdraw, "Withdraw from a Spoke reserve on behalf of a position owner via the Taker.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      amount: [kind: :value, description: @amount_desc],
      on_behalf_of: [kind: :value, description: @owner_desc],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec withdraw(address(), non_neg_integer(), non_neg_integer(), address(), keyword()) :: result(String.t())
  def withdraw(spoke, reserve_id, amount, on_behalf_of, opts) do
    on_behalf_of_tx(@taker, @withdraw_sig, spoke, reserve_id, amount, on_behalf_of, opts)
  end

  # --- approve_borrow ---

  api(:approve_borrow, "Grant a spender Taker borrow allowance from the signer (msg.sender) position.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      spender: [kind: :value, description: @spender_desc],
      amount: [kind: :value, description: "Allowance amount; `type(uint256).max` is infinite"],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec approve_borrow(address(), non_neg_integer(), address(), non_neg_integer(), keyword()) :: result(String.t())
  def approve_borrow(spoke, reserve_id, spender, amount, opts) do
    approve_tx(@approve_borrow_sig, spoke, reserve_id, spender, amount, opts)
  end

  # --- approve_withdraw ---

  api(:approve_withdraw, "Grant a spender Taker withdraw allowance from the signer (msg.sender) position.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      spender: [kind: :value, description: @spender_desc],
      amount: [kind: :value, description: "Allowance amount; `type(uint256).max` is infinite"],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec approve_withdraw(address(), non_neg_integer(), address(), non_neg_integer(), keyword()) :: result(String.t())
  def approve_withdraw(spoke, reserve_id, spender, amount, opts) do
    approve_tx(@approve_withdraw_sig, spoke, reserve_id, spender, amount, opts)
  end

  # --- renounce_borrow_allowance ---

  api(:renounce_borrow_allowance, "Renounce the Taker borrow allowance granted by a position owner.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      owner: [kind: :value, description: @owner_desc],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec renounce_borrow_allowance(address(), non_neg_integer(), address(), keyword()) :: result(String.t())
  def renounce_borrow_allowance(spoke, reserve_id, owner, opts) do
    renounce_tx(@renounce_borrow_sig, spoke, reserve_id, owner, opts)
  end

  # --- renounce_withdraw_allowance ---

  api(:renounce_withdraw_allowance, "Renounce the Taker withdraw allowance granted by a position owner.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      owner: [kind: :value, description: @owner_desc],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec renounce_withdraw_allowance(address(), non_neg_integer(), address(), keyword()) :: result(String.t())
  def renounce_withdraw_allowance(spoke, reserve_id, owner, opts) do
    renounce_tx(@renounce_withdraw_sig, spoke, reserve_id, owner, opts)
  end

  # --- borrow_allowance ---

  api(:borrow_allowance, "Read the Taker borrow allowance a spender holds from a position owner.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      owner: [kind: :value, description: @owner_desc],
      spender: [kind: :value, description: @spender_desc],
      opts: [kind: :value, default: [], description: @read_opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Current borrow allowance"}
  )

  @spec borrow_allowance(address(), non_neg_integer(), address(), address(), keyword()) :: result(non_neg_integer())
  def borrow_allowance(spoke, reserve_id, owner, spender, opts \\ []) do
    allowance_view(@borrow_allowance_sig, spoke, reserve_id, owner, spender, opts)
  end

  # --- withdraw_allowance ---

  api(:withdraw_allowance, "Read the Taker withdraw allowance a spender holds from a position owner.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      owner: [kind: :value, description: @owner_desc],
      spender: [kind: :value, description: @spender_desc],
      opts: [kind: :value, default: [], description: @read_opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Current withdraw allowance"}
  )

  @spec withdraw_allowance(address(), non_neg_integer(), address(), address(), keyword()) :: result(non_neg_integer())
  def withdraw_allowance(spoke, reserve_id, owner, spender, opts \\ []) do
    allowance_view(@withdraw_allowance_sig, spoke, reserve_id, owner, spender, opts)
  end

  # --- set_user_position_manager ---

  api(:set_user_position_manager, "Authorize or revoke a position manager on a Spoke for the signer (msg.sender).",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      position_manager: [kind: :value, description: @manager_desc],
      approve: [kind: :value, description: @flag_desc],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec set_user_position_manager(address(), address(), boolean(), keyword()) :: result(String.t())
  def set_user_position_manager(spoke, position_manager, approve, opts) do
    with {:ok, _spoke_bin} <- Address.validate(spoke),
         {:ok, manager_bin} <- Address.validate(position_manager),
         {:ok, approve} <- validate_bool(approve) do
      send_spoke_tx(spoke, @set_user_position_manager_sig, [manager_bin, approve], opts)
    end
  end

  # --- set_using_as_collateral ---

  api(:set_using_as_collateral, "Toggle a Spoke reserve as collateral on behalf of a position owner.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      using_as_collateral: [kind: :value, description: @flag_desc],
      on_behalf_of: [kind: :value, description: @owner_desc],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec set_using_as_collateral(address(), non_neg_integer(), boolean(), address(), keyword()) :: result(String.t())
  def set_using_as_collateral(spoke, reserve_id, using_as_collateral, on_behalf_of, opts) do
    with {:ok, _spoke_bin} <- Address.validate(spoke),
         {:ok, reserve_id} <- validate_uint(reserve_id, :invalid_reserve_id),
         {:ok, using_as_collateral} <- validate_bool(using_as_collateral),
         {:ok, owner_bin} <- Address.validate(on_behalf_of) do
      send_spoke_tx(spoke, @set_using_as_collateral_sig, [reserve_id, using_as_collateral, owner_bin], opts)
    end
  end

  # --- set_using_as_collateral_on_behalf_of ---

  api(
    :set_using_as_collateral_on_behalf_of,
    "Toggle a Spoke reserve as collateral via the Config Position Manager on behalf of a position owner.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      reserve_id: [kind: :value, description: @reserve_id_desc],
      using_as_collateral: [kind: :value, description: @flag_desc],
      on_behalf_of: [kind: :value, description: @owner_desc],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec set_using_as_collateral_on_behalf_of(address(), non_neg_integer(), boolean(), address(), keyword()) ::
          result(String.t())
  def set_using_as_collateral_on_behalf_of(spoke, reserve_id, using_as_collateral, on_behalf_of, opts) do
    with {:ok, spoke_bin} <- Address.validate(spoke),
         {:ok, reserve_id} <- validate_uint(reserve_id, :invalid_reserve_id),
         {:ok, using_as_collateral} <- validate_bool(using_as_collateral),
         {:ok, owner_bin} <- Address.validate(on_behalf_of) do
      send_manager_tx(
        @config,
        @set_using_as_collateral_obo_sig,
        [spoke_bin, reserve_id, using_as_collateral, owner_bin],
        opts
      )
    end
  end

  # --- update_user_risk_premium_on_behalf_of ---

  api(
    :update_user_risk_premium_on_behalf_of,
    "Refresh a position owner's Spoke risk premium via the Config Position Manager.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      on_behalf_of: [kind: :value, description: @owner_desc],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec update_user_risk_premium_on_behalf_of(address(), address(), keyword()) :: result(String.t())
  def update_user_risk_premium_on_behalf_of(spoke, on_behalf_of, opts) do
    config_on_behalf_of_tx(@update_risk_premium_sig, spoke, on_behalf_of, opts)
  end

  # --- update_user_dynamic_config_on_behalf_of ---

  api(
    :update_user_dynamic_config_on_behalf_of,
    "Refresh a position owner's Spoke dynamic config via the Config Position Manager.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      on_behalf_of: [kind: :value, description: @owner_desc],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec update_user_dynamic_config_on_behalf_of(address(), address(), keyword()) :: result(String.t())
  def update_user_dynamic_config_on_behalf_of(spoke, on_behalf_of, opts) do
    config_on_behalf_of_tx(@update_dynamic_config_sig, spoke, on_behalf_of, opts)
  end

  # --- set_can_set_using_as_collateral_permission ---

  api(
    :set_can_set_using_as_collateral_permission,
    "Grant or revoke a delegatee's Config permission to toggle collateral from the signer (msg.sender).",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      delegatee: [kind: :value, description: @delegatee_desc],
      status: [kind: :value, description: @flag_desc],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec set_can_set_using_as_collateral_permission(address(), address(), boolean(), keyword()) :: result(String.t())
  def set_can_set_using_as_collateral_permission(spoke, delegatee, status, opts) do
    config_permission_tx(@set_can_set_collateral_permission_sig, spoke, delegatee, status, opts)
  end

  api(
    :set_can_update_user_risk_premium_permission,
    "Grant or revoke a delegatee's Config permission to update risk premium from the signer (msg.sender).",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      delegatee: [kind: :value, description: @delegatee_desc],
      status: [kind: :value, description: @flag_desc],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec set_can_update_user_risk_premium_permission(address(), address(), boolean(), keyword()) :: result(String.t())
  def set_can_update_user_risk_premium_permission(spoke, delegatee, status, opts) do
    config_permission_tx(@set_can_update_risk_permission_sig, spoke, delegatee, status, opts)
  end

  api(
    :set_can_update_user_dynamic_config_permission,
    "Grant or revoke a delegatee's Config permission to update dynamic config from the signer (msg.sender).",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      delegatee: [kind: :value, description: @delegatee_desc],
      status: [kind: :value, description: @flag_desc],
      opts: [kind: :value, description: @write_opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: @tx_hash_desc}
  )

  @spec set_can_update_user_dynamic_config_permission(address(), address(), boolean(), keyword()) :: result(String.t())
  def set_can_update_user_dynamic_config_permission(spoke, delegatee, status, opts) do
    config_permission_tx(@set_can_update_dynamic_permission_sig, spoke, delegatee, status, opts)
  end

  # --- decode_revert ---

  api(:decode_revert, "Decode Taker InsufficientBorrow/WithdrawAllowance custom-error revert data.",
    params: [
      revert_data: [
        kind: :value,
        description: "0x-prefixed hex or raw revert bytes (4-byte selector + ABI args)"
      ]
    ],
    returns: %{
      type:
        "{:error, {:insufficient_borrow_allowance | :insufficient_withdraw_allowance, non_neg_integer(), non_neg_integer()}} | {:error, {:unknown_revert, term()}}",
      description: "Tagged allowance error with (allowance, required), or unknown_revert"
    }
  )

  @spec decode_revert(String.t() | binary()) ::
          {:error, {:insufficient_borrow_allowance, non_neg_integer(), non_neg_integer()}}
          | {:error, {:insufficient_withdraw_allowance, non_neg_integer(), non_neg_integer()}}
          | {:error, {:unknown_revert, term()}}
  def decode_revert(revert_data) do
    case ABI.decode_error(revert_hex(revert_data), @allowance_errors) do
      {:ok, %{error: "InsufficientBorrowAllowance", args: [allowance, required]}} ->
        {:error, {:insufficient_borrow_allowance, allowance, required}}

      {:ok, %{error: "InsufficientWithdrawAllowance", args: [allowance, required]}} ->
        {:error, {:insufficient_withdraw_allowance, allowance, required}}

      {:error, reason} ->
        {:error, {:unknown_revert, reason}}
    end
  end

  @spec on_behalf_of_tx(atom(), String.t(), address(), term(), term(), address(), keyword()) :: result(String.t())
  defp on_behalf_of_tx(contract_key, signature, spoke, reserve_id, amount, on_behalf_of, opts) do
    with {:ok, spoke_bin} <- Address.validate(spoke),
         {:ok, reserve_id} <- validate_uint(reserve_id, :invalid_reserve_id),
         {:ok, amount} <- validate_uint(amount, :invalid_amount),
         {:ok, owner_bin} <- Address.validate(on_behalf_of) do
      send_manager_tx(contract_key, signature, [spoke_bin, reserve_id, amount, owner_bin], opts)
    end
  end

  @spec approve_tx(String.t(), address(), term(), address(), term(), keyword()) :: result(String.t())
  defp approve_tx(signature, spoke, reserve_id, spender, amount, opts) do
    with {:ok, spoke_bin} <- Address.validate(spoke),
         {:ok, reserve_id} <- validate_uint(reserve_id, :invalid_reserve_id),
         {:ok, spender_bin} <- Address.validate(spender),
         {:ok, amount} <- validate_uint(amount, :invalid_amount) do
      send_manager_tx(@taker, signature, [spoke_bin, reserve_id, spender_bin, amount], opts)
    end
  end

  @spec renounce_tx(String.t(), address(), term(), address(), keyword()) :: result(String.t())
  defp renounce_tx(signature, spoke, reserve_id, owner, opts) do
    with {:ok, spoke_bin} <- Address.validate(spoke),
         {:ok, reserve_id} <- validate_uint(reserve_id, :invalid_reserve_id),
         {:ok, owner_bin} <- Address.validate(owner) do
      send_manager_tx(@taker, signature, [spoke_bin, reserve_id, owner_bin], opts)
    end
  end

  @spec allowance_view(String.t(), address(), term(), address(), address(), keyword()) :: result(non_neg_integer())
  defp allowance_view(signature, spoke, reserve_id, owner, spender, opts) do
    {network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, spoke_bin} <- Address.validate(spoke),
         {:ok, reserve_id} <- validate_uint(reserve_id, :invalid_reserve_id),
         {:ok, owner_bin} <- Address.validate(owner),
         {:ok, spender_bin} <- Address.validate(spender),
         {:ok, taker} <- Contracts.address(@taker, network_opts) do
      taker
      |> Contract.call(signature, [spoke_bin, reserve_id, owner_bin, spender_bin], "(uint256)", rpc_opts)
      |> unwrap_uint()
    end
  end

  @spec config_permission_tx(String.t(), address(), address(), boolean(), keyword()) :: result(String.t())
  defp config_permission_tx(signature, spoke, delegatee, status, opts) do
    with {:ok, spoke_bin} <- Address.validate(spoke),
         {:ok, delegatee_bin} <- Address.validate(delegatee),
         {:ok, status} <- validate_bool(status) do
      send_manager_tx(@config, signature, [spoke_bin, delegatee_bin, status], opts)
    end
  end

  @spec config_on_behalf_of_tx(String.t(), address(), address(), keyword()) :: result(String.t())
  defp config_on_behalf_of_tx(signature, spoke, on_behalf_of, opts) do
    with {:ok, spoke_bin} <- Address.validate(spoke),
         {:ok, owner_bin} <- Address.validate(on_behalf_of) do
      send_manager_tx(@config, signature, [spoke_bin, owner_bin], opts)
    end
  end

  @spec send_spoke_tx(address(), String.t(), [term()], keyword()) :: result(String.t())
  defp send_spoke_tx(spoke, signature, args, opts) do
    {_network_opts, signer_opts} = Opts.split_network(opts)

    with {:ok, calldata_hex} <- ABI.encode_call(signature, args) do
      spoke
      |> Signer.send_transaction(Hex.decode!(calldata_hex), signer_opts)
      |> map_rpc_error()
    end
  end

  @spec send_manager_tx(atom(), String.t(), [term()], keyword()) :: result(String.t())
  defp send_manager_tx(contract_key, signature, args, opts) do
    {network_opts, signer_opts} = Opts.split_network(opts)

    with {:ok, addr} <- Contracts.address(contract_key, network_opts),
         {:ok, calldata_hex} <- ABI.encode_call(signature, args) do
      addr
      |> Signer.send_transaction(Hex.decode!(calldata_hex), signer_opts)
      |> map_rpc_error()
    end
  end

  @spec validate_uint(term(), atom()) :: {:ok, non_neg_integer()} | {:error, {atom(), term()}}
  defp validate_uint(value, _tag) when is_integer(value) and value >= 0, do: {:ok, value}
  defp validate_uint(value, tag), do: {:error, {tag, value}}

  @spec validate_bool(term()) :: {:ok, boolean()} | {:error, {:invalid_flag, term()}}
  defp validate_bool(value) when is_boolean(value), do: {:ok, value}
  defp validate_bool(value), do: {:error, {:invalid_flag, value}}

  @spec unwrap_uint({:ok, list()} | {:error, term()}) :: result(non_neg_integer())
  defp unwrap_uint({:ok, [value]}) when is_integer(value) and value >= 0, do: {:ok, value}
  defp unwrap_uint({:error, _} = error), do: map_rpc_error(error)

  @spec map_rpc_error({:ok, term()} | {:error, term()}) :: {:ok, term()} | {:error, term()}
  defp map_rpc_error({:error, {:rpc_error, %{data: data}}} = error) when is_binary(data) do
    case decode_revert(data) do
      {:error, {:insufficient_borrow_allowance, _, _}} = decoded -> decoded
      {:error, {:insufficient_withdraw_allowance, _, _}} = decoded -> decoded
      {:error, {:unknown_revert, _}} -> error
    end
  end

  defp map_rpc_error(other), do: other

  @spec revert_hex(String.t() | binary()) :: String.t()
  defp revert_hex(<<"0x", _::binary>> = hex), do: hex
  defp revert_hex(bin) when is_binary(bin), do: Hex.encode(bin)
end
