defmodule Onchain.Block.QueryTest do
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

  test "fetch and timestamp search preserve the full block and per-call transport" do
    plug = fn conn ->
      request = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
      [number, false] = request["params"]
      n = Onchain.Hex.to_integer!(number)

      block = %{
        "number" => number,
        "timestamp" => Onchain.Hex.from_integer(n * 10),
        "hash" => Onchain.Hex.encode(<<n::256>>),
        "gasLimit" => "0x100",
        "transactions" => [],
        "withdrawals" => []
      }

      Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => request["id"], "result" => block})
    end

    opts = [rpc_url: "http://block.invalid", req_options: [plug: plug]]

    assert {:ok, %Block{number: 3, hash: <<3::256>>, gas_limit: 256, withdrawals: []}} =
             Block.get_by_number(3, opts)

    assert {:ok, %Block{number: 4, timestamp: 40, gas_limit: 256}} =
             Block.find_by_timestamp(45, opts ++ [floor: 0, ceil: 10])

    assert {:error, {:timestamp_before_floor, 1}} =
             Block.find_by_timestamp(1, opts ++ [floor: 2, ceil: 10])
  end

  test "missing and pending blocks return errors" do
    for {result, reason} <- [{nil, :block_not_found}, {%{"timestamp" => "0x1"}, :pending_block}] do
      plug = fn conn ->
        request = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => request["id"], "result" => result})
      end

      assert {:error, ^reason} = Block.get_by_number("pending", req_options: [plug: plug])
    end
  end
end
