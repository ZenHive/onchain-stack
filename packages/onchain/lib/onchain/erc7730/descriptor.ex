defmodule Onchain.ERC7730.Descriptor do
  @moduledoc """
  Parsed, validated representation of an [ERC-7730](https://eips.ethereum.org/EIPS/eip-7730)
  clear-signing descriptor.

  An ERC-7730 descriptor is a JSON document with three top-level sections:

  - `context` — the binding constraints: either a `contract` (deployments + ABI)
    or an `eip712` (domain + typed-data schemas) context.
  - `metadata` — owner, constants, enums, and optional token info.
  - `display` — `formats` keyed by function signature (contract) or primary type
    (EIP-712), each carrying an ordered list of display `fields`.

  `parse/1` turns the decoded JSON map into a `t:t/0` struct, validating the
  structural rules. The original decoded JSON is retained in `:raw` so that
  `$.`-rooted paths (e.g. `$.metadata.constants.tokenAddress`) resolve against
  the document.

  ## Scope

  This first pass keeps the structure faithful to the spec but does not resolve
  `includes` / `$ref`-to-external-document references — descriptors are expected
  to be self-contained (the registry-side resolution of shared `ercs/*` includes
  is out of scope, per Task 74).
  """

  use Descripex, namespace: "/erc7730/descriptor"

  alias Onchain.Address

  @enforce_keys [:context, :display, :metadata, :raw]
  defstruct [:context, :display, :metadata, :raw]

  @type deployment :: %{chain_id: non_neg_integer(), address: <<_::160>>}

  @type context ::
          {:contract,
           %{
             deployments: [deployment()],
             abi: term() | nil,
             address_matcher: String.t() | nil
           }}
          | {:eip712,
             %{
               deployments: [deployment()],
               domain: map() | nil,
               domain_separator: String.t() | nil,
               schemas: term() | nil
             }}

  @type field :: %{
          path: String.t() | nil,
          value: term(),
          label: String.t() | nil,
          format: atom(),
          params: map(),
          visible: boolean()
        }

  @type format :: %{
          intent: String.t() | map() | nil,
          fields: [field()]
        }

  @type t :: %__MODULE__{
          context: context(),
          metadata: map(),
          display: %{formats: %{optional(String.t()) => format()}},
          raw: map()
        }

  api(:parse, "Parse and structurally validate a decoded ERC-7730 JSON map.",
    params: [
      raw: [kind: :value, description: "Decoded JSON map (string keys) of an ERC-7730 descriptor"]
    ],
    returns: %{
      type: "{:ok, t()} | {:error, {tag, reason}}",
      description:
        "Validated descriptor struct, or an error: :missing_context, :invalid_context, :no_deployments, :invalid_address, :missing_display, :invalid_field"
    }
  )

  @spec parse(map()) :: {:ok, t()} | {:error, {atom(), term()}}
  def parse(raw) when is_map(raw) do
    with {:ok, context} <- parse_context(raw),
         {:ok, display} <- parse_display(raw) do
      {:ok,
       %__MODULE__{
         context: context,
         metadata: Map.get(raw, "metadata", %{}),
         display: display,
         raw: raw
       }}
    end
  end

  def parse(_other), do: {:error, {:invalid_descriptor, :not_a_map}}

  # --- context ---

  defp parse_context(%{"context" => %{"contract" => contract}}) when is_map(contract) do
    with {:ok, deployments} <- parse_deployments(contract) do
      {:ok,
       {:contract,
        %{
          deployments: deployments,
          abi: Map.get(contract, "abi"),
          address_matcher: Map.get(contract, "addressMatcher")
        }}}
    end
  end

  defp parse_context(%{"context" => %{"eip712" => eip712}}) when is_map(eip712) do
    # Deployments are optional for EIP-712 contexts (binding can match on domain).
    case parse_deployments(eip712, _required = false) do
      {:ok, deployments} ->
        {:ok,
         {:eip712,
          %{
            deployments: deployments,
            domain: Map.get(eip712, "domain"),
            domain_separator: Map.get(eip712, "domainSeparator"),
            schemas: Map.get(eip712, "schemas")
          }}}

      {:error, _} = error ->
        error
    end
  end

  defp parse_context(%{"context" => _}), do: {:error, {:invalid_context, :unknown_context_type}}
  defp parse_context(_), do: {:error, {:missing_context, "descriptor has no \"context\" key"}}

  defp parse_deployments(map, required \\ true)

  defp parse_deployments(%{"deployments" => []}, true), do: {:error, {:no_deployments, "context has no deployments"}}

  defp parse_deployments(%{"deployments" => deployments}, _required) when is_list(deployments) do
    deployments
    |> Enum.reduce_while({:ok, []}, fn dep, {:ok, acc} ->
      case parse_deployment(dep) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      {:error, _} = error -> error
    end
  end

  defp parse_deployments(_map, false), do: {:ok, []}

  defp parse_deployments(_map, true), do: {:error, {:no_deployments, "context has no deployments"}}

  defp parse_deployment(%{"chainId" => chain_id, "address" => address}) when is_integer(chain_id) do
    case Address.validate(address) do
      {:ok, bin} -> {:ok, %{chain_id: chain_id, address: bin}}
      {:error, _} -> {:error, {:invalid_address, address}}
    end
  end

  defp parse_deployment(other), do: {:error, {:invalid_deployment, other}}

  # --- display ---

  defp parse_display(%{"display" => %{"formats" => formats}}) when is_map(formats) do
    formats
    |> Enum.reduce_while({:ok, %{}}, fn {key, format}, {:ok, acc} ->
      case parse_format(format) do
        {:ok, parsed} -> {:cont, {:ok, Map.put(acc, key, parsed)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, formats} -> {:ok, %{formats: formats}}
      {:error, _} = error -> error
    end
  end

  defp parse_display(%{"display" => _}), do: {:error, {:missing_display, "display has no \"formats\" map"}}

  defp parse_display(_), do: {:error, {:missing_display, "descriptor has no \"display\" key"}}

  defp parse_format(format) when is_map(format) do
    excluded = Map.get(format, "excluded", [])

    with {:ok, fields} <- parse_fields(Map.get(format, "fields", []), excluded) do
      {:ok,
       %{
         intent: Map.get(format, "intent"),
         interpolated_intent: Map.get(format, "interpolatedIntent"),
         fields: fields
       }}
    end
  end

  defp parse_format(other), do: {:error, {:invalid_format, other}}

  defp parse_fields(_fields, excluded) when not is_list(excluded),
    do: {:error, {:invalid_field, {:invalid_excluded, excluded}}}

  defp parse_fields(fields, excluded) when is_list(fields) do
    fields
    |> Enum.reduce_while({:ok, []}, fn field, {:ok, acc} ->
      case parse_field(field, excluded) do
        {:ok, parsed} -> {:cont, {:ok, [parsed | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      {:error, _} = error -> error
    end
  end

  defp parse_fields(_other, _excluded), do: {:error, {:invalid_field, :fields_not_a_list}}

  defp parse_field(field, excluded) when is_map(field) do
    path = Map.get(field, "path")
    params = Map.get(field, "params", %{})

    # A field must carry either a path (into the bound data) or a literal value.
    cond do
      is_nil(path) and not Map.has_key?(field, "value") ->
        {:error, {:invalid_field, {:no_path_or_value, field}}}

      not is_map(params) ->
        {:error, {:invalid_field, {:invalid_params, params}}}

      true ->
        with {:ok, format} <- parse_format_type(Map.get(field, "format")) do
          {:ok,
           %{
             path: path,
             value: Map.get(field, "value"),
             label: Map.get(field, "label"),
             format: format,
             params: params,
             visible: visible?(field, path, excluded)
           }}
        end
    end
  end

  defp parse_field(other, _excluded), do: {:error, {:invalid_field, other}}

  # `visible` is the v2 spec key ("always" | "optional" | "never"); the legacy
  # spec used a format-level `excluded` array. A field is hidden if either says so.
  defp visible?(field, path, excluded) do
    Map.get(field, "visible") != "never" and path not in excluded
  end

  @format_types %{
    "raw" => :raw,
    "amount" => :amount,
    "tokenAmount" => :token_amount,
    "addressName" => :address_name,
    "date" => :date,
    "duration" => :duration,
    "unit" => :unit,
    "enum" => :enum,
    "calldata" => :calldata,
    "nftName" => :nft_name
  }

  defp parse_format_type(nil), do: {:ok, :raw}

  defp parse_format_type(type) when is_binary(type), do: {:ok, Map.get(@format_types, type, :unknown)}

  defp parse_format_type(other), do: {:error, {:invalid_field, {:invalid_format, other}}}
end
