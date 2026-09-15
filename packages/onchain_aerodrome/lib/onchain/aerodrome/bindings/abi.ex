defmodule Onchain.Aerodrome.Bindings.Abi do
  @moduledoc """
  Canonical signatures from the nine deployed ABI captures in `priv/abis`.

  Decode positionally with `Onchain.RPC.eth_call/3` followed by
  `Onchain.ABI.decode_response/2` and hand-written `from_raw/1` constructors,
  matching onchain_aave. Named components are evidence for field-count and
  field-order drift tests, not instructions to decode maps.

  The decision was made against Hex onchain 0.13.0: `Onchain.Contract.call/5`
  called the two-arity `Onchain.ABI.decode_response/2` without forwarding
  options, making hieroglyph 1.7.0's `decode_structs: true` unreachable through
  those wrappers. The monorepo's onchain 0.14.0 now forwards decode options,
  but map decoding still raises on un-interned field atoms. Positional decode
  avoids dynamic atom lookup and remains the package strategy.

  Files are identified by basename, including `.json`. A unique function name
  suffices; overloaded functions require their full canonical call signature.
  Unknown files/functions and ambiguous names return tagged errors.
  """

  paths = Path.wildcard(Application.app_dir(:onchain_aerodrome, "priv/abis/*.json"))

  for path <- paths do
    @external_resource path
  end

  canonical = fn
    recurse, %{"type" => "tuple" <> suffix, "components" => components} ->
      "(" <> Enum.map_join(components, ",", &recurse.(recurse, &1)) <> ")" <> suffix

    _recurse, %{"type" => type} ->
      type
  end

  @abis Map.new(paths, fn path ->
          functions =
            path
            |> File.read!()
            |> Jason.decode!()
            |> Enum.filter(&(&1["type"] == "function"))
            |> Enum.map(fn function ->
              inputs = Enum.map_join(function["inputs"], ",", &canonical.(canonical, &1))
              outputs = Enum.map_join(function["outputs"], ",", &canonical.(canonical, &1))
              {function["name"], function["name"] <> "(" <> inputs <> ")", "(" <> outputs <> ")"}
            end)

          {Path.basename(path), functions}
        end)

  @type lookup_error :: :unknown_file | :unknown_function | :ambiguous_function

  @doc "Returns the canonical call signature for a captured function."
  @spec signature(String.t(), String.t()) :: {:ok, String.t()} | {:error, lookup_error()}
  def signature(file, function) do
    with {:ok, {_name, signature, _return_type}} <- lookup(file, function), do: {:ok, signature}
  end

  @doc "Returns the parenthesized output signature accepted by Onchain.ABI.decode_response/2."
  @spec return_type(String.t(), String.t()) :: {:ok, String.t()} | {:error, lookup_error()}
  def return_type(file, function) do
    with {:ok, {_name, _signature, return_type}} <- lookup(file, function), do: {:ok, return_type}
  end

  defp lookup(file, function) do
    case Map.fetch(@abis, file) do
      {:ok, functions} ->
        find_function(functions, function)

      :error ->
        {:error, :unknown_file}
    end
  end

  defp find_function(functions, function) do
    case Enum.filter(functions, fn {name, signature, _} ->
           function == name or function == signature
         end) do
      [match] -> {:ok, match}
      [] -> {:error, :unknown_function}
      _matches -> {:error, :ambiguous_function}
    end
  end
end
