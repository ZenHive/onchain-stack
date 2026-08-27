defmodule Onchain.RPC.EstimateGasTest do
  # Mutates global cartouche client config; cannot run async with other RPC tests.
  use ExUnit.Case, async: false

  alias Onchain.RPC

  # Req function plug returning canned JSON-RPC responses from a queued payload,
  # capturing the decoded request so tests can assert on the serialized call
  # object. Injected via cartouche's `config :cartouche, Cartouche.RPC, plug:`.
  defmodule StubClient do
    @moduledoc false

    @stub_key :onchain_rpc_estimate_gas_stub_response
    @request_key :onchain_rpc_estimate_gas_last_request

    def call(conn) do
      decoded = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
      Process.put(@request_key, decoded)

      case Process.get(@stub_key) do
        nil -> raise "StubClient: no response queued"
        {:result, result} -> json(conn, decoded, %{"result" => result})
        {:error, payload} -> json(conn, decoded, %{"error" => payload})
      end
    end

    @spec queue_result(term()) :: :ok
    def queue_result(result) do
      Process.put(@stub_key, {:result, result})
      :ok
    end

    @spec queue_error(map()) :: :ok
    def queue_error(payload) when is_map(payload) do
      Process.put(@stub_key, {:error, payload})
      :ok
    end

    @spec last_params() :: list()
    def last_params, do: Process.get(@request_key)["params"]

    defp json(conn, %{"id" => id}, extra) do
      Req.Test.json(conn, Map.merge(%{"jsonrpc" => "2.0", "id" => id}, extra))
    end
  end

  setup_all do
    previous = Application.get_env(:cartouche, Cartouche.RPC)
    Application.put_env(:cartouche, Cartouche.RPC, plug: &StubClient.call/1)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:cartouche, Cartouche.RPC)
        config -> Application.put_env(:cartouche, Cartouche.RPC, config)
      end
    end)

    :ok
  end

  @from "0x" <> String.duplicate("ab", 20)
  @to "0x" <> String.duplicate("CD", 20)
  @data "0x18160ddd"

  describe "eth_estimate_gas/2 input validation (no transport)" do
    test "rejects a malformed :from address" do
      assert {:error, {:invalid_address, "nope"}} =
               RPC.eth_estimate_gas(%{from: "nope", to: @to, data: @data})
    end

    test "rejects a :to address of wrong byte length" do
      short = "0x" <> String.duplicate("aa", 10)

      assert {:error, {:invalid_address, ^short}} =
               RPC.eth_estimate_gas(%{from: @from, to: short, data: @data})
    end

    test "rejects :data without 0x prefix" do
      assert {:error, {:invalid_data, "18160ddd"}} =
               RPC.eth_estimate_gas(%{from: @from, to: @to, data: "18160ddd"})
    end

    test "rejects odd-length :data" do
      assert {:error, {:invalid_data, "0x123"}} =
               RPC.eth_estimate_gas(%{from: @from, to: @to, data: "0x123"})
    end

    test "rejects a negative quantity field instead of crashing" do
      assert {:error, {:invalid_quantity, "value", -1}} =
               RPC.eth_estimate_gas(%{from: @from, to: @to, value: -1})
    end

    test "rejects a non-integer quantity field instead of crashing" do
      assert {:error, {:invalid_quantity, "gas", "lots"}} =
               RPC.eth_estimate_gas(%{from: @from, to: @to, gas: "lots"})
    end
  end

  describe "eth_estimate_gas/2 success path" do
    test "decodes the quantity-hex result to an integer" do
      StubClient.queue_result("0x5208")

      assert {:ok, 21_000} =
               RPC.eth_estimate_gas(%{from: @from, to: @to, data: @data},
                 rpc_url: "http://stub.invalid"
               )
    end

    test "serializes the call object: lowercased addresses, big-hex data, quantity value" do
      StubClient.queue_result("0x5208")

      assert {:ok, _} =
               RPC.eth_estimate_gas(%{from: @from, to: @to, data: @data, value: 256},
                 rpc_url: "http://stub.invalid"
               )

      assert [call_object, "latest"] = StubClient.last_params()
      assert call_object["from"] == @from
      # mixed-case input is lowercased for the JSON-RPC call object
      assert call_object["to"] == "0x" <> String.duplicate("cd", 20)
      assert call_object["data"] == @data
      # value is quantity hex (no leading zeros): 256 == 0x100
      assert call_object["value"] == "0x100"
    end

    test "omits absent optional keys from the call object" do
      StubClient.queue_result("0x5208")

      assert {:ok, _} =
               RPC.eth_estimate_gas(%{from: @from, to: @to}, rpc_url: "http://stub.invalid")

      assert [call_object, "latest"] = StubClient.last_params()
      refute Map.has_key?(call_object, "data")
      refute Map.has_key?(call_object, "value")
    end

    test "honors an explicit :block tag" do
      StubClient.queue_result("0x5208")

      assert {:ok, _} =
               RPC.eth_estimate_gas(%{from: @from, to: @to},
                 rpc_url: "http://stub.invalid",
                 block: "pending"
               )

      assert [_call_object, "pending"] = StubClient.last_params()
    end

    test "serializes an EIP-2930 access list (binary shape) into accessList" do
      StubClient.queue_result("0x5208")

      addr = String.duplicate(<<0xAB>>, 20)
      key = String.duplicate(<<0x01>>, 32)

      assert {:ok, _} =
               RPC.eth_estimate_gas(
                 %{from: @from, to: @to, access_list: [{addr, [key]}]},
                 rpc_url: "http://stub.invalid"
               )

      assert [call_object, "latest"] = StubClient.last_params()

      assert call_object["accessList"] == [
               %{
                 "address" => "0x" <> String.duplicate("ab", 20),
                 "storageKeys" => ["0x" <> String.duplicate("01", 32)]
               }
             ]
    end

    test "omits accessList when the list is empty" do
      StubClient.queue_result("0x5208")

      assert {:ok, _} =
               RPC.eth_estimate_gas(%{from: @from, to: @to, access_list: []},
                 rpc_url: "http://stub.invalid"
               )

      assert [call_object, "latest"] = StubClient.last_params()
      refute Map.has_key?(call_object, "accessList")
    end

    test "rejects a malformed access-list entry instead of crashing" do
      assert {:error, {:invalid_access_list_entry, :nope}} =
               RPC.eth_estimate_gas(%{from: @from, to: @to, access_list: [:nope]})
    end

    test "rejects an odd-length 0x storage key instead of crashing" do
      addr = String.duplicate(<<0xAB>>, 20)

      assert {:error, {:invalid_data, "0x123"}} =
               RPC.eth_estimate_gas(%{from: @from, to: @to, access_list: [{addr, ["0x123"]}]})
    end

    test "rejects a non-hex storage key instead of crashing" do
      addr = String.duplicate(<<0xAB>>, 20)

      assert {:error, {:invalid_storage_key, :nope}} =
               RPC.eth_estimate_gas(%{from: @from, to: @to, access_list: [{addr, [:nope]}]})
    end
  end

  describe "eth_estimate_gas/2 node error" do
    test "returns an rpc_error tuple when the node reverts the estimate" do
      StubClient.queue_error(%{"code" => 3, "message" => "execution reverted"})

      assert {:error, {:rpc_error, %{code: 3}}} =
               RPC.eth_estimate_gas(%{from: @from, to: @to, data: @data},
                 rpc_url: "http://stub.invalid"
               )
    end
  end

  describe "eth_estimate_gas!/2" do
    test "returns the integer on success" do
      StubClient.queue_result("0x5208")

      assert 21_000 =
               RPC.eth_estimate_gas!(%{from: @from, to: @to, data: @data},
                 rpc_url: "http://stub.invalid"
               )
    end

    test "raises on error" do
      StubClient.queue_error(%{"code" => 3, "message" => "execution reverted"})

      assert_raise RuntimeError, ~r/eth_estimate_gas failed/, fn ->
        RPC.eth_estimate_gas!(%{from: @from, to: @to, data: @data}, rpc_url: "http://stub.invalid")
      end
    end
  end
end
