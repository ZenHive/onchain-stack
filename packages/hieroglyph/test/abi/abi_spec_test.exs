defmodule ABI.SpecTest do
  @moduledoc """
  Spec-anchored assertions: each one pins a byte pattern that the Solidity ABI
  specification states outright, so the run fails when hieroglyph drifts from
  the spec even if encoder and decoder drift together.

  Every expected value below was derived by hand from the cited spec section
  and cross-checked with Foundry `cast` (an independent implementation) —
  never by running this library. Authorities and fetch dates are recorded in
  `docs/abi-verification-ledger.md`.

  One assertion is deliberately self-referential and is called out here so the
  claim above stays exact: the selector test compares `ABI.method_id/1` against
  a slice of `ABI.Math.kec/1`, which is this library's own digest and is itself
  a mutation site. That comparison pins the slice *position* (the leading four
  bytes, not some other window); what pins the digest itself is the external
  literal `0xa9059cbb` on the following line, and that literal is what kills
  both the `keccak-digest-reversed` and `selector-slice-shifted` mutants.

  These close the three round-trip blind spots named in roadmap task 44:

    * the *value* of a dynamic head/tail offset, which `ABI.TypeDecoder` never
      reads back (it consumes the tail sequentially), so a wrong offset is
      invisible to `decode(encode(x))`;
    * the length word that prefixes `bytes`, `string` and dynamic arrays;
    * standard-ABI padding *direction*, which is left for value types and
      right for `bytes<M>` / `string`.
  """

  use ExUnit.Case, async: true
  use ABI.Hex

  alias ABI.EthersCorpus, as: Corpus
  alias ABI.FunctionSelector
  alias ABI.Math

  # https://docs.soliditylang.org/en/latest/abi-spec.html
  #   #formal-specification-of-the-encoding
  #
  # "head(X(i)) = enc(len(head(X(1)) ... head(X(k))
  #                      tail(X(1)) ... tail(X(i-1))))"
  # -- the offset written into a dynamic argument's head slot is the byte
  # distance from the start of the enclosing tuple's encoding to that
  # argument's tail, counting ALL head slots plus every preceding tail.
  describe "head/tail offset value (spec: formal-specification-of-the-encoding)" do
    test "a single static word before a dynamic argument gives offset 0x40" do
      assert words("(uint256,string)", [{42, "hi"}]) == [
               "000000000000000000000000000000000000000000000000000000000000002a",
               "0000000000000000000000000000000000000000000000000000000000000040",
               "0000000000000000000000000000000000000000000000000000000000000002",
               "6869000000000000000000000000000000000000000000000000000000000000"
             ]
    end

    test "a static T[k] is inlined into the head and counts k slots, not one" do
      # head = [offset(bytes)] ++ 3 inlined address words, so the tail
      # starts at 4 * 32 = 0x80.
      # Counting `address[3]` as a single head slot yields 0x40 and silently
      # corrupts every downstream reader.
      assert words("(bytes,address[3])", [
               {~h[0xc4143f],
                [
                  ~h[0x1eb324b9959c03d9b256267c353894aaafc0929c],
                  ~h[0x29574f77c8a06ff506c7ea4a3b2f752fddd9fdfe],
                  ~h[0x153bf0bdca97dc7e69b782e46377a9164de3d609]
                ]}
             ]) == [
               "0000000000000000000000000000000000000000000000000000000000000080",
               "0000000000000000000000001eb324b9959c03d9b256267c353894aaafc0929c",
               "00000000000000000000000029574f77c8a06ff506c7ea4a3b2f752fddd9fdfe",
               "000000000000000000000000153bf0bdca97dc7e69b782e46377a9164de3d609",
               "0000000000000000000000000000000000000000000000000000000000000003",
               "c4143f0000000000000000000000000000000000000000000000000000000000"
             ]
    end

    test "a nested static array counts every leaf slot" do
      # uint256[2][2] occupies 4 head slots, so the string's tail is at
      # 5 * 32 = 0xa0.
      assert Enum.at(words("(uint256[2][2],string)", [{[[1, 2], [3, 4]], "hi"}]), 4) ==
               "00000000000000000000000000000000000000000000000000000000000000a0"
    end

    test "an inlined static tuple counts its members, not itself" do
      # (uint256,uint256) is static, so it occupies 2 head slots and the
      # string's tail sits at 3 * 32 = 0x60.
      assert Enum.at(words("((uint256,uint256),string)", [{{0x11, 0x22}, "Ether Token"}]), 2) ==
               "0000000000000000000000000000000000000000000000000000000000000060"
    end

    test "offsets inside a dynamic array are relative to the array's element area" do
      # enc(T[]) = enc(k) enc([X(1) ... X(k)]) -- the inner offsets skip the
      # count word and are measured from the first element head.
      assert words("(string[])", [{["alpha", "beta"]}]) == [
               "0000000000000000000000000000000000000000000000000000000000000020",
               "0000000000000000000000000000000000000000000000000000000000000002",
               "0000000000000000000000000000000000000000000000000000000000000040",
               "0000000000000000000000000000000000000000000000000000000000000080",
               "0000000000000000000000000000000000000000000000000000000000000005",
               "616c706861000000000000000000000000000000000000000000000000000000",
               "0000000000000000000000000000000000000000000000000000000000000004",
               "6265746100000000000000000000000000000000000000000000000000000000"
             ]
    end
  end

  # https://docs.soliditylang.org/en/latest/abi-spec.html
  #   #formal-specification-of-the-encoding
  #
  # "bytes, of length k: enc(X) = enc(k) pad_right(X)" and
  # "T[]: enc(X) = enc(k) enc([X[0], ..., X[k-1]])" -- the count is the number
  # of BYTES for bytes/string and the number of ELEMENTS for a dynamic array.
  describe "length word (spec: formal-specification-of-the-encoding)" do
    test "bytes carries its byte length" do
      assert Enum.at(
               words("(bytes)", [
                 {~h[0xc4143f5573e53881285d8ba65bb4606cc370c2971aad52eb87ae92b877b98b649f88b7d4cb218f2769059012]}
               ]),
               1
             ) ==
               "000000000000000000000000000000000000000000000000000000000000002c"
    end

    test "string carries its UTF-8 byte length, not its codepoint count" do
      # "é" is one codepoint and two bytes; the spec counts bytes.
      assert words("(string)", [{"é"}]) == [
               "0000000000000000000000000000000000000000000000000000000000000020",
               "0000000000000000000000000000000000000000000000000000000000000002",
               "c3a9000000000000000000000000000000000000000000000000000000000000"
             ]
    end

    test "a dynamic array carries its element count" do
      assert Enum.at(words("(uint256[])", [{[7, 8, 9]}]), 1) ==
               "0000000000000000000000000000000000000000000000000000000000000003"
    end

    test "a fixed-size array carries no length word" do
      # T[k] for static T is encoded in place with no count prefix.
      assert words("(uint256[2])", [{[7, 8]}]) == [
               "0000000000000000000000000000000000000000000000000000000000000007",
               "0000000000000000000000000000000000000000000000000000000000000008"
             ]
    end
  end

  # https://docs.soliditylang.org/en/latest/abi-spec.html
  #   #formal-specification-of-the-encoding
  #
  # "uint<M>: enc(X) is the big-endian encoding of X, padded on the
  # higher-order (left) side with zero-bytes"; "int<M>: ... padded on the
  # higher-order (left) side with 0xff bytes for negative X"; "bytes<M>:
  # enc(X) is the sequence of bytes in X padded with trailing zero-bytes".
  describe "padding direction (spec: formal-specification-of-the-encoding)" do
    test "uint is left-padded with zero bytes" do
      assert words("(uint8)", [{1}]) == ["0000000000000000000000000000000000000000000000000000000000000001"]
    end

    test "negative int is left-padded with 0xff, not with zeroes" do
      assert words("(int8)", [{-1}]) == ["ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"]
      assert words("(int16)", [{-255}]) == ["ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff01"]
    end

    test "address is left-padded into the low 20 bytes" do
      assert words("(address)", [{~h[0x1eb324b9959c03d9b256267c353894aaafc0929c]}]) == [
               "0000000000000000000000001eb324b9959c03d9b256267c353894aaafc0929c"
             ]
    end

    test "bool is left-padded to 0x...01 / 0x...00" do
      assert words("(bool,bool)", [{true, false}]) == [
               "0000000000000000000000000000000000000000000000000000000000000001",
               "0000000000000000000000000000000000000000000000000000000000000000"
             ]
    end

    test "bytes<M> is right-padded — the opposite side from the value types" do
      assert words("(bytes1)", [{~h[0xab]}]) == ["ab00000000000000000000000000000000000000000000000000000000000000"]
      assert words("(bytes3)", [{~h[0xabcdef]}]) == ["abcdef0000000000000000000000000000000000000000000000000000000000"]
    end

    test "the string tail is right-padded to the next word boundary" do
      assert Enum.at(words("(string)", [{"hi"}]), 2) ==
               "6869000000000000000000000000000000000000000000000000000000000000"
    end
  end

  # https://docs.soliditylang.org/en/latest/abi-spec.html
  #   #encoding-of-indexed-event-parameters
  #
  # "if the value of an indexed argument is a ... reference type ..., the
  # topic contains the keccak256 hash of a special in-place encoded value"
  # -- the rule covers ALL complex types, including a `T[k]` that the head/tail
  # rules classify as static.
  describe "indexed event parameters (spec: encoding-of-indexed-event-parameters)" do
    test "an indexed tuple is stored as the keccak256 of its in-place encoding" do
      selector =
        FunctionSelector.decode("E((uint256,bool) indexed p, uint256 q)")

      assert [topic0, topic1] = ABI.encode_event_topics(selector, [{42, true}])

      assert Corpus.to_hex(topic0) == "0x702837e4d0bfe8e8da17be1b373139053d5199535e67afc3ea1eea255a6e332e"
      assert Corpus.to_hex(topic1) == "0xd9ae7388d2083c2e208c0dfdf9b10bc72bbfb00d63d88b3c7fd7c315bfc1cf40"
    end

    test "an anonymous event has no topics[0], on both the encode and decode side" do
      # https://docs.soliditylang.org/en/latest/abi-spec.html#events
      # "for anonymous events ... topics[0] is not the event signature" -- the
      # log carries only the indexed-parameter topics, so the decoder must not
      # reserve a slot for a signature that was never emitted.
      selector =
        FunctionSelector.parse_specification_item(%{
          "type" => "event",
          "name" => "Anon",
          "anonymous" => true,
          "inputs" => [
            %{"name" => "who", "type" => "address", "indexed" => true},
            %{"name" => "amount", "type" => "uint256", "indexed" => false}
          ]
        })

      who = ~h[0x1eb324b9959c03d9b256267c353894aaafc0929c]

      assert [topic] = ABI.encode_event_topics(selector, [who])
      assert topic == ~h[0x0000000000000000000000001eb324b9959c03d9b256267c353894aaafc0929c]

      # A hand-written single-word payload, not `ABI.encode/2` output: this file
      # must not take its expected bytes from the library under test.
      data = ~h[0x000000000000000000000000000000000000000000000000000000000000002a]

      assert ABI.decode_event(selector, data, [topic]) ==
               {:ok, "Anon", %{"who" => who, "amount" => 42}}
    end

    test "an indexed static array is hashed too, despite being ABI-static" do
      selector = FunctionSelector.decode("E(uint256[2] indexed p, uint256 q)")

      assert [topic0, topic1] = ABI.encode_event_topics(selector, [[7, 8]])

      assert Corpus.to_hex(topic0) == "0x83109997aaecafb126f0131ce59ffe4636eaa4122c42b22b985401932bbd493a"
      assert Corpus.to_hex(topic1) == "0x24cd397636bedc6cf9b490d0edd57c769c19b367fb7d5c2344ae1ddc7d21c144"
    end
  end

  # https://docs.soliditylang.org/en/latest/abi-spec.html#function-selector
  #
  # "the first four bytes of the Keccak-256 hash of the signature" -- the
  # FIRST four, in digest order.
  describe "function selector (spec: function-selector)" do
    test "the method id is the leading four bytes of the signature digest" do
      digest = Math.kec("transfer(address,uint256)")

      assert <<expected::binary-size(4), _rest::binary>> = digest
      assert ABI.method_id("transfer(address,uint256)") == expected
      assert Corpus.to_hex(expected) == "0xa9059cbb"
    end
  end

  @spec words(String.t(), [tuple()]) :: [String.t()]
  defp words(signature, args) do
    signature
    |> ABI.encode(args)
    |> Base.encode16(case: :lower)
    |> String.to_charlist()
    |> Enum.chunk_every(64)
    |> Enum.map(&to_string/1)
  end
end
