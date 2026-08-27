defmodule Onchain.RPC.Specs do
  @moduledoc """
  Compile-time lookup table for the vendored Ethereum OpenRPC method specs.
  """

  @openrpc_spec_path Application.app_dir(:onchain, "priv/specs/openrpc-v1.0.0-beta.4.json")
  @erigon_spec_path Application.app_dir(:onchain, "priv/specs/erigon-methods.json")
  @external_resource @openrpc_spec_path
  @external_resource @erigon_spec_path

  @raw_spec @openrpc_spec_path |> File.read!() |> Jason.decode!()

  @openrpc_specs_by_method_name Map.new(@raw_spec["methods"], fn method ->
                                  description =
                                    method["description"] ||
                                      method["summary"] ||
                                      ""

                                  {method["name"],
                                   %{
                                     params: Map.get(method, "params", []),
                                     returns: method["result"],
                                     description: description
                                   }}
                                end)

  @erigon_specs_by_method_name (if File.exists?(@erigon_spec_path) do
                                  @erigon_spec_path
                                  |> File.read!()
                                  |> Jason.decode!()
                                  |> Map.new(fn method ->
                                    {method["method"],
                                     %{
                                       params: [],
                                       returns: %{},
                                       description:
                                         "Erigon #{method["receiver"]}.#{method["go_method"]} scraped from #{method["source"]}"
                                     }}
                                  end)
                                else
                                  %{}
                                end)

  @specs_by_method_name Map.merge(@openrpc_specs_by_method_name, @erigon_specs_by_method_name)

  @type method_spec :: %{
          params: [map()],
          returns: map(),
          description: String.t()
        }

  @doc "Returns all vendored OpenRPC method specs keyed by JSON-RPC method name."
  @spec all() :: %{optional(String.t()) => method_spec()}
  def all, do: @specs_by_method_name

  @doc "Looks up a vendored OpenRPC method spec by JSON-RPC method name."
  @spec lookup(String.t()) :: method_spec() | nil
  def lookup(method) when is_binary(method), do: Map.get(@specs_by_method_name, method)
end
