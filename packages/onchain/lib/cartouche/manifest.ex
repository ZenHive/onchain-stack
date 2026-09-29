defmodule Cartouche.Manifest do
  @moduledoc """
  Runtime accessor for Cartouche's API manifest — returns the same structure
  that `mix descripex.manifest` (aliased as `mix manifest`) writes to JSON.

  HTTP endpoints, MCP servers, and other agent-economy consumers can call
  `Cartouche.Manifest.build/0` to retrieve the live manifest without depending
  on an out-of-band JSON artifact. The static `api_manifest.json` is the same
  shape, regenerated from source on demand and not checked into git.

  See [`descripex`](https://hexdocs.pm/descripex) for the manifest schema and
  the broader self-describing-library pattern.
  """

  use Descripex, namespace: "/cartouche/manifest"

  api(:build, "Build the live API manifest for every Cartouche module registered for descripex discovery.",
    params: [],
    returns: %{
      type: :map,
      description:
        "Manifest map with `:version`, `:generated_at`, and `:modules` keys, mirroring the JSON shape produced by `mix descripex.manifest`."
    }
  )

  @doc """
  Build the live API manifest for every registered Cartouche module.

  Mirrors the JSON shape produced by `mix manifest` (aliased to
  `mix descripex.manifest --pretty --output api_manifest.json`); use this
  variant when serving the manifest from a running Erlang VM (HTTP endpoint,
  MCP server, A2A agent) rather than from a static build-time artifact.
  """
  @spec build() :: map()
  def build, do: Descripex.Manifest.build(Cartouche.__descripex_modules__())
end
