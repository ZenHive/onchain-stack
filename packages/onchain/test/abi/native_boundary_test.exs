defmodule Onchain.ABI.NativeBoundaryTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Onchain.ABI.Native

  # spec-tags: NIF-2
  @tag timeout: 10_000
  test "deep schemas and values return errors promptly and leave the BEAM alive" do
    # 1,000 levels fit below 4,096 bytes: the 64 nesting-marker budget,
    # not the byte or 100,000-node budget, rejects these before alloy parses.
    depth = 1_000
    tuple_type = String.duplicate("(", depth) <> "uint256" <> String.duplicate(")", depth)
    array_type = "uint256" <> String.duplicate("[]", depth)
    tuple_value = Enum.reduce(1..depth, 1, fn _, value -> {value} end)
    array_value = Enum.reduce(1..depth, 1, fn _, value -> [value] end)

    task =
      Task.async(fn ->
        for {type, value} <- [{tuple_type, tuple_value}, {array_type, array_value}] do
          assert byte_size(type) < 4_096
          assert {:error, "type_limit"} = Native.compile(type, <<>>)
          assert {:error, "type_limit"} = Native.abi(:encode, type, value)
          assert {:error, "type_limit"} = Native.abi_small(:encode, type, value)
          assert {:error, "type_limit"} = Native.abi(:parse, type, :type)
        end

        # A valid schema also bounds traversal of a much deeper supplied value.
        assert {:ok, schema} = Native.compile("uint256" <> String.duplicate("[]", 64), <<>>)
        assert {:error, "invalid_term"} = Native.abi(:encode, schema, array_value)
        assert {:ok, <<1::256>>} = Native.abi(:encode, "uint256", 1)
      end)

    assert Task.await(task, 5_000) == {:ok, <<1::256>>}
    assert Process.alive?(self())
  end

  # spec-tags: NIF-1
  test "improper lists return errors without entering Rust's panic path" do
    for result <- [
          Native.abi(:encode, "uint256[]", [1 | 2]),
          Native.abi_small(:event, "((uint256),())", {[<<0::256>> | 2], <<>>}),
          Native.abi(:events, "((),())", [{[], <<>>} | 2])
        ] do
      assert {:error, reason} = result
      refute reason == "panic"
    end
  end

  # spec-tags: NIF-1
  property "arbitrary payloads remain contained at the native boundary" do
    check all(payload <- binary(max_length: 256), max_runs: 1_000) do
      for type <- ["uint256[]", "(bytes,bytes[])", "((uint256,string)[])"] do
        assert {tag, _} = Native.abi(:decode, type, payload)
        assert tag in [:ok, :error]
        refute Native.abi(:decode, type, payload) == {:error, "panic"}
      end
    end
  end

  # spec-tags: NIF-2
  test "excessive allocation claims are refused before decoding" do
    assert {:error, _} = Native.compile("uint256[999999999999]", <<>>)
    assert {:error, _} = Native.abi(:parse, "uint256[18446744073709551615]", :type)
    assert {:error, _} = Native.abi(:decode, "uint256[]", <<32::256, 100_001::256>>)
    assert {:error, _} = Native.abi(:decode, "(bytes)", <<1::256>>)

    for n <- [0, 19, 21, 32] do
      assert {:error, _} = Native.abi(:encode, "address", :binary.copy(<<1>>, n))
    end
  end

  test "packed address errors describe the invalid value" do
    assert_raise ArgumentError, "encode_packed address: expected 20 bytes, got 19", fn ->
      Onchain.ABI.encode_packed("f(address)", [:binary.copy(<<1>>, 19)])
    end
  end

  test "compiled schemas survive reuse and preserve encode/decode results" do
    {:ok, schema} = Native.compile("(uint256,address)", <<>>)
    value = {123, <<42::160>>}
    assert {:ok, encoded} = Native.abi(:encode, schema, value)
    assert {:ok, ^encoded} = Native.abi(:encode, "(uint256,address)", value)
    assert {:ok, ^value} = Native.abi(:decode, schema, encoded)
    assert {:error, _} = Native.abi(:encode, schema, {true, <<>>})
    assert {:error, _} = Native.abi(:decode, schema, <<1>>)
  end

  # spec-tags: NIF-3
  test "compiled events enforce topic0 and retain scheduler limits" do
    {:ok, schema} = Native.compile("((bytes32,address),(uint256))", <<1::256>>)
    log = {[<<1::256>>, <<2::256>>], <<3::256>>}
    assert {:ok, decoded} = Native.abi_small(:event, schema, log)
    assert {:ok, ^decoded} = Native.abi(:event, schema, log)

    assert {:ok, [{:error, "event_signature_mismatch"}]} =
             Native.abi(:events, schema, [{[<<9::256>>, <<2::256>>], <<3::256>>}])

    assert {:error, "event_signature_mismatch"} =
             Native.abi_small(:event, schema, {[<<9::256>>, <<2::256>>], <<3::256>>})

    assert {:error, "payload_limit"} =
             Native.abi_small(:event, schema, {[<<1::256>>, <<2::256>>], :binary.copy(<<0>>, 4097)})

    {:ok, dynamic} = Native.compile("((),(bytes))", <<>>)
    assert {:error, "dirty_required"} = Native.abi_small(:event, dynamic, {[], <<>>})
  end

  test "compilation rejects invalid terms, signatures and recursion" do
    for {type, topic} <- [{42, <<>>}, {"uint256", nil}, {"uint256", <<1>>}, {String.duplicate("(", 65), <<>>}] do
      assert {:error, _} = Native.compile(type, topic)
    end
  end

  # spec-tags: NIF-1
  property "malformed type strings return errors" do
    check all(text <- string(:alphanumeric, max_length: 128), max_runs: 1_000) do
      assert {:error, _} = Native.compile(text <> "?", <<>>)
      assert {:error, _} = Native.abi(:encode, text <> "?", 0)
      assert {:error, _} = Native.abi(:decode, text <> "?", <<>>)
    end
  end

  # spec-tags: NIF-1
  property "wrong value terms return errors" do
    check all(value <- one_of([integer(), binary(), list_of(integer(), max_length: 10)]), max_runs: 1_000) do
      assert {:error, _} = Native.abi(:encode, "bool", value)
    end
  end

  # spec-tags: NIF-1
  property "truncated words return errors" do
    check all(payload <- binary(max_length: 31), max_runs: 1_000) do
      assert {:error, _} = Native.abi(:decode, "uint256", payload)
    end
  end

  # spec-tags: NIF-1, NIF-2
  test "wrong argument kinds and excessive parser nesting return errors" do
    assert {:error, _} = Native.abi(:unknown, "uint256", 0)
    assert {:error, _} = Native.abi(:encode, 42, 0)
    assert {:error, _} = Native.abi(:decode, "uint256", :not_binary)
    assert {:error, _} = Native.abi(:encode, String.duplicate("(", 65), {})
  end

  test "recursive values, fixed arrays and full width integers round-trip" do
    type = "(int256,uint256,address,bytes4,function,(string,bool)[],uint8[2])"

    value = {
      -Integer.pow(2, 255),
      Integer.pow(2, 256) - 1,
      <<1::160>>,
      <<1, 2, 3, 4>>,
      <<2::192>>,
      [{"hello", true}, {"world", false}],
      [0, 255]
    }

    assert {:ok, encoded} = Native.abi(:encode, type, value)
    assert {:ok, ^value} = Native.abi(:decode, type, encoded)
  end

  test "integer widths, array lengths and tuple arity are checked" do
    for {type, value} <- [
          {"uint8", 256},
          {"uint256", -1},
          {"int8", 128},
          {"int8", -129},
          {"uint8[2]", [1]},
          {"(uint8,bool)", {1}},
          {"address", <<0>>}
        ] do
      assert {:error, _} = Native.abi(:encode, type, value)
    end
  end

  test "one-call and batch event decoding agree, including per-log errors" do
    schema = "((bytes32,address,address),(uint256))"
    log = {[<<1::256>>, <<2::256>>, <<3::256>>], <<4::256>>}
    assert {:ok, decoded} = Native.abi_small(:event, schema, log)
    assert decoded == {[<<1::256>>, <<2::160>>, <<3::160>>], {4}}

    assert {:ok, [{:ok, ^decoded}, {:error, _}, {:ok, ^decoded}]} =
             Native.abi(:events, schema, [log, {[], <<>>}, log])

    assert {:ok, []} = Native.abi(:events, schema, [])
  end

  # spec-tags: NIF-3
  test "normal scheduler refuses dynamic schemas, oversized data and large schemas" do
    assert {:error, "dirty_required"} = Native.abi_small(:event, "((),(bytes))", {[], <<>>})
    assert {:error, "payload_limit"} = Native.abi_small(:event, "((),(uint256))", {[], :binary.copy(<<0>>, 4097)})
    assert {:error, _} = Native.abi_small(:event, String.duplicate("(", 257), {})
    assert {:error, _} = Native.abi_small(:event, "((),())", {List.duplicate(<<0::256>>, 100), <<>>})
    assert {:error, _} = Native.abi(:events, "((),())", List.duplicate({[], <<>>}, 10_001))
  end

  # spec-tags: NIF-1
  property "malformed event words return errors on both schedulers and in batches" do
    check all(payload <- binary(max_length: 31), max_runs: 1_000) do
      schema = "((uint256),(uint256))"
      log = {[payload], <<0::256>>}
      assert {:error, _} = Native.abi_small(:event, schema, log)
      assert {:error, _} = Native.abi(:event, schema, log)
      assert {:ok, [{:error, _}]} = Native.abi(:events, schema, [log])
    end
  end
end
