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
  | `Onchain.ABI.encode_call/2` | `{:error, {:encode_error, ...}}` |
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

  alias Onchain.ABI
  alias Onchain.Address
  alias Onchain.Contract
  alias Onchain.ERC.Helpers
  alias Onchain.Hex
  alias Onchain.Signer

  # --- balance_of ---

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

  @spec balance_of(String.t() | binary(), String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def balance_of(token, holder, opts \\ []), do: Helpers.balance_of(token, holder, opts)

  # --- balance_of! ---

  api(:balance_of!, "Get the token balance of an address. Raises on error.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      holder: [kind: :value, description: "Address to check balance for"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :non_neg_integer, description: "Raw token balance"}
  )

  @spec balance_of!(String.t() | binary(), String.t() | binary(), keyword()) :: non_neg_integer()
  def balance_of!(token, holder, opts \\ []), do: Helpers.unwrap!(balance_of(token, holder, opts), "balance_of")

  # --- allowance ---

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
             token,
             "allowance(address,address)",
             [owner_bin, spender_bin],
             "(uint256)",
             opts
           ) do
      {:ok, amount}
    end
  end

  # --- allowance! ---

  api(:allowance!, "Get the approved spending amount. Raises on error.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      owner: [kind: :value, description: "Token owner address"],
      spender: [kind: :value, description: "Approved spender address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :non_neg_integer, description: "Approved spending amount"}
  )

  @spec allowance!(String.t() | binary(), String.t() | binary(), String.t() | binary(), keyword()) ::
          non_neg_integer()
  def allowance!(token, owner, spender, opts \\ []) do
    case allowance(token, owner, spender, opts) do
      {:ok, amount} -> amount
      {:error, reason} -> raise "allowance failed: #{inspect(reason)}"
    end
  end

  # --- decimals ---

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

  @spec decimals(String.t() | binary(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def decimals(token, opts \\ []) do
    with {:ok, [value]} <- Contract.call(token, "decimals()", [], "(uint8)", opts) do
      {:ok, value}
    end
  end

  # --- decimals! ---

  api(:decimals!, "Get the number of decimal places for a token. Raises on error.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :non_neg_integer, description: "Token decimal places"}
  )

  @spec decimals!(String.t() | binary(), keyword()) :: non_neg_integer()
  def decimals!(token, opts \\ []) do
    case decimals(token, opts) do
      {:ok, value} -> value
      {:error, reason} -> raise "decimals failed: #{inspect(reason)}"
    end
  end

  # --- symbol ---

  api(:symbol, "Get the ticker symbol of a token.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Token symbol string",
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

  # --- symbol! ---

  api(:symbol!, "Get the ticker symbol of a token. Raises on error.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :string, description: "Token symbol string"}
  )

  @spec symbol!(String.t() | binary(), keyword()) :: String.t()
  def symbol!(token, opts \\ []), do: Helpers.unwrap!(symbol(token, opts), "symbol")

  # --- total_supply ---

  api(:total_supply, "Get the total supply of a token.",
    params: [
      token: [kind: :value, description: "ERC-20 token contract address"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
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

  # --- total_supply! ---

  api(:total_supply!, "Get the total supply of a token. Raises on error.",
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

  # --- approve ---

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
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Transaction hash hex string"
    }
  )

  @spec approve(String.t() | binary(), String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def approve(token, spender, amount, opts) do
    with {:ok, spender_bin} <- Address.validate(spender),
         {:ok, calldata_hex} <- ABI.encode_call("approve(address,uint256)", [spender_bin, amount]) do
      Signer.send_transaction(token, Hex.decode!(calldata_hex), opts)
    end
  end

  # --- approve! ---

  api(:approve!, "Approve a spender to transfer tokens on your behalf. Raises on error.",
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

  # --- transfer ---

  api(:transfer, "Transfer tokens to a recipient.",
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
    returns: %{
      type: "{:ok, String.t()} | {:error, term()}",
      description: "Transaction hash hex string"
    }
  )

  @spec transfer(String.t() | binary(), String.t() | binary(), non_neg_integer(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def transfer(token, to, amount, opts) do
    with {:ok, to_bin} <- Address.validate(to),
         {:ok, calldata_hex} <- ABI.encode_call("transfer(address,uint256)", [to_bin, amount]) do
      Signer.send_transaction(token, Hex.decode!(calldata_hex), opts)
    end
  end

  # --- transfer! ---

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
end
