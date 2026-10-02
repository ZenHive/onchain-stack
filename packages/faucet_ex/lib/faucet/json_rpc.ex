defmodule Faucet.JSONRPC do
  @moduledoc """
  Minimal JSON-RPC 2.0 client over Req, shared by the EVM, Tempo and Solana
  adapters.

  Deliberately tiny: one request, one decoded `result`. Pass `:req_options`
  (a keyword list handed to `Req.request/2`) to inject a `Req.Test` plug or
  adjust timeouts.
  """

  use Descripex, namespace: "/faucet/json_rpc"

  @default_timeout_ms 30_000

  @typedoc "Why a call failed: node-side error object, unexpected status, or transport failure."
  @type error ::
          {:rpc_error, map() | term()}
          | {:unexpected_response, non_neg_integer(), term()}
          | {:transport, Exception.t()}

  api(:call, "POST one JSON-RPC 2.0 request and return its decoded `result`.",
    params: [
      url: [kind: :value, description: "Node endpoint URL"],
      method: [kind: :value, description: "JSON-RPC method name"],
      params: [kind: :value, description: "Positional params list"],
      opts: [
        kind: :value,
        default: [],
        description: "`:req_options` passed to Req (plug, retry, timeouts); `:receive_timeout` in ms (default 30_000)"
      ]
    ],
    returns: %{type: "{:ok, term} | {:error, error()}", description: "Raw decoded result or a tagged error"}
  )

  @spec call(String.t(), String.t(), list(), keyword()) :: {:ok, term()} | {:error, error()}
  def call(url, method, params, opts \\ []) when is_binary(url) and is_binary(method) and is_list(params) do
    body = %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}

    [url: url, method: :post, json: body, receive_timeout: Keyword.get(opts, :receive_timeout, @default_timeout_ms)]
    |> Req.request(Keyword.get(opts, :req_options, []))
    |> classify()
  end

  defp classify({:ok, %Req.Response{status: status, body: %{"result" => value}}}) when status in 200..299,
    do: {:ok, value}

  defp classify({:ok, %Req.Response{body: %{"error" => error}}}), do: {:error, {:rpc_error, error}}
  defp classify({:ok, %Req.Response{status: status, body: body}}), do: {:error, {:unexpected_response, status, body}}
  defp classify({:error, exception}), do: {:error, {:transport, exception}}

  api(:quantity, "Decode an EVM `0x`-prefixed hex quantity into an integer.",
    params: [value: [kind: :value, description: "Hex string as returned by eth_getBalance / eth_call"]],
    returns: %{type: "{:ok, non_neg_integer} | {:error, {:invalid_quantity, term}}", description: "Decoded integer"}
  )

  @spec quantity(term()) :: {:ok, non_neg_integer()} | {:error, {:invalid_quantity, term()}}
  def quantity("0x" <> hex = value) do
    case Integer.parse(hex, 16) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> {:error, {:invalid_quantity, value}}
    end
  end

  def quantity(other), do: {:error, {:invalid_quantity, other}}
end
