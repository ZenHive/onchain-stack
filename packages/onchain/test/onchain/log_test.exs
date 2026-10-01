defmodule Onchain.ABI.ConsolidatedLogTest do
  use ExUnit.Case, async: true

  alias Onchain.Hex

  @from <<0xA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48::160>>
  @to <<0xDAC17F958D2EE523A2206206994597C13D831EC7::160>>

  test "canonical Transfer and Approval topic hashes" do
    assert Hex.encode(Onchain.ABI.event_signature("Transfer(address,address,uint256)")) ==
             "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

    assert Hex.encode(Onchain.ABI.event_signature("Approval(address,address,uint256)")) ==
             "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925"
  end

  test "indexed and non-indexed addresses remain raw bytes with string keys" do
    signature = "Transfer(address indexed from, address to, uint256 value)"
    topics = [Onchain.ABI.event_signature(signature), <<0::96, @from::binary>>]
    data = <<0::96, @to::binary, 1_000_000::256>>

    assert {:ok, "Transfer", %{"from" => @from, "to" => @to, "value" => 1_000_000}} =
             Onchain.ABI.decode_event(signature, data, topics)
  end

  test "tuple parameter commas are parsed as part of the tuple" do
    signature = "Position(address indexed owner, (uint256,address) position)"
    data = <<42::256, 0::96, @to::binary>>
    topics = [Onchain.ABI.event_signature(signature), <<0::96, @from::binary>>]

    assert {:ok, "Position", %{"owner" => @from, "position" => {42, @to}}} =
             Onchain.ABI.decode_event(signature, data, topics)
  end

  test "indexed reference types return their hash, including tuples and fixed arrays" do
    hash = :binary.copy(<<0xAB>>, 32)

    for type <- ["string", "bytes", "uint256[]", "uint256[3]", "bytes32[]", "(uint256,address)"] do
      signature = "Value(#{type} indexed key, uint256 amount)"

      assert {:ok, "Value", %{"key" => {:indexed_hash, ^hash}, "amount" => 99}} =
               Onchain.ABI.decode_event(signature, <<99::256>>, [Onchain.ABI.event_signature(signature), hash])
    end
  end

  test "indexed-only and empty events need no data" do
    signature = "OwnerChanged(address indexed newOwner)"

    assert {:ok, "OwnerChanged", %{"newOwner" => @from}} =
             Onchain.ABI.decode_event(signature, <<>>, [
               Onchain.ABI.event_signature(signature),
               <<0::96, @from::binary>>
             ])

    assert {:ok, "EmptyEvent", %{}} =
             Onchain.ABI.decode_event("EmptyEvent()", <<>>, [Onchain.ABI.event_signature("EmptyEvent()")])
  end

  test "unnamed parameters use positional string keys" do
    assert {:ok, "Deposit", %{"0" => 42}} =
             Onchain.ABI.decode_event("Deposit(uint256)", <<42::256>>, [Onchain.ABI.event_signature("Deposit(uint256)")])
  end

  test "missing and extra topics are rejected" do
    signature = "Value(uint256 indexed value)"
    topic = Onchain.ABI.event_signature(signature)

    for topics <- [[], [topic], [topic, <<1::256>>, <<2::256>>]] do
      assert {:error, {:topics_length_mismatch, _}} = Onchain.ABI.decode_event(signature, <<>>, topics)
    end
  end

  test "wrong signature and empty non-indexed data are rejected" do
    signature = "Value(uint256 value)"
    assert {:error, {:event_signature_mismatch, _}} = Onchain.ABI.decode_event(signature, <<1::256>>, [<<1::256>>])

    assert {:error, {:malformed_data, _}} =
             Onchain.ABI.decode_event(signature, <<>>, [Onchain.ABI.event_signature(signature)])
  end

  test "names remain strings beyond the removed atom parser's caps" do
    name = String.duplicate("a", 65)
    signature = "Value(uint256 #{name})"

    assert {:ok, "Value", %{^name => 1}} =
             Onchain.ABI.decode_event(signature, <<1::256>>, [Onchain.ABI.event_signature(signature)])

    params = Enum.map_join(1..33, ",", &"uint256 p#{&1}")
    signature = "Many(#{params})"
    data = :binary.copy(<<1::256>>, 33)
    assert {:ok, "Many", values} = Onchain.ABI.decode_event(signature, data, [Onchain.ABI.event_signature(signature)])
    assert map_size(values) == 33
    assert values["p33"] == 1
  end

  test "strict decoding rejects dirty indexed and non-indexed words" do
    dirty = <<1>> <> :binary.copy(<<0>>, 30) <> <<1>>

    for {signature, data, extra_topics} <- [
          {"Tiny(uint8 value)", dirty, []},
          {"Tiny(uint8 indexed value)", <<>>, [dirty]}
        ] do
      assert {:error, {:strict_violation, {:non_canonical_padding, %{type: {:uint, 8}}}}} =
               Onchain.ABI.decode_event(signature, data, [Onchain.ABI.event_signature(signature) | extra_topics],
                 strict: true
               )
    end
  end

  test "strict decoding accepts canonical data and rejects trailing bytes and oversized lengths" do
    signature = "Deposit(uint256 value)"
    topic = Onchain.ABI.event_signature(signature)
    assert {:ok, "Deposit", %{"value" => 99}} = Onchain.ABI.decode_event(signature, <<99::256>>, [topic], strict: true)

    assert {:error, {:strict_violation, {:trailing_bytes, 32}}} =
             Onchain.ABI.decode_event(signature, <<99::256, 0::256>>, [topic], strict: true)

    signature = "Note(string value)"

    assert {:error, {:strict_violation, {:length_out_of_bounds, _}}} =
             Onchain.ABI.decode_event(signature, <<32::256, 0xFFFFFFFF::256>>, [Onchain.ABI.event_signature(signature)],
               strict: true
             )
  end
end
