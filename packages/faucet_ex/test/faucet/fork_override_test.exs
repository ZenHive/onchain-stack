defmodule Faucet.ForkOverrideTest do
  use ExUnit.Case, async: true

  alias Faucet.ForkOverride

  @weth "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  @user "0x1111111111111111111111111111111111111111"
  @other "0x2222222222222222222222222222222222222222"

  test "mapping_slot/2 matches keccak(pad32(holder) ++ pad32(slot))" do
    expected =
      (<<0::96>> <> Base.decode16!(String.trim_leading(@user, "0x"), case: :mixed) <> <<3::256>>)
      |> Cartouche.Hash.keccak()
      |> Base.encode16(case: :lower)

    assert ForkOverride.mapping_slot(@user, 3) == "0x" <> expected
  end

  test "native/3 and erc20/5 build the Onchain.EVM state_overrides shape" do
    overrides =
      ForkOverride.new()
      |> ForkOverride.native(@user, 10 ** 18)
      |> ForkOverride.erc20(@weth, @user, 3, 5)
      |> ForkOverride.erc20(@weth, @other, 3, 7)

    assert overrides[@user] == %{"balance" => "0xDE0B6B3A7640000"}

    storage = Jason.decode!(overrides[@weth]["storage"])
    assert storage[ForkOverride.mapping_slot(@user, 3)] == "0x5"
    assert storage[ForkOverride.mapping_slot(@other, 3)] == "0x7"
  end

  test "native/3 keeps an existing storage override on the same address" do
    overrides = ForkOverride.new() |> ForkOverride.erc20(@weth, @user, 3, 1) |> ForkOverride.native(@weth, 9)
    assert %{"balance" => "0x9", "storage" => _} = overrides[@weth]
  end

  test "hex_quantity/1 is minimal" do
    assert ForkOverride.hex_quantity(0) == "0x0"
    assert ForkOverride.hex_quantity(255) == "0xFF"
  end
end
