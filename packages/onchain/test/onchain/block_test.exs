defmodule Onchain.BlockTest do
  use ExUnit.Case, async: true

  import Onchain.TypeEvasion, only: [untyped: 1]

  alias Onchain.Block

  # --- Unit tests: input validation (no network calls) ---

  describe "find_by_timestamp/2 input validation" do
    test "rejects non-integer timestamp" do
      assert {:error, {:invalid_timestamp, "not_an_int"}} =
               Block.find_by_timestamp("not_an_int")
    end

    test "rejects negative timestamp" do
      assert {:error, {:invalid_timestamp, -1}} = Block.find_by_timestamp(-1)
    end

    test "rejects float timestamp" do
      assert {:error, {:invalid_timestamp, 1.5}} = Block.find_by_timestamp(1.5)
    end
  end

  describe "find_by_timestamp!/2" do
    test "raises on invalid timestamp" do
      assert_raise RuntimeError, ~r/find_by_timestamp failed/, fn ->
        Block.find_by_timestamp!(untyped("bad"))
      end
    end
  end

  describe "get_by_number!/2" do
    test "raises on RPC failure" do
      assert_raise RuntimeError, ~r/get_by_number failed/, fn ->
        Block.get_by_number!(999_999_999, rpc_url: "http://localhost:1")
      end
    end
  end
end
