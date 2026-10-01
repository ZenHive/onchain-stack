defmodule Onchain.ABI.Event do
  @moduledoc """
  Decodes Ethereum event log data into Solidity-typed arguments.

  Splits the topic list (indexed parameters) from the data blob (non-indexed
  parameters) per the ABI specification, and optionally verifies that
  `topics[0]` matches the `keccak256` hash of the event signature.
  """

  use Descripex, namespace: "/selector"

  alias Onchain.ABI.AlloyEvents
  alias Onchain.ABI.FunctionSelector
  alias Onchain.ABI.Math
  alias Onchain.ABI.TypeEncoder

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

  # A list of ABI argument descriptors (the `:types` of a FunctionSelector).
  @typep arg_types :: [FunctionSelector.argument_type()]
  @typep topic_filter :: binary() | :any

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

      iex> Onchain.ABI.Event.encode_event_topics(
      ...>   %Onchain.ABI.FunctionSelector{
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

      iex> Onchain.ABI.Event.decode_event(
      ...>   ~h[0x00000000000000000000000000000000000000000000000000000004a817c800],
      ...>   [
      ...>     ~h[0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef],
      ...>     ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
      ...>     ~h[0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea]
      ...>   ],
      ...>   %Onchain.ABI.FunctionSelector{
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

      iex> Onchain.ABI.Event.decode_event(
      ...>   ~h[0x00000000000000000000000000000000000000000000000000000004a817c800],
      ...>   [
      ...>     ~h[0x0000000000000000000000000000000000000000000000000000000000000001],
      ...>     ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
      ...>     ~h[0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea]
      ...>   ],
      ...>   %Onchain.ABI.FunctionSelector{
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

      iex> Onchain.ABI.Event.decode_event(
      ...>   ~h[0x00000000000000000000000000000000000000000000000000000004a817c800],
      ...>   [
      ...>     ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
      ...>     ~h[0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea]
      ...>   ],
      ...>   %Onchain.ABI.FunctionSelector{
      ...>     function: "Transfer",
      ...>     types: [
      ...>       %{type: :address, name: "from", indexed: true},
      ...>       %{type: :address, name: "to", indexed: true},
      ...>       %{type: {:uint, 256}, name: "amount"},
      ...>     ]
      ...>   })
      {:error, {:topics_length_mismatch, %{got: 2, expected: 3}}}

      iex> Onchain.ABI.Event.decode_event(
      ...>   ~h[0x00000000000000000000000000000000000000000000000000000004a817c800],
      ...>   [
      ...>     ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
      ...>     ~h[0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea]
      ...>   ],
      ...>   %Onchain.ABI.FunctionSelector{
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
    AlloyEvents.decode(data, topics, function_selector, opts)
  end

  api(:decode_events, "Decode a bounded batch of event logs with shared schema compilation.",
    params: [
      logs: [kind: :value, description: "List of {data, topics} pairs"],
      function_selector: [kind: :value, description: "Parsed event selector"],
      opts: [kind: :value, default: [], description: "Event decode options"]
    ],
    returns: %{type: :list, description: "One result per input log"}
  )

  @doc "Decode a batch of event logs with one native call per bounded chunk."
  @spec decode_events([{binary(), [binary()]}], FunctionSelector.t(), keyword()) :: [term()]
  def decode_events(logs, function_selector, opts \\ []) do
    AlloyEvents.decode_batch(logs, function_selector, opts)
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

      iex> Onchain.ABI.Event.event_signature(
      ...>   %Onchain.ABI.FunctionSelector{
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
    Onchain.ABI.Alloy.signature(function_selector, :event)
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

      iex> Onchain.ABI.Event.canonical(
      ...>   %Onchain.ABI.FunctionSelector{
      ...>     function: "Transfer",
      ...>     types: [
      ...>       %{type: :address, name: "from", indexed: true},
      ...>       %{type: :address, name: "to", indexed: true},
      ...>       %{type: {:uint, 256}, name: "amount"},
      ...>     ]
      ...>   }
      ...> )
      "Transfer(address,address,uint256)"

      iex> Onchain.ABI.Event.canonical(
      ...>   %Onchain.ABI.FunctionSelector{
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

      iex> Onchain.ABI.Event.canonical(
      ...>   %Onchain.ABI.FunctionSelector{
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

      iex> Onchain.ABI.Event.canonical(
      ...>   %Onchain.ABI.FunctionSelector{
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
