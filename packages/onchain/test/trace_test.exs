defmodule Cartouche.TraceTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.Trace.Action

  doctest Cartouche.Trace
  doctest Action

  defp base_trace_params do
    %{
      "action" => %{
        "callType" => "call",
        "from" => "0x0000000000000000000000000000000000000000",
        "gas" => "0x0",
        "input" => "0x",
        "to" => "0x0000000000000000000000000000000000000000",
        "value" => "0x0"
      },
      "subtraces" => 0,
      "type" => "call"
    }
  end

  describe "deserialize/1 — trace_address list shapes" do
    test "mixed-element list grounds the integer | <<_::160>> union" do
      params = Map.put(base_trace_params(), "traceAddress", [42, "0x1c39ba39e4735cb65978d4db400ddd70a72dc750"])
      trace = Cartouche.Trace.deserialize(params)

      assert trace.trace_address == [42, ~h[0x1c39ba39e4735cb65978d4db400ddd70a72dc750]]
    end

    test "empty trace address deserializes to []" do
      params = Map.put(base_trace_params(), "traceAddress", [])
      trace = Cartouche.Trace.deserialize(params)

      assert trace.trace_address == []
    end
  end

  describe "deserialize/1 — traceAddress absent/nil (Task 55)" do
    test "missing traceAddress key raises ArgumentError" do
      params = base_trace_params()
      refute Map.has_key?(params, "traceAddress")

      assert_raise ArgumentError, ~r/missing traceAddress/, fn ->
        Cartouche.Trace.deserialize(params)
      end
    end

    test "explicit nil traceAddress raises ArgumentError" do
      params = Map.put(base_trace_params(), "traceAddress", nil)

      assert_raise ArgumentError, ~r/missing traceAddress/, fn ->
        Cartouche.Trace.deserialize(params)
      end
    end
  end

  describe "deserialize/1 — action optional field shape (Task 16/17/18)" do
    test "call action grounds present non-nil fields and zero-value boundaries" do
      trace = base_trace_params() |> Map.put("traceAddress", []) |> Cartouche.Trace.deserialize()

      assert %Action{
               call_type: "call",
               from: ~h[0x0000000000000000000000000000000000000000],
               gas: 0,
               input: "",
               to: ~h[0x0000000000000000000000000000000000000000],
               value: 0,
               init: nil,
               refund_address: nil,
               balance: nil
             } = trace.action
    end

    test "create action deserializes fields absent from create JSON to nil" do
      params =
        base_trace_params()
        |> put_in(["action"], %{
          "from" => "0x13172ee393713fba9925a9a752341ebd31e8d9a7",
          "gas" => "0x1",
          "init" => "0x",
          "value" => "0x0"
        })
        |> Map.merge(%{"traceAddress" => [0], "type" => "create"})

      trace = Cartouche.Trace.deserialize(params)

      assert %Action{
               call_type: nil,
               init: "",
               from: ~h[0x13172ee393713fba9925a9a752341ebd31e8d9a7],
               gas: 1,
               input: nil,
               to: nil,
               value: 0,
               refund_address: nil,
               balance: nil
             } = trace.action
    end

    test "suicide action deserializes call/create-only fields to nil" do
      params =
        base_trace_params()
        |> put_in(["action"], %{
          "balance" => "0x0",
          "refundAddress" => "0x0000000000b3f879cb30fe243b4dfee438691c04"
        })
        |> Map.merge(%{"traceAddress" => [1], "type" => "suicide"})

      trace = Cartouche.Trace.deserialize(params)

      assert %Action{
               call_type: nil,
               init: nil,
               from: nil,
               gas: nil,
               input: nil,
               to: nil,
               value: nil,
               refund_address: ~h[0x0000000000b3f879cb30fe243b4dfee438691c04],
               balance: 0
             } = trace.action
    end

    test "suicide action serializes nil gas and value without raising" do
      params = %{
        "balance" => "0x0",
        "refundAddress" => "0x0000000000b3f879cb30fe243b4dfee438691c04"
      }

      assert %{
               callType: nil,
               from: nil,
               gas: nil,
               input: nil,
               init: nil,
               to: nil,
               value: nil
             } = params |> Action.deserialize() |> Action.serialize()
    end
  end

  describe "deserialize/1 — top-level optional field shape (Task 16/17/18)" do
    test "present result and transaction metadata deserialize to non-nil fields" do
      params =
        Map.merge(base_trace_params(), %{
          "blockHash" => "0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add",
          "blockNumber" => 3_068_185,
          "result" => %{
            "gasUsed" => "0x0",
            "output" => "0x",
            "code" => "0x",
            "address" => "0x0000000000000000000000000000000000000000"
          },
          "traceAddress" => [],
          "transactionHash" => "0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3",
          "transactionPosition" => 0
        })

      trace = Cartouche.Trace.deserialize(params)

      assert trace.block_hash == ~h[0x7eb25504e4c202cf3d62fd585d3e238f592c780cca82dacb2ed3cb5b38883add]
      assert trace.block_number == 3_068_185
      assert trace.gas_used == 0
      assert trace.output == ""
      assert trace.result_code == ""
      assert trace.result_address == ~h[0x0000000000000000000000000000000000000000]
      assert trace.transaction_hash == ~h[0x17104ac9d3312d8c136b7f44d4b8b47852618065ebfa534bd2d3b5ef218ca1f3]
      assert trace.transaction_position == 0
    end

    test "absent optional metadata and nil result deserialize to nil fields" do
      params =
        Map.merge(base_trace_params(), %{"error" => "contract address collision", "result" => nil, "traceAddress" => [0]})

      trace = Cartouche.Trace.deserialize(params)

      assert trace.block_hash == nil
      assert trace.block_number == nil
      assert trace.gas_used == nil
      assert trace.error == "contract address collision"
      assert trace.output == nil
      assert trace.result_code == nil
      assert trace.result_address == nil
      assert trace.transaction_hash == nil
      assert trace.transaction_position == nil
    end

    test "absent error deserializes to nil while zero subtraces stays integer zero" do
      trace = base_trace_params() |> Map.put("traceAddress", []) |> Cartouche.Trace.deserialize()

      assert trace.error == nil
      assert trace.subtraces == 0
    end
  end

  describe "deserialize_many/1" do
    test "returns a list of Trace structs each with list-shaped trace_address" do
      base = base_trace_params()

      input = [
        Map.put(base, "traceAddress", [0]),
        Map.put(base, "traceAddress", [1, 2])
      ]

      assert [
               %Cartouche.Trace{trace_address: [0]},
               %Cartouche.Trace{trace_address: [1, 2]}
             ] = Cartouche.Trace.deserialize_many(input)
    end
  end
end
