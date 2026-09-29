defmodule Cartouche.Contract.BlockNumberTest do
  @moduledoc ~S"""
  # This test is for the BlockNumber generated contract

  To regenerate the block number contract, run:

  ```sh
  mix compile && mix cartouche.gen --out test/support --prefix cartouche/contract ./test/abi/BlockNumber.json
  ```
  """
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Contract.BlockNumber

  doctest BlockNumber

  test "returns correct contract name" do
    assert BlockNumber.contract_name() == "BlockNumber"
  end

  test "exec_vm_raw" do
    assert {:ok, res} = BlockNumber.exec_vm_query_four_raw()

    assert to_hex(res) ==
             "0x" <>
               "0000000000000000000000000000000000000000000000000000000000000040" <>
               "0000000000000000000000000000000000000000000000000000000000000001" <>
               "0000000000000000000000000000000000000000000000000000000000000003" <>
               "0102030000000000000000000000000000000000000000000000000000000000"
  end

  test "exec_vm" do
    assert {:ok, res} = BlockNumber.exec_vm_query_four()
    assert res == [~h[0x010203], <<1::160>>]
  end
end
