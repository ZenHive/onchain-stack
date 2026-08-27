defmodule Onchain.MulticallTest do
  use ExUnit.Case, async: true

  alias Onchain.Multicall

  @valid_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

  describe "aggregate3/2" do
    test "returns error for invalid address in call list" do
      {:ok, calldata} = Onchain.ABI.encode_call("symbol()", [])
      assert {:error, {:invalid_address, "bad"}} = Multicall.aggregate3([{"bad", true, calldata}])
    end
  end

  describe "aggregate3!/2" do
    test "raises on invalid address" do
      {:ok, calldata} = Onchain.ABI.encode_call("symbol()", [])

      assert_raise RuntimeError, ~r/aggregate3 failed/, fn ->
        Multicall.aggregate3!([{"bad", true, calldata}])
      end
    end
  end

  describe "call_many/2" do
    test "returns error for invalid address in call list" do
      assert {:error, {:invalid_address, "bad"}} =
               Multicall.call_many([{"bad", "symbol()", [], "(string)"}])
    end
  end

  describe "call_many!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/call_many failed/, fn ->
        Multicall.call_many!([{"bad", "symbol()", [], "(string)"}])
      end
    end

    test "raises on invalid ABI signature" do
      assert_raise RuntimeError, ~r/call_many failed/, fn ->
        Multicall.call_many!([{@valid_address, "not valid!!!", [], "(string)"}])
      end
    end
  end

  describe "aggregate3/2 — invalid calldata" do
    test "returns error for non-hex calldata" do
      assert {:error, {:invalid_hex, "not_hex"}} =
               Multicall.aggregate3([{@valid_address, true, "not_hex"}])
    end
  end
end
