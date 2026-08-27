defmodule Cartouche.TraceCallTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  doctest Cartouche.TraceCall

  defp single_trace_map do
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
      "type" => "call",
      "traceAddress" => [0]
    }
  end

  describe "deserialize/1 — trace list shape" do
    test "empty trace list deserializes to []" do
      input = %{"output" => "0x", "trace" => []}

      assert %Cartouche.TraceCall{output: "", trace: []} = Cartouche.TraceCall.deserialize(input)
    end
  end

  describe "deserialize/1 — wrapper fields shape (Task 16/17/18)" do
    test "output decodes non-empty hex and unsupported traces stay nil" do
      input = %{
        "output" => "0x01020304",
        "stateDiff" => %{"ignored" => true},
        "trace" => [],
        "vmTrace" => %{"ignored" => true}
      }

      trace_call = Cartouche.TraceCall.deserialize(input)

      assert trace_call.output == ~h[0x01020304]
      assert trace_call.state_diff == nil
      assert trace_call.vm_trace == nil
    end

    test "empty output hex decodes to an empty binary" do
      input = %{"output" => "0x", "trace" => []}

      trace_call = Cartouche.TraceCall.deserialize(input)

      assert trace_call.output == ""
    end

    test "embedded Trace structs retain nil fields from trace_callMany payloads" do
      input = %{"output" => "0x", "trace" => [single_trace_map()]}

      trace_call = Cartouche.TraceCall.deserialize(input)

      assert [
               %Cartouche.Trace{
                 block_hash: nil,
                 block_number: nil,
                 transaction_hash: nil,
                 transaction_position: nil
               }
             ] = trace_call.trace
    end
  end

  describe "deserialize_many/1" do
    test "returns a list of TraceCall structs each with list-shaped trace" do
      input = [
        %{"output" => "0x", "trace" => [single_trace_map()]},
        %{"output" => "0x", "trace" => [single_trace_map(), single_trace_map()]}
      ]

      assert [
               %Cartouche.TraceCall{trace: [%Cartouche.Trace{trace_address: [0]}]},
               %Cartouche.TraceCall{
                 trace: [
                   %Cartouche.Trace{trace_address: [0]},
                   %Cartouche.Trace{trace_address: [0]}
                 ]
               }
             ] = Cartouche.TraceCall.deserialize_many(input)
    end
  end
end
