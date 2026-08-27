defmodule Onchain.Log do
  @moduledoc """
  Event log parsing for Ethereum contract events.

  Computes event topic hashes from signatures and decodes raw log data
  against event signatures with indexed parameter markers.

  ## Limitations

  - Tuple-typed params (e.g. `(uint256,address)`) are not supported in event signatures.
    The comma-based parser cannot distinguish tuple-internal commas from param separators.
  - Indexed dynamic types (string, bytes, arrays) return the raw keccak256 topic hash
    since the original value is not recoverable from the log.

  ## Error Format

  - Invalid signature: `{:error, {:invalid_signature, input}}`
  - Topic mismatch: `{:error, {:decode_error, {:topic_mismatch, [expected: ..., got: ...]}}}`
  - Decode errors: `{:error, {:decode_error, reason}}`
  - Strict decode: `{:error, {:decode_error, {:strict_violation, detail}}}` when
    `strict: true` rejected a non-canonical payload. Bang variants raise.

  ## Security — signature is a trust boundary

  Each parameter name in a `signature` is interned with `String.to_atom/1` so the
  decoded map can use atom keys. **The `signature` argument MUST be developer-controlled**
  (a compile-time constant or value you author), never attacker-influenced input
  (request body, config supplied by a third party). Atoms are not garbage-collected, so
  routing untrusted signatures here is an atom-table-exhaustion (DoS) vector.

  As a defence-in-depth bound — not a substitute for the contract above — `decode_event/3`
  rejects signatures with more than `32` params and rejects any segment that is not a
  bounded identifier-shaped token before interning it (`{:error, {:invalid_signature, _}}`).
  This caps the per-call surface; it does not stop an attacker looping distinct valid
  names across many calls. The only structural fix is string-keyed output, a breaking
  change deliberately not taken here.

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `event_topic/1` | Event signature → keccak256 topic hash |
  | `event_topic!/1` | Same, raises on error |
  | `decode_event/3` | Raw log + signature → decoded param map (optional decode opts) |
  | `decode_event!/3` | Same, raises on error |
  """

  use Descripex, namespace: "/log"

  # Defence-in-depth bounds on signature parsing — see the "Security" section of the
  # @moduledoc. The signature is a trust boundary; these cap the atom-minting surface.
  @max_event_params 32
  @max_atom_segment_length 64
  # A segment safe to intern: a Solidity identifier (which may start with or contain
  # `$` per the language grammar) optionally carrying array suffixes (e.g. "value",
  # "uint256", "uint256[]", "uint256[3]", "$amount"). Rejects whitespace, unicode, and
  # other punctuation an attacker could use to spray distinct atoms.
  @atom_segment ~r/^[a-zA-Z_$][a-zA-Z0-9_$\[\]]*$/

  # --- event_topic ---

  api(:event_topic, "Compute the keccak256 topic hash for an event signature.",
    params: [
      signature: [
        kind: :value,
        description: ~s{Event signature without param names, e.g. "Transfer(address,address,uint256)"}
      ]
    ],
    returns: %{
      type: "{:ok, hex_string} | {:error, term}",
      description: "0x-prefixed 32-byte keccak256 hash",
      example: "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
    }
  )

  @spec event_topic(String.t()) :: {:ok, String.t()} | {:error, term()}
  def event_topic(signature) when is_binary(signature) do
    if String.contains?(signature, "(") and String.ends_with?(signature, ")") do
      {:ok, Onchain.Hex.encode(Cartouche.Hash.keccak(signature))}
    else
      {:error, {:invalid_signature, signature}}
    end
  end

  def event_topic(other), do: {:error, {:invalid_signature, other}}

  # --- event_topic! ---

  api(:event_topic!, "Compute the keccak256 topic hash. Raises on error.",
    params: [
      signature: [kind: :value, description: "Event signature string"]
    ],
    returns: %{type: :string, description: "0x-prefixed 32-byte keccak256 hash"}
  )

  @spec event_topic!(String.t()) :: String.t()
  def event_topic!(signature) do
    case event_topic(signature) do
      {:ok, hash} -> hash
      {:error, reason} -> raise "event_topic failed: #{inspect(reason)}"
    end
  end

  # --- decode_event ---

  api(:decode_event, "Decode a raw log map against an event signature with indexed markers.",
    params: [
      log: [
        kind: :value,
        description: "Raw log map with :topics (list of hex strings) and :data (hex string) keys"
      ],
      signature: [
        kind: :value,
        description:
          ~s{Event signature with indexed markers, e.g. "Transfer(address indexed from, address indexed to, uint256 value)". MUST be developer-controlled — param names are interned as atoms; untrusted signatures are an atom-table DoS vector (see module "Security").}
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          ~s|Forwarded to Onchain.ABI.decode_response/3 and hieroglyph's indexed-value decode. Pass `strict: true` to reject non-canonical payloads (`{:error, {:decode_error, {:strict_violation, detail}}}`).|
      ]
    ],
    returns: %{
      type: "{:ok, map} | {:error, term}",
      description: "Map with atom keys for each decoded parameter",
      example: ~s(%{from: "0xAb5...", to: "0xCd9...", value: 1000000})
    }
  )

  @spec decode_event(map(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def decode_event(log, signature, opts \\ [])

  def decode_event(%{topics: [topic0 | _] = topics, data: data}, signature, opts)
      when is_binary(signature) and is_list(opts) do
    with {:ok, params} <- parse_event_signature(signature),
         :ok <- verify_topic0(topic0, signature) do
      {indexed, non_indexed} = Enum.split_with(params, fn {_name, _type, indexed?} -> indexed? end)
      do_decode_event(topics, data, indexed, non_indexed, opts)
    end
  end

  def decode_event(%{topics: [], data: _data}, _signature, _opts), do: {:error, {:decode_error, :missing_event_topic}}

  def decode_event(_log, _signature, _opts), do: {:error, {:decode_error, :invalid_log_format}}

  # --- decode_event! ---

  api(:decode_event!, "Decode a raw log map. Raises on error.",
    params: [
      log: [kind: :value, description: "Raw log map with :topics and :data keys"],
      signature: [
        kind: :value,
        description:
          ~s{Event signature with indexed markers. MUST be developer-controlled — param names are interned as atoms; untrusted signatures are an atom-table DoS vector (see module "Security" and decode_event/3).}
      ],
      opts: [
        kind: :value,
        default: [],
        description: "Forwarded to decode_event/3 (e.g. `strict: true`)"
      ]
    ],
    returns: %{type: :map, description: "Map with atom keys for each decoded parameter"}
  )

  @spec decode_event!(map(), String.t(), keyword()) :: map()
  def decode_event!(log, signature, opts \\ []) do
    case decode_event(log, signature, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise "decode_event failed: #{inspect(reason)}"
    end
  end

  # --- Private helpers ---

  @doc false
  # Verifies that topics[0] matches the keccak256 hash of the canonical event signature.
  # Strips param names and "indexed" keywords to produce the canonical form.
  @spec verify_topic0(String.t(), String.t()) :: :ok | {:error, term()}
  defp verify_topic0(topic0, signature) do
    canonical = to_canonical_signature(signature)
    expected = Onchain.Hex.encode(Cartouche.Hash.keccak(canonical))

    if String.downcase(topic0) == String.downcase(expected),
      do: :ok,
      else: {:error, {:decode_error, {:topic_mismatch, expected: expected, got: topic0}}}
  end

  @doc false
  # Converts "Transfer(address indexed from, address indexed to, uint256 value)"
  # into "Transfer(address,address,uint256)" for hashing.
  @spec to_canonical_signature(String.t()) :: String.t()
  defp to_canonical_signature(signature) do
    case Regex.run(~r/^(\w+)\((.+)\)$/, signature) do
      [_, name, params_str] ->
        types =
          params_str
          |> String.split(",")
          |> Enum.map_join(",", fn param ->
            param |> String.trim() |> String.split() |> extract_type()
          end)

        "#{name}(#{types})"

      nil ->
        signature
    end
  end

  @doc false
  # Extracts the type from a parsed param like ["address", "indexed", "from"] or ["uint256", "value"].
  @spec extract_type([String.t()]) :: String.t()
  defp extract_type([type, "indexed", _name]), do: type
  defp extract_type([type, _name]), do: type
  defp extract_type([type]), do: type

  @doc false
  # Parses "Transfer(address indexed from, address indexed to, uint256 value)"
  # into [{:from, "address", true}, {:to, "address", true}, {:value, "uint256", false}]
  @spec parse_event_signature(String.t()) ::
          {:ok, [{atom(), String.t(), boolean()}]} | {:error, term()}
  defp parse_event_signature(signature) do
    case Regex.run(~r/^\w+\((.+)\)$/, signature) do
      [_, params_str] ->
        parts =
          params_str
          |> String.split(",")
          |> Enum.map(&String.trim/1)

        if length(parts) > @max_event_params do
          {:error, {:invalid_signature, signature}}
        else
          parse_params(parts)
        end

      nil ->
        # Try empty params: "EventName()"
        if Regex.match?(~r/^\w+\(\)$/, signature) do
          {:ok, []}
        else
          {:error, {:invalid_signature, signature}}
        end
    end
  end

  @doc false
  # Parses each param, bailing to {:error, {:invalid_signature, segment}} on the first
  # segment that fails the trust-boundary check in build_param/3.
  @spec parse_params([String.t()]) :: {:ok, [{atom(), String.t(), boolean()}]} | {:error, term()}
  defp parse_params(parts) do
    parts
    |> Enum.reduce_while([], fn part, acc ->
      case parse_param(part) do
        {:ok, parsed} -> {:cont, [parsed | acc]}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:error, _} = err -> err
      parsed -> {:ok, Enum.reverse(parsed)}
    end
  end

  @doc false
  # Parses a single param like "address indexed from" or "uint256 value". The name
  # interned to an atom is validated against @atom_segment first (see build_param/3) —
  # the signature is a trust boundary (@moduledoc "Security").
  @spec parse_param(String.t()) :: {:ok, {atom(), String.t(), boolean()}} | {:error, term()}
  defp parse_param(param_str) do
    case String.split(param_str) do
      [type, "indexed", name] -> build_param(name, type, true)
      [type, name] -> build_param(name, type, false)
      [type] -> build_param(type, type, false)
      _other -> build_param(param_str, param_str, false)
    end
  end

  @doc false
  # Interns the param name only after bounding it. An over-long or non-identifier-shaped
  # segment is rejected rather than minting an arbitrary atom from untrusted input.
  # sobelow_skip ["DOS.StringToAtom"]
  @spec build_param(String.t(), String.t(), boolean()) ::
          {:ok, {atom(), String.t(), boolean()}} | {:error, term()}
  defp build_param(name, type, indexed?) do
    if byte_size(name) <= @max_atom_segment_length and Regex.match?(@atom_segment, name) do
      # Reached only after the length + identifier-shape guard above and the per-call
      # param-count cap; the signature is contractually developer-controlled (@moduledoc).
      # reach:disable-next-line unsafe_atom_creation
      {:ok, {String.to_atom(name), type, indexed?}}
    else
      {:error, {:invalid_signature, name}}
    end
  end

  @doc false
  # Decodes indexed params from topics and non-indexed from data.
  @spec do_decode_event(list(), String.t() | nil, list(), list(), keyword()) ::
          {:ok, map()} | {:error, term()}
  defp do_decode_event(topics, data, indexed, non_indexed, opts) do
    # topics[0] is the event signature hash, indexed params start at topics[1]
    indexed_topics = Enum.drop(topics, 1)

    with {:ok, indexed_result} <- decode_indexed_params(indexed, indexed_topics, opts),
         {:ok, decoded_pairs} <- decode_non_indexed_params(data, non_indexed, opts) do
      {:ok, Map.new(indexed_result ++ decoded_pairs)}
    end
  end

  @doc false
  @spec decode_indexed_params(list(), list(), keyword()) ::
          {:ok, [{atom(), term()}]} | {:error, term()}
  defp decode_indexed_params(indexed, topics, opts) do
    indexed
    |> Enum.zip(topics)
    |> Enum.reduce_while([], fn {{name, type, _}, topic_hex}, acc ->
      case decode_indexed_param(topic_hex, type, opts) do
        {:ok, value} -> {:cont, [{name, value} | acc]}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> reverse_indexed()
  end

  @doc false
  @spec reverse_indexed(term()) :: {:ok, [{atom(), term()}]} | {:error, term()}
  defp reverse_indexed({:error, _} = err), do: err
  defp reverse_indexed(acc), do: {:ok, Enum.reverse(acc)}

  # Indexed dynamic types (string, bytes, arrays, tuples) are stored as keccak256(value)
  # in topics. The original value is not recoverable — return the raw topic hash.
  @dynamic_indexed_types ["string", "bytes"]

  @doc false
  # Decodes a single indexed param from a 32-byte topic.
  # Dynamic types (string, bytes, arrays, tuples) return the raw topic hash
  # since Solidity stores keccak256(value) for these, not the value itself.
  @spec decode_indexed_param(String.t(), String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defp decode_indexed_param(topic_hex, type, opts) do
    if dynamic_indexed_type?(type) do
      {:ok, topic_hex}
    else
      binary = Onchain.Hex.decode!(topic_hex)
      decode_static_indexed_value(binary, type, opts)
    end
  end

  @doc false
  # Address is left-padded in 32 bytes — take last 20. Other static value types
  # (uint256, int256, bool, bytes32, …) decode as a single ABI word.
  @spec decode_static_indexed_value(binary(), String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  defp decode_static_indexed_value(binary, "address", _opts) do
    <<_::binary-size(12), addr::binary-size(20)>> = binary
    {:ok, Onchain.Address.checksum!(addr)}
  end

  defp decode_static_indexed_value(binary, type, opts) do
    case ABI.decode("(#{type})", binary, opts) do
      {:error, {:strict_violation, _} = reason} ->
        {:error, {:decode_error, reason}}

      [value] ->
        {:ok, value}
    end
  end

  @doc false
  # Returns true for types that Solidity stores as keccak256(value) when indexed.
  # Covers string, bytes (not bytesN), and array types (e.g. uint256[]).
  # Tuple types are not supported by the signature parser (see @moduledoc Limitations).
  @spec dynamic_indexed_type?(String.t()) :: boolean()
  defp dynamic_indexed_type?(type) when type in @dynamic_indexed_types, do: true
  defp dynamic_indexed_type?(type), do: String.contains?(type, "[")

  @doc false
  # Decodes non-indexed params from the data field.
  @spec decode_non_indexed_params(String.t() | nil, list(), keyword()) ::
          {:ok, [{atom(), term()}]} | {:error, term()}
  defp decode_non_indexed_params(_data, [], _opts), do: {:ok, []}

  defp decode_non_indexed_params(nil, _params, _opts), do: {:error, {:decode_error, :missing_data_field}}

  defp decode_non_indexed_params("0x", _params, _opts), do: {:error, {:decode_error, :empty_data_field}}

  defp decode_non_indexed_params(data, params, opts) do
    type_sig = "(" <> Enum.map_join(params, ",", fn {_name, type, _} -> type end) <> ")"

    case Onchain.ABI.decode_response(type_sig, data, opts) do
      {:ok, values} ->
        pairs =
          params
          |> Enum.zip(values)
          |> Enum.map(fn {{name, type, _}, value} ->
            {name, maybe_checksum_address(value, type)}
          end)

        {:ok, pairs}

      error ->
        error
    end
  end

  @doc false
  # Checksums address values from non-indexed ABI decoding.
  @spec maybe_checksum_address(term(), String.t()) :: term()
  defp maybe_checksum_address(value, "address") when is_binary(value) and byte_size(value) == 20,
    do: Onchain.Address.checksum!(value)

  defp maybe_checksum_address(value, _type), do: value
end
