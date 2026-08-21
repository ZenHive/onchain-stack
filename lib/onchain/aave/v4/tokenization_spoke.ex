defmodule Onchain.Aave.V4.TokenizationSpoke do
  @moduledoc """
  Aave V4 Tokenization Spoke reads — ERC-4626 share accounting plus V4 metadata.

  Each Tokenization Spoke is a supply-only ERC-4626 vault for one `{Hub, asset}`
  pair. Resolve a configured spoke with `lookup/3`, then pass that address to
  the read functions. Amounts stay raw integers (token units / shares).

  ## Error Format

  Errors pass through from the underlying module that failed:

  | Source | Error Shape |
  |--------|-------------|
  | `lookup/3` | `{:error, {:unknown_hub, hub}}`, `{:error, {:unknown_tokenization_spoke, {hub, asset}}}`, `{:error, {:unsupported_network, network}}` |
  | `Onchain.Address.validate/1` | `{:error, {:invalid_address, input}}` |
  | `Onchain.Contract.call/5` | `{:error, {:encode_error, ...}}`, `{:error, {:rpc_error, ...}}`, `{:error, {:decode_error, ...}}` |

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `lookup/3` | Resolve a configured spoke by `{hub, asset}` |
  | `asset/2` | Underlying ERC-20 |
  | `total_assets/2` | Assets managed by the vault |
  | `total_supply/2` | Share token supply |
  | `balance_of/3` | Share balance of an owner |
  | `convert_to_shares/3` | Ideal assets → shares |
  | `convert_to_assets/3` | Ideal shares → assets |
  | `preview_deposit/3` | Shares minted for a deposit |
  | `preview_mint/3` | Assets required to mint shares |
  | `preview_withdraw/3` | Shares burned to withdraw assets |
  | `preview_redeem/3` | Assets returned when redeeming shares |
  | `max_deposit/3` | Deposit cap for a receiver |
  | `max_mint/3` | Mint cap for a receiver |
  | `max_withdraw/3` | Withdrawable assets for an owner |
  | `max_redeem/3` | Redeemable shares for an owner |
  | `hub/2` | Associated Hub |
  | `asset_id/2` | Hub asset identifier |
  | `max_allowed_spoke_cap/2` | Protocol spoke-cap bound |
  | `permit_nonce_namespace/2` | EIP-2612 permit nonce key |
  | `deposit_typehash/2` | Deposit intent typehash |
  | `mint_typehash/2` | Mint intent typehash |
  | `withdraw_typehash/2` | Withdraw intent typehash |
  | `redeem_typehash/2` | Redeem intent typehash |
  | `permit_typehash/2` | Share-token permit typehash |
  | `domain_separator/2` | EIP-712 domain separator |
  """

  use Descripex, namespace: "/aave/v4/tokenization_spoke"

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.Opts
  alias Onchain.Address
  alias Onchain.Contract
  alias Onchain.Hex

  @type hub :: :core | :prime | :plus

  @opts_desc "Options: :network (default :ethereum), :rpc_url, :timeout, :block"
  @spoke_desc "Tokenization Spoke address as 0x hex string or 20-byte binary"
  @hub_desc "Hub atom: :core, :prime, or :plus"
  @asset_desc "Underlying asset atom, e.g. :weth, :usdc, :pt_susde"
  @account_desc "Account address as 0x hex string or 20-byte binary"

  # --- lookup ---

  api(:lookup, "Resolve a configured V4 Tokenization Spoke by {hub, asset}.",
    params: [
      hub: [kind: :value, description: @hub_desc],
      asset: [kind: :value, description: @asset_desc],
      opts: [kind: :value, default: [], description: "Options: [network: :ethereum]"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Checksummed Tokenization Spoke address",
      example: "0x7320CF22Ac095bA2a2e0a652F77efB836c2E751b"
    }
  )

  @spec lookup(hub(), atom(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def lookup(hub, asset, opts \\ []) do
    Contracts.v4_tokenization_spoke(hub, asset, opts)
  end

  # --- asset ---

  api(:asset, "Underlying ERC-20 of a Tokenization Spoke.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: "Checksummed underlying address"}
  )

  @spec asset(String.t() | binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def asset(spoke, opts \\ []) do
    spoke
    |> call_spoke("asset()", [], "(address)", opts)
    |> unwrap_address()
  end

  # --- total_assets ---

  api(:total_assets, "Total underlying assets managed by the vault.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Managed assets (token units)"}
  )

  @spec total_assets(String.t() | binary(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def total_assets(spoke, opts \\ []) do
    call_uint(spoke, "totalAssets()", [], opts)
  end

  # --- total_supply ---

  api(:total_supply, "Total supply of vault share tokens.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Share token supply"}
  )

  @spec total_supply(String.t() | binary(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def total_supply(spoke, opts \\ []) do
    call_uint(spoke, "totalSupply()", [], opts)
  end

  # --- balance_of ---

  api(:balance_of, "Vault share balance of an owner.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      owner: [kind: :value, description: @account_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Share balance"}
  )

  @spec balance_of(String.t() | binary(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def balance_of(spoke, owner, opts \\ []) do
    call_account_uint(spoke, "balanceOf(address)", owner, opts)
  end

  # --- convert_to_shares ---

  api(:convert_to_shares, "Ideal share amount exchanged for the given assets.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      assets: [kind: :value, description: "Asset amount in token units"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Shares"}
  )

  @spec convert_to_shares(String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def convert_to_shares(spoke, assets, opts \\ []) when is_integer(assets) and assets >= 0 do
    call_uint(spoke, "convertToShares(uint256)", [assets], opts)
  end

  # --- convert_to_assets ---

  api(:convert_to_assets, "Ideal asset amount exchanged for the given shares.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      shares: [kind: :value, description: "Share token amount"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Assets (token units)"}
  )

  @spec convert_to_assets(String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def convert_to_assets(spoke, shares, opts \\ []) when is_integer(shares) and shares >= 0 do
    call_uint(spoke, "convertToAssets(uint256)", [shares], opts)
  end

  # --- preview_deposit ---

  api(:preview_deposit, "Shares that would be minted for a deposit at the current block.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      assets: [kind: :value, description: "Asset amount in token units"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Shares minted"}
  )

  @spec preview_deposit(String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def preview_deposit(spoke, assets, opts \\ []) when is_integer(assets) and assets >= 0 do
    call_uint(spoke, "previewDeposit(uint256)", [assets], opts)
  end

  # --- preview_mint ---

  api(:preview_mint, "Assets that would be deposited to mint the given shares.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      shares: [kind: :value, description: "Share token amount"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Assets deposited"}
  )

  @spec preview_mint(String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def preview_mint(spoke, shares, opts \\ []) when is_integer(shares) and shares >= 0 do
    call_uint(spoke, "previewMint(uint256)", [shares], opts)
  end

  # --- preview_withdraw ---

  api(:preview_withdraw, "Shares that would be burned to withdraw the given assets.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      assets: [kind: :value, description: "Asset amount in token units"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Shares burned"}
  )

  @spec preview_withdraw(String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def preview_withdraw(spoke, assets, opts \\ []) when is_integer(assets) and assets >= 0 do
    call_uint(spoke, "previewWithdraw(uint256)", [assets], opts)
  end

  # --- preview_redeem ---

  api(:preview_redeem, "Assets that would be returned when redeeming the given shares.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      shares: [kind: :value, description: "Share token amount"],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Assets returned"}
  )

  @spec preview_redeem(String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def preview_redeem(spoke, shares, opts \\ []) when is_integer(shares) and shares >= 0 do
    call_uint(spoke, "previewRedeem(uint256)", [shares], opts)
  end

  # --- max_deposit ---

  api(:max_deposit, "Maximum assets a receiver can deposit.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      receiver: [kind: :value, description: @account_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Max deposit (token units)"}
  )

  @spec max_deposit(String.t() | binary(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def max_deposit(spoke, receiver, opts \\ []) do
    call_account_uint(spoke, "maxDeposit(address)", receiver, opts)
  end

  # --- max_mint ---

  api(:max_mint, "Maximum shares that can be minted for a receiver.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      receiver: [kind: :value, description: @account_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Max shares minted"}
  )

  @spec max_mint(String.t() | binary(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def max_mint(spoke, receiver, opts \\ []) do
    call_account_uint(spoke, "maxMint(address)", receiver, opts)
  end

  # --- max_withdraw ---

  api(:max_withdraw, "Maximum assets an owner can withdraw.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      owner: [kind: :value, description: @account_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Max withdraw (token units)"}
  )

  @spec max_withdraw(String.t() | binary(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def max_withdraw(spoke, owner, opts \\ []) do
    call_account_uint(spoke, "maxWithdraw(address)", owner, opts)
  end

  # --- max_redeem ---

  api(:max_redeem, "Maximum shares an owner can redeem.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      owner: [kind: :value, description: @account_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Max shares redeemed"}
  )

  @spec max_redeem(String.t() | binary(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def max_redeem(spoke, owner, opts \\ []) do
    call_account_uint(spoke, "maxRedeem(address)", owner, opts)
  end

  # --- hub ---

  api(:hub, "Hub this Tokenization Spoke is bound to.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: "Checksummed Hub address"}
  )

  @spec hub(String.t() | binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def hub(spoke, opts \\ []) do
    spoke
    |> call_spoke("hub()", [], "(address)", opts)
    |> unwrap_address()
  end

  # --- asset_id ---

  api(:asset_id, "Hub asset identifier for this Tokenization Spoke.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Asset identifier"}
  )

  @spec asset_id(String.t() | binary(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def asset_id(spoke, opts \\ []) do
    call_uint(spoke, "assetId()", [], opts)
  end

  # --- max_allowed_spoke_cap ---

  api(:max_allowed_spoke_cap, "Maximum allowed spoke cap (ITokenizationSpoke constant).",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Cap bound (uint40)"}
  )

  @spec max_allowed_spoke_cap(String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def max_allowed_spoke_cap(spoke, opts \\ []) do
    call_uint(spoke, "MAX_ALLOWED_SPOKE_CAP()", [], opts)
  end

  # --- permit_nonce_namespace ---

  api(:permit_nonce_namespace, "Nonce namespace used for share-token EIP-2612 permits.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, non_neg_integer()} | {:error, term()}", description: "Permit nonce key (uint192)"}
  )

  @spec permit_nonce_namespace(String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def permit_nonce_namespace(spoke, opts \\ []) do
    call_uint(spoke, "PERMIT_NONCE_NAMESPACE()", [], opts)
  end

  # --- typehashes ---

  api(:deposit_typehash, "EIP-712 typehash for the deposit intent.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: "0x-prefixed bytes32"}
  )

  @spec deposit_typehash(String.t() | binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def deposit_typehash(spoke, opts \\ []), do: call_bytes32(spoke, "DEPOSIT_TYPEHASH()", opts)

  api(:mint_typehash, "EIP-712 typehash for the mint intent.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: "0x-prefixed bytes32"}
  )

  @spec mint_typehash(String.t() | binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def mint_typehash(spoke, opts \\ []), do: call_bytes32(spoke, "MINT_TYPEHASH()", opts)

  api(:withdraw_typehash, "EIP-712 typehash for the withdraw intent.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: "0x-prefixed bytes32"}
  )

  @spec withdraw_typehash(String.t() | binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def withdraw_typehash(spoke, opts \\ []), do: call_bytes32(spoke, "WITHDRAW_TYPEHASH()", opts)

  api(:redeem_typehash, "EIP-712 typehash for the redeem intent.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: "0x-prefixed bytes32"}
  )

  @spec redeem_typehash(String.t() | binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def redeem_typehash(spoke, opts \\ []), do: call_bytes32(spoke, "REDEEM_TYPEHASH()", opts)

  api(:permit_typehash, "EIP-712 typehash for the share-token permit.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: "0x-prefixed bytes32"}
  )

  @spec permit_typehash(String.t() | binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def permit_typehash(spoke, opts \\ []), do: call_bytes32(spoke, "PERMIT_TYPEHASH()", opts)

  # --- domain_separator ---

  api(:domain_separator, "EIP-712 domain separator for this Tokenization Spoke.",
    params: [
      spoke: [kind: :value, description: @spoke_desc],
      opts: [kind: :value, default: [], description: @opts_desc]
    ],
    returns: %{type: "{:ok, String.t()} | {:error, term()}", description: "0x-prefixed bytes32"}
  )

  @spec domain_separator(String.t() | binary(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def domain_separator(spoke, opts \\ []), do: call_bytes32(spoke, "DOMAIN_SEPARATOR()", opts)

  @spec call_spoke(String.t() | binary(), String.t(), list(), String.t(), keyword()) ::
          {:ok, list()} | {:error, term()}
  defp call_spoke(spoke, signature, params, return_type, opts) do
    {_network_opts, rpc_opts} = Opts.split_network(opts)
    Contract.call(spoke, signature, params, return_type, rpc_opts)
  end

  @spec call_uint(String.t() | binary(), String.t(), list(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp call_uint(spoke, signature, params, opts) do
    spoke
    |> call_spoke(signature, params, "(uint256)", opts)
    |> unwrap_uint()
  end

  @spec call_account_uint(String.t() | binary(), String.t(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defp call_account_uint(spoke, signature, account, opts) do
    with {:ok, account_bin} <- Address.validate(account) do
      call_uint(spoke, signature, [account_bin], opts)
    end
  end

  @spec call_bytes32(String.t() | binary(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defp call_bytes32(spoke, signature, opts) do
    spoke
    |> call_spoke(signature, [], "(bytes32)", opts)
    |> unwrap_bytes32()
  end

  @spec unwrap_uint({:ok, list()} | {:error, term()}) :: {:ok, non_neg_integer()} | {:error, term()}
  defp unwrap_uint({:ok, [value]}) when is_integer(value) and value >= 0, do: {:ok, value}
  defp unwrap_uint({:error, _} = error), do: error

  @spec unwrap_address({:ok, list()} | {:error, term()}) :: {:ok, String.t()} | {:error, term()}
  defp unwrap_address({:ok, [bin]}) when is_binary(bin), do: Address.checksum(bin)
  defp unwrap_address({:error, _} = error), do: error

  @spec unwrap_bytes32({:ok, list()} | {:error, term()}) :: {:ok, String.t()} | {:error, term()}
  defp unwrap_bytes32({:ok, [bin]}) when is_binary(bin) and byte_size(bin) == 32, do: {:ok, Hex.encode(bin)}
  defp unwrap_bytes32({:error, _} = error), do: error
end
