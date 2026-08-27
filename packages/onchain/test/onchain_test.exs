defmodule OnchainTest do
  use ExUnit.Case, async: true

  test "module exists" do
    assert {:module, Onchain} = Code.ensure_compiled(Onchain)
  end
end
