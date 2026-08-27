defmodule Onchain.Wallet do
  @moduledoc """
  Thin convenience layer for wallet-level queries.

  ## Does

  - Classify addresses as EOA or contract (`classify/2`)
  - Fetch native ETH balance (`balance/2`)

  ## Does Not

  - Track token balances (see `Onchain.ERC20`)
  - Manage keys or signing (see `Onchain.Signer`)
  - Parse transactions or receipts (see `Onchain.RPC`)

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `classify/2` | Determine if address is `:eoa` or `:contract` |
  | `classify!/2` | Same, raises on error |
  | `balance/2` | Native ETH balance in wei |
  | `balance!/2` | Same, raises on error |
  """

  use Descripex, namespace: "/wallet"

  alias Onchain.RPC

  # --- classify ---

  api(:classify, "Classify an address as EOA or contract.",
    params: [
      address: [kind: :value, description: "Account address as 0x hex string or 20-byte binary"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, :eoa | :contract} | {:error, term}",
      description: ":eoa if no bytecode, :contract if bytecode exists"
    }
  )

  @spec classify(String.t() | binary(), keyword()) :: {:ok, :eoa | :contract} | {:error, term()}
  def classify(address, opts \\ []) do
    case RPC.eth_get_code(address, opts) do
      {:ok, "0x"} -> {:ok, :eoa}
      {:ok, _bytecode} -> {:ok, :contract}
      {:error, _} = error -> error
    end
  end

  # --- classify! ---

  api(:classify!, "Classify an address as EOA or contract. Raises on error.",
    params: [
      address: [kind: :value, description: "Account address as 0x hex string or 20-byte binary"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: ":eoa | :contract", description: "Address type atom"}
  )

  @spec classify!(String.t() | binary(), keyword()) :: :eoa | :contract
  def classify!(address, opts \\ []) do
    case classify(address, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "classify failed: #{inspect(reason)}"
    end
  end

  # --- balance ---

  api(:balance, "Get the native ETH balance of an address in wei.",
    params: [
      address: [kind: :value, description: "Account address as 0x hex string or 20-byte binary"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{
      type: "{:ok, non_neg_integer} | {:error, term}",
      description: "Balance in wei"
    }
  )

  @spec balance(String.t() | binary(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def balance(address, opts \\ []), do: RPC.get_balance(address, opts)

  # --- balance! ---

  api(:balance!, "Get the native ETH balance of an address in wei. Raises on error.",
    params: [
      address: [kind: :value, description: "Account address as 0x hex string or 20-byte binary"],
      opts: [kind: :value, default: [], description: "Options: :rpc_url, :timeout, :block"]
    ],
    returns: %{type: :non_neg_integer, description: "Balance in wei"}
  )

  @spec balance!(String.t() | binary(), keyword()) :: non_neg_integer()
  def balance!(address, opts \\ []) do
    case balance(address, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "balance failed: #{inspect(reason)}"
    end
  end
end
