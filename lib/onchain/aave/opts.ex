defmodule Onchain.Aave.Opts do
  @moduledoc false
  # Shared option splitting for Aave modules.
  # Separates :network (for Contracts lookup) from remaining options (RPC, Signer, etc.).

  @doc false
  @spec split_network(keyword()) :: {keyword(), keyword()}
  def split_network(opts) do
    if Keyword.has_key?(opts, :network) do
      {network_val, rest} = Keyword.pop(opts, :network)
      {[network: network_val], rest}
    else
      {[], opts}
    end
  end
end
