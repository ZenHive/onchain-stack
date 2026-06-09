defmodule Onchain.Aave.DebtToken do
  @moduledoc """
  Aave V3 debt token credit delegation reads and writes.

  Credit delegation lives on the variable/stable debt token contracts, not the Pool.
  Use `debt_token_address/3` to resolve the debt token for an asset and rate mode via
  `Pool.getReserveData/1`, then `approve_delegation/4` to grant or revoke (amount `0`)
  borrowing power and `borrow_allowance/3` to read the current allowance.

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
  | Interest rate mode validation | `{:error, {:invalid_interest_rate_mode, value}}` |

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `debt_token_address/3` | Resolve variable/stable debt token address for an asset |
  | `approve_delegation/4` | Grant or revoke delegated borrow allowance (returns tx hash) |
  | `borrow_allowance/3` | Read delegated borrow allowance between two addresses |
  """

  use Descripex, namespace: "/aave/debt_token"

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.Opts
  alias Onchain.ABI
  alias Onchain.Address
  alias Onchain.Contract
  alias Onchain.Hex
  alias Onchain.Signer

  @variable_rate :variable
  @stable_rate :stable

  @reserve_data_return "((uint256),uint128,uint128,uint128,uint128,uint128,uint40,uint16,address,address,address,address,uint128,uint128,uint128)"
  @stable_debt_token_index 9
  @variable_debt_token_index 10

  # --- debt_token_address ---

  api(:debt_token_address, "Resolve the variable or stable debt token address for an asset.",
    params: [
      asset: [kind: :value, description: "Underlying reserve asset address"],
      rate_mode: [
        kind: :value,
        description: "Interest rate mode: :variable or :stable"
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :network (default :ethereum), :rpc_url, :timeout, :block"
      ]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Checksummed debt token contract address"
    }
  )

  @spec debt_token_address(String.t() | binary(), :variable | :stable, keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def debt_token_address(asset, rate_mode, opts \\ []) do
    {network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, asset_bin} <- Address.validate(asset),
         {:ok, rate} <- resolve_interest_rate_mode(rate_mode),
         {:ok, pool_addr} <- Contracts.address(:pool, network_opts),
         {:ok, reserve_fields} <-
           Contract.call(
             pool_addr,
             "getReserveData(address)",
             [asset_bin],
             @reserve_data_return,
             rpc_opts
           ),
         {:ok, debt_token_bin} <- pick_debt_token_address(reserve_fields, rate) do
      Address.checksum(debt_token_bin)
    end
  end

  # --- approve_delegation ---

  api(:approve_delegation, "Approve or revoke credit delegation on a debt token.",
    params: [
      debt_token: [kind: :value, description: "Variable or stable debt token contract address"],
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
      debt_token: [kind: :value, description: "Variable or stable debt token contract address"],
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

  # --- Private helpers ---

  @variable_rate_mode 2
  @stable_rate_mode 1

  @doc false
  @spec resolve_interest_rate_mode(:variable | :stable) ::
          {:ok, pos_integer()} | {:error, {:invalid_interest_rate_mode, term()}}
  defp resolve_interest_rate_mode(@variable_rate), do: {:ok, @variable_rate_mode}
  defp resolve_interest_rate_mode(@stable_rate), do: {:ok, @stable_rate_mode}

  defp resolve_interest_rate_mode(other), do: {:error, {:invalid_interest_rate_mode, other}}

  @doc false
  @spec pick_debt_token_address([term()], pos_integer()) :: {:ok, binary()} | {:error, term()}
  defp pick_debt_token_address(reserve_fields, rate_mode) when is_list(reserve_fields) do
    index =
      case rate_mode do
        @variable_rate_mode -> @variable_debt_token_index
        @stable_rate_mode -> @stable_debt_token_index
      end

    case Enum.at(reserve_fields, index) do
      debt_token when is_binary(debt_token) -> {:ok, debt_token}
      _ -> {:error, {:invalid_reserve_data, reserve_fields}}
    end
  end
end
