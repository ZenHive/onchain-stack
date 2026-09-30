defmodule Onchain.HTTP do
  @moduledoc false

  # HTTP options for the CCIP-Read gateway. JSON-RPC uses Cartouche.HTTP.

  @doc """
  Builds the `Req.request/1` option list for an onchain transport call.

  Merges, in increasing precedence:

    1. `base` — the transport-built options (`:method`, `:url`, `:headers`,
       `:body`, `:receive_timeout`, plus `decode_body: false` and `retry: false`).
    2. `config :onchain, <owner>, [...]` — per-transport options keyed by the
       calling module (`Onchain.ENS`). Tests inject a stub
       `:plug` here; production leaves it unset.
    3. `config :onchain, :req_options, [...]` — the global production seam
       (custom Finch pool, retries, telemetry, proxies, …).
    4. `call_opts[:req_options]` — per-call overrides (highest).
  """
  @spec req_options(module(), keyword(), keyword()) :: keyword()
  def req_options(owner, base, call_opts) do
    base
    |> Keyword.merge(Application.get_env(:onchain, owner, []))
    |> Keyword.merge(Application.get_env(:onchain, :req_options, []))
    |> Keyword.merge(Keyword.get(call_opts, :req_options, []))
  end
end
