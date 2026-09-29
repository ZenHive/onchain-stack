defmodule Onchain.Tempo.Native do
  @moduledoc false
  use RustlerPrecompiled, Onchain.Precompiled.opts("onchain_tempo")

  @spec transaction_json(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def transaction_json(_input), do: :erlang.nif_error(:nif_not_loaded)
end
