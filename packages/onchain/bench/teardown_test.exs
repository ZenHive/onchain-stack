defmodule Onchain.ABI.NativeTeardownTest do
  use ExUnit.Case, async: true

  test "core resources stay live through VM shutdown in each consumer" do
    {:ok, schema} = Onchain.ABI.Native.compile("(address,uint256)", <<>>)
    :persistent_term.put({__MODULE__, :retained_until_halt}, schema)
    assert {:ok, payload} = Onchain.ABI.Native.abi(:encode, schema, {<<1::160>>, 42})
    assert {:ok, {<<1::160>>, 42}} = Onchain.ABI.Native.abi(:decode, schema, payload)
    assert Onchain.ABI.encode("transfer(address,uint256)", [<<1::160>>, 42]) != <<>>
  end
end
