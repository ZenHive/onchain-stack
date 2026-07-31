defmodule Onchain.Tempo.RPCTest do
  use ExUnit.Case, async: true

  alias Onchain.Tempo.RPC
  alias Onchain.Tempo.Transaction
  alias Onchain.Tempo.Transaction.Builder

  # Hardhat default accounts (testnet only, no security concern).
  @client_key Base.decode16!("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", case: :lower)
  @fee_payer_key Base.decode16!("59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d", case: :lower)
  @fee_token Base.decode16!("20c0000000000000000000000000000000000000", case: :lower)
  @token "0x20c0000000000000000000000000000000000000"
  @recipient "0x70997970c51812dc3a010c7d01b50e0d17dc79c8"

  defp cosigned_hex do
    {:ok, raw} =
      Builder.build_fee_payer_transfer(
        private_key: @client_key,
        token: @token,
        recipient: @recipient,
        amount: 1,
        chain_id: 42_431,
        rpc_url: "http://localhost",
        nonce: 1,
        gas_limit: 100_000
      )

    {:ok, tx} = Transaction.deserialize(raw)
    {:ok, cosigned} = Transaction.cosign_fee_payer(tx, @fee_payer_key, @fee_token)
    cosigned.raw
  end

  describe "parse_receipt/1" do
    test "parses a successful receipt" do
      raw = %{
        "status" => "0x1",
        "logs" => [
          %{
            "address" => "0x20c0000000000000000000000000000000000000",
            "topics" => ["0xabc123"],
            "data" => "0x",
            "blockNumber" => "0xa",
            "transactionHash" => "0xdeadbeef",
            "logIndex" => "0x0"
          }
        ]
      }

      receipt = RPC.parse_receipt(raw)
      assert receipt.status == 1

      assert [log] = receipt.logs
      assert log.address == "0x20c0000000000000000000000000000000000000"
      assert log.topics == ["0xabc123"]
      assert log.block_number == 10
      assert log.log_index == 0
    end

    test "parses a reverted receipt" do
      raw = %{"status" => "0x0", "logs" => []}
      receipt = RPC.parse_receipt(raw)
      assert receipt.status == 0
      assert receipt.logs == []
    end

    test "handles missing logs key" do
      raw = %{"status" => "0x1"}
      receipt = RPC.parse_receipt(raw)
      assert receipt.logs == []
    end

    test "handles nil status" do
      raw = %{"status" => nil, "logs" => []}
      receipt = RPC.parse_receipt(raw)
      assert receipt.status == nil
    end
  end

  describe "broadcast_async/3" do
    test "returns ok with tx hash on success" do
      Req.Test.stub(:tempo_rpc, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["method"] == "eth_sendRawTransaction"

        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => "0xdeadbeef"})
      end)

      assert {:ok, "0xdeadbeef"} =
               RPC.broadcast_async("0x76abc", "http://localhost", req_options: [plug: {Req.Test, :tempo_rpc}])
    end

    test "returns error on RPC error response" do
      Req.Test.stub(:tempo_rpc_err, fn conn ->
        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "error" => %{"code" => -32_000, "message" => "nonce too low"}
        })
      end)

      assert {:error, msg} =
               RPC.broadcast_async("0x76abc", "http://localhost", req_options: [plug: {Req.Test, :tempo_rpc_err}])

      assert msg =~ "nonce too low"
    end
  end

  describe "broadcast_sync/3" do
    test "returns ok with tx hash and parsed receipt" do
      Req.Test.stub(:tempo_rpc_sync, fn conn ->
        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => %{
            "transactionHash" => "0xbeef",
            "status" => "0x1",
            "logs" => []
          }
        })
      end)

      assert {:ok, "0xbeef", receipt} =
               RPC.broadcast_sync("0x76abc", "http://localhost", req_options: [plug: {Req.Test, :tempo_rpc_sync}])

      assert receipt.status == 1
    end
  end

  describe "fetch_receipt/3" do
    test "returns ok with parsed receipt" do
      Req.Test.stub(:tempo_rpc_receipt, fn conn ->
        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => %{
            "status" => "0x1",
            "logs" => [],
            "transactionHash" => "0xbeef"
          }
        })
      end)

      assert {:ok, receipt} =
               RPC.fetch_receipt("0xbeef", "http://localhost", req_options: [plug: {Req.Test, :tempo_rpc_receipt}])

      assert receipt.status == 1
    end

    test "returns error when transaction not found" do
      Req.Test.stub(:tempo_rpc_nil, fn conn ->
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => nil})
      end)

      assert {:error, "Transaction not found on-chain"} =
               RPC.fetch_receipt("0xbeef", "http://localhost", req_options: [plug: {Req.Test, :tempo_rpc_nil}])
    end
  end

  describe "simulate/3" do
    test "sends the exact eth_simulateV1 wire format and returns :success on status 0x1" do
      raw = cosigned_hex()

      Req.Test.stub(:sim_ok, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["method"] == "eth_simulateV1"

        assert [payload] = decoded["params"]
        assert payload["validation"] == false
        assert payload["traceTransfers"] == false
        assert payload["returnFullTransactions"] == false

        assert [%{"calls" => [call]}] = payload["blockStateCalls"]
        assert call["type"] == "0x76"
        assert String.starts_with?(call["from"], "0x")
        assert String.starts_with?(call["to"], "0x")
        assert call["calls"] == []
        assert call["feeToken"] == "0x" <> Base.encode16(@fee_token, case: :lower)
        assert call["gas"] == "0x186a0"

        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          # eth_simulateV1 returns a bare list of block results.
          "result" => [%{"calls" => [%{"status" => "0x1", "gasUsed" => "0x5208"}]}]
        })
      end)

      assert {:ok, :success} =
               RPC.simulate(raw, "http://localhost", req_options: [plug: {Req.Test, :sim_ok}])
    end

    test "returns {:revert, detail} with the node error message on per-call status 0x0" do
      raw = cosigned_hex()

      Req.Test.stub(:sim_revert, fn conn ->
        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => [
            %{
              "calls" => [
                %{
                  "status" => "0x0",
                  "gasUsed" => "0x441d8",
                  "error" => %{"code" => -32_015, "message" => "out of gas"}
                }
              ]
            }
          ]
        })
      end)

      assert {:ok, {:revert, detail}} =
               RPC.simulate(raw, "http://localhost", req_options: [plug: {Req.Test, :sim_revert}])

      assert detail =~ "out of gas"
      assert detail =~ "code -32015"
      assert detail =~ "gasUsed"
    end

    test "maps a top-level eth_simulateV1 execution error (-38013) to a revert" do
      raw = cosigned_hex()

      Req.Test.stub(:sim_intrinsic, fn conn ->
        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "error" => %{"code" => -38_013, "message" => "intrinsic gas too low"}
        })
      end)

      assert {:ok, {:revert, detail}} =
               RPC.simulate(raw, "http://localhost", req_options: [plug: {Req.Test, :sim_intrinsic}])

      assert detail =~ "intrinsic gas too low"
      assert detail =~ "code -38013"
    end

    test "revert detail falls back to returnData when no error object is present" do
      raw = cosigned_hex()

      Req.Test.stub(:sim_revert_data, fn conn ->
        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => [%{"calls" => [%{"status" => "0x0", "returnData" => "0xdeadbeef"}]}]
        })
      end)

      assert {:ok, {:revert, detail}} =
               RPC.simulate(raw, "http://localhost", req_options: [plug: {Req.Test, :sim_revert_data}])

      assert detail =~ "0xdeadbeef"
    end

    test "returns {:ok, :unsupported} when the node lacks eth_simulateV1 (-32601)" do
      raw = cosigned_hex()

      Req.Test.stub(:sim_unsupported, fn conn ->
        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "error" => %{"code" => -32_601, "message" => "method not allowed: eth_simulateV1"}
        })
      end)

      assert {:ok, :unsupported} =
               RPC.simulate(raw, "http://localhost", req_options: [plug: {Req.Test, :sim_unsupported}])
    end

    test "returns {:error, _} on other JSON-RPC errors" do
      raw = cosigned_hex()

      Req.Test.stub(:sim_err, fn conn ->
        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "error" => %{"code" => -32_000, "message" => "boom"}
        })
      end)

      assert {:error, msg} =
               RPC.simulate(raw, "http://localhost", req_options: [plug: {Req.Test, :sim_err}])

      assert msg =~ "boom"
    end

    test "returns {:error, _} when the response has no call results" do
      raw = cosigned_hex()

      Req.Test.stub(:sim_empty, fn conn ->
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => []})
      end)

      assert {:error, msg} =
               RPC.simulate(raw, "http://localhost", req_options: [plug: {Req.Test, :sim_empty}])

      assert msg =~ "no call results"
    end

    test "returns {:error, _} when the transaction cannot be deserialized" do
      assert {:error, msg} = RPC.simulate("0x02abcd", "http://localhost")
      assert msg =~ "Not a Tempo transaction"
    end

    test "surfaces a transport error" do
      raw = cosigned_hex()
      Req.Test.stub(:sim_transport, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert {:error, msg} =
               RPC.simulate(raw, "http://localhost", req_options: [plug: {Req.Test, :sim_transport}])

      assert msg =~ "RPC request failed"
    end

    test "returns {:error, _} on an unexpected per-call status" do
      raw = cosigned_hex()

      Req.Test.stub(:sim_status_other, fn conn ->
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => [%{"calls" => [%{"status" => "0x2"}]}]})
      end)

      assert {:error, msg} =
               RPC.simulate(raw, "http://localhost", req_options: [plug: {Req.Test, :sim_status_other}])

      assert msg =~ "Unexpected simulation status"
    end

    test "returns {:error, _} on a malformed call result" do
      raw = cosigned_hex()

      Req.Test.stub(:sim_malformed, fn conn ->
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => [%{"calls" => ["not-a-map"]}]})
      end)

      assert {:error, msg} =
               RPC.simulate(raw, "http://localhost", req_options: [plug: {Req.Test, :sim_malformed}])

      assert msg =~ "Malformed simulation call result"
    end

    test "revert detail reports 'no revert reason' when neither error nor returnData is present" do
      raw = cosigned_hex()

      Req.Test.stub(:sim_no_reason, fn conn ->
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => [%{"calls" => [%{"status" => "0x0"}]}]})
      end)

      assert {:ok, {:revert, detail}} =
               RPC.simulate(raw, "http://localhost", req_options: [plug: {Req.Test, :sim_no_reason}])

      assert detail =~ "no revert reason"
    end

    test "maps a top-level execution error without a message to a revert" do
      raw = cosigned_hex()

      Req.Test.stub(:sim_no_msg, fn conn ->
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "error" => %{"code" => -38_005}})
      end)

      assert {:ok, {:revert, detail}} =
               RPC.simulate(raw, "http://localhost", req_options: [plug: {Req.Test, :sim_no_msg}])

      assert detail =~ "-38005"
    end
  end

  describe "broadcast/receipt error and edge handling" do
    test "broadcast_async surfaces a transport error" do
      Req.Test.stub(:ba_transport, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, msg} =
               RPC.broadcast_async("0x76abc", "http://localhost", req_options: [plug: {Req.Test, :ba_transport}])

      assert msg =~ "RPC request failed"
    end

    test "broadcast_async reports an unexpected response with neither result nor error" do
      Req.Test.stub(:ba_unexpected, fn conn -> Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1}) end)

      assert {:error, msg} =
               RPC.broadcast_async("0x76abc", "http://localhost", req_options: [plug: {Req.Test, :ba_unexpected}])

      assert msg =~ "Unexpected RPC response"
    end

    test "broadcast_async rejects a non-string result" do
      Req.Test.stub(:ba_nonstring, fn conn ->
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => %{"unexpected" => true}})
      end)

      assert {:error, msg} =
               RPC.broadcast_async("0x76abc", "http://localhost", req_options: [plug: {Req.Test, :ba_nonstring}])

      assert msg =~ "Unexpected broadcast response"
    end

    test "broadcast_sync rejects a non-map result" do
      Req.Test.stub(:bs_nonmap, fn conn ->
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => "not-a-receipt"})
      end)

      assert {:error, msg} =
               RPC.broadcast_sync("0x76abc", "http://localhost", req_options: [plug: {Req.Test, :bs_nonmap}])

      assert msg =~ "Unexpected sync broadcast response"
    end

    test "broadcast_sync surfaces a transport error" do
      Req.Test.stub(:bs_transport, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, msg} =
               RPC.broadcast_sync("0x76abc", "http://localhost", req_options: [plug: {Req.Test, :bs_transport}])

      assert msg =~ "RPC request failed"
    end

    test "fetch_receipt surfaces a transport error" do
      Req.Test.stub(:fr_transport, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, msg} =
               RPC.fetch_receipt("0xbeef", "http://localhost", req_options: [plug: {Req.Test, :fr_transport}])

      assert msg =~ "RPC request failed"
    end

    test "parse_receipt yields nil status for an unparseable status value" do
      assert RPC.parse_receipt(%{"status" => 123, "logs" => []}).status == nil
    end
  end
end
