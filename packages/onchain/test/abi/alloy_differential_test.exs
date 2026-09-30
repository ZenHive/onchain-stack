for file <- ~w(type_encoder type_decoder event abi) do
  Code.require_file("../../bench/legacy/#{file}.ex", __DIR__)
end

defmodule ABI.AlloyDifferentialTest do
  use ExUnit.Case, async: true

  alias ABI.Bench.Legacy

  # spec-tags: NIF-4, NIF-5
  test "malformed decode inputs preserve legacy outcome classes" do
    cases = [
      {<<>>, [%{type: {:uint, 256}}]},
      {<<1::248>>, [%{type: :address}]},
      {<<2::256>>, [%{type: :bool}]},
      {<<1::256, 3::256, "abc", 0::232>>, [%{type: {:tuple, [%{type: :string}]}}]},
      {<<255::8, 0::248, 3::256, "abc", 0::232>>, [%{type: {:tuple, [%{type: :string}]}}]},
      {<<1::256, 3::256, "abc", 0::232>>, [%{type: {:array, :string}}]},
      {<<1::256, 0>>, [%{type: {:uint, 256}}]},
      {<<255::8, 0::248>>, [%{type: :string}]},
      {<<255::8, 0::248>>, [%{type: {:array, :address}}]}
    ]

    for {data, types} <- cases, opts <- [[], [strict: true]] do
      assert outcome(fn -> ABI.TypeDecoder.decode_raw(data, types, opts) end) ==
               outcome(fn -> Legacy.TypeDecoder.decode_raw(data, types, opts) end)
    end
  end

  test "declaration-order tails win when offset words disagree" do
    types = [%{type: {:tuple, [%{type: :bytes}, %{type: :bytes}]}}]
    payload = ABI.TypeEncoder.encode_raw([{"hello", "world"}], types)
    <<_offset::256, rest::binary>> = payload
    corrupted = <<0::256, rest::binary>>

    assert ABI.TypeDecoder.decode_raw(corrupted, types) == [{"hello", "world"}]

    assert ABI.TypeDecoder.decode_raw(corrupted, types) ==
             Legacy.TypeDecoder.decode_raw(corrupted, types)

    array = [%{type: {:array, {:tuple, [%{type: :bool}, %{type: :bytes}]}}}]
    encoded = ABI.TypeEncoder.encode_raw([[{true, "ab"}, {false, "cd"}]], array)
    <<count::256, _element_offset::256, tail::binary>> = encoded
    shifted = <<count::256, 0::256, tail::binary>>

    assert ABI.TypeDecoder.decode_raw(shifted, array) ==
             Legacy.TypeDecoder.decode_raw(shifted, array)
  end

  test "tuple and fixed-array arity failures retain their legacy outcomes" do
    for {types, values} <- [
          {[%{type: {:uint, 256}}], []},
          {[%{type: {:tuple, [%{type: {:uint, 256}}, %{type: :string}]}}], [{1, "abc", 42}]},
          {[%{type: {:array, {:uint, 256}, 2}}], [[1]]},
          {[%{type: {:array, {:uint, 256}, 2}}], [[1, 2, 3]]}
        ] do
      assert raw_outcome(fn -> ABI.TypeEncoder.encode_raw(values, types) end) ==
               raw_outcome(fn -> Legacy.TypeEncoder.encode_raw(values, types) end)
    end
  end

  defp raw_outcome(fun) do
    {:ok, fun.()}
  catch
    kind, reason -> {kind, reason}
  end

  test "wrong-length packed addresses remain errors with a clearer message" do
    for n <- [0, 19, 21, 32] do
      data = [:binary.copy(<<1>>, n)]

      assert outcome(fn -> ABI.encode_packed("f(address)", data) end) ==
               outcome(fn -> Legacy.encode_packed("f(address)", data) end)
    end
  end

  test "a non-indexed field can use the internal signature-marker name" do
    selector = ABI.FunctionSelector.decode("Marked(uint256 __abi__topic)")
    topics = [ABI.Event.event_signature(selector)]
    expected = Legacy.Event.decode_event(<<42::256>>, topics, selector)
    assert expected == {:ok, "Marked", %{"__abi__topic" => 42}}
    assert ABI.Event.decode_event(<<42::256>>, topics, selector) == expected
    assert ABI.Event.decode_events([{<<42::256>>, topics}], selector) == [expected]
  end

  test "batch event decoding preserves input order and per-log outcomes" do
    selector = ABI.FunctionSelector.decode("Transfer(address indexed from,address indexed to,uint256 value)")
    topic = ABI.Event.event_signature(selector)

    logs = [
      {<<1::256>>, [topic, <<2::256>>, <<3::256>>]},
      {<<>>, [topic, <<2::256>>, <<3::256>>]},
      {<<2::256>>, [<<0::256>>, <<2::256>>, <<3::256>>]},
      {<<3::256>>, [topic, <<4::256>>, <<5::256>>]}
    ]

    for opts <- [[], [strict: true]] do
      assert ABI.Event.decode_events(logs, selector, opts) ==
               Enum.map(logs, fn {data, topics} -> Legacy.Event.decode_event(data, topics, selector, opts) end)
    end
  end

  defp outcome(fun) do
    {:ok, fun.()}
  rescue
    e in [ABI.TypeDecoder.StrictViolation, Legacy.TypeDecoder.StrictViolation] ->
      {:error, {:strict_violation, e.detail}}

    e ->
      {:error, e.__struct__}
  end
end
