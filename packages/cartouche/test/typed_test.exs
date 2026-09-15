defmodule Cartouche.TypedTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Typed
  alias Cartouche.Typed.Type

  doctest Typed
  doctest Cartouche.Typed.Domain
  doctest Type

  describe "EIP-712 conformance" do
    test "fixed bytes pad on the right while addresses and uints pad on the left" do
      assert Type.encode_data_value(<<0xCC>>, {:bytes, 32}) == <<0xCC, 0::248>>
      assert Type.encode_data_value(<<0xCC>>, {:bytes, 2}) == <<0xCC, 0, 0::240>>
      assert Type.encode_data_value(<<0xCC, 0xDD>>, {:bytes, 2}) == <<0xCC, 0xDD, 0::240>>
      assert Type.encode_data_value(<<0xCC::160>>, :address) == <<0::248, 0xCC>>
      assert Type.encode_data_value(0xCC, {:uint, 256}) == <<0::248, 0xCC>>
      assert Type.deserialize_value!("0xcc", {:bytes, 2}) == <<0xCC, 0>>
      assert Type.serialize_value(<<0xCC>>, {:bytes, 2}) == "0xcc00"

      assert_raise FunctionClauseError, fn ->
        Type.encode_data_value(<<0xCC, 0xDD, 0xEE>>, {:bytes, 2})
      end
    end

    test "array dependencies appear in encodeType" do
      types = person_array_types()
      assert Typed.encode_type("Root", types) == "Root(Person[] people)Person(string name)"
    end

    test "distinct dependencies terminate and sort by name" do
      types = %{
        "Root" => %Type{fields: [{"z", "Zebra"}, {"a", "Apple"}]},
        "Zebra" => %Type{fields: [{"stripes", {:uint, 256}}]},
        "Apple" => %Type{fields: [{"color", :string}]}
      }

      task = Task.async(fn -> Typed.encode_type("Root", types) end)
      result = Task.yield(task, 1000) || Task.shutdown(task, :brutal_kill)
      assert result == {:ok, "Root(Zebra z,Apple a)Apple(string color)Zebra(uint256 stripes)"}
    end

    test "struct arrays hash each element and support empty arrays" do
      types = person_array_types()
      people = [%{"name" => "Alice"}, %{"name" => "Bob"}]
      expected = Enum.map_join(people, &Typed.hash_struct("Person", &1, types))
      assert Type.encode_data_value(people, {:array, "Person"}, types) == Cartouche.Hash.keccak(expected)
      assert Type.encode_data_value([], {:array, "Person"}, types) == Cartouche.Hash.keccak(<<>>)
    end

    test "recursive and shared dependencies occur once, including nested arrays" do
      types = %{
        "Root" => %Type{fields: [{"z", "Zebra"}, {"a", "Apple"}, {"roots", {:array, "Root"}}]},
        "Zebra" => %Type{fields: [{"fruit", {:array, {:array, "Apple"}}}]},
        "Apple" => %Type{fields: [{"parent", {:array, "Root"}}]}
      }

      task = Task.async(fn -> Typed.encode_type("Root", types) end)
      result = Task.yield(task, 1000) || Task.shutdown(task, :brutal_kill)

      assert result ==
               {:ok, "Root(Zebra z,Apple a,Root[] roots)Apple(Root[] parent)Zebra(Apple[][] fruit)"}
    end

    test "hashes and signatures match both external implementations" do
      fixtures =
        for source <- ["ethers-6.17.0", "viem-2.55.19"] do
          "fixtures/vectors/typed/typed-#{source}.json"
          |> Path.expand(__DIR__)
          |> File.read!()
          |> Jason.decode!()
        end

      assert Enum.at(fixtures, 0)["vectors"] == Enum.at(fixtures, 1)["vectors"]

      for fixture <- fixtures, vector <- fixture["vectors"] do
        params = %{"domain" => vector["domain"], "types" => vector["types"], "value" => vector["message"]}
        typed = Typed.deserialize(params)
        assert Typed.serialize(typed) == params
        assert Typed.encode_type(vector["primaryType"], typed.types) == vector["encode_type"]

        assert to_hex(Typed.hash_struct(vector["primaryType"], typed.value, typed.types)) == vector["struct_hash"]

        encoded = Typed.encode(typed)
        assert to_hex(Cartouche.Hash.keccak(encoded)) == vector["digest"]
        signature = from_hex!(vector["signature"])
        assert to_hex(Cartouche.Recover.recover_eth(encoded, signature)) == vector["signer"]
        backend = {Cartouche.Signer.Curvy, :sign, [from_hex!(fixture["privateKey"])]}
        assert {:ok, ^signature} = Cartouche.Signer.sign_direct(encoded, from_hex!(vector["signer"]), backend, 0)
      end
    end

    test "signed integer widths round-trip and sign-extend without truncation" do
      for width <- 8..256//8 do
        type = {:int, width}
        assert Type.deserialize_type("int#{width}") == type
        assert Type.serialize_type(type) == "int#{width}"
        limit = Integer.pow(2, width - 1)

        for value <- [-limit, -1, 0, limit - 1] do
          assert Type.encode_data_value(value, type) == <<value::signed-big-256>>
          assert Type.deserialize_value!(value, type) == value
          assert Type.serialize_value(value, type) == value
        end

        for value <- [-limit - 1, limit] do
          assert_raise ArgumentError, fn -> Type.encode_data_value(value, type) end
        end
      end

      for type <- ["int", "int0", "int7", "int264"] do
        assert_raise RuntimeError, fn -> Type.deserialize_type(type) end
      end
    end

    test "unsigned integer widths reject values outside the declared range" do
      assert Type.encode_data_value(255, {:uint, 8}) == <<0::248, 255>>
      assert_raise ArgumentError, fn -> Type.encode_data_value(256, {:uint, 8}) end
      assert_raise ArgumentError, fn -> Type.encode_data_value(-1, {:uint, 256}) end
    end
  end

  defp person_array_types do
    %{
      "Root" => %Type{fields: [{"people", {:array, "Person"}}]},
      "Person" => %Type{fields: [{"name", :string}]}
    }
  end

  describe "encode_value_map/3 return-shape evidence" do
    test "encode_value_map/3 returns binary when encoding primitive fields" do
      types = %{"Message" => %Type{fields: [{"count", {:uint, 256}}]}}

      assert <<_::256>> = hash = Typed.hash_struct("Message", %{"count" => 7}, types)
      assert is_binary(hash)
      assert byte_size(hash) == 32
    end

    test "encode_value_map/3 returns binary when encoding custom-type fields" do
      types = %{
        "Envelope" => %Type{fields: [{"message", "Message"}]},
        "Message" => %Type{fields: [{"count", {:uint, 256}}]}
      }

      assert <<_::256>> = hash = Typed.hash_struct("Envelope", %{"message" => %{"count" => 7}}, types)
      assert is_binary(hash)
      assert byte_size(hash) == 32
    end

    test "serialize_value_map/3 returns map when encoding values for JSON" do
      typed = Typed.deserialize(message_params())

      assert %{"count" => 7} = Typed.serialize(typed)["value"]
    end
  end

  describe "find_type/2 return-shape evidence" do
    test "find_type/2 returns {name, %Type{}} tuple, deserialize/1 extracts the %Type{} into %Typed{}" do
      assert %Typed{value: %{"count" => 7}, types: %{"Message" => %Type{fields: [{"count", {:uint, 256}}]}}} =
               Typed.deserialize(message_params())
    end

    test "find_type/2 returns {_, _} shape to encode/1 before EIP-712 bytes are built" do
      typed = Typed.deserialize(message_params())

      assert <<0x19, 0x01, _::binary>> = Typed.encode(typed)
    end

    test "find_type/2 returns {name, %Type{}} tuple, deserialize/1 normalizes atom-keyed params first" do
      assert %Typed{value: %{"count" => 7}, types: %{"Message" => %Type{fields: [{"count", {:uint, 256}}]}}} =
               Typed.deserialize(%{
                 domain: %{"name" => "Cartouche"},
                 types: %{"Message" => [%{"name" => "count", "type" => "uint256"}]},
                 value: %{"count" => 7}
               })
    end

    test "find_type/2 raises when no type matches the value fields" do
      params = put_in(message_params(), ["value"], %{"missing" => 7})

      assert_raise RuntimeError, ~r/Failed to find matching type/, fn ->
        Typed.deserialize(params)
      end
    end

    test "find_type/2 raises when multiple types match the value fields" do
      params =
        put_in(message_params(), ["types"], %{
          "Message" => [%{"name" => "count", "type" => "uint256"}],
          "DuplicateMessage" => [%{"name" => "count", "type" => "uint256"}]
        })

      assert_raise RuntimeError, ~r/Found multiple types/, fn ->
        Typed.serialize(Typed.deserialize(params))
      end
    end
  end

  defp message_params do
    %{
      "domain" => %{"name" => "Cartouche"},
      "types" => %{"Message" => [%{"name" => "count", "type" => "uint256"}]},
      "value" => %{"count" => 7}
    }
  end
end
