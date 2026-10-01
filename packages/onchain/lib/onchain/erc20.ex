defmodule Onchain.ERC20 do
  @moduledoc """
  ERC-20 token operations.

  Read operations are thin wrappers around `Onchain.Contract.call/5`.
  Write operations delegate to `Onchain.Signer.send_transaction/3`.
  Returns raw integer values for balances — consumers use
  `Onchain.Decimal.to_decimal/2` with the result of `decimals/2` to normalize.

  ## Error Format

  Errors pass through from underlying modules:

  | Source | Error Shape |
  |--------|-------------|
  | `Onchain.Address.validate/1` | `{:error, {:invalid_address, input}}` |
  | `Onchain.Contract.call/5` | `{:error, {:encode_error, ...}}`, `{:error, {:rpc_error, ...}}`, `{:error, {:decode_error, ...}}` |
  | `Onchain.ABI.encode_hex_call/2` | `{:error, {:encode_error, ...}}` |
  | `Onchain.Signer.send_transaction/3` | `{:error, {:missing_option, ...}}`, `{:error, {:sign_error, ...}}`, etc. |

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `balance_of/3` | Token balance for a holder (raw integer) |
  | `balance_of!/3` | Same, raises on error |
  | `allowance/4` | Approved spending amount (raw integer) |
  | `allowance!/4` | Same, raises on error |
  | `decimals/2` | Token decimal places |
  | `decimals!/2` | Same, raises on error |
  | `symbol/2` | Token ticker symbol |
  | `symbol!/2` | Same, raises on error |
  | `approve/4` | Approve spender to transfer tokens (returns tx hash) |
  | `approve!/4` | Same, raises on error |
  | `transfer/4` | Transfer tokens to recipient (returns tx hash) |
  | `transfer!/4` | Same, raises on error |
  """

  use Descripex, namespace: "/erc20"

  alias Onchain.Address
  alias Onchain.Contract

  # --- balance_of ---

  alias Onchain.ERC.Helpers
  alias Onchain.Hex
  alias Onchain.Signer

  api(:balance_of, "Get the token balance of an address.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      holder: [kind: :value, description: "Address to check balance for"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Raw token balance (use decimals/2 + Onchain.Decimal.to_decimal/2 to normalize)",
      example: "1000000"
    }
  )

  # --- balance_of! ---

  @spec balance_of(String.t() | binary(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def balance_of(token, holder, opts \\ []), do: Helpers.balance_of(token, holder, opts)

  api(:balance_of!, "Get the token balance of an address. Raises on error.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      holder: [kind: :value, description: "Address to check balance for"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],

    # --- allowance ---

    returns: %{type: :non_neg_integer, description: "Raw token balance"}
  )

  @spec balance_of!(String.t() | binary(), String.t() | binary(), keyword()) :: non_neg_integer()
  def balance_of!(token, holder, opts \\ []), do: Helpers.unwrap!(balance_of(token, holder, opts), "balance_of")

  api(:allowance, "Get the amount an owner has approved a spender to transfer.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      owner: [kind: :value, description: "Token owner address"],
      spender: [kind: :value, description: "Approved spender address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Approved spending amount as raw integer",
      example: "0"
    }
  )

  @spec allowance(String.t() | binary(), String.t() | binary(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def allowance(token, owner, spender, opts \\ []) do
    with {:ok, owner_bin} <- Address.validate(owner),
         {:ok, spender_bin} <- Address.validate(spender),
         {:ok, [amount]} <-
           Contract.call(
             # --- allowance! ---
             token,
             "allowance(address,address)",
             [owner_bin, spender_bin],
             "(uint256)",
             opts
           ) do
      {:ok, amount}
    end
  end

  api(:allowance!, "Get the approved spending amount. Raises on error.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      owner: [kind: :value, description: "Token owner address"],
      spender: [kind: :value, description: "Approved spender address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :non_neg_integer, description: "Approved spending amount"}
  )

  # --- decimals ---

  @spec allowance!(String.t() | binary(), String.t() | binary(), String.t() | binary(), keyword()) ::
          non_neg_integer()
  def allowance!(token, owner, spender, opts \\ []) do
    case allowance(token, owner, spender, opts) do
      {:ok, amount} -> amount
      {:error, reason} -> raise "allowance failed: #{inspect(reason)}"
    end
  end

  api(:decimals, "Get the number of decimal places for a token.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Token decimal places (e.g. 6 for USDC, 18 for DAI)",
      example: "6"
    }
  )

  # --- decimals! ---

  @spec decimals(String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def decimals(token, opts \\ []) do
    with {:ok, [value]} <- Contract.call(token, "decimals()", [], "(uint8)", opts) do
      {:ok, value}
    end
  end

  api(:decimals!, "Get the number of decimal places for a token. Raises on error.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    # --- symbol ---
    returns: %{type: :non_neg_integer, description: "Token decimal places"}
  )

  @spec decimals!(String.t() | binary(), keyword()) :: non_neg_integer()
  def decimals!(token, opts \\ []) do
    case decimals(token, opts) do
      {:ok, value} -> value
      {:error, reason} -> raise "decimals failed: #{inspect(reason)}"
    end
  end

  api(:symbol, "Get the ticker symbol of a token.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Token symbol string",
      # --- symbol! ---
      example: ~s("USDC")
    }
  )

  @spec symbol(String.t() | binary(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def symbol(token, opts \\ []) do
    with {:ok, [value]} <- Contract.call(token, "symbol()", [], "(string)", opts) do
      {:ok, value}
    end
  end

  # --- total_supply ---

  api(:symbol!, "Get the ticker symbol of a token. Raises on error.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :string, description: "Token symbol string"}
  )

  @spec symbol!(String.t() | binary(), keyword()) :: String.t()
  def symbol!(token, opts \\ []), do: Helpers.unwrap!(symbol(token, opts), "symbol")

  api(:total_supply, "Get the total supply of a token.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      # --- total_supply! ---
      type: "{:ok, non_neg_integer()} | {:error, term()}",
      description: "Raw total supply (use decimals/2 + Onchain.Decimal.to_decimal/2 to normalize)",
      example: "1000000000000"
    }
  )

  @spec total_supply(String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def total_supply(token, opts \\ []) do
    with {:ok, [value]} <- Contract.call(token, "totalSupply()", [], "(uint256)", opts) do
      {:ok, value}
    end
  end

  api(:total_supply!, "Get the total supply of a token. Raises on error.",
    # --- approve ---
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :non_neg_integer, description: "Raw total supply"}
  )

  @spec total_supply!(String.t() | binary(), keyword()) :: non_neg_integer()
  def total_supply!(token, opts \\ []) do
    case total_supply(token, opts) do
      {:ok, value} -> value
      {:error, reason} -> raise "total_supply failed: #{inspect(reason)}"
    end
  end

  api(:approve, "Approve a spender to transfer tokens on your behalf.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      spender: [kind: :value, description: "Address to approve for spending"],
      amount: [kind: :value, description: "Amount to approve (raw integer, not decimal-adjusted)"],
      opts: [
        kind: :value,
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :gas_limit, :max_fee_per_gas, :max_priority_fee_per_gas"
      ]
    ],

    # --- approve! ---

    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Transaction hash hex string"
    }
  )

  @spec approve(String.t() | binary(), String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def approve(token, spender, amount, opts) do
    with {:ok, spender_bin} <- Address.validate(spender),
         {:ok, calldata_hex} <- Onchain.ABI.encode_hex_call("approve(address,uint256)", [spender_bin, amount]) do
      Signer.send_transaction(token, Hex.decode!(calldata_hex), opts)
    end
  end

  api(:approve!, "Approve a spender to transfer tokens on your behalf. Raises on error.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      spender: [kind: :value, description: "Address to approve for spending"],
      amount: [kind: :value, description: "Amount to approve (raw integer, not decimal-adjusted)"],
      opts: [
        # --- transfer ---
        kind: :value,
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :gas_limit, :max_fee_per_gas, :max_priority_fee_per_gas"
      ]
    ],
    returns: %{type: :string, description: "Transaction hash hex string"}
  )

  @spec approve!(String.t() | binary(), String.t() | binary(), non_neg_integer(), keyword()) ::
          String.t()
  def approve!(token, spender, amount, opts) do
    case approve(token, spender, amount, opts) do
      {:ok, tx_hash} -> tx_hash
      {:error, reason} -> raise "approve failed: #{inspect(reason)}"
    end
  end

  api(:transfer, "Transfer tokens to a recipient.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      to: [kind: :value, description: "Recipient address"],
      amount: [kind: :value, description: "Amount to transfer (raw integer, not decimal-adjusted)"],
      opts: [
        kind: :value,
        # --- transfer! ---
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :gas_limit, :max_fee_per_gas, :max_priority_fee_per_gas"
      ]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Transaction hash hex string"
    }
  )

  @spec transfer(String.t() | binary(), String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def transfer(token, to, amount, opts) do
    with {:ok, to_bin} <- Address.validate(to),
         {:ok, calldata_hex} <- Onchain.ABI.encode_hex_call("transfer(address,uint256)", [to_bin, amount]) do
      Signer.send_transaction(token, Hex.decode!(calldata_hex), opts)
    end
  end

  api(:transfer!, "Transfer tokens to a recipient. Raises on error.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      to: [kind: :value, description: "Recipient address"],
      amount: [kind: :value, description: "Amount to transfer (raw integer, not decimal-adjusted)"],
      opts: [
        kind: :value,
        description:
          "Required: :private_key, :nonce, :chain_id, :rpc_url. Optional: :gas_limit, :max_fee_per_gas, :max_priority_fee_per_gas"
      ]
    ],
    returns: %{type: :string, description: "Transaction hash hex string"}
  )

  @spec transfer!(String.t() | binary(), String.t() | binary(), non_neg_integer(), keyword()) ::
          String.t()
  def transfer!(token, to, amount, opts) do
    case transfer(token, to, amount, opts) do
      {:ok, tx_hash} -> tx_hash
      {:error, reason} -> raise "transfer failed: #{inspect(reason)}"
    end
  end

  @type call_opts() :: Keyword.t()
  @type exec_opts() :: Keyword.t()

  @errors []

  api(:errors, "Return the ERC-20 error signatures known to this wrapper.",
    returns: %{
      type: :abi_error_signatures,
      description: "List of ABI error signature strings to merge into RPC error parsing."
    }
  )

  @doc ~S"""
  Returns a list of known error codes (ABI signatures), which can be used
  when parsing error messages from contract calls.
  """
  @spec errors() :: [String.t()]
  def errors, do: @errors

  api(:exec_trx, "Execute ABI-encoded ERC-20 calldata as a signed transaction.",
    params: [
      token: [
        kind: :value,
        description: "ERC-20 token contract address or configured contract atom."
      ],
      call_data: [
        kind: :value,
        description: "ABI-encoded ERC-20 calldata bytes, such as `transfer(address,uint256)` calldata."
      ],
      exec_opts: [
        kind: :value,
        description:
          "Execution options forwarded to `Onchain.RPC.execute_trx/3`; `:errors` defaults to ERC-20 signatures when absent."
      ]
    ],
    returns: %{
      type: :rpc_result,
      description: "Result returned by `Onchain.RPC.execute_trx/3`, usually `{:ok, tx_hash}` or `{:error, reason}`."
    }
  )

  @doc ~S"""
  Executes a transaction against the given ERC-20 token, using the provided
  ABI-encoded `call_data`. The configured Cartouche signer signs and submits
  the transaction; `exec_opts` is forwarded to `Onchain.RPC.execute_trx/3`
  with this module's known error signatures merged in.
  """
  @spec exec_trx(Onchain.Configuration.contract(), binary(), exec_opts()) ::
          {:ok, binary()} | {:error, term()}
  def exec_trx(token, call_data, exec_opts) do
    Onchain.RPC.execute_trx(
      Onchain.Configuration.get_contract_address(token),
      call_data,
      Keyword.put_new(exec_opts, :errors, errors())
    )
  end

  api(:call_trx, "Run ABI-encoded ERC-20 calldata as a read-only `eth_call`.",
    params: [
      token: [
        kind: :value,
        description: "ERC-20 token contract address or configured contract atom."
      ],
      call_data: [
        kind: :value,
        description: "ABI-encoded ERC-20 calldata bytes for the read-only call."
      ],
      call_opts: [
        kind: :value,
        description:
          "Call options forwarded to `Onchain.RPC.call_trx/2`; `:errors` defaults to ERC-20 signatures when absent."
      ]
    ],
    returns: %{
      type: :rpc_result,
      description: "Result returned by `Onchain.RPC.call_trx/2`, decoded according to `call_opts[:decode]`."
    }
  )

  @doc ~S"""
  Performs an `eth_call` against the given ERC-20 token with the provided
  ABI-encoded `call_data` and zero value/gas. Returns the call's return data
  without sending a transaction. `call_opts` is forwarded to
  `Onchain.RPC.call_trx/2` with this module's known error signatures
  merged in.
  """
  @spec call_trx(Onchain.Configuration.contract(), binary(), call_opts()) :: term()
  def call_trx(token, call_data, call_opts) do
    token
    |> Onchain.Configuration.get_contract_address()
    |> Onchain.Transaction.build_trx(0, call_data, 0, 0, 0)
    |> Onchain.RPC.call_trx(Keyword.put_new(call_opts, :errors, errors()))
  end

  defmodule CallData do
    @moduledoc """
    Module to encode `calldata` for given adaptor operations.
    """

    use Descripex, namespace: "/ethereum/erc20/call_data"

    api(:balance_of, "Encode ERC-20 `balanceOf(address)` calldata.",
      params: [
        address: [
          kind: :value,
          description: "20-byte Ethereum owner address whose token balance will be queried."
        ]
      ],
      returns: %{
        type: :abi_calldata,
        description: "ABI-encoded calldata bytes for `balanceOf(address)`."
      }
    )

    @doc ~S"""
    Encodes the call data for a `balanceOf` operation.

    ## Examples

        iex> Onchain.ERC20.CallData.balance_of(<<0xDD>>) |> Onchain.Hex.encode_hex()
        "0x"
    """
    @spec balance_of(Onchain.Configuration.address()) :: binary()
    def balance_of(address) do
      Onchain.ABI.encode("balanceOf(address)", [address])
    end

    api(:transfer, "Encode ERC-20 `transfer(address,uint256)` calldata.",
      params: [
        destination: [
          kind: :value,
          description: "20-byte Ethereum recipient address."
        ],
        amount_wei: [
          kind: :value,
          description: "Token base-unit amount to transfer; already scaled by the token's decimals."
        ]
      ],
      returns: %{
        type: :abi_calldata,
        description: "ABI-encoded calldata bytes for `transfer(address,uint256)`."
      }
    )

    @doc ~S"""
    Encodes the call data for a `transfer` operation.

    ## Examples

        iex> Onchain.ERC20.CallData.transfer(<<0xDD>>, 100_000)
        ...> |> Onchain.Hex.encode_hex()
        "0x8035f0ce"
    """
    @spec transfer(Onchain.Configuration.address(), non_neg_integer()) :: binary()
    def transfer(destination, amount_wei) do
      Onchain.ABI.encode("transfer(address,uint256)", [destination, amount_wei])
    end
  end

  defmodule Call do
    @moduledoc """
    Module to call operations and receive return value, without sending a transaction.
    """

    use Descripex, namespace: "/ethereum/erc20/call"

    api(:balance_of, "Call ERC-20 `balanceOf(address)` and decode the token base-unit balance.",
      params: [
        token: [
          kind: :value,
          description: "ERC-20 token contract address or configured contract atom."
        ],
        address: [
          kind: :value,
          description: "20-byte Ethereum owner address whose token balance will be queried."
        ],
        call_opts: [
          kind: :value,
          default: [],
          description: "RPC call options; this helper forces `decode: :hex_unsigned` for the returned balance."
        ]
      ],
      returns: %{
        type: :ok_error_tuple,
        description: "`{:ok, amount_wei}` with the token base-unit balance, or `{:error, reason}`."
      }
    )

    @doc ~S"""
    Calls the `balanceOf` operation, returning the result of the Ethereum function call.

    ## Examples

        iex> Onchain.ERC20.Call.balance_of(<<0xCC>>, <<0xDD>>)
        {:ok, <<>>}
    """
    @spec balance_of(Onchain.Configuration.contract(), Onchain.Configuration.address(), Onchain.ERC20.call_opts()) ::
            {:ok, number()} | {:error, term()}
    def balance_of(token, address, call_opts \\ []) do
      call_opts = Keyword.put(call_opts, :decode, :hex_unsigned)
      Onchain.ERC20.call_trx(token, CallData.balance_of(address), call_opts)
    end

    api(:transfer, "Call ERC-20 `transfer(address,uint256)` without sending a transaction.",
      params: [
        token: [
          kind: :value,
          description: "ERC-20 token contract address or configured contract atom."
        ],
        destination: [
          kind: :value,
          description: "20-byte Ethereum recipient address."
        ],
        amount_wei: [
          kind: :value,
          description: "Token base-unit amount to transfer; already scaled by the token's decimals."
        ],
        call_opts: [
          kind: :value,
          default: [],
          description: "RPC call options; this helper forces `decode: :hex` for the returned bytes."
        ]
      ],
      returns: %{
        type: :ok_error_tuple,
        description: "`{:ok, raw_return_bytes}` from the simulated transfer call, or `{:error, reason}`."
      }
    )

    @doc ~S"""
    Calls the `transfer` operation, returning the result of the Ethereum function call.

    ## Examples

        iex> Onchain.ERC20.Call.transfer(<<0xCC>>, <<0xDD>>, 100_000)
        {:ok, <<>>}
    """
    @spec transfer(
            Onchain.Configuration.contract(),
            Onchain.Configuration.address(),
            non_neg_integer(),
            Onchain.ERC20.call_opts()
          ) :: {:ok, binary()} | {:error, term()}
    def transfer(token, destination, amount_wei, call_opts \\ []) do
      call_opts = Keyword.put(call_opts, :decode, :hex)
      Onchain.ERC20.call_trx(token, CallData.transfer(destination, amount_wei), call_opts)
    end
  end
end
