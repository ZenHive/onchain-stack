defmodule Onchain.HTTP do
  @moduledoc false

  # Transport-option seam for onchain's own `Req`-based HTTP paths (the JSON-RPC
  # array batch in `Onchain.RPC` and the CCIP-Read gateway in `Onchain.ENS`).
  #
  # Mirrors `Cartouche.HTTP.req_options/3` but keyed under the `:onchain`
  # application so onchain stops depending on cartouche's removed
  # `:cartouche, :client | :finch_name` seams. Single-call RPC keeps flowing
  # through `Cartouche.RPC.send_rpc/3` (cartouche's own Req transport); only the
  # two paths that build HTTP requests directly use this.

  @doc """
  Builds the `Req.request/1` option list for an onchain transport call.

  Merges, in increasing precedence:

    1. `base` — the transport-built options (`:method`, `:url`, `:headers`,
       `:body`, `:receive_timeout`, plus `decode_body: false` and `retry: false`).
    2. `config :onchain, <owner>, [...]` — per-transport options keyed by the
       calling module (`Onchain.RPC`, `Onchain.ENS`). Tests inject a stub
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
