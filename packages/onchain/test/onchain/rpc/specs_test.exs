defmodule Onchain.RPC.SpecsTest do
  use ExUnit.Case, async: true

  alias Onchain.RPC.Specs

  describe "lookup/1" do
    test "returns the parsed eth_blockNumber spec" do
      assert %{
               description: description,
               params: [],
               returns: returns
             } = Specs.lookup("eth_blockNumber")

      assert is_binary(description)
      assert description != ""
      assert is_map(returns)
    end

    test "returns nil for unknown methods" do
      assert is_nil(Specs.lookup("eth_missingMethod"))
    end
  end

  test "loads the pinned OpenRPC corpus" do
    openrpc_methods =
      Specs.all()
      |> Map.keys()
      |> Enum.reject(&(String.starts_with?(&1, "trace_") or String.starts_with?(&1, "ots_")))

    assert 78 = length(openrpc_methods)
  end

  test "loads every block-level read used by RPC codegen" do
    methods = [
      "eth_getBlockReceipts",
      "eth_getBlockTransactionCountByHash",
      "eth_getBlockTransactionCountByNumber",
      "eth_getTransactionByBlockHashAndIndex",
      "eth_getTransactionByBlockNumberAndIndex",
      "eth_getBlockAccessList"
    ]

    assert Enum.all?(methods, &is_map(Specs.lookup(&1)))
  end

  test "loads scraped Erigon trace and otterscan methods" do
    assert %{description: description, params: [], returns: %{}} = Specs.lookup("trace_call")
    assert String.contains?(description, "Erigon")
    assert %{params: [], returns: %{}} = Specs.lookup("ots_getApiLevel")
  end
end
