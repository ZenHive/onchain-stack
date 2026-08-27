defmodule ABI.EventTest do
  use ExUnit.Case, async: true
  use ABI.Hex

  alias ABI.Event
  alias ABI.FunctionSelector
  alias ABI.Math
  alias ABI.TypeEncoder

  doctest Event

  describe "encode_event_topics/2" do
    test "returns topic0 plus padded indexed value topics and :any wildcards" do
      from = ~h[0xb2b7c1795f19fbc28fda77a95e59edbb8b3709c8]

      topics =
        ABI.encode_event_topics(
          "Transfer(address indexed from,address indexed to,uint256 amount)",
          [from, :any]
        )

      assert topics == [
               Event.event_signature(
                 FunctionSelector.decode("Transfer(address indexed from,address indexed to,uint256 amount)")
               ),
               ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
               :any
             ]
    end

    test "hashes indexed reference-type values before adding topics" do
      selector = FunctionSelector.decode("Named(string indexed who,bytes indexed payload,uint256 amount)")
      payload = <<0xDE, 0xAD, 0xBE, 0xEF>>

      assert ABI.encode_event_topics(selector, ["alice", payload]) == [
               Event.event_signature(selector),
               Math.kec("alice"),
               Math.kec(payload)
             ]
    end

    test "hashes indexed arrays and tuples using their in-place event encoding" do
      selector =
        FunctionSelector.decode("Shaped(uint256[2] indexed pair,(uint256,uint256) indexed point)")

      pair_encoding =
        TypeEncoder.encode_packed([[1, 2]], [
          %{type: {:array, {:uint, 256}, 2}}
        ])

      point_encoding = ABI.encode("(uint256,uint256)", [{3, 4}])

      assert ABI.encode_event_topics(selector, [[1, 2], {3, 4}]) == [
               Event.event_signature(selector),
               Math.kec(pair_encoding),
               Math.kec(point_encoding)
             ]
    end

    test "anonymous parsed events omit topic0" do
      selector =
        FunctionSelector.parse_specification_item(%{
          "anonymous" => true,
          "inputs" => [
            %{"indexed" => true, "name" => "who", "type" => "address"}
          ],
          "name" => "Seen",
          "type" => "event"
        })

      assert ABI.encode_event_topics(selector, [<<1::160>>]) == [
               ~h[0x0000000000000000000000000000000000000000000000000000000000000001]
             ]
    end

    test "api metadata composes with decode_event and event_signature" do
      entry = Enum.find(ABI.__api__(), &(&1.name == :encode_event_topics))

      assert entry.hints.composes_with == [:decode_event, :event_signature]
    end
  end

  describe "encode_event_topics/2 argument validation" do
    test "raises when more indexed values are supplied than the event declares" do
      selector = FunctionSelector.decode("Transfer(address indexed from,address indexed to,uint256 amount)")

      assert_raise ArgumentError, ~r/got 3 indexed values for 2 indexed event parameters/, fn ->
        ABI.encode_event_topics(selector, [<<1::160>>, <<2::160>>, <<3::160>>])
      end
    end

    test "raises when a fixed-size indexed array has the wrong element count" do
      selector = FunctionSelector.decode("Shaped(uint256[2] indexed pair)")

      assert_raise ArgumentError, ~r/array size mismatch: expected 2, got 3/, fn ->
        ABI.encode_event_topics(selector, [[1, 2, 3]])
      end
    end

    test "raises when an indexed tuple has the wrong member count" do
      selector = FunctionSelector.decode("Placed((uint256,uint256) indexed point)")

      assert_raise ArgumentError, ~r/tuple size mismatch: expected 2, got 3/, fn ->
        ABI.encode_event_topics(selector, [{1, 2, 3}])
      end
    end

    test "accepts an indexed tuple given as a list, identically to a tuple" do
      selector = FunctionSelector.decode("Placed((uint256,uint256) indexed point)")

      assert ABI.encode_event_topics(selector, [[3, 4]]) ==
               ABI.encode_event_topics(selector, [{3, 4}])
    end
  end

  describe "encode_event_topics/2 nested reference members" do
    # The topic preimage of an indexed reference type is the *in-place*
    # (packed-ish) encoding of its members, never the head/tail ABI
    # encoding: each member is padded to a whole word and concatenated.
    # A member that is itself a reference type recurses through the same
    # rule, so a dynamic member contributes only its padded payload — no
    # tail offset and no length word.

    test "a dynamic member of an indexed tuple contributes only padded bytes" do
      selector = %FunctionSelector{
        function: "Nested",
        function_type: :event,
        types: [
          %{
            name: "t",
            type: {:tuple, [%{type: :string}, %{type: {:uint, 256}}]},
            indexed: true
          }
        ]
      }

      # "abc" right-padded to one word, then the uint256 word. 64 bytes —
      # the head/tail encoding of the same tuple would be 96 (offset word,
      # length word, padded payload) and hash differently.
      preimage = "abc" <> <<0::size(29 * 8)>> <> <<7::256>>
      assert byte_size(preimage) == 64

      assert ABI.encode_event_topics(selector, [{"abc", 7}]) == [
               Event.event_signature(selector),
               Math.kec(preimage)
             ]
    end

    test "a dynamic member of an indexed dynamic array is padded in place" do
      selector = %FunctionSelector{
        function: "Listed",
        function_type: :event,
        types: [%{name: "names", type: {:array, :string}, indexed: true}]
      }

      preimage = "a" <> <<0::size(31 * 8)>> <> "bb" <> <<0::size(30 * 8)>>
      assert byte_size(preimage) == 64

      assert ABI.encode_event_topics(selector, [["a", "bb"]]) == [
               Event.event_signature(selector),
               Math.kec(preimage)
             ]
    end
  end

  describe "decode_event/4 indexed/non-indexed name collision" do
    # Solidity forbids two parameters of one event sharing a name, but
    # hand-written ABI JSON can do it (and an unnamed input is keyed by its
    # positional index, which can collide with an explicit name). The
    # non-indexed value wins: it is the fully recoverable one, whereas a
    # topic slot may only carry a hash.
    test "the non-indexed value wins when both slots share a name" do
      selector = %FunctionSelector{
        function: "Dup",
        function_type: :event,
        types: [
          %{name: "x", type: :address, indexed: true},
          %{name: "x", type: {:uint, 256}, indexed: false}
        ]
      }

      topic0 = Event.event_signature(selector)
      indexed_topic = <<0::96, 1::160>>

      assert {:ok, "Dup", %{"x" => 99}} =
               ABI.decode_event(selector, <<99::256>>, [topic0, indexed_topic])
    end
  end

  describe "indexed reference-type parameters (upstream #53)" do
    # Per the Solidity ABI spec, indexed parameters of reference type
    # (all arrays — fixed-size or dynamic — plus string, bytes, and
    # tuples/structs) are stored in topics as keccak256(value) — the
    # original value is unrecoverable. The decoder returns
    # {:indexed_hash, <<32 bytes>>} for these slots.

    test "indexed string is returned as a tagged hash of the keccak topic" do
      selector = %FunctionSelector{
        function: "Named",
        types: [%{type: :string, name: "who", indexed: true}]
      }

      hashed_name = Math.kec("alice")
      sig_topic = Event.event_signature(selector)

      assert {:ok, "Named", %{"who" => {:indexed_hash, ^hashed_name}}} =
               Event.decode_event(<<>>, [sig_topic, hashed_name], selector)
    end

    test "indexed bytes is returned as a tagged hash" do
      selector = %FunctionSelector{
        function: "Tagged",
        types: [%{type: :bytes, name: "payload", indexed: true}]
      }

      hashed = Math.kec(<<0xDE, 0xAD, 0xBE, 0xEF>>)
      sig_topic = Event.event_signature(selector)

      assert {:ok, "Tagged", %{"payload" => {:indexed_hash, ^hashed}}} =
               Event.decode_event(<<>>, [sig_topic, hashed], selector)
    end

    test "indexed dynamic array is returned as a tagged hash" do
      selector = %FunctionSelector{
        function: "Batch",
        types: [%{type: {:array, {:uint, 256}}, name: "ids", indexed: true}]
      }

      # Arbitrary 32-byte hash stand-in — chain emits keccak256 of the
      # packed array encoding; from the decoder's viewpoint the bytes are
      # opaque.
      hashed = Math.kec("ids-payload")
      sig_topic = Event.event_signature(selector)

      assert {:ok, "Batch", %{"ids" => {:indexed_hash, ^hashed}}} =
               Event.decode_event(<<>>, [sig_topic, hashed], selector)
    end

    test "indexed fixed-size static array is returned as a tagged hash" do
      # `uint256[2]` is static under the ABI head/tail rule but the event
      # encoding still hashes it — this is the regression the narrower
      # `dynamic?/1` predicate missed.
      selector = %FunctionSelector{
        function: "Pair",
        types: [%{type: {:array, {:uint, 256}, 2}, name: "pair", indexed: true}]
      }

      hashed = Math.kec("pair-payload")
      sig_topic = Event.event_signature(selector)

      assert {:ok, "Pair", %{"pair" => {:indexed_hash, ^hashed}}} =
               Event.decode_event(<<>>, [sig_topic, hashed], selector)
    end

    test "indexed tuple of static members is returned as a tagged hash" do
      # A struct/tuple with all-static members is still a reference type
      # for event-indexing purposes and must be hashed.
      selector = %FunctionSelector{
        function: "Point",
        types: [
          %{
            type: {:tuple, [%{type: {:uint, 256}}, %{type: {:uint, 256}}]},
            name: "p",
            indexed: true
          }
        ]
      }

      hashed = Math.kec("point-payload")
      sig_topic = Event.event_signature(selector)

      assert {:ok, "Point", %{"p" => {:indexed_hash, ^hashed}}} =
               Event.decode_event(<<>>, [sig_topic, hashed], selector)
    end

    test "mixed static + dynamic indexed params: each slot decoded per its type" do
      selector = %FunctionSelector{
        function: "Mixed",
        types: [
          %{type: :address, name: "who", indexed: true},
          %{type: :string, name: "label", indexed: true},
          %{type: {:uint, 256}, name: "amount"}
        ]
      }

      who_topic = ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8]
      label_hash = Math.kec("promo")
      sig_topic = Event.event_signature(selector)
      data = ~h[0x00000000000000000000000000000000000000000000000000000004a817c800]

      topics = [sig_topic, who_topic, label_hash]

      assert {:ok, "Mixed", result} =
               Event.decode_event(data, topics, selector)

      assert %{
               "who" => ~h[0xb2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
               "label" => {:indexed_hash, ^label_hash},
               "amount" => 20_000_000_000
             } = result
    end
  end

  describe "error paths" do
    @transfer_selector %FunctionSelector{
      function: "Transfer",
      types: [
        %{type: :address, name: "from", indexed: true},
        %{type: :address, name: "to", indexed: true},
        %{type: {:uint, 256}, name: "amount"}
      ]
    }

    test "returns :event_signature_mismatch when topic[0] does not match" do
      data = ~h[0x00000000000000000000000000000000000000000000000000000004a817c800]
      bad = ~h[0x0000000000000000000000000000000000000000000000000000000000000001]

      topics = [
        bad,
        ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
        ~h[0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea]
      ]

      expected = Event.event_signature(@transfer_selector)
      result = Event.decode_event(data, topics, @transfer_selector)

      assert {:error, {:event_signature_mismatch, payload}} = result
      assert payload == %{expected: expected, got: bad}
    end

    test "returns :topics_length_mismatch when topic count disagrees with indexed count" do
      data = ~h[0x00000000000000000000000000000000000000000000000000000004a817c800]

      topics = [
        ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
        ~h[0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea]
      ]

      case Event.decode_event(data, topics, @transfer_selector) do
        {:error, {:topics_length_mismatch, %{got: 2, expected: 3}}} ->
          :ok

        other ->
          flunk("Expected {:error, {:topics_length_mismatch, _}}, got #{inspect(other)}")
      end
    end

    test "returns :malformed_data when non-indexed payload is too short to decode" do
      truncated_data = ~h[0x000000000000000000000000000000000000000000000000000000000000]

      topics = [
        Event.event_signature(@transfer_selector),
        ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
        ~h[0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea]
      ]

      case Event.decode_event(truncated_data, topics, @transfer_selector) do
        {:error, {:malformed_data, msg}} when is_binary(msg) ->
          :ok

        other ->
          flunk("Expected {:error, {:malformed_data, _}}, got #{inspect(other)}")
      end
    end

    test "returns strict violation when non-indexed payload is non-canonical in strict mode" do
      selector = %FunctionSelector{
        function: "Small",
        types: [%{type: {:uint, 8}, name: "amount"}]
      }

      topics = [Event.event_signature(selector)]
      bad_uint8 = <<1::248, 5>>

      assert {:error, {:strict_violation, _detail}} =
               Event.decode_event(bad_uint8, topics, selector, strict: true)
    end

    test "returns :malformed_data when an array length prefix exceeds the payload" do
      selector = %FunctionSelector{
        function: "Bulk",
        types: [%{type: {:array, {:uint, 256}}, name: "ids"}]
      }

      # Head offset of 0x20, then a length prefix claiming 2^32-1 elements with
      # no element words behind it. Without the element-count bound this
      # materializes 4 billion type maps before the decode can fail.
      data = <<32::256, 0xFFFFFFFF::256>>
      topics = [Event.event_signature(selector)]

      assert {:error, {:malformed_data, msg}} =
               Event.decode_event(data, topics, selector)

      assert msg =~ "exceeds"
    end
  end

  describe "totality of decode_event/4" do
    test "keys inputs with no name by positional index instead of raising" do
      # Solidity's own ABI JSON always emits `name` (possibly ""), but
      # hand-written or partial JSON can omit the key entirely.
      [selector] =
        ABI.parse_specification([
          %{
            "type" => "event",
            "name" => "Ping",
            "inputs" => [
              %{"type" => "address", "indexed" => true},
              %{"type" => "uint256", "indexed" => false}
            ]
          }
        ])

      who = ~h[0xb2b7c1795f19fbc28fda77a95e59edbb8b3709c8]

      topics = [
        Event.event_signature(selector),
        ~h[0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8]
      ]

      assert {:ok, "Ping", %{"0" => ^who, "1" => 20_000_000_000}} =
               Event.decode_event(<<20_000_000_000::256>>, topics, selector)
    end

    test "decode_structs: true keeps the top-level parameter-name keys" do
      selector = %FunctionSelector{
        function: "Small",
        types: [%{type: {:uint, 256}, name: "amount"}]
      }

      topics = [Event.event_signature(selector)]
      opts = [decode_structs: true]

      assert {:ok, "Small", %{"amount" => 17}} =
               Event.decode_event(<<17::256>>, topics, selector, opts)
    end

    test "decode_structs: true still renders a struct-typed parameter as a map" do
      members = [
        %{type: {:uint, 256}, name: "a"},
        %{type: :bool, name: "b"}
      ]

      selector = %FunctionSelector{
        function: "Wrapped",
        types: [%{type: {:tuple, members}, name: "point"}]
      }

      topics = [Event.event_signature(selector)]
      opts = [decode_structs: true]

      assert {:ok, "Wrapped", %{"point" => %{a: 17, b: true}}} =
               Event.decode_event(<<17::256, 1::256>>, topics, selector, opts)
    end

    test "propagates the non-interned atom ArgumentError instead of reporting malformed data" do
      selector = %FunctionSelector{
        function: "Wrapped",
        types: [
          %{
            type: {:tuple, [%{type: {:uint, 256}, name: "neverInternedZ47Q"}]},
            name: "point"
          }
        ]
      }

      topics = [Event.event_signature(selector)]

      assert_raise ArgumentError, ~r/never_interned_z47_q/, fn ->
        Event.decode_event(<<17::256>>, topics, selector, decode_structs: true)
      end
    end
  end
end
