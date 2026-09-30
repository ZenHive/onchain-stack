defmodule ABI.Native do
  @moduledoc false
  use RustlerPrecompiled, Onchain.Precompiled.opts("onchain_abi")

  @doc false
  @spec consensus(String.t(), String.t(), binary()) :: {:ok, binary()} | {:error, term()}
  def consensus(_family, _operation, _input), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  @spec compile(String.t(), binary()) :: {:ok, reference()} | {:error, term()}
  def compile(_types, _topic0), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  @spec abi(atom(), reference() | String.t(), term()) :: {:ok, term()} | {:error, term()}
  def abi(_operation, _schema, _value), do: :erlang.nif_error(:nif_not_loaded)

  @doc false
  @spec abi_small(atom(), reference() | String.t(), term()) :: {:ok, term()} | {:error, term()}
  def abi_small(_operation, _schema, _value), do: :erlang.nif_error(:nif_not_loaded)
end
