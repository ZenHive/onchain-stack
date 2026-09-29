defmodule Cartouche.Erc20.CallTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Erc20

  @token <<0xCC::160>>
  @address <<0xDD::160>>

  describe "balance_of/3" do
    test "defaults to unsigned integer decoding" do
      assert {:ok, 0x0C} = Erc20.Call.balance_of(@token, @address)
    end

    test "overrides caller decode option with unsigned integer decoding" do
      assert {:ok, 0x0C} = Erc20.Call.balance_of(@token, @address, decode: :hex)
    end
  end

  describe "transfer/4" do
    test "defaults to raw hex decoding" do
      assert {:ok, <<0x0C>>} = Erc20.Call.transfer(@token, @address, 100_000)
    end

    test "overrides caller decode option with raw hex decoding" do
      assert {:ok, <<0x0C>>} = Erc20.Call.transfer(@token, @address, 100_000, decode: :hex_unsigned)
    end
  end
end
