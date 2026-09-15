defmodule Onchain.Aave.DebtToken do
  @moduledoc """
  Aave V3 debt token credit delegation reads and writes.

  Credit delegation lives on the variable debt token contracts, not the Pool.
  Use `debt_token_address/3` to resolve the variable debt token for an asset via
  `Pool.get_reserve_variable_debt_token/2`, then `approve_delegation/4` to grant
  or revoke (amount `0`) borrowing power and `borrow_allowance/3` to read the
  current allowance.

  Deployed ValidationLogic accepts only `DataTypes.InterestRateMode.VARIABLE`.
  Passing `:stable` returns `{:error, {:unsupported_interest_rate_mode, :stable}}`
  before any RPC call.

  ## Error Format

  Errors pass through from underlying modules:

  | Source | Error Shape |
  |--------|-------------|
  | `Onchain.Address.validate/1` | `{:error, {:invalid_address, input}}` |
  | `Onchain.Aave.Contracts.address/2` | `{:error, {:unsupported_network, network}}` |
  | `Onchain.ABI.encode_call/2` | `{:error, {:encode_error, reason}}` |
  | `Onchain.RPC.eth_call/3` | `{:error, {:rpc_error, map}}` |
  | `Onchain.ABI.decode_response/2` | `{:error, {:decode_error, reason}}` |
  | `Onchain.Signer.send_transaction/3` | `{:error, {:missing_option, ...}}`, `{:error, {:sign_error, ...}}`, etc. |
  | Interest rate mode validation | `{:error, {:invalid_interest_rate_mode, value}}`, `{:error, {:unsupported_interest_rate_mode, :stable}}` |

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `debt_token_address/3` | Resolve the variable debt token address for an asset |
  | `approve_delegation/4` | Grant or revoke delegated borrow allowance (returns tx hash) |
  | `borrow_allowance/3` | Read delegated borrow allowance between two addresses |
  """

  use Descripex, namespace: "/aave/debt_token"

  alias Onchain.Aave.Pool
  alias Onchain.ABI
  alias Onchain.Address
  alias Onchain.Contract
  alias Onchain.Hex
  alias Onchain.Signer

  # --- debt_token_address ---

  api(:debt_token_address, "Resolve the variable debt token address for an asset.",
    params: [
      asset: [kind: :value, description: "Underlying reserve asset address"],
      rate_mode: [
        kind: :value,
        description: "Interest rate mode. Only :variable is supported."
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :network (default :ethereum), :rpc_url, :timeout, :block"
      ]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Checksummed variable debt token contract address"
    }
  )

  @spec debt_token_address(String.t() | binary(), :variable, keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def debt_token_address(asset, rate_mode, opts \\ []) do
    case rate_mode do
      :variable -> Pool.get_reserve_variable_debt_token(asset, opts)
      :stable -> {:error, {:unsupported_interest_rate_mode, :stable}}
      other -> {:error, {:invalid_interest_rate_mode, other}}
    end
  end

  # --- approve_delegation ---

  api(:approve_delegation, "Approve or revoke credit delegation on a debt token.",
    params: [
      debt_token: [kind: :value, description: "Variable debt token contract address"],
      delegatee: [kind: :value, description: "Address receiving delegated borrowing power"],
      amount: [
        kind: :value,
        description: "Delegated borrow amount (raw integer); use 0 to revoke"
      ],
      opts: [
        kind: :value,
        description: "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :gas_limit (recommend ~120k)"
      ]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Transaction hash hex string"
    }
  )

  @spec approve_delegation(String.t() | binary(), String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def approve_delegation(debt_token, delegatee, amount, opts) do
    with {:ok, _debt_token_bin} <- Address.validate(debt_token),
         {:ok, delegatee_bin} <- Address.validate(delegatee),
         {:ok, calldata_hex} <-
           ABI.encode_call("approveDelegation(address,uint256)", [delegatee_bin, amount]) do
      Signer.send_transaction(debt_token, Hex.decode!(calldata_hex), opts)
    end
  end

  # --- borrow_allowance ---

  api(:borrow_allowance, "Read the delegated borrow allowance between two addresses.",
    params: [
      debt_token: [kind: :value, description: "Variable debt token contract address"],
      from_user: [kind: :value, description: "Delegator address"],
      to_user: [kind: :value, description: "Delegatee address"],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :rpc_url, :timeout, :block"
      ]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Delegated borrow allowance in underlying asset units"
    }
  )

  @spec borrow_allowance(String.t() | binary(), String.t() | binary(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def borrow_allowance(debt_token, from_user, to_user, opts \\ []) do
    with {:ok, debt_token_bin} <- Address.validate(debt_token),
         {:ok, from_bin} <- Address.validate(from_user),
         {:ok, to_bin} <- Address.validate(to_user),
         {:ok, [allowance]} <-
           Contract.call(
             debt_token_bin,
             "borrowAllowance(address,address)",
             [from_bin, to_bin],
             "(uint256)",
             opts
           ) do
      {:ok, allowance}
    end
  end
end
