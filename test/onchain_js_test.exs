defmodule OnchainJsTest do
  use ExUnit.Case

  describe "module" do
    test "exists" do
      assert Code.ensure_loaded?(OnchainJs)
    end
  end
end
