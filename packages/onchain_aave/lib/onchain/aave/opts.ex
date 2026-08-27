defmodule Onchain.Aave.Opts do
  @moduledoc false
  # Shared internal helpers for Aave modules: option splitting and address
  # list validation. Not part of the public API.

  alias Onchain.Address

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

  @doc false
  # Validates a list of addresses, preserving order. Halts on the first
  # invalid one.
  @spec validate_addresses([term()]) :: {:ok, [binary()]} | {:error, term()}
  def validate_addresses(addresses) do
    addresses
    |> Enum.reduce_while({:ok, []}, fn addr, {:ok, acc} ->
      case Address.validate(addr) do
        {:ok, bin} -> {:cont, {:ok, [bin | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, bins} -> {:ok, Enum.reverse(bins)}
      error -> error
    end
  end
end
