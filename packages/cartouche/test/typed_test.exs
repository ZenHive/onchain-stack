defmodule Cartouche.TypedTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Typed
  alias Cartouche.Typed.Type

  doctest Typed
  doctest Cartouche.Typed.Domain
  doctest Type

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
