defmodule Onchain.ChainTest do
  use ExUnit.Case, async: true

  doctest Onchain.Chain

  describe "chain_id_value/1" do
    test "defaults nil to the application chain id" do
      assert Onchain.Chain.chain_id_value(nil) == Onchain.Application.chain_id()
    end
  end
end
