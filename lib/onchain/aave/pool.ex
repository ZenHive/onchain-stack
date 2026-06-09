defmodule Onchain.Aave.Pool do
  @moduledoc """
  High-level Aave V3 Pool read and write operations.

  **Read operations** compose `Address`, `Contracts`, `ABI`, `RPC`, and `Math`
  into single-call functions that return converted `Decimal` values.

  **Write operations** validate inputs, ABI-encode calldata, and delegate to
  `Signer.send_transaction/3`. Gas limits are NOT defaulted per operation —
  Aave ops typically need more than Signer's default 100k (supply ~200k,
  borrow ~300k). Specify via `:gas_limit` in opts.

  ## Error Format

  Errors pass through from the underlying module that failed:

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
  | `get_user_account_data/2` | Full position summary as `UserAccountData` struct |
  | `get_user_account_data!/2` | Same, raises on error |
  | `get_user_account_data_many/2` | Batch many users' positions in one Multicall3 round-trip |
  | `get_user_account_data_many!/2` | Same, raises on error |
  | `supply/4` | Supply asset to pool (returns tx hash) |
  | `supply!/4` | Same, raises on error |
  | `withdraw/4` | Withdraw asset from pool (returns tx hash) |
  | `withdraw!/4` | Same, raises on error |
  | `borrow/4` | Borrow asset from pool (returns tx hash) |
  | `borrow!/4` | Same, raises on error |
  | `repay/4` | Repay borrowed asset (returns tx hash) |
  | `repay!/4` | Same, raises on error |
  """

  use Descripex, namespace: "/aave/pool"

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.Opts
  alias Onchain.Aave.Types.UserAccountData
  alias Onchain.ABI
  alias Onchain.Address
  alias Onchain.Hex
  alias Onchain.Multicall
  alias Onchain.RPC
  alias Onchain.Signer

  @referral_code 0
  @variable_rate 2
  @stable_rate 1

  @user_account_data_response "(uint256,uint256,uint256,uint256,uint256,uint256)"

  # --- get_user_account_data ---

  api(:get_user_account_data, "Fetch a user's full Aave V3 position as converted Decimal values.",
    params: [
      user_address: [
        kind: :value,
        description: "User address as 0x hex string or 20-byte binary"
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :network (default :ethereum), :rpc_url, :timeout, :block"
      ]
    ],
    returns: %{
      type: "{:ok, UserAccountData.t()} | {:error, term()}",
      description:
        "UserAccountData struct with Decimal values for collateral, debt, borrows, thresholds, and health factor",
      example: ~s[%UserAccountData{total_collateral_base: Decimal.new("1234.56"), health_factor: Decimal.new("1.5"), ...}]
    }
  )

  @spec get_user_account_data(String.t() | binary(), keyword()) ::
          {:ok, UserAccountData.t()} | {:error, term()}
  def get_user_account_data(user_address, opts \\ []) do
    {network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, user_bin} <- Address.validate(user_address),
         {:ok, pool_addr} <- Contracts.address(:pool, network_opts),
         {:ok, calldata} <- ABI.encode_call("getUserAccountData(address)", [user_bin]),
         {:ok, hex_result} <- RPC.eth_call(pool_addr, calldata, rpc_opts),
         {:ok, values} <- ABI.decode_response(@user_account_data_response, hex_result) do
      {:ok, UserAccountData.from_raw(values)}
    end
  end

  # --- get_user_account_data! ---

  api(:get_user_account_data!, "Fetch a user's full Aave V3 position. Raises on error.",
    params: [
      user_address: [
        kind: :value,
        description: "User address as 0x hex string or 20-byte binary"
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :network (default :ethereum), :rpc_url, :timeout, :block"
      ]
    ],
    returns: %{
      type: "UserAccountData.t()",
      description:
        "UserAccountData struct with Decimal values for collateral, debt, borrows, thresholds, and health factor"
    }
  )

  @spec get_user_account_data!(String.t() | binary(), keyword()) :: UserAccountData.t()
  def get_user_account_data!(user_address, opts \\ []) do
    case get_user_account_data(user_address, opts) do
      {:ok, data} -> data
      {:error, reason} -> raise "get_user_account_data failed: #{inspect(reason)}"
    end
  end

  # --- get_user_account_data_many ---

  api(
    :get_user_account_data_many,
    "Batch-fetch many users' Aave V3 positions in a single Multicall3 round-trip.",
    params: [
      user_addresses: [
        kind: :value,
        description: "List of user addresses as 0x hex strings or 20-byte binaries"
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :network (default :ethereum), :rpc_url, :timeout, :block"
      ]
    ],
    returns: %{
      type: "{:ok, [UserAccountData.t()]} | {:error, term()}",
      description:
        "List of UserAccountData structs aligned positionally with the input. Empty input returns {:ok, []} with no RPC call."
    }
  )

  @spec get_user_account_data_many([String.t() | binary()], keyword()) ::
          {:ok, [UserAccountData.t()]} | {:error, term()}
  def get_user_account_data_many(user_addresses, opts \\ [])

  def get_user_account_data_many([], _opts), do: {:ok, []}

  def get_user_account_data_many(user_addresses, opts) when is_list(user_addresses) do
    {network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, user_bins} <- validate_addresses(user_addresses),
         {:ok, pool_addr} <- Contracts.address(:pool, network_opts),
         calls = build_account_data_calls(pool_addr, user_bins),
         {:ok, results} <- Multicall.call_many(calls, rpc_opts) do
      collect_account_data(results)
    end
  end

  # --- get_user_account_data_many! ---

  api(
    :get_user_account_data_many!,
    "Batch-fetch many users' Aave V3 positions in one round-trip. Raises on error.",
    params: [
      user_addresses: [
        kind: :value,
        description: "List of user addresses as 0x hex strings or 20-byte binaries"
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Options: :network (default :ethereum), :rpc_url, :timeout, :block"
      ]
    ],
    returns: %{
      type: "[UserAccountData.t()]",
      description: "List of UserAccountData structs aligned positionally with the input"
    }
  )

  @spec get_user_account_data_many!([String.t() | binary()], keyword()) :: [UserAccountData.t()]
  def get_user_account_data_many!(user_addresses, opts \\ []) do
    case get_user_account_data_many(user_addresses, opts) do
      {:ok, data} -> data
      {:error, reason} -> raise "get_user_account_data_many failed: #{inspect(reason)}"
    end
  end

  # --- supply ---

  api(:supply, "Supply an asset to the Aave V3 Pool.",
    params: [
      asset: [kind: :value, description: "ERC-20 token contract address to supply"],
      amount: [kind: :value, description: "Amount to supply (raw integer, not decimal-adjusted)"],
      on_behalf_of: [kind: :value, description: "Address that receives the aTokens"],
      opts: [
        kind: :value,
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :network (default :ethereum), :gas_limit (recommend ~200k for supply)"
      ]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Transaction hash hex string"
    }
  )

  @spec supply(String.t() | binary(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def supply(asset, amount, on_behalf_of, opts) do
    {network_opts, _rate_mode, signer_opts} = split_write_opts(opts)

    with {:ok, asset_bin} <- Address.validate(asset),
         {:ok, obo_bin} <- Address.validate(on_behalf_of) do
      send_pool_tx(
        network_opts,
        "supply(address,uint256,address,uint16)",
        [asset_bin, amount, obo_bin, @referral_code],
        signer_opts
      )
    end
  end

  # --- supply! ---

  api(:supply!, "Supply an asset to the Aave V3 Pool. Raises on error.",
    params: [
      asset: [kind: :value, description: "ERC-20 token contract address to supply"],
      amount: [kind: :value, description: "Amount to supply (raw integer, not decimal-adjusted)"],
      on_behalf_of: [kind: :value, description: "Address that receives the aTokens"],
      opts: [
        kind: :value,
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :network (default :ethereum), :gas_limit (recommend ~200k for supply)"
      ]
    ],
    returns: %{type: :string, description: "Transaction hash hex string"}
  )

  @spec supply!(String.t() | binary(), non_neg_integer(), String.t() | binary(), keyword()) ::
          String.t()
  def supply!(asset, amount, on_behalf_of, opts) do
    case supply(asset, amount, on_behalf_of, opts) do
      {:ok, tx_hash} -> tx_hash
      {:error, reason} -> raise "supply failed: #{inspect(reason)}"
    end
  end

  # --- withdraw ---

  api(:withdraw, "Withdraw an asset from the Aave V3 Pool.",
    params: [
      asset: [kind: :value, description: "ERC-20 token contract address to withdraw"],
      amount: [kind: :value, description: "Amount to withdraw (raw integer, or max uint256 for full balance)"],
      to: [kind: :value, description: "Address that receives the withdrawn tokens"],
      opts: [
        kind: :value,
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :network (default :ethereum), :gas_limit (recommend ~200k for withdraw)"
      ]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Transaction hash hex string"
    }
  )

  @spec withdraw(String.t() | binary(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def withdraw(asset, amount, to, opts) do
    {network_opts, _rate_mode, signer_opts} = split_write_opts(opts)

    with {:ok, asset_bin} <- Address.validate(asset),
         {:ok, to_bin} <- Address.validate(to) do
      send_pool_tx(
        network_opts,
        "withdraw(address,uint256,address)",
        [asset_bin, amount, to_bin],
        signer_opts
      )
    end
  end

  # --- withdraw! ---

  api(:withdraw!, "Withdraw an asset from the Aave V3 Pool. Raises on error.",
    params: [
      asset: [kind: :value, description: "ERC-20 token contract address to withdraw"],
      amount: [kind: :value, description: "Amount to withdraw (raw integer, or max uint256 for full balance)"],
      to: [kind: :value, description: "Address that receives the withdrawn tokens"],
      opts: [
        kind: :value,
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :network (default :ethereum), :gas_limit (recommend ~200k for withdraw)"
      ]
    ],
    returns: %{type: :string, description: "Transaction hash hex string"}
  )

  @spec withdraw!(String.t() | binary(), non_neg_integer(), String.t() | binary(), keyword()) ::
          String.t()
  def withdraw!(asset, amount, to, opts) do
    case withdraw(asset, amount, to, opts) do
      {:ok, tx_hash} -> tx_hash
      {:error, reason} -> raise "withdraw failed: #{inspect(reason)}"
    end
  end

  # --- borrow ---

  api(:borrow, "Borrow an asset from the Aave V3 Pool.",
    params: [
      asset: [kind: :value, description: "ERC-20 token contract address to borrow"],
      amount: [kind: :value, description: "Amount to borrow (raw integer, not decimal-adjusted)"],
      on_behalf_of: [kind: :value, description: "Address that incurs the debt"],
      opts: [
        kind: :value,
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :network (default :ethereum), :interest_rate_mode (:variable default, :stable), :gas_limit (recommend ~300k for borrow)"
      ]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Transaction hash hex string"
    }
  )

  @spec borrow(String.t() | binary(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def borrow(asset, amount, on_behalf_of, opts) do
    {network_opts, rate_mode, signer_opts} = split_write_opts(opts)

    with {:ok, rate} <- resolve_interest_rate_mode(rate_mode),
         {:ok, asset_bin} <- Address.validate(asset),
         {:ok, obo_bin} <- Address.validate(on_behalf_of) do
      send_pool_tx(
        network_opts,
        "borrow(address,uint256,uint256,uint16,address)",
        [asset_bin, amount, rate, @referral_code, obo_bin],
        signer_opts
      )
    end
  end

  # --- borrow! ---

  api(:borrow!, "Borrow an asset from the Aave V3 Pool. Raises on error.",
    params: [
      asset: [kind: :value, description: "ERC-20 token contract address to borrow"],
      amount: [kind: :value, description: "Amount to borrow (raw integer, not decimal-adjusted)"],
      on_behalf_of: [kind: :value, description: "Address that incurs the debt"],
      opts: [
        kind: :value,
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :network (default :ethereum), :interest_rate_mode (:variable default, :stable), :gas_limit (recommend ~300k for borrow)"
      ]
    ],
    returns: %{type: :string, description: "Transaction hash hex string"}
  )

  @spec borrow!(String.t() | binary(), non_neg_integer(), String.t() | binary(), keyword()) ::
          String.t()
  def borrow!(asset, amount, on_behalf_of, opts) do
    case borrow(asset, amount, on_behalf_of, opts) do
      {:ok, tx_hash} -> tx_hash
      {:error, reason} -> raise "borrow failed: #{inspect(reason)}"
    end
  end

  # --- repay ---

  api(:repay, "Repay a borrowed asset to the Aave V3 Pool.",
    params: [
      asset: [kind: :value, description: "ERC-20 token contract address to repay"],
      amount: [kind: :value, description: "Amount to repay (raw integer, or max uint256 for full debt)"],
      on_behalf_of: [kind: :value, description: "Address whose debt is being repaid"],
      opts: [
        kind: :value,
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :network (default :ethereum), :interest_rate_mode (:variable default, :stable), :gas_limit (recommend ~200k for repay)"
      ]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Transaction hash hex string"
    }
  )

  @spec repay(String.t() | binary(), non_neg_integer(), String.t() | binary(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def repay(asset, amount, on_behalf_of, opts) do
    {network_opts, rate_mode, signer_opts} = split_write_opts(opts)

    with {:ok, rate} <- resolve_interest_rate_mode(rate_mode),
         {:ok, asset_bin} <- Address.validate(asset),
         {:ok, obo_bin} <- Address.validate(on_behalf_of) do
      send_pool_tx(
        network_opts,
        "repay(address,uint256,uint256,address)",
        [asset_bin, amount, rate, obo_bin],
        signer_opts
      )
    end
  end

  # --- repay! ---

  api(:repay!, "Repay a borrowed asset to the Aave V3 Pool. Raises on error.",
    params: [
      asset: [kind: :value, description: "ERC-20 token contract address to repay"],
      amount: [kind: :value, description: "Amount to repay (raw integer, or max uint256 for full debt)"],
      on_behalf_of: [kind: :value, description: "Address whose debt is being repaid"],
      opts: [
        kind: :value,
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :network (default :ethereum), :interest_rate_mode (:variable default, :stable), :gas_limit (recommend ~200k for repay)"
      ]
    ],
    returns: %{type: :string, description: "Transaction hash hex string"}
  )

  @spec repay!(String.t() | binary(), non_neg_integer(), String.t() | binary(), keyword()) ::
          String.t()
  def repay!(asset, amount, on_behalf_of, opts) do
    case repay(asset, amount, on_behalf_of, opts) do
      {:ok, tx_hash} -> tx_hash
      {:error, reason} -> raise "repay failed: #{inspect(reason)}"
    end
  end

  # --- Private helpers ---

  # Validates a list of addresses, preserving order. Halts on the first invalid one.
  @spec validate_addresses([String.t() | binary()]) :: {:ok, [binary()]} | {:error, term()}
  defp validate_addresses(addresses) do
    addresses
    |> Enum.reduce_while({:ok, []}, fn addr, {:ok, acc} ->
      case Address.validate(addr) do
        {:ok, bin} -> {:cont, {:ok, [bin | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, bins} -> {:ok, Enum.reverse(bins)}
      error -> error
    end
  end

  # Builds one getUserAccountData Multicall call spec per user against the Pool address.
  @spec build_account_data_calls(String.t(), [binary()]) ::
          [{String.t(), String.t(), [binary()], String.t()}]
  defp build_account_data_calls(pool_addr, user_bins) do
    Enum.map(user_bins, fn user_bin ->
      {pool_addr, "getUserAccountData(address)", [user_bin], @user_account_data_response}
    end)
  end

  # Converts Multicall call_many results into UserAccountData structs, preserving
  # order. A reverted sub-call fails the whole batch loudly rather than silently.
  @spec collect_account_data([{:ok, list()} | {:error, String.t()}]) ::
          {:ok, [UserAccountData.t()]} | {:error, {:multicall_call_failed, String.t()}}
  defp collect_account_data(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, values}, {:ok, acc} -> {:cont, {:ok, [UserAccountData.from_raw(values) | acc]}}
      {:error, data}, _acc -> {:halt, {:error, {:multicall_call_failed, data}}}
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  # Pool-specific tx dispatch: looks up the Pool address, ABI-encodes the call,
  # and delegates to Signer. Shared by supply/withdraw/borrow/repay. Pool-only
  # by design — Faucet uses a different contract key and has only one call site.
  @spec send_pool_tx(keyword(), String.t(), [term()], keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defp send_pool_tx(network_opts, abi_sig, args, signer_opts) do
    with {:ok, pool_addr} <- Contracts.address(:pool, network_opts),
         {:ok, calldata_hex} <- ABI.encode_call(abi_sig, args) do
      Signer.send_transaction(pool_addr, Hex.decode!(calldata_hex), signer_opts)
    end
  end

  # Separates :network and :interest_rate_mode from opts; remainder passes to Signer.
  @spec split_write_opts(keyword()) :: {keyword(), atom(), keyword()}
  defp split_write_opts(opts) do
    {network_opts, rest} = Opts.split_network(opts)
    {rate_mode, signer_opts} = Keyword.pop(rest, :interest_rate_mode, :variable)
    {network_opts, rate_mode, signer_opts}
  end

  @doc false
  # Maps :variable → 2, :stable → 1. Returns error tuple for invalid values.
  @spec resolve_interest_rate_mode(term()) :: {:ok, pos_integer()} | {:error, {:invalid_interest_rate_mode, term()}}
  defp resolve_interest_rate_mode(:variable), do: {:ok, @variable_rate}
  defp resolve_interest_rate_mode(:stable), do: {:ok, @stable_rate}
  defp resolve_interest_rate_mode(other), do: {:error, {:invalid_interest_rate_mode, other}}
end
