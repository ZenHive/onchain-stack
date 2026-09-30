defmodule Cartouche.Transaction.NativeTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Cartouche.Transaction
  alias Cartouche.Transaction.V1

  @fixture Path.expand("../../fixtures/vectors/ethers-6.17.0.json", __DIR__)
  @external_resource @fixture
  @vectors @fixture |> File.read!() |> Jason.decode!() |> Map.fetch!("vectors")

  test "wire fields beyond each consensus bound return the existing decoder error" do
    positions = %{
      "v1" => [{0, 64}, {1, 128}, {2, 64}, {4, 256}, {6, 64}],
      "v2930" => [{0, 64}, {1, 64}, {2, 128}, {3, 64}, {5, 256}],
      "v2" => [{0, 64}, {1, 64}, {2, 128}, {3, 128}, {4, 64}, {6, 256}],
      "v3" => [{0, 64}, {1, 64}, {2, 128}, {3, 128}, {4, 64}, {6, 256}, {9, 128}],
      "v4" => [{0, 64}, {1, 64}, {2, 128}, {3, 128}, {4, 64}, {6, 256}]
    }

    for {name, vector} <- @vectors, {index, width} <- Map.fetch!(positions, name) do
      raw = Cartouche.Hex.decode_hex!(vector["unsigned_serialized"])
      {prefix, body} = if name == "v1", do: {<<>>, raw}, else: :erlang.split_binary(raw, 1)
      fields = body |> ExRLP.decode() |> List.replace_at(index, Integer.pow(2, width))
      assert {:error, reason} = Transaction.decode(prefix <> ExRLP.encode(fields))
      assert reason =~ "invalid"
    end
  end

  test "legacy chain ID at u64 maximum is preserved without wrapping v" do
    max = Integer.pow(2, 64) - 1
    tx = V1.new(0, 0, 21_000, <<1::160>>, 0, <<>>, max)

    for tx <- [tx, %{tx | v: max * 2 + 36, r: 1, s: 2}] do
      assert {:ok, ^tx} = tx |> V1.encode() |> V1.decode()
    end

    assert_raise ArgumentError, "chain_id must be in 0..2^64-1", fn -> V1.encode(%{tx | v: max + 1}) end
  end

  test "native term input cannot truncate legacy fees" do
    tx = %{
      "type" => "0x0",
      "chainId" => "0x1",
      "nonce" => "0x0",
      "gas" => "0x5208",
      "gasPrice" => "0x100000000000000000000000000000000",
      "value" => "0x0",
      "input" => "0x",
      "to" => "0x3535353535353535353535353535353535353535"
    }

    assert {:error, "gas_price must be in 0..2^128-1"} = ABI.Native.consensus("transaction", "encode", tx)
  end

  test "native boundary rejects excessive input, nesting and schema expansion" do
    assert {:error, "payload_limit"} =
             ABI.Native.consensus("transaction", "decode", :binary.copy(<<0>>, 16 * 1024 * 1024 + 1))

    # Build nested lists as terms so each level is a list, not a byte string.
    nested = 1..66 |> Enum.reduce([], fn _, inner -> [inner] end) |> ExRLP.encode()
    assert {:error, "depth_limit"} = ABI.Native.consensus("transaction", "decode", nested)

    types =
      0..20
      |> Map.new(fn i ->
        {"T#{i}", [%{"name" => "a", "type" => "T#{i + 1}"}, %{"name" => "b", "type" => "T#{i + 1}"}]}
      end)
      |> Map.put("T21", [%{"name" => "end", "type" => "uint256"}])

    data = %{"domain" => %{}, "types" => types, "primaryType" => "T0", "message" => %{}}
    assert {:error, "value_limit"} = ABI.Native.consensus("typed", "hash", data)
    assert {:error, _} = ABI.Native.consensus("typed", "hash", "not JSON")
  end

  # spec-tags: NIF-1, NIF-2
  test "term conversion rejects malformed input and remains usable" do
    malformed = [
      nil,
      :unknown,
      [],
      %{:nonce => 0},
      %{<<255>> => "value"},
      %{"value" => <<255>>},
      %{"value" => [1 | 2]},
      %{"value" => {1, 2}},
      %{"value" => self()},
      %{"value" => make_ref()},
      %{"value" => :unknown},
      %{"value" => 1.5}
    ]

    for input <- malformed, {family, operation} <- [{"transaction", "encode"}, {"typed", "hash"}] do
      assert {:error, reason} = ABI.Native.consensus(family, operation, input)
      refute reason == "native_panic"
    end

    assert {:error, "invalid_term"} = ABI.Native.consensus(nil, "encode", %{})
    assert {:error, "invalid_term"} = ABI.Native.consensus("transaction", nil, %{})

    raw = Cartouche.Hex.decode_hex!(@vectors["v2"]["serialized"])
    assert {:ok, %{"type" => "0x2"}} = ABI.Native.consensus("transaction", "decode", raw)
    assert {:ok, tx} = Transaction.decode(raw)
    assert Transaction.encode(tx) == raw
  end

  # spec-tags: NIF-1, NIF-2
  test "term budgets count nested values and aggregate string bytes, including map keys" do
    nested = Enum.reduce(1..65, [], fn _, value -> [value] end)
    chunk = :binary.copy("x", 1024 * 1024)

    for {input, expected} <- [
          {%{"value" => nested}, "depth_limit"},
          {%{"value" => List.duplicate(nil, 100_000)}, "value_limit"},
          {%{"value" => List.duplicate(chunk, 17)}, "payload_limit"},
          {%{:binary.copy("x", 16 * 1024 * 1024 + 1) => nil}, "payload_limit"}
        ],
        family <- ["transaction", "typed"] do
      assert {:error, ^expected} = ABI.Native.consensus(family, "encode", input)
    end

    assert {:ok, _} =
             ABI.Native.consensus("transaction", "decode", Cartouche.Hex.decode_hex!(@vectors["v2"]["serialized"]))
  end

  test "valid envelopes reject trailing bytes and truncation" do
    for {_, vector} <- @vectors do
      raw = Cartouche.Hex.decode_hex!(vector["serialized"])
      assert {:error, _} = Transaction.decode(raw <> <<0>>)
      assert {:error, _} = Transaction.decode(binary_part(raw, 0, byte_size(raw) - 1))
    end
  end

  test "legacy unsigned payloads retain their nine-field public shape" do
    six_fields = [0, 1, 21_000, <<1::160>>, 0, <<>>]
    assert {:error, "invalid legacy transaction"} = V1.decode(ExRLP.encode(six_fields))
    raw = ExRLP.encode(six_fields ++ [0, 0, 0])
    assert {:ok, tx} = V1.decode(raw)
    assert V1.encode(tx) == raw
    assert {:error, "invalid legacy transaction"} = V1.decode(<<0>> <> raw)
  end

  test "EIP-712 domain chain IDs retain U256 precision" do
    typed = %Cartouche.Typed{
      domain: %Cartouche.Typed.Domain{chain_id: Integer.pow(2, 200) + 1},
      types: %{"Message" => %Cartouche.Typed.Type{fields: [{"value", {:uint, 256}}]}},
      value: %{"value" => 1}
    }

    <<0x19, 0x01, separator::binary-size(32), _::binary-size(32)>> = Cartouche.Typed.encode(typed)
    assert separator == Cartouche.Typed.domain_seperator(typed)
    assert Cartouche.Typed.Native.signing_hash(typed) == Cartouche.Hash.keccak(Cartouche.Typed.encode(typed))
  end

  property "arbitrary wire input never crashes the native boundary" do
    check all(raw <- StreamData.binary(max_length: 512), max_runs: 500) do
      native = ABI.Native.consensus("transaction", "decode", raw)
      assert {tag, _} = native
      assert tag in [:ok, :error]
      refute native == {:error, "native_panic"}

      case Transaction.decode(raw) do
        {:ok, tx} -> assert is_binary(Transaction.encode(tx))
        {:error, reason} -> refute reason == "native_panic"
      end
    end
  end
end
