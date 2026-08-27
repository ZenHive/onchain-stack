defmodule Onchain.SleuthTest do
  use ExUnit.Case, async: true

  alias Onchain.Sleuth

  describe "query/5 — input validation" do
    test "returns {:invalid_hex, _} for bad bytecode" do
      assert {:error, {:invalid_hex, "not_hex!!"}} =
               Sleuth.query("not_hex!!", "()", {}, "(uint256)")
    end

    test "returns {:encode_error, _} when ctor args don't match types" do
      # uint8 overflow is a deterministic ABI.encode failure — no RPC hit.
      assert {:error, {:encode_error, _msg}} =
               Sleuth.query("0x6080", "(uint8)", {9999}, "(uint256)")
    end
  end

  describe "query!/5" do
    test "raises on invalid bytecode" do
      assert_raise RuntimeError, ~r/Sleuth query failed/, fn ->
        Sleuth.query!("not_hex!!", "()", {}, "(uint256)")
      end
    end

    test "raises on ctor encode failure" do
      assert_raise RuntimeError, ~r/Sleuth query failed/, fn ->
        Sleuth.query!("0x6080", "(uint8)", {9999}, "(uint256)")
      end
    end
  end

  describe "descripex annotations" do
    test "exposes query/5 via __api__/0" do
      api = Sleuth.__api__()
      assert is_list(api)
      assert Enum.any?(api, fn fun -> fun.name == :query and fun.arity == 5 end)
      assert Enum.any?(api, fn fun -> fun.name == :query! and fun.arity == 5 end)
    end

    test "query/5 hints include all params" do
      fun = Enum.find(Sleuth.__api__(), fn f -> f.name == :query and f.arity == 5 end)
      param_names = Map.keys(fun.hints.params)

      for name <- [:bytecode, :constructor_types, :constructor_args, :return_type, :opts] do
        assert name in param_names
      end
    end
  end
end
