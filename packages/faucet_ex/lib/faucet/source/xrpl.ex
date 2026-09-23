defmodule Faucet.Source.XRPL do
  @moduledoc """
  XRP Ledger testnet (altnet) — the public faucet's HTTP API.

  `POST /accounts` with a `destination` funds an existing address; the faucet
  decides the amount. Balance is read with `account_info` against the
  validated ledger; an account the ledger has not seen yet (`actNotFound`)
  reads as zero, which is what makes a fresh address fundable.

  ## Options

    * `:faucet_url` — default `https://faucet.altnet.rippletest.net/accounts`
    * `:rpc_url` — default `https://s.altnet.rippletest.net:51234`
    * `:req_options` — passed to Req
  """

  @behaviour Faucet.Source

  @default_faucet_url "https://faucet.altnet.rippletest.net/accounts"
  @default_rpc_url "https://s.altnet.rippletest.net:51234"
  @request_timeout_ms 60_000

  @impl true
  def unit, do: "drops"

  @impl true
  def balance(address, opts) do
    body = %{"method" => "account_info", "params" => [%{"account" => address, "ledger_index" => "validated"}]}

    [
      url: Keyword.get(opts, :rpc_url, @default_rpc_url),
      method: :post,
      json: body,
      receive_timeout: @request_timeout_ms
    ]
    |> Req.request(Keyword.get(opts, :req_options, []))
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"result" => %{"account_data" => %{"Balance" => drops}}}}} ->
        parse_drops(drops)

      {:ok, %Req.Response{status: 200, body: %{"result" => %{"error" => "actNotFound"}}}} ->
        {:ok, 0}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:unexpected_response, status, body}}

      {:error, exception} ->
        {:error, {:transport, exception}}
    end
  end

  @impl true
  def fund(address, opts) do
    [
      url: Keyword.get(opts, :faucet_url, @default_faucet_url),
      method: :post,
      json: %{"destination" => address},
      receive_timeout: @request_timeout_ms,
      retry: false
    ]
    |> Req.request(Keyword.get(opts, :req_options, []))
    |> case do
      {:ok, %Req.Response{status: status, body: %{"account" => %{"address" => ^address}}}} when status in 200..299 ->
        {:ok, [address]}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:provider_rejected, status, body}}

      {:error, exception} ->
        {:error, {:transport, exception}}
    end
  end

  defp parse_drops(drops) when is_binary(drops) do
    case Integer.parse(drops) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> {:error, {:invalid_quantity, drops}}
    end
  end

  defp parse_drops(other), do: {:error, {:invalid_quantity, other}}
end
