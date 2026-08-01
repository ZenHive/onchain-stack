defmodule OnchainEvmTest do
  use ExUnit.Case

  test "discoverable modules are listed" do
    modules = OnchainEvm.describe()
    assert is_list(modules)
    assert match?([_, _, _, _], modules)
  end
end
