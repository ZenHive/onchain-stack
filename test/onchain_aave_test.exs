defmodule OnchainAaveTest do
  use ExUnit.Case

  test "discoverable modules are listed" do
    modules = OnchainAave.describe()
    assert is_list(modules)
    assert length(modules) == 10
  end
end
