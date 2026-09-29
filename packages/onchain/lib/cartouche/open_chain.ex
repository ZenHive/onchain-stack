defmodule Cartouche.OpenChain do
  @moduledoc ~S"""
  API Client for [OpenChain.xyz](https://openchain.xyz] API.
  """

  use Cartouche.Hex

  defmodule Signatures do
    @moduledoc false
    defstruct [:events, :functions]

    @type t :: %__MODULE__{
            events: [{binary(), String.t()}],
            functions: [{binary(), String.t()}]
          }

    @doc ~S"""
    Deserializes an open chain signature.

    ## Examples

        iex> %{
        ...>   "event" => %{
        ...>     "0x08c379a0" => []
        ...>   },
        ...>   "function" => %{
        ...>     "0x08c379a0" => [
        ...>       %{
        ...>         "name" => "Error(string)",
        ...>         "filtered" => false
        ...>       }
        ...>     ]
        ...>   }
        ...> }
        ...> |> Cartouche.OpenChain.Signatures.deserialize()
        %Cartouche.OpenChain.Signatures{
          events: [],
          functions: [
            {<<8, 195, 121, 160>>, "Error(string)"}
          ]
        }
    """
    @spec deserialize(%{required(String.t()) => map()}) :: t()
    def deserialize(%{"event" => event_list, "function" => function_list}) do
      %__MODULE__{
        events: decode_entries(event_list),
        functions: decode_entries(function_list)
      }
    end

    @spec decode_entries(map()) :: [{binary(), String.t()}]
    defp decode_entries(entries) when is_map(entries) do
      entries
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.flat_map(fn
        {k, vs} ->
          vs
          |> Enum.filter(fn v -> not v["filtered"] end)
          |> Enum.map(fn v -> {from_hex!(k), v["name"]} end)
      end)
    end
  end

  defmodule API do
    @moduledoc false
    import Cartouche.HTTP, only: [normalize_response: 1]

    @spec base_url() :: String.t()
    defp base_url, do: Application.get_env(:cartouche, :open_chain_base_url, "https://api.4byte.sourcify.dev")

    @doc false
    @spec get(String.t(), Keyword.t()) :: {:ok, term()} | {:error, Req.Response.t() | String.t()}
    def get(url, opts) do
      headers = Keyword.get(opts, :headers, [])
      timeout = Keyword.get(opts, :timeout, 30_000)

      req_result =
        normalize_response(
          Req.request(
            Cartouche.HTTP.req_options(
              __MODULE__,
              [method: :get, url: url, headers: headers, receive_timeout: timeout, decode_body: false, retry: false],
              opts
            )
          )
        )

      case req_result do
        {:ok, %Req.Response{status: _, body: resp_body}} ->
          decode_response(resp_body)

        {:error, _} = error ->
          error
      end
    end

    @spec decode_response(binary()) :: {:ok, term()} | {:error, String.t()}
    defp decode_response(resp_body) do
      case Jason.decode(resp_body) do
        {:ok, %{"ok" => true, "result" => result}} -> {:ok, result}
        {:ok, %{"ok" => false, "error" => error}} -> {:error, error}
        {:ok, other} -> {:error, "unexpected response shape: #{inspect(other)}"}
        {:error, json_error} -> {:error, Jason.DecodeError.message(json_error)}
      end
    end

    @doc ~S"""
    Runs a lookup query from OpenChain, returning matching signtures.

    ## Examples

        iex> Cartouche.OpenChain.API.lookup([<<8, 195, 121, 160>>], [])
        {:ok,
          %Cartouche.OpenChain.Signatures{
            events: [],
            functions: [{<<8, 195, 121, 160>>, "Error(string)"}]
          }
        }
    """
    @spec lookup([binary()], [binary()], Keyword.t()) ::
            {:ok, Signatures.t()} | {:error, String.t()}
    def lookup(event_signatures, function_signatures, opts \\ []) do
      {filter, opts} = Keyword.pop(opts, :filter, true)

      query =
        if filter do
          [filter: filter]
        else
          []
        end

      query =
        case event_signatures do
          [] ->
            query

          _ ->
            Keyword.put(
              query,
              :event,
              Enum.map_join(event_signatures, ",", &Cartouche.Hex.to_hex/1)
            )
        end

      query =
        case function_signatures do
          [] ->
            query

          _ ->
            Keyword.put(
              query,
              :function,
              Enum.map_join(function_signatures, ",", &Cartouche.Hex.to_hex/1)
            )
        end

      with {:ok, resp} <-
             get(
               "#{base_url()}/signature-database/v1/lookup?#{URI.encode_query(query)}",
               opts
             ) do
        {:ok, Signatures.deserialize(resp)}
      end
    end
  end

  @doc ~S"""
  Tries to lookup given signature of given type.

  ## Examples

      iex> Cartouche.OpenChain.lookup(<<8, 195, 121, 160>>, :function)
      {:ok, "Error(string)"}
  """
  @spec lookup(binary(), :function | :event, Keyword.t()) ::
          {:ok, String.t()} | {:error, String.t()}
  def lookup(signature, type, opts \\ []) do
    {raise_on_multiple, opts} = Keyword.pop(opts, :raise_on_multiple, false)

    found_signatures_result =
      case type do
        :function ->
          with {:ok, signatures} <- API.lookup([], [signature], opts) do
            {:ok, signatures.functions}
          end

        :event ->
          with {:ok, signatures} <- API.lookup([signature], [], opts) do
            {:ok, signatures.events}
          end
      end

    with {:ok, found_signatures} <- found_signatures_result do
      pick_signature(found_signatures, signature, raise_on_multiple)
    end
  end

  @spec pick_signature([{binary(), String.t()}], binary(), boolean()) ::
          {:ok, String.t()} | {:error, String.t()}
  defp pick_signature([], _signature, _raise_on_multiple), do: {:error, "Signature not found"}

  defp pick_signature([{signature, abi}], signature, _raise_on_multiple), do: {:ok, abi}

  defp pick_signature([{signature, abi} | _], signature, false), do: {:ok, abi}

  defp pick_signature(found_signatures, _signature, _raise_on_multiple) do
    names = Enum.map_join(found_signatures, ",", fn {_, name} -> name end)
    {:error, "Multiple matching signatures: #{names}"}
  end

  @doc ~S"""
  Looks up and tries to decode a given error message from its ABI-encoded form.

  ## Examples

      iex> Cartouche.OpenChain.lookup_error(~h[0x08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001b43616c6c6572206e6f74206174746573746572206d616e616765720000000000])
      {:ok, ["Caller not attester manager"]}
  """
  @spec lookup_error(binary(), Keyword.t()) ::
          {:ok, [term()]} | {:error, String.t()}
  def lookup_error(_, opts \\ [])

  def lookup_error(<<signature::binary-size(4), data::binary>>, opts) do
    with {:ok, signature} <- lookup(signature, :function, opts) do
      function_selector = ABI.FunctionSelector.decode(signature)
      result = ABI.decode(function_selector, data)
      {:ok, result}
    end
  end

  def lookup_error(_, _opts), do: {:error, "Error must include 4-byte signature"}

  @doc """
    Looks up an error and decodes its values, returning both.

      ## Examples

          iex> Cartouche.OpenChain.lookup_error_and_values(~h[0x08c379a00000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001b43616c6c6572206e6f74206174746573746572206d616e616765720000000000])
          {:ok, "Error(string)", ["Caller not attester manager"]}
  """
  @spec lookup_error_and_values(binary(), Keyword.t()) ::
          {:ok, String.t(), [term()]} | {:error, String.t()}
  def lookup_error_and_values(_, opts \\ [])

  def lookup_error_and_values(<<signature::binary-size(4), data::binary>>, opts) do
    with {:ok, signature} <- lookup(signature, :function, opts) do
      function_selector = ABI.FunctionSelector.decode(signature)
      result = ABI.decode(function_selector, data)
      {:ok, signature, result}
    end
  end

  def lookup_error_and_values(_, _opts), do: {:error, "Error must include 4-byte signature"}
end
