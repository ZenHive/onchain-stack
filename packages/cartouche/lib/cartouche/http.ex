defmodule Cartouche.HTTP do
  @moduledoc """
  HTTP helpers shared by cartouche's `Req`-based RPC transports.
  """

  @doc """
  Builds the `Req.request/1` option list for a transport call.

  Merges, in increasing precedence:

    1. `base` — the transport-built options (`:method`, `:url`, `:headers`, `:body`,
       `:receive_timeout`, plus `decode_body: false` and `retry: false`).
    2. `config :cartouche, <owner>, [...]` — per-transport options keyed by the calling
       module (`Cartouche.RPC`, `Cartouche.Solana.RPC`, or the hidden OpenChain API
       transport). This
       is where test/consumer code injects a stub `:plug`; production leaves it unset.
    3. `config :cartouche, :req_options, [...]` — the global production seam (a custom
       Finch pool, retries, telemetry, proxies, …).
    4. `Keyword.get(call_opts, :req_options, [])` — per-call overrides (highest), e.g.
       `req_options: [plug: nil]` to bypass a configured stub and hit the network.
  """
  @spec req_options(module(), Keyword.t(), Keyword.t()) :: Keyword.t()
  def req_options(owner, base, call_opts) do
    base
    |> Keyword.merge(Application.get_env(:cartouche, owner, []))
    |> Keyword.merge(Application.get_env(:cartouche, :req_options, []))
    |> Keyword.merge(Keyword.get(call_opts, :req_options, []))
  end

  @doc """
  Normalizes the result of a `Req` request.

  Any non-2xx status code is wrapped in `{:error, response}`. Transport and other client
  errors are abstracted into a `{:error, message}` string so callers never see Req's
  internals.

  > #### Transport-error contract {: .info}
  >
  > A `%Req.TransportError{}` (connection closed/refused/timeout) maps to
  > `"[Cartouche] HTTP client error: <reason>"`. This is a deliberate 0.5.0 contract:
  > under the old Finch transport the analogous mock surfaced as a bare
  > `"[Cartouche] Unknown error: :closed"`, but a real transport failure is an HTTP
  > client error and is reported as one.
  """
  @spec normalize_response({:ok, Req.Response.t()} | {:error, Exception.t() | term()}) ::
          {:ok, Req.Response.t()} | {:error, Req.Response.t() | String.t()}
  def normalize_response(result) do
    case result do
      {:ok, %Req.Response{status: code} = resp} when code >= 200 and code < 300 ->
        {:ok, resp}

      {:ok, %Req.Response{status: _} = resp} ->
        {:error, resp}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, "[Cartouche] HTTP client error: #{inspect(reason)}"}

      {:error, %{__exception__: true} = e} ->
        {:error, "[Cartouche] HTTP client error: #{Exception.message(e)}"}

      {:error, error} ->
        {:error, "[Cartouche] Unknown error: #{inspect(error)}"}
    end
  end
end
