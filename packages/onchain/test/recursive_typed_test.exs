defmodule Onchain.RecursiveTypedTest do
  use ExUnit.Case, async: true

  alias Onchain.Typed

  @fixture Path.expand("support/fixtures/recursive_typed_before_alloy.json", __DIR__)
  @external_resource @fixture
  @oracle @fixture |> File.read!() |> Jason.decode!()

  # spec-tags: NIF-4
  test "finite recursive values retain the pre-9032 bytes and digest" do
    typed = Typed.deserialize(@oracle["input"])
    assert Typed.encode_type("Node", typed.types) == @oracle["encode_type"]
    assert Typed.encode(typed) == hex("encode")
    assert Typed.Native.signing_hash(typed) == hex("hash")
    assert Typed.hash_struct("Node", typed.value, typed.types) == hex("hash_struct")
    assert Typed.Type.encode_data_value(typed.value, "Node", typed.types) == hex("hash_struct")

    for operation <- ["encode", "hash", "hash_struct"] do
      assert {:ok, expected} = native(operation, document())
      assert expected == hex(operation)
    end

    assert {:ok, @oracle["encode_type"]} == native("encode_type", document())
  end

  test "mutual recursion and nested arrays hash each finite struct with its own type hash" do
    types = %{
      "Branch" => %Typed.Type{fields: [{"leaves", {:array, {:array, "Leaf"}}}]},
      "Leaf" => %Typed.Type{fields: [{"weight", {:int, 8}}, {"branches", {:array, "Branch"}}]}
    }

    empty_array = Onchain.Hash.keccak(<<>>)
    leaf = Onchain.Hash.keccak(Typed.encode_type("Leaf", types))
    leaf = Onchain.Hash.keccak(leaf <> <<-1::signed-256>> <> empty_array)
    nested = Onchain.Hash.keccak(Onchain.Hash.keccak(leaf))
    expected = Onchain.Hash.keccak(Onchain.Hash.keccak(Typed.encode_type("Branch", types)) <> nested)
    value = %{"leaves" => [[%{"weight" => -1, "branches" => []}]]}

    assert Typed.hash_struct("Branch", value, types) == expected
  end

  test "recursive structs hash strings, addresses, and dynamic bytes as EIP-712 words" do
    types = %{
      "Node" => %Typed.Type{
        fields: [
          {"note", :string},
          {"wallet", :address},
          {"blob", :bytes},
          {"children", {:array, "Node"}}
        ]
      }
    }

    type_hash = Onchain.Hash.keccak(Typed.encode_type("Node", types))
    empty = Onchain.Hash.keccak(<<>>)

    leaf =
      Onchain.Hash.keccak(
        type_hash <>
          Onchain.Hash.keccak("leaf") <>
          <<0::96, 2::160>> <>
          Onchain.Hash.keccak(<<>>) <>
          empty
      )

    expected =
      Onchain.Hash.keccak(
        type_hash <>
          Onchain.Hash.keccak("root") <>
          <<0::96, 1::160>> <>
          Onchain.Hash.keccak(<<0xAB, 0xCD>>) <>
          Onchain.Hash.keccak(leaf)
      )

    value = %{
      "note" => "root",
      "wallet" => <<1::160>>,
      "blob" => <<0xAB, 0xCD>>,
      "children" => [
        %{"note" => "leaf", "wallet" => <<2::160>>, "blob" => <<>>, "children" => []}
      ]
    }

    assert Typed.hash_struct("Node", value, types) == expected
  end

  test "recursive fixed arrays enforce cardinality and preserve nested-array hashing" do
    data = document()
    fields = [%{"name" => "children", "type" => "Node[][1]"}]
    data = put_in(data, ["types", "Node"], fields)
    data = Map.put(data, "message", %{"children" => [[]]})
    type_hash = Onchain.Hash.keccak("Node(Node[][1] children)")
    children = Onchain.Hash.keccak(Onchain.Hash.keccak(<<>>))
    expected = Onchain.Hash.keccak(type_hash <> children)

    assert {:ok, ^expected} = native("hash_struct", data)

    for children <- [[], [[], []]] do
      assert {:error, "array_length_mismatch"} =
               native("hash_struct", put_in(data, ["message", "children"], children))
    end
  end

  # spec-tags: NIF-1, NIF-2
  test "excessive recursive value depth returns an error and the NIF remains usable" do
    leaf = %{"value" => 0, "children" => []}
    message = Enum.reduce(1..33, leaf, fn _, child -> %{"value" => 1, "children" => [child]} end)
    assert {:error, "depth_limit"} = native("hash", Map.put(document(), "message", message))
    assert {:ok, expected} = native("hash", document())
    assert expected == hex("hash")

    typed = Typed.deserialize(@oracle["input"])

    assert_raise ArgumentError, "depth_limit", fn ->
      Typed.hash_struct("Node", message, typed.types)
    end

    assert Typed.hash_struct("Node", typed.value, typed.types) == hex("hash_struct")
  end

  # spec-tags: NIF-1
  test "malformed recursive fields return errors rather than native panics" do
    for message <- [
          %{"value" => 1},
          %{"value" => 1, "children" => %{}},
          %{"value" => "invalid", "children" => []},
          %{"value" => 1, "children" => [nil]}
        ] do
      assert {:error, reason} = native("hash", Map.put(document(), "message", message))
      refute reason == "native_panic"
    end
  end

  defp document do
    @oracle["input"]
    |> Map.put("primaryType", "Node")
    |> Map.put("message", @oracle["input"]["value"])
    |> Map.delete("value")
  end

  defp native(operation, document), do: Onchain.ABI.Native.consensus("typed", operation, document)
  defp hex(key), do: Onchain.Hex.decode_hex!(@oracle[key])
end
