defmodule Cartouche.ChainTest do
  use ExUnit.Case, async: true

  doctest Cartouche.Chain

  describe "chain_id_value/1" do
    test "defaults nil to the application chain id" do
      assert Cartouche.Chain.chain_id_value(nil) == Cartouche.Application.chain_id()
    end
  end
end
