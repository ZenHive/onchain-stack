defmodule Onchain.Tempo.Verification.Vectors do
  @moduledoc false

  @fixture "priv/verification/0x76/ox_vectors.json"

  @spec path() :: String.t()
  def path, do: Application.app_dir(:onchain_tempo, @fixture)

  @spec load() :: map()
  def load do
    path()
    |> File.read!()
    |> Jason.decode!()
  end

  @spec oracle_meta() :: map()
  def oracle_meta, do: Map.fetch!(load(), "oracle")

  @spec keys() :: map()
  def keys, do: Map.fetch!(load(), "keys")

  @spec case!(String.t()) :: map()
  def case!(name) do
    cases = Map.fetch!(load(), "cases")

    case Map.fetch(cases, name) do
      {:ok, vec} -> vec
      :error -> raise ArgumentError, "unknown ox vector #{inspect(name)}"
    end
  end

  @spec case_names() :: [String.t()]
  def case_names, do: load() |> Map.fetch!("cases") |> Map.keys() |> Enum.sort()
end
