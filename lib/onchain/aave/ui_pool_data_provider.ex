defmodule Onchain.Aave.UiPoolDataProvider do
  @moduledoc """
  High-level Aave V3 UiPoolDataProvider read operations.

  Composes `Address`, `Contracts`, `ABI`, `RPC`, and type structs into single-call
  functions that return typed structs. Consumers don't need to manually encode
  ABI calls, make RPC requests, and decode responses.

  ## Contract

  Calls the UiPoolDataProvider contract (registered as `:ui_pool_data_provider`
  in `Contracts`), passing the PoolAddressesProvider address (`:pool_addresses_provider`)
  as a parameter.

  ## Error Format

  Errors pass through from the underlying module that failed:

  | Source | Error Shape |
  |--------|-------------|
  | `Onchain.Aave.Contracts.address/2` | `{:error, {:unsupported_network, network}}` |
  | `Onchain.ABI.encode_call/2` | `{:error, {:encode_error, reason}}` |
  | `Onchain.RPC.eth_call/3` | `{:error, {:rpc_error, map}}` |
  | `Onchain.ABI.decode_response/2` | `{:error, {:decode_error, reason}}` |
  | `Onchain.Address.validate/1` | `{:error, {:invalid_address, input}}` |

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `get_reserves_list/1` | List of reserve token addresses |
  | `get_reserves_list!/1` | Same, raises on error |
  | `get_reserves_data/1` | Per-reserve data + base currency info |
  | `get_reserves_data!/1` | Same, raises on error |
  | `get_user_reserves_data/2` | Per-user reserve balances |
  | `get_user_reserves_data!/2` | Same, raises on error |
  """

  use Descripex, namespace: "/aave/ui-pool-data-provider"

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.Opts
  alias Onchain.Aave.Types.AggregatedReserveData
  alias Onchain.Aave.Types.BaseCurrencyInfo
  alias Onchain.Aave.Types.UserReserveData
  alias Onchain.ABI
  alias Onchain.Address
  alias Onchain.RPC

  # TODO: ABI.decode_response/2 has upstream spec mismatch (success typing is no_return()
  # due to Signet.Hex spec issues). Remove these suppressions once upstream is fixed.
  # Same root cause as @dialyzer annotations in pool.ex and abi.ex.
  @dialyzer {:no_match,
             [
               get_reserves_list: 1,
               get_reserves_data: 1,
               get_user_reserves_data: 2,
               get_reserves_list!: 1,
               get_reserves_data!: 1,
               get_user_reserves_data!: 2
             ]}
  @dialyzer {:no_return,
             [
               get_reserves_list!: 0,
               get_reserves_list!: 1,
               get_reserves_data!: 0,
               get_reserves_data!: 1,
               get_user_reserves_data!: 1,
               get_user_reserves_data!: 2
             ]}
  @dialyzer {:no_contracts,
             [
               get_reserves_list!: 0,
               get_reserves_list!: 1,
               get_reserves_data!: 0,
               get_reserves_data!: 1,
               get_user_reserves_data!: 1,
               get_user_reserves_data!: 2
             ]}

  @reserves_list_response "(address[])"

  @reserves_data_response "((" <>
                            "address,string,string,uint256," <>
                            "uint256,uint256,uint256,uint256," <>
                            "bool,bool,bool,bool," <>
                            "uint128,uint128,uint128,uint128," <>
                            "uint40," <>
                            "address,address,address," <>
                            "uint256,uint256,uint256," <>
                            "address," <>
                            "uint256,uint256,uint256,uint256," <>
                            "bool,bool," <>
                            "uint128,uint128," <>
                            "bool," <>
                            "uint256,uint256,uint256,uint256," <>
                            "bool," <>
                            "uint128,uint128" <>
                            ")[],(uint256,int256,int256,uint8))"

  @user_reserves_data_response "((address,uint256,bool,uint256)[],uint8)"

  # --- get_reserves_list ---

  api(:get_reserves_list, "Fetch the list of reserve token addresses from the Aave V3 pool.",
    params: [
      opts: [
        kind: :value,
        default: [],
        description: "Options: :network (default :ethereum), :rpc_url, :timeout, :block"
      ]
    ],
    returns: %{
      type: "{:ok, [String.t()]} | {:error, term()}",
      description: "List of checksummed reserve token addresses"
    }
  )

  @spec get_reserves_list(keyword()) :: {:ok, [String.t()]} | {:error, term()}
  def get_reserves_list(opts \\ []) do
    {network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, ui_addr} <- Contracts.address(:ui_pool_data_provider, network_opts),
         {:ok, provider_bin} <- provider_address(network_opts),
         {:ok, calldata} <- ABI.encode_call("getReservesList(address)", [provider_bin]),
         {:ok, hex_result} <- RPC.eth_call(ui_addr, calldata, rpc_opts),
         {:ok, [addresses]} <- ABI.decode_response(@reserves_list_response, hex_result) do
      {:ok, Enum.map(addresses, &Address.checksum!/1)}
    end
  end

  # --- get_reserves_list! ---

  api(:get_reserves_list!, "Fetch the list of reserve token addresses. Raises on error.",
    params: [
      opts: [
        kind: :value,
        default: [],
        description: "Options: :network (default :ethereum), :rpc_url, :timeout, :block"
      ]
    ],
    returns: %{type: "[String.t()]", description: "List of checksummed reserve token addresses"}
  )

  @spec get_reserves_list!(keyword()) :: [String.t()]
  def get_reserves_list!(opts \\ []) do
    case get_reserves_list(opts) do
      {:ok, addresses} -> addresses
      {:error, reason} -> raise "get_reserves_list failed: #{inspect(reason)}"
    end
  end

  # --- get_reserves_data ---

  api(:get_reserves_data, "Fetch per-reserve aggregated data and base currency info.",
    params: [
      opts: [
        kind: :value,
        default: [],
        description: "Options: :network (default :ethereum), :rpc_url, :timeout, :block"
      ]
    ],
    returns: %{
      type: "{:ok, {[AggregatedReserveData.t()], BaseCurrencyInfo.t()}} | {:error, term()}",
      description: "Tuple of reserve data list and base currency info"
    }
  )

  @spec get_reserves_data(keyword()) ::
          {:ok, {[AggregatedReserveData.t()], BaseCurrencyInfo.t()}} | {:error, term()}
  def get_reserves_data(opts \\ []) do
    {network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, ui_addr} <- Contracts.address(:ui_pool_data_provider, network_opts),
         {:ok, provider_bin} <- provider_address(network_opts),
         {:ok, calldata} <- ABI.encode_call("getReservesData(address)", [provider_bin]),
         {:ok, hex_result} <- RPC.eth_call(ui_addr, calldata, rpc_opts),
         {:ok, [reserves_raw, base_raw]} <-
           ABI.decode_response(@reserves_data_response, hex_result) do
      reserves = Enum.map(reserves_raw, &AggregatedReserveData.from_raw/1)
      base = BaseCurrencyInfo.from_raw(base_raw)
      {:ok, {reserves, base}}
    end
  end

  # --- get_reserves_data! ---

  api(:get_reserves_data!, "Fetch per-reserve aggregated data and base currency info. Raises on error.",
    params: [
      opts: [
        kind: :value,
        default: [],
        description: "Options: :network (default :ethereum), :rpc_url, :timeout, :block"
      ]
    ],
    returns: %{
      type: "{[AggregatedReserveData.t()], BaseCurrencyInfo.t()}",
      description: "Tuple of reserve data list and base currency info"
    }
  )

  @spec get_reserves_data!(keyword()) :: {[AggregatedReserveData.t()], BaseCurrencyInfo.t()}
  def get_reserves_data!(opts \\ []) do
    case get_reserves_data(opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "get_reserves_data failed: #{inspect(reason)}"
    end
  end

  # --- get_user_reserves_data ---

  api(:get_user_reserves_data, "Fetch per-user reserve balances and e-mode category.",
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
      type: "{:ok, {[UserReserveData.t()], non_neg_integer()}} | {:error, term()}",
      description: "Tuple of user reserve data list and e-mode category ID"
    }
  )

  @spec get_user_reserves_data(String.t() | binary(), keyword()) ::
          {:ok, {[UserReserveData.t()], non_neg_integer()}} | {:error, term()}
  def get_user_reserves_data(user_address, opts \\ []) do
    {network_opts, rpc_opts} = Opts.split_network(opts)

    with {:ok, user_bin} <- Address.validate(user_address),
         {:ok, ui_addr} <- Contracts.address(:ui_pool_data_provider, network_opts),
         {:ok, provider_bin} <- provider_address(network_opts),
         {:ok, calldata} <-
           ABI.encode_call("getUserReservesData(address,address)", [provider_bin, user_bin]),
         {:ok, hex_result} <- RPC.eth_call(ui_addr, calldata, rpc_opts),
         {:ok, [reserves_raw, e_mode_id]} <-
           ABI.decode_response(@user_reserves_data_response, hex_result) do
      reserves = Enum.map(reserves_raw, &UserReserveData.from_raw/1)
      {:ok, {reserves, e_mode_id}}
    end
  end

  # --- get_user_reserves_data! ---

  api(:get_user_reserves_data!, "Fetch per-user reserve balances and e-mode category. Raises on error.",
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
      type: "{[UserReserveData.t()], non_neg_integer()}",
      description: "Tuple of user reserve data list and e-mode category ID"
    }
  )

  @spec get_user_reserves_data!(String.t() | binary(), keyword()) ::
          {[UserReserveData.t()], non_neg_integer()}
  def get_user_reserves_data!(user_address, opts \\ []) do
    case get_user_reserves_data(user_address, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "get_user_reserves_data failed: #{inspect(reason)}"
    end
  end

  # --- Private helpers ---

  @doc false
  # Resolves the PoolAddressesProvider binary address for ABI encoding.
  @spec provider_address(keyword()) :: {:ok, binary()} | {:error, term()}
  defp provider_address(network_opts) do
    with {:ok, addr_hex} <- Contracts.address(:pool_addresses_provider, network_opts) do
      Address.validate(addr_hex)
    end
  end
end
