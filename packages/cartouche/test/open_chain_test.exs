defmodule Cartouche.OpenChainTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  alias Cartouche.OpenChain
  alias Cartouche.OpenChain.Signatures

  doctest OpenChain
  doctest Signatures
  doctest Cartouche.OpenChain.API

  defmodule TestClient do
    @moduledoc false
    @lookup_success ~S"""
    {
      "ok": true,
      "result": {
        "event": {
          "0x08c379a0": []
        },
        "function": {
          "0x08c379a0": [
            {
              "name": "Error(string)",
              "filtered": false
            }
          ]
        }
      }
    }
    """

    @lookup_ok_false ~S"""
    {"ok": false, "error": "rate limited"}
    """

    @lookup_bad_json "not json"

    @lookup_multi ~S"""
    {
      "ok": true,
      "result": {
        "event": {},
        "function": {
          "0xee000003": [
            {"name": "Foo(uint256)", "filtered": false},
            {"name": "Bar(string)", "filtered": false}
          ]
        }
      }
    }
    """

    @lookup_empty ~S"""
    {
      "ok": true,
      "result": {
        "event": {},
        "function": {
          "0xee000004": null
        }
      }
    }
    """

    # Req function plug. The fixtures are already-encoded JSON strings and the
    # transport keeps `decode_body: false`, so each is returned verbatim with
    # `Req.Test.text/2` (using `json/2` would re-encode the string). The query
    # string comes from `Plug.Conn.query_string` rather than a Finch field.
    def call(%Plug.Conn{method: "GET", request_path: "/open-chain/signature-database/v1/lookup"} = conn) do
      query = URI.decode_query(conn.query_string || "")
      function_sigs = String.split(query["function"] || "", ",", trim: true)

      cond do
        "0xee000001" in function_sigs -> Req.Test.text(conn, @lookup_ok_false)
        "0xee000002" in function_sigs -> Req.Test.text(conn, @lookup_bad_json)
        "0xee000003" in function_sigs -> Req.Test.text(conn, @lookup_multi)
        "0xee000004" in function_sigs -> Req.Test.text(conn, @lookup_empty)
        "0xee000005" in function_sigs -> Req.Test.transport_error(conn, :nxdomain)
        true -> Req.Test.text(conn, @lookup_success)
      end
    end
  end

  describe "API.get error paths" do
    test "{\"ok\": false, ...} body returns {:error, error}" do
      assert {:error, "rate limited"} =
               OpenChain.lookup(<<0xEE, 0x00, 0x00, 0x01>>, :function)
    end

    test "non-JSON body returns {:error, decode_message}" do
      assert {:error, msg} = OpenChain.lookup(<<0xEE, 0x00, 0x00, 0x02>>, :function)
      assert is_binary(msg)
    end

    test "transport-level error propagates" do
      assert {:error, msg} = OpenChain.lookup(<<0xEE, 0x00, 0x00, 0x05>>, :function)
      assert msg =~ "nxdomain"
    end
  end

  describe "OpenChain.lookup/3" do
    test "empty results returns Signature not found" do
      assert {:error, "Signature not found"} =
               OpenChain.lookup(<<0xEE, 0x00, 0x00, 0x04>>, :function)
    end

    test "multiple results with raise_on_multiple: true returns error tuple" do
      assert {:error, msg} =
               OpenChain.lookup(<<0xEE, 0x00, 0x00, 0x03>>, :function, raise_on_multiple: true)

      assert msg =~ "Multiple matching signatures"
      assert msg =~ "Foo(uint256)"
      assert msg =~ "Bar(string)"
    end

    test "multiple results with raise_on_multiple: false (default) returns first" do
      assert {:ok, "Foo(uint256)"} =
               OpenChain.lookup(<<0xEE, 0x00, 0x00, 0x03>>, :function)
    end

    test "event lookup miss returns Signature not found" do
      # Same fixture body has the function under 0x08c379a0 but no events;
      # this exercises the :event branch of the case in lookup/3.
      assert {:error, "Signature not found"} =
               OpenChain.lookup(<<8, 195, 121, 160>>, :event)
    end
  end

  describe "lookup_error and lookup_error_and_values short-binary clauses" do
    test "lookup_error with <4-byte input returns error" do
      assert {:error, "Error must include 4-byte signature"} = OpenChain.lookup_error(<<>>)
      assert {:error, "Error must include 4-byte signature"} = OpenChain.lookup_error(<<1, 2, 3>>)
    end

    test "lookup_error_and_values with <4-byte input returns error" do
      assert {:error, "Error must include 4-byte signature"} =
               OpenChain.lookup_error_and_values(<<>>)

      assert {:error, "Error must include 4-byte signature"} =
               OpenChain.lookup_error_and_values(<<1, 2, 3>>)
    end
  end

  describe "Signatures.deserialize/1 filter behavior" do
    test "filtered: true entries are dropped" do
      input = %{
        "event" => %{},
        "function" => %{
          "0x08c379a0" => [
            %{"name" => "Error(string)", "filtered" => false},
            %{"name" => "Spam(uint256)", "filtered" => true}
          ]
        }
      }

      result = Signatures.deserialize(input)
      assert result.functions == [{<<8, 195, 121, 160>>, "Error(string)"}]
    end
  end
end
