defmodule Onchain.Aerodrome.Fixtures do
  @moduledoc """
  Offline loader for committed Sugar `eth_call` fixtures.

  Reads `test/fixtures/aerodrome/` with no network. The `nonempty/` subcollection
  has its own manifest and positive Position/Reward witnesses; load it with
  `load("nonempty/manifest")` and `load("nonempty/" <> id)`. Decode uses
  `Bindings.Abi.return_type/2` and `Onchain.ABI.decode_response/2`.
  """

  alias Onchain.Aerodrome.Bindings.Abi

  @dir Path.expand("../fixtures/aerodrome", __DIR__)

  @doc "Absolute path of the committed fixture directory."
  @spec dir() :: String.t()
  def dir, do: @dir

  @doc "Decoded `manifest.json`."
  @spec manifest() :: map()
  def manifest, do: read_json!("manifest.json")

  @doc "Fixture ids in capture order from the manifest."
  @spec ids() :: [String.t()]
  def ids do
    case manifest() do
      %{"fixtures" => ids} when is_list(ids) -> ids
    end
  end

  @doc "Load one fixture map by id."
  @spec load(String.t()) :: map()
  def load(id) when is_binary(id), do: read_json!(id <> ".json")

  @doc "Load every fixture listed in the manifest."
  @spec load_all() :: [map()]
  def load_all, do: Enum.map(ids(), &load/1)

  @doc "Positionally decode a fixture's response hex. Zero network."
  @spec decode(map()) :: {:ok, term()} | {:error, term()}
  def decode(%{"contract" => contract, "function" => function, "response" => response} = fixture) do
    lookup = fixture["signature"] || function

    with {:ok, return_type} <- Abi.return_type(contract <> ".json", lookup) do
      Onchain.ABI.decode_response(return_type, response)
    end
  end

  @spec read_json!(String.t()) :: map()
  defp read_json!(name) do
    @dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end
end
