defmodule Faucet.Source.Tempo do
  @moduledoc """
  Tempo Moderato testnet — the non-standard `tempo_fundAddress` JSON-RPC.

  One call funds native gas **and** pathUSD. The balance this source reports
  is the fee token's (`pathUSD` by default): gas can land first, and the fee
  token is what callers actually need to pay for transactions. Set
  `asset: :native` to track gas instead.

  Only Moderato (chain `42_431`) exposes the RPC; mainnet does not.

  ## Options

    * `:rpc_url` — default `TEMPO_RPC_URL` env var, else `https://rpc.moderato.tempo.xyz`
    * `:fee_token` — TIP-20 token to poll, default Moderato pathUSD
    * `:asset` — `:fee_token` (default) or `:native`
    * `:req_options` — passed to Req
  """

  @behaviour Faucet.Source

  alias Faucet.EVM
  alias Faucet.JSONRPC

  @default_rpc_url "https://rpc.moderato.tempo.xyz"
  @default_fee_token "0x20c0000000000000000000000000000000000000"

  @doc "RPC URL used by default — `TEMPO_RPC_URL` if set, otherwise Moderato's public endpoint."
  @spec rpc_url() :: String.t()
  def rpc_url, do: System.get_env("TEMPO_RPC_URL") || @default_rpc_url

  @impl true
  def unit, do: "token units"

  @impl true
  def balance(address, opts) do
    opts = resolve(opts)

    case Keyword.get(opts, :asset, :fee_token) do
      :native -> EVM.native_balance(address, opts)
      :fee_token -> EVM.erc20_balance(Keyword.fetch!(opts, :fee_token), address, opts)
      other -> {:error, {:invalid_option, :asset, other}}
    end
  end

  @impl true
  def fund(address, opts) do
    opts = resolve(opts)

    case JSONRPC.call(Keyword.fetch!(opts, :rpc_url), "tempo_fundAddress", [address], opts) do
      {:ok, hashes} when is_list(hashes) -> {:ok, hashes}
      {:ok, other} -> {:error, {:unexpected_result, other}}
      {:error, _} = error -> error
    end
  end

  defp resolve(opts) do
    opts
    |> Keyword.put_new_lazy(:rpc_url, &rpc_url/0)
    |> Keyword.put_new(:fee_token, @default_fee_token)
  end
end
