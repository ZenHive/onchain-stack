defmodule ABI.Event do
  @moduledoc """
  Decodes Ethereum event log data into Solidity-typed arguments.

  Splits the topic list (indexed parameters) from the data blob (non-indexed
  parameters) per the ABI specification, and optionally verifies that
  `topics[0]` matches the `keccak256` hash of the event signature.
  """

  use Descripex, namespace: "/selector"

  alias ABI.FunctionSelector
  alias ABI.Math
  alias ABI.TypeDecoder
  alias ABI.TypeDecoder.StrictViolation
  alias ABI.TypeEncoder

  api(
    :decode_event,
    "Decode an Ethereum event log, splitting indexed parameters from topics and non-indexed parameters from the data blob, optionally verifying topics[0] against the event signature.",
    params: [
      data: [
        kind: :exchange_data,
        description: "Non-indexed event payload (binary); originates from the log's data field returned by eth_getLogs",
        source: "eth_getLogs"
      ],
      topics: [
        kind: :exchange_data,
        description:
          "List of topic binaries (each 32 bytes). topics[0] is the event signature hash unless check_event_signature is false",
        source: "eth_getLogs"
      ],
      function_selector: [
        kind: :value,
        description: "Pre-parsed FunctionSelector with type metadata including indexed flags"
      ],
      opts: [
        kind: :value,
        default: [],
        description:
          "Optional keyword list. Supports check_event_signature: false to skip topics[0] verification (anonymous events or pre-stripped topics), and strict: true to reject non-canonical payloads."
      ]
    ],
    returns: %{
      type: :tuple,
      description:
        "{:ok, function_name, %{name => value}} on success, or {:error, reason} where reason is a closed tagged-tuple set"
    },
    errors: [
      event_signature_mismatch:
        "topics[0] did not match keccak256(canonical_signature). Reason payload: %{expected: <<32 bytes>>, got: <<32 bytes>>}.",
      topics_length_mismatch:
        "Number of topics did not match the indexed-parameter count (plus topics[0] when check_event_signature is true). Reason payload: %{got: integer, expected: integer}.",
      malformed_data:
        "Non-indexed payload bytes failed to decode (truncated, wrong type, or otherwise inconsistent with the function_selector types). Reason payload: a human-readable string describing the underlying decode failure.",
      strict_violation: "strict: true rejected a non-canonical payload."
    ],
    composes_with: [:event_signature]
  )

  @typedoc """
  Closed error set returned by `decode_event/4`.

  * `:event_signature_mismatch` — `topics[0]` did not match `keccak256(canonical_signature)`.
  * `:topics_length_mismatch` — number of topics did not match the indexed-parameter count
    (plus the implicit `topics[0]` slot when `check_event_signature: true`).
  * `:malformed_data` — non-indexed payload failed to decode (truncated, wrong types, or
    otherwise inconsistent with `function_selector.types`).
  * `:strict_violation` — `strict: true` rejected non-canonical padding, trailing
    bytes, or string/bytes length prefixes beyond the available data.
  """
  @type decode_error ::
          {:event_signature_mismatch, %{expected: binary(), got: binary()}}
          | {:topics_length_mismatch, length_pair()}
          | {:malformed_data, String.t()}
          | {:strict_violation, term()}

  @typep length_pair :: %{got: non_neg_integer(), expected: non_neg_integer()}

  # Decoded argument map keyed by parameter name; values are decoded ABI
  # values, or `{:indexed_hash, <<32 bytes>>}` for reference-typed topics.
  @typep decoded_map :: %{optional(String.t()) => term()}
  # A list of ABI argument descriptors (the `:types` of a FunctionSelector).
  @typep arg_types :: [FunctionSelector.argument_type()]
  @typep topic_filter :: binary() | :any
  # The `topics[0]` verification failure, mirrored from `t:decode_error/0`.
  @typep sig_mismatch ::
           {:event_signature_mismatch, %{expected: binary(), got: binary()}}

  api(
    :encode_event_topics,
    "Build an eth_getLogs topic filter list from an event selector and indexed argument values.",
    params: [
      function_selector: [
        kind: :value,
        description: "Pre-parsed event FunctionSelector with type metadata including indexed flags"
      ],
      indexed_values: [
        kind: :value,
        description: "Prefix list of indexed argument values in event order. Use :any to leave a topic slot unfiltered."
      ]
    ],
    returns: %{
      type: :list,
      description:
        "Topic filter list. Non-anonymous events start with topics[0] = event_signature/1; anonymous events omit that slot. Value-type indexed args encode to one 32-byte topic, while indexed reference-type args encode to keccak256 of their in-place event encoding."
    },
    composes_with: [:decode_event, :event_signature]
  )

  @doc """
  Builds an `eth_getLogs` topic filter list for indexed event arguments.

  Pass indexed argument values in event order. Use `:any` for an unfiltered
  indexed slot. Non-anonymous events include `topics[0]`; anonymous events
  parsed from JSON ABI omit it.

  ## Examples

      iex> ABI.Event.encode_event_topics(
      ...>   %ABI.FunctionSelector{
      ...>     function: "Transfer",
      ...>     types: [
      ...>       %{type: :address, name: "from", indexed: true},
      ...>       %{type: :address, name: "to", indexed: true},
      ...>       %{type: {:uint, 256}, name: "amount"}
      ...>     ]
      ...>   },
      ...>   [~h[0xb2b7c1795f19fbc28fda77a95e59edbb8b3709c8], :any]
      ...> )
      [
        ~h[0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef],
        ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
        :any
      ]
  """
  @spec encode_event_topics(FunctionSelector.t(), [any() | :any]) ::
          [topic_filter()]
  def encode_event_topics(%FunctionSelector{} = function_selector, indexed_values) when is_list(indexed_values) do
    indexed_types = Enum.filter(function_selector.types, &Map.get(&1, :indexed, false))

    if length(indexed_values) > length(indexed_types) do
      raise ArgumentError,
            "encode_event_topics/2 got #{length(indexed_values)} indexed values " <>
              "for #{length(indexed_types)} indexed event parameters"
    end

    function_selector
    |> event_topic0()
    |> Kernel.++(encode_indexed_topic_filters(indexed_types, indexed_values))
  end

  @doc ~S"""
  Decodes an event, including handling parsing out data from topics.

  Returns `{:ok, function_name, args_map}` on success, or `{:error, reason}` where
  `reason` is one of the variants in `t:decode_error/0`.

  ## Examples

      iex> ABI.Event.decode_event(
      ...>   ~h[0x00000000000000000000000000000000000000000000000000000004a817c800],
      ...>   [
      ...>     ~h[0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef],
      ...>     ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
      ...>     ~h[0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea]
      ...>   ],
      ...>   %ABI.FunctionSelector{
      ...>     function: "Transfer",
      ...>     types: [
      ...>       %{type: :address, name: "from", indexed: true},
      ...>       %{type: :address, name: "to", indexed: true},
      ...>       %{type: {:uint, 256}, name: "amount"},
      ...>     ]
      ...>   })
      {:ok,
        "Transfer", %{
          "amount" => 20000000000,
          "from" => ~h[0xb2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
          "to" => ~h[0x7795126b3ae468f44c901287de98594198ce38ea]
      }}

      iex> ABI.Event.decode_event(
      ...>   ~h[0x00000000000000000000000000000000000000000000000000000004a817c800],
      ...>   [
      ...>     ~h[0x0000000000000000000000000000000000000000000000000000000000000001],
      ...>     ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
      ...>     ~h[0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea]
      ...>   ],
      ...>   %ABI.FunctionSelector{
      ...>     function: "Transfer",
      ...>     types: [
      ...>       %{type: :address, name: "from", indexed: true},
      ...>       %{type: :address, name: "to", indexed: true},
      ...>       %{type: {:uint, 256}, name: "amount"},
      ...>     ]
      ...>   })
      {:error,
        {:event_signature_mismatch,
         %{
           expected: ~h[0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef],
           got: ~h[0x0000000000000000000000000000000000000000000000000000000000000001]
         }}}

      iex> ABI.Event.decode_event(
      ...>   ~h[0x00000000000000000000000000000000000000000000000000000004a817c800],
      ...>   [
      ...>     ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
      ...>     ~h[0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea]
      ...>   ],
      ...>   %ABI.FunctionSelector{
      ...>     function: "Transfer",
      ...>     types: [
      ...>       %{type: :address, name: "from", indexed: true},
      ...>       %{type: :address, name: "to", indexed: true},
      ...>       %{type: {:uint, 256}, name: "amount"},
      ...>     ]
      ...>   })
      {:error, {:topics_length_mismatch, %{got: 2, expected: 3}}}

      iex> ABI.Event.decode_event(
      ...>   ~h[0x00000000000000000000000000000000000000000000000000000004a817c800],
      ...>   [
      ...>     ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
      ...>     ~h[0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea]
      ...>   ],
      ...>   %ABI.FunctionSelector{
      ...>     function: "Transfer",
      ...>     types: [
      ...>       %{type: :address, name: "from", indexed: true},
      ...>       %{type: :address, name: "to", indexed: true},
      ...>       %{type: {:uint, 256}, name: "amount"},
      ...>     ]
      ...>   },
      ...>   check_event_signature: false
      ...> )
      {:ok,
        "Transfer", %{
          "amount" => 20000000000,
          "from" => ~h[0xb2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
          "to" => ~h[0x7795126b3ae468f44c901287de98594198ce38ea]
      }}

  When the non-indexed payload bytes are truncated or wrongly typed, the underlying
  decoder previously raised; the function now wraps that path and returns
  `{:error, {:malformed_data, msg}}` with a human-readable description.

  Inputs whose type map carries no `:name` at all — possible with hand-written
  or partial ABI JSON, since Solidity always emits the key — are keyed by their
  positional index as a string (`"0"`, `"1"`, …).
  """
  @spec decode_event(binary(), [binary()], FunctionSelector.t(), keyword()) ::
          {:ok, String.t() | nil, map()} | {:error, decode_error()}
  def decode_event(data, topics, function_selector, opts \\ []) do
    do_decode_event(data, topics, function_selector, opts)
  rescue
    e in StrictViolation -> {:error, {:strict_violation, e.detail}}
  end

  @spec do_decode_event(
          binary(),
          [binary()],
          FunctionSelector.t(),
          keyword()
        ) :: {:ok, String.t() | nil, map()} | {:error, decode_error()}
  defp do_decode_event(data, topics, function_selector, opts) do
    # An anonymous event emits no topics[0], so there is neither a slot to
    # decode nor a signature to verify (abi-spec.html#events). `event_topic0/1`
    # already honours this on the encode side; folding it in here keeps the two
    # directions symmetric -- without it every anonymous log fails as
    # `:topics_length_mismatch`.
    check_event_signature =
      Keyword.get(opts, :check_event_signature, true) and
        not anonymous_event?(function_selector)

    # Solidity's own ABI JSON always emits a `name` for every event input
    # (possibly ""), but hand-written or partial ABI JSON can omit the key
    # entirely — `parse_specification_type/1` then yields a type map with no
    # `:name` at all. Key those by their positional index so the decoded map
    # stays total; without this the name-keying below raises (KeyError on the
    # topic path, FunctionClauseError on the data path), breaking this
    # function's documented "never raises" contract.
    named_types =
      Enum.with_index(function_selector.types, fn type, index ->
        Map.put_new(type, :name, Integer.to_string(index))
      end)

    # First, split the types into indexed and not indexed
    {indexed_types, non_indexed_types} =
      Enum.split_with(named_types, fn t -> Map.get(t, :indexed) end)

    indexed_types_full =
      if check_event_signature do
        [%{type: {:bytes, 32}, name: "__abi__topic"} | indexed_types]
      else
        indexed_types
      end

    expected_count = Enum.count(indexed_types_full)
    actual_count = Enum.count(topics)

    if expected_count == actual_count do
      indexed_data = decode_indexed_topics(indexed_types_full, topics, opts)

      verified =
        maybe_verify(indexed_data, function_selector, check_event_signature)

      with {:ok, idx} <- verified,
           {:ok, non_idx} <-
             decode_non_indexed(data, non_indexed_types, opts) do
        {:ok, function_selector.function, Map.merge(idx, non_idx)}
      end
    else
      lengths = %{got: actual_count, expected: expected_count}
      {:error, {:topics_length_mismatch, lengths}}
    end
  end

  @spec decode_indexed_topics(arg_types(), [binary()], keyword()) ::
          decoded_map()
  defp decode_indexed_topics(indexed_types_full, topics, opts) do
    indexed_types_full
    |> Enum.zip(topics)
    |> Map.new(fn {type, topic} ->
      {type.name, decode_indexed(type, topic, opts)}
    end)
  end

  @spec decode_non_indexed(binary(), arg_types(), keyword()) ::
          {:ok, decoded_map()} | {:error, {:malformed_data, String.t()}}
  defp decode_non_indexed(data, non_indexed_types, opts) do
    # The wrapping tuple is synthetic — it exists only to drive head/tail
    # decoding of the data blob, and THIS function owns the top-level keys
    # (parameter name -> value, merged with the indexed topics below). Strip
    # `:name` from the wrapper's members so `decode_structs: true` cannot turn
    # that synthetic level into an atom-keyed map (which would then hit
    # `Tuple.to_list/1` and surface as the caller's malformed data). Members
    # keep their own nested types intact, so a struct-typed parameter still
    # decodes as a map under `decode_structs: true`.
    wrapper_types = Enum.map(non_indexed_types, &Map.delete(&1, :name))
    tuple_type = [%{type: {:tuple, wrapper_types}}]
    [non_indexed_data] = TypeDecoder.decode_raw(data, tuple_type, opts)

    map =
      non_indexed_data
      |> Tuple.to_list()
      |> Enum.zip(non_indexed_types)
      |> Map.new(fn {res, %{name: name}} -> {name, res} end)

    {:ok, map}
  rescue
    e in StrictViolation ->
      reraise e, __STACKTRACE__

    # These are the exception types TypeDecoder.decode_raw/3 can genuinely
    # raise while walking arbitrary chain-supplied non-indexed payload bytes:
    # MatchError (truncated/malformed binary — the primary case, see the
    # "too short to decode" test), CaseClauseError (non-canonical bool byte,
    # non-strict mode), and RuntimeError (unsupported type marker, an element
    # count that cannot fit the remaining bytes, or trailing bytes after all
    # types consumed, non-strict mode). Any other exception indicates a real
    # bug rather than malformed event data, so it should propagate instead of
    # being reported as the caller's fault — notably the ArgumentError that
    # `decode_structs: true` raises for a non-interned field-name atom, which
    # carries a migration hint and raises identically out of `ABI.decode/3`.
    e in [MatchError, CaseClauseError, RuntimeError] ->
      {:error, {:malformed_data, Exception.message(e)}}
  end

  @spec maybe_verify(decoded_map(), FunctionSelector.t(), boolean()) ::
          {:ok, decoded_map()} | {:error, sig_mismatch()}
  defp maybe_verify(indexed_data, function_selector, true) do
    verify_event_signature(indexed_data, function_selector)
  end

  defp maybe_verify(indexed_data, _function_selector, false) do
    {:ok, indexed_data}
  end

  @spec decode_indexed(FunctionSelector.argument_type(), binary(), keyword()) ::
          {:indexed_hash, binary()} | term()
  defp decode_indexed(param, topic, opts) do
    if reference_type?(param.type) do
      {:indexed_hash, topic}
    else
      [value] = TypeDecoder.decode_raw(topic, [param], opts)
      value
    end
  end

  # Per the Solidity ABI spec, indexed parameters of reference types
  # (all arrays — fixed-size or dynamic — plus `string`, `bytes`, and
  # tuples/structs) are stored in topics as keccak256(value). The
  # original is unrecoverable, so we surface the hash as a tagged tuple
  # rather than decoding garbage bytes. This is broader than
  # `FunctionSelector.dynamic?/1` — that predicate answers the ABI
  # head/tail question and says `uint256[2]` is static, but the event
  # encoding rule hashes it all the same.
  @spec reference_type?(FunctionSelector.type()) :: boolean()
  defp reference_type?(:string), do: true
  defp reference_type?(:bytes), do: true
  defp reference_type?({:array, _}), do: true
  defp reference_type?({:array, _, _}), do: true
  defp reference_type?({:tuple, _}), do: true
  defp reference_type?(_), do: false

  @spec event_topic0(FunctionSelector.t()) :: [binary()]
  defp event_topic0(%FunctionSelector{} = function_selector) do
    if anonymous_event?(function_selector),
      do: [],
      else: [event_signature(function_selector)]
  end

  @spec anonymous_event?(FunctionSelector.t()) :: boolean()
  defp anonymous_event?(%FunctionSelector{function_type: :event, returns: :anonymous}), do: true

  defp anonymous_event?(_function_selector), do: false

  @spec encode_indexed_topic_filters(arg_types(), [any() | :any]) ::
          [topic_filter()]
  defp encode_indexed_topic_filters(indexed_types, indexed_values) do
    indexed_types
    |> Enum.zip(indexed_values)
    |> Enum.map(fn
      {_param, :any} -> :any
      {param, value} -> encode_indexed_topic(param, value)
    end)
  end

  @spec encode_indexed_topic(FunctionSelector.argument_type(), any()) ::
          binary()
  defp encode_indexed_topic(%{type: type} = param, value) do
    if reference_type?(type) do
      type
      |> encode_indexed_reference(value)
      |> Math.kec()
    else
      TypeEncoder.encode_raw([value], [param])
    end
  end

  @spec encode_indexed_reference(FunctionSelector.type(), any()) :: binary()
  defp encode_indexed_reference(:string, value) when is_binary(value), do: value
  defp encode_indexed_reference(:bytes, value) when is_binary(value), do: value

  defp encode_indexed_reference({:array, type, element_count}, values)
       when is_list(values) and length(values) == element_count do
    Enum.map_join(values, <<>>, &encode_indexed_member(type, &1))
  end

  defp encode_indexed_reference({:array, _type, element_count}, values) when is_list(values) do
    raise ArgumentError,
          "encode_event_topics/2 array size mismatch: expected #{element_count}, got #{length(values)}"
  end

  defp encode_indexed_reference({:array, type}, values) when is_list(values) do
    Enum.map_join(values, <<>>, &encode_indexed_member(type, &1))
  end

  defp encode_indexed_reference({:tuple, types}, values) do
    tuple_values = tuple_to_list(values)

    if length(tuple_values) != length(types) do
      raise ArgumentError,
            "encode_event_topics/2 tuple size mismatch: expected #{length(types)}, " <>
              "got #{length(tuple_values)}"
    end

    types
    |> Enum.zip(tuple_values)
    |> Enum.map_join(<<>>, fn {%{type: type}, value} ->
      encode_indexed_member(type, value)
    end)
  end

  @spec encode_indexed_member(FunctionSelector.type(), any()) :: binary()
  defp encode_indexed_member(type, value) do
    if reference_type?(type) do
      encoded = encode_indexed_reference(type, value)
      Math.pad(encoded, byte_size(encoded), :right)
    else
      TypeEncoder.encode_raw([value], [%{type: type}])
    end
  end

  @spec tuple_to_list(tuple() | [any()]) :: [any()]
  defp tuple_to_list(values) when is_tuple(values), do: Tuple.to_list(values)
  defp tuple_to_list(values) when is_list(values), do: values

  @spec verify_event_signature(decoded_map(), FunctionSelector.t()) ::
          {:ok, decoded_map()} | {:error, sig_mismatch()}
  defp verify_event_signature(indexed_data, function_selector) do
    {got, res} = Map.pop(indexed_data, "__abi__topic")
    expected = event_signature(function_selector)

    if got == expected do
      {:ok, res}
    else
      {:error, {:event_signature_mismatch, %{expected: expected, got: got}}}
    end
  end

  api(
    :event_signature,
    "Compute the keccak-256 hash of the event's canonical signature, used as topics[0] in event logs.",
    params: [
      function_selector: [kind: :value, description: "Event FunctionSelector with name and type metadata"]
    ],
    returns: %{type: :binary, description: "32-byte topic hash matching the first topic of an emitted log for this event"},
    composes_with: [:decode_event]
  )

  @doc ~S"""
  Returns the signature of an event, i.e. the first item that appears
  in an Ethereum log for this event.

  ## Examples

      iex> ABI.Event.event_signature(
      ...>   %ABI.FunctionSelector{
      ...>     function: "Transfer",
      ...>     types: [
      ...>       %{type: :address, name: "from", indexed: true},
      ...>       %{type: :address, name: "to", indexed: true},
      ...>       %{type: {:uint, 256}, name: "amount"},
      ...>     ]
      ...>   }
      ...> )
      ...> |> to_hex()
      "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
  """
  @spec event_signature(FunctionSelector.t()) :: binary()
  def event_signature(function_selector) do
    function_selector
    |> FunctionSelector.encode()
    |> Math.kec()
  end

  api(
    :canonical,
    "Render the canonical signature string of an event for hashing or display, optionally including indexed and parameter-name annotations.",
    params: [
      function_selector: [kind: :value, description: "Event FunctionSelector with name and type metadata"],
      opts: [
        kind: :value,
        default: [],
        description:
          "Optional keyword list. Supports indexed: true to include the indexed keyword on indexed parameters, and names: true to include parameter names"
      ]
    ],
    returns: %{
      type: :string,
      description:
        "Canonical signature string such as Transfer(address,address,uint256) or with indexed/names annotations applied"
    }
  )

  @doc ~S"""
  Returns the canonical form of this event topic. Pass in `indexed: true`
  to include "indexed" keywords.

  ## Examples

      iex> ABI.Event.canonical(
      ...>   %ABI.FunctionSelector{
      ...>     function: "Transfer",
      ...>     types: [
      ...>       %{type: :address, name: "from", indexed: true},
      ...>       %{type: :address, name: "to", indexed: true},
      ...>       %{type: {:uint, 256}, name: "amount"},
      ...>     ]
      ...>   }
      ...> )
      "Transfer(address,address,uint256)"

      iex> ABI.Event.canonical(
      ...>   %ABI.FunctionSelector{
      ...>     function: "Transfer",
      ...>     types: [
      ...>       %{type: :address, name: "from", indexed: true},
      ...>       %{type: :address, name: "to", indexed: true},
      ...>       %{type: {:uint, 256}, name: "amount"},
      ...>     ]
      ...>   },
      ...>   names: true
      ...> )
      "Transfer(address from,address to,uint256 amount)"

      iex> ABI.Event.canonical(
      ...>   %ABI.FunctionSelector{
      ...>     function: "Transfer",
      ...>     types: [
      ...>       %{type: :address, name: "from", indexed: true},
      ...>       %{type: :address, name: "to", indexed: true},
      ...>       %{type: {:uint, 256}, name: "amount"},
      ...>     ]
      ...>   },
      ...>   indexed: true
      ...> )
      "Transfer(address indexed,address indexed,uint256)"

      iex> ABI.Event.canonical(
      ...>   %ABI.FunctionSelector{
      ...>     function: "Transfer",
      ...>     types: [
      ...>       %{type: :address, name: "from", indexed: true},
      ...>       %{type: :address, name: "to", indexed: true},
      ...>       %{type: {:uint, 256}, name: "amount"},
      ...>     ]
      ...>   },
      ...>   indexed: true,
      ...>   names: true
      ...> )
      "Transfer(address indexed from,address indexed to,uint256 amount)"
  """
  @spec canonical(FunctionSelector.t(), keyword()) :: String.t()
  def canonical(function_selector, opts \\ []) do
    indexed = Keyword.get(opts, :indexed, false)
    names = Keyword.get(opts, :names, false)

    FunctionSelector.encode(function_selector, indexed, names)
  end
end
