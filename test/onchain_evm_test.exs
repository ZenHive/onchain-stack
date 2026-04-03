defmodule OnchainEvmTest do
  use ExUnit.Case

  test "discoverable modules are listed" do
    modules = OnchainEvm.describe()
    assert is_list(modules)
    assert length(modules) == 4
  end
end
