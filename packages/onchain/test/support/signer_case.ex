defmodule Onchain.SignerCase do
  @moduledoc false

  # Reusable test helpers for transaction signing tests (tasks 12, 13, 14).
  # Provides credential loading from env vars and receipt polling.

  alias Cartouche.Signer.Curvy

  @poll_interval_ms 3_000
  @max_poll_attempts 20

  @doc false
  def signer_key! do
    System.get_env("ETH_SEPOLIA_PRIVATE_KEY") ||
      ExUnit.Assertions.flunk("""
      Missing Sepolia private key!

      Set this environment variable:
        export ETH_SEPOLIA_PRIVATE_KEY="0x your 64-char hex private key"

      Use a dedicated testnet wallet — never use mainnet keys for testing.
      """)
  end

  @doc false
  def signer_address! do
    key_binary = Onchain.Hex.decode!(signer_key!())
    {:ok, addr_binary} = Curvy.get_address(key_binary)
    Onchain.Address.checksum!(addr_binary)
  end

  @doc false
  def sepolia_rpc_url! do
    System.get_env("ETH_SEPOLIA_RPC_URL") ||
      ExUnit.Assertions.flunk("""
      Missing Sepolia RPC URL!

      Set this environment variable:
        export ETH_SEPOLIA_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY"

      Get a free key at: https://dashboard.alchemy.com
      """)
  end

  @doc false
  # Polls get_transaction_receipt until it returns a non-nil result or times out.
  def wait_for_receipt(tx_hash, opts \\ []) do
    rpc_url = Keyword.fetch!(opts, :rpc_url)
    interval = Keyword.get(opts, :interval_ms, @poll_interval_ms)
    max_attempts = Keyword.get(opts, :max_attempts, @max_poll_attempts)

    do_poll(tx_hash, rpc_url, interval, max_attempts, 0)
  end

  defp do_poll(_tx_hash, _rpc_url, _interval, max, attempt) when attempt >= max do
    {:error, :receipt_timeout}
  end

  defp do_poll(tx_hash, rpc_url, interval, max, attempt) do
    case Onchain.RPC.get_transaction_receipt(tx_hash, rpc_url: rpc_url) do
      {:ok, nil} ->
        Process.sleep(interval)
        do_poll(tx_hash, rpc_url, interval, max, attempt + 1)

      {:ok, receipt} ->
        {:ok, receipt}

      {:error, _} = error ->
        error
    end
  end
end
