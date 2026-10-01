defmodule Onchain.ABIRegressionTest do
  use ExUnit.Case, async: true

  alias Onchain.ABI.Event
  alias Onchain.ABI.FunctionSelector

  describe "hieroglyph 1.4 adoption regressions" do
    test "indexed reference-type event params surface the topic hash" do
      selector = FunctionSelector.decode("Message(string indexed tag, uint256 value)")
      indexed_topic = :binary.copy(<<0xCD>>, 32)
      data = Onchain.ABI.encode("(uint256)", [{7}])

      assert Event.decode_event(data, [Event.event_signature(selector), indexed_topic], selector) ==
               {:ok, "Message", %{"tag" => {:indexed_hash, indexed_topic}, "value" => 7}}
    end

    test "generated call decoding preserves embedded NUL bytes in strings" do
      message = "alpha" <> <<0>> <> "omega"
      encoded = Onchain.ABI.encode("log(address,address,string)", [<<1::160>>, <<2::160>>, message])

      assert [<<1::160>>, <<2::160>>, ^message] =
               Onchain.ABI.decode("log(address,address,string)", binary_part(encoded, 4, byte_size(encoded) - 4))
    end

    test "small signed-int overflow raises at the Cartouche ABI call layer" do
      assert byte_size(Onchain.ABI.encode("set(int8)", [0])) == 36
      assert byte_size(Onchain.ABI.encode("set(int8)", [127])) == 36
      assert byte_size(Onchain.ABI.encode("set(int8)", [-128])) == 36

      assert_raise RuntimeError,
                   ~r/Data overflow encoding int, data `128` cannot fit in 8-bit signed range/,
                   fn -> Onchain.ABI.encode("set(int8)", [128]) end

      assert_raise RuntimeError,
                   ~r/Data overflow encoding int, data `-129` cannot fit in 8-bit signed range/,
                   fn -> Onchain.ABI.encode("set(int8)", [-129]) end
    end

    test "zero-length fixed dynamic arrays round-trip through ABI encode/decode" do
      selector = FunctionSelector.decode("accept(string[0] xs)")

      encoded = Onchain.ABI.encode(selector, [[]])
      assert binary_part(encoded, 0, 4) == Onchain.ABI.method_id(selector)
      assert Onchain.ABI.decode(selector, binary_part(encoded, 4, byte_size(encoded) - 4)) == [[]]
    end
  end
end
