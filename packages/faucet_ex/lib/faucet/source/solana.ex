defmodule Faucet.Source.Solana do
  @moduledoc """
  Solana devnet / testnet — `requestAirdrop` JSON-RPC.

  Public airdrops are rate-limited and capped per request (devnet: 5 SOL per
  request, with a rolling per-address limit). Balance is read via
  `getBalance` at the configured commitment.

  ## Options

    * `:rpc_url` — default `https://api.devnet.solana.com`
    * `:lamports` — airdrop size per request, default `1_000_000_000` (1 SOL);
      capped to the `:deficit` the loop supplies when that is smaller
    * `:commitment` — `"confirmed"` (default) or `"finalized"`
    * `:req_options` — passed to Req
  """

  @behaviour Faucet.Source

  alias Faucet.JSONRPC

  @default_rpc_url "https://api.devnet.solana.com"
  @default_lamports 1_000_000_000

  @impl true
  def unit, do: "lamports"

  @impl true
  def balance(pubkey, opts) do
    case JSONRPC.call(rpc_url(opts), "getBalance", [pubkey, %{"commitment" => commitment(opts)}], opts) do
      {:ok, %{"value" => lamports}} when is_integer(lamports) -> {:ok, lamports}
      {:ok, other} -> {:error, {:unexpected_result, other}}
      {:error, _} = error -> error
    end
  end

  @impl true
  def fund(pubkey, opts) do
    lamports = airdrop_size(opts)
    params = [pubkey, lamports, %{"commitment" => commitment(opts)}]

    case JSONRPC.call(rpc_url(opts), "requestAirdrop", params, opts) do
      {:ok, signature} when is_binary(signature) -> {:ok, [signature]}
      {:ok, other} -> {:error, {:unexpected_result, other}}
      {:error, _} = error -> error
    end
  end

  defp airdrop_size(opts) do
    size = Keyword.get(opts, :lamports, @default_lamports)

    case Keyword.get(opts, :deficit) do
      deficit when is_integer(deficit) and deficit > 0 -> min(size, deficit)
      _ -> size
    end
  end

  defp rpc_url(opts), do: Keyword.get(opts, :rpc_url, @default_rpc_url)
  defp commitment(opts), do: Keyword.get(opts, :commitment, "confirmed")
end
