defmodule Onchain.Test.RPCAdapter do
  @moduledoc false

  # Only the former Cartouche suite's default endpoint uses its canned RPC
  # responses. Onchain's connection-failure tests must reach their own URLs.
  @doc false
  @spec run(Req.Request.t()) :: {Req.Request.t(), Req.Response.t() | Exception.t()}
  def run(request) do
    if request.url.host in ["mainnet.infura.io", "example.com"] and
         not Process.get(:onchain_real_rpc, false) and not Map.has_key?(request.options, :plug) do
      request
      |> Req.Request.put_option(:plug, &Onchain.Test.Client.call/1)
      |> Req.Plug.run()
    else
      Req.Finch.run(request)
    end
  end
end
