defmodule Faucet.EVM do
  @moduledoc """
  EVM building blocks the EVM-flavoured sources share: native and ERC-20
  balance reads, receipt polling, and (when `onchain` is present) fresh
  keypairs.

  Only plain JSON-RPC is used here. `fresh_funded_wallet/3` is the one function
  that needs the optional `onchain` dependency, for secp256k1 address derivation.
  """

  use Descripex, namespace: "/faucet/evm"

  alias Faucet.JSONRPC
  alias Faucet.Wait

  # ERC-20 balanceOf(address) selector — keccak256("balanceOf(address)")[0..4].
  @balance_of_selector "70a08231"

  @typedoc "Fresh EVM wallet: raw 32-byte key, checksummed hex address, 20-byte address."
  @type wallet :: %{private_key: binary(), address_hex: String.t(), address_bin: binary()}

  api(:native_balance, "Read the native (gas) balance via eth_getBalance at `latest`.",
    params: [
      address: [kind: :value, description: "0x-prefixed hex address"],
      opts: [kind: :value, description: "Required `:rpc_url`; optional `:req_options`"]
    ],
    returns: %{type: "{:ok, wei} | {:error, term}", description: "Balance in wei"}
  )

  @spec native_balance(String.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def native_balance(address, opts) do
    with {:ok, hex} <- JSONRPC.call(rpc_url!(opts), "eth_getBalance", [address, "latest"], opts) do
      JSONRPC.quantity(hex)
    end
  end

  api(:erc20_balance, "Read an ERC-20 `balanceOf(address)` via eth_call at `latest`.",
    params: [
      token: [kind: :value, description: "0x-prefixed token contract address"],
      address: [kind: :value, description: "0x-prefixed holder address"],
      opts: [kind: :value, description: "Required `:rpc_url`; optional `:req_options`"]
    ],
    returns: %{type: "{:ok, units} | {:error, term}", description: "Balance in the token's base units"}
  )

  @spec erc20_balance(String.t(), String.t(), keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def erc20_balance(token, address, opts) do
    with {:ok, data} <- balance_of_calldata(address),
         {:ok, hex} <- JSONRPC.call(rpc_url!(opts), "eth_call", [%{"to" => token, "data" => data}, "latest"], opts) do
      JSONRPC.quantity(hex)
    end
  end

  api(:balance_of_calldata, "ABI-encode `balanceOf(address)` for `address` as 0x hex.",
    params: [address: [kind: :value, description: "0x-prefixed hex address (40 hex chars)"]],
    returns: %{
      type: "{:ok, String.t} | {:error, {:invalid_address, term}}",
      description: "0x + 4-byte selector + padded address"
    }
  )

  @spec balance_of_calldata(String.t()) :: {:ok, String.t()} | {:error, {:invalid_address, term()}}
  def balance_of_calldata("0x" <> hex = address) when byte_size(hex) == 40 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, _} -> {:ok, "0x" <> @balance_of_selector <> String.duplicate("0", 24) <> String.downcase(hex)}
      :error -> {:error, {:invalid_address, address}}
    end
  end

  def balance_of_calldata(other), do: {:error, {:invalid_address, other}}

  api(:wait_receipt, "Poll eth_getTransactionReceipt until the transaction succeeds, reverts, or the deadline passes.",
    params: [
      tx_hash: [kind: :value, description: "0x-prefixed transaction hash"],
      opts: [kind: :value, description: "Required `:rpc_url`; `:timeout_ms`, `:poll_interval_ms`, `:req_options`"]
    ],
    returns: %{
      type: ":ok | {:error, {:reverted, receipt} | :timeout | term}",
      description: "`:ok` on status 0x1; the receipt on revert"
    }
  )

  @spec wait_receipt(String.t(), keyword()) :: :ok | {:error, term()}
  def wait_receipt(tx_hash, opts) do
    url = rpc_url!(opts)

    probe = fn ->
      case JSONRPC.call(url, "eth_getTransactionReceipt", [tx_hash], opts) do
        {:ok, nil} -> :retry
        {:ok, %{"status" => "0x1"}} -> {:done, :ok}
        {:ok, receipt} -> {:error, {:reverted, receipt}}
        {:error, reason} -> {:error, reason}
      end
    end

    with {:ok, :ok} <- Wait.until(probe, opts), do: :ok
  end

  api(:wait_receipts, "Poll every receipt in turn; stop at the first revert or timeout.",
    params: [
      tx_hashes: [kind: :value, description: "List of 0x-prefixed transaction hashes"],
      opts: [kind: :value, description: "As `wait_receipt/2`"]
    ],
    returns: %{type: ":ok | {:error, term}", description: "`:ok` once every receipt reports status 0x1"}
  )

  @spec wait_receipts([String.t()], keyword()) :: :ok | {:error, term()}
  def wait_receipts(tx_hashes, opts) when is_list(tx_hashes) do
    Enum.reduce_while(tx_hashes, :ok, fn hash, :ok ->
      case wait_receipt(hash, opts) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  api(:fresh_funded_wallet, "Generate a random keypair and fund it to `minimum` through `source`.",
    params: [
      source: [kind: :value, description: "A `Faucet.Source` module for an EVM asset"],
      minimum: [kind: :value, description: "Target balance in the source's base unit"],
      opts: [kind: :value, default: [], description: "Passed through to `Faucet.ensure_min_balance/4`"]
    ],
    returns: %{
      type: "{:ok, wallet} | {:error, :onchain_not_available | term}",
      description: "Wallet map with `:private_key`, `:address_hex`, `:address_bin`; requires the optional `onchain` dep"
    }
  )

  @spec fresh_funded_wallet(module(), non_neg_integer(), keyword()) :: {:ok, wallet()} | {:error, term()}
  def fresh_funded_wallet(source, minimum, opts \\ []) do
    with {:ok, wallet} <- fresh_wallet(),
         {:ok, _balance} <- Faucet.ensure_min_balance(source, wallet.address_hex, minimum, opts) do
      {:ok, wallet}
    end
  end

  api(:fresh_wallet, "Generate a random secp256k1 keypair (needs the optional `onchain` dep).",
    params: [],
    returns: %{type: "{:ok, wallet} | {:error, :onchain_not_available}", description: "Unfunded wallet map"}
  )

  @spec fresh_wallet() :: {:ok, wallet()} | {:error, :onchain_not_available}
  def fresh_wallet do
    if Code.ensure_loaded?(Onchain.Signer) do
      priv = :crypto.strong_rand_bytes(32)
      {:ok, address_hex} = Onchain.Signer.address_from_key(priv)

      {:ok,
       %{
         private_key: priv,
         address_hex: address_hex,
         address_bin: Base.decode16!(String.slice(address_hex, 2..-1//1), case: :mixed)
       }}
    else
      {:error, :onchain_not_available}
    end
  end

  @doc false
  @spec rpc_url!(keyword()) :: String.t()
  def rpc_url!(opts), do: Keyword.fetch!(opts, :rpc_url)
end
