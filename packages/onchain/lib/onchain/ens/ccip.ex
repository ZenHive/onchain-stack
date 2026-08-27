defmodule Onchain.ENS.CCIP do
  @moduledoc false

  # EIP-3668 (CCIP-Read) pure helpers plus an injectable gateway round-trip.
  #
  # A resolver that holds data off-chain does not return it directly: it reverts
  # with `OffchainLookup(address sender, string[] urls, bytes callData,
  # bytes4 callbackFunction, bytes extraData)` (selector 0x556f1830). The client
  # then queries one of the gateway `urls`, and re-calls `sender` with
  # `callbackFunction(response, extraData)`. That callback may itself revert with
  # another `OffchainLookup`, so the round-trip is a bounded loop.
  #
  # The transport-bearing functions (`fetch/5`) take `call_fun` and `gateway_fun`
  # as explicit arguments so the spec-heavy revert→gateway→callback logic is unit
  # testable offline; `Onchain.ENS` supplies real `eth_call` / HTTP closures.
  #
  # Reference: https://eips.ethereum.org/EIPS/eip-3668

  alias Onchain.Address
  alias Onchain.Hex

  # keccak256("OffchainLookup(address,string[],bytes,bytes4,bytes)")[0..3]
  @offchain_lookup_selector <<0x55, 0x6F, 0x18, 0x30>>
  @offchain_lookup_args "(address,string[],bytes,bytes4,bytes)"
  @callback_args "(bytes,bytes)"
  @max_redirects 4

  @type lookup :: %{
          sender: String.t(),
          urls: [String.t()],
          call_data: binary(),
          callback_function: binary(),
          extra_data: binary()
        }

  @type call_fun :: (String.t() | binary(), String.t() ->
                       {:ok, String.t()} | {:revert, binary()} | {:error, term()})
  @type gateway_fun :: (lookup() -> {:ok, binary()} | {:error, term()})

  @doc false
  @spec offchain_lookup_selector() :: binary()
  def offchain_lookup_selector, do: @offchain_lookup_selector

  @doc false
  # Decodes raw revert data into an OffchainLookup struct, or reports that the
  # revert is something else (a plain require/custom error, not CCIP).
  @spec parse_offchain_lookup(binary()) :: {:ok, lookup()} | {:error, :not_offchain_lookup}
  def parse_offchain_lookup(<<@offchain_lookup_selector, rest::binary>>) do
    case safe_decode(@offchain_lookup_args, rest) do
      {:ok, [sender, urls, call_data, callback_function, extra_data]}
      when is_binary(sender) and is_list(urls) and is_binary(call_data) and
             is_binary(callback_function) and is_binary(extra_data) ->
        {:ok,
         %{
           sender: to_hex_address(sender),
           urls: urls,
           call_data: call_data,
           callback_function: callback_function,
           extra_data: extra_data
         }}

      _ ->
        {:error, :not_offchain_lookup}
    end
  end

  def parse_offchain_lookup(_other), do: {:error, :not_offchain_lookup}

  @doc false
  # Builds the gateway HTTP request from a URL template (EIP-3668 step 5):
  # `{data}` present → GET (no body); absent → POST with a JSON body. Both
  # substitute `{sender}` and `{data}` with lowercase 0x-hex values.
  @spec build_gateway_request(lookup(), String.t()) ::
          {:get, String.t(), nil} | {:post, String.t(), binary()}
  def build_gateway_request(lookup, template) when is_binary(template) do
    sender_hex = String.downcase(lookup.sender)
    data_hex = Hex.encode(lookup.call_data)

    if String.contains?(template, "{data}") do
      url =
        template
        |> String.replace("{sender}", sender_hex)
        |> String.replace("{data}", data_hex)

      {:get, url, nil}
    else
      url = String.replace(template, "{sender}", sender_hex)
      body = Jason.encode!(%{"data" => data_hex, "sender" => sender_hex})
      {:post, url, body}
    end
  end

  @doc false
  # Builds the callback calldata: callbackFunction(bytes response, bytes extraData).
  @spec build_callback_calldata(lookup(), binary()) :: binary()
  def build_callback_calldata(lookup, response) when is_binary(response) do
    # hieroglyph encodes a tuple type from a tuple wrapped in a list.
    lookup.callback_function <> ABI.encode(@callback_args, [{response, lookup.extra_data}])
  end

  @doc false
  # Runs the bounded OffchainLookup round-trip. `call_fun` performs an eth_call
  # (returning `{:revert, bytes}` when the node hands back execution-revert data);
  # `gateway_fun` performs the HTTP fetch and returns the gateway's response bytes.
  @spec fetch(call_fun(), gateway_fun(), String.t() | binary(), String.t(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, term()}
  def fetch(call_fun, gateway_fun, to, data_hex, depth \\ 0)

  def fetch(_call_fun, _gateway_fun, _to, _data_hex, depth) when depth > @max_redirects, do: {:error, :ccip_max_redirects}

  def fetch(call_fun, gateway_fun, to, data_hex, depth) do
    case call_fun.(to, data_hex) do
      {:ok, hex} -> {:ok, hex}
      {:revert, revert} -> handle_revert(revert, call_fun, gateway_fun, depth)
      {:error, _reason} = error -> error
    end
  end

  @spec handle_revert(binary(), call_fun(), gateway_fun(), non_neg_integer()) ::
          {:ok, String.t()} | {:error, term()}
  defp handle_revert(revert, call_fun, gateway_fun, depth) do
    case parse_offchain_lookup(revert) do
      {:ok, lookup} ->
        case gateway_fun.(lookup) do
          {:ok, response} ->
            callback = build_callback_calldata(lookup, response)
            fetch(call_fun, gateway_fun, lookup.sender, Hex.encode(callback), depth + 1)

          {:error, _reason} = error ->
            error
        end

      {:error, :not_offchain_lookup} ->
        {:error, {:execution_reverted, revert}}
    end
  end

  # Gateway/resolver payloads are attacker-influenced, so a malformed one is an
  # expected `:error`, not a crash. Exception set mirrors `Onchain.ABI`'s
  # `@abi_errors` — see the note there for how each was verified against
  # hieroglyph. Anything outside it is a bug in this module and propagates.
  @spec safe_decode(String.t(), binary()) :: {:ok, list()} | :error
  defp safe_decode(types, binary) do
    {:ok, ABI.decode(types, binary)}
  rescue
    _ in [
      ABI.TypeDecoder.StrictViolation,
      ArgumentError,
      CaseClauseError,
      FunctionClauseError,
      MatchError,
      RuntimeError
    ] ->
      :error
  end

  @spec to_hex_address(binary()) :: String.t()
  defp to_hex_address(bin) do
    case Address.checksum(bin) do
      {:ok, checksummed} -> checksummed
      {:error, _} -> Hex.encode(bin)
    end
  end
end
