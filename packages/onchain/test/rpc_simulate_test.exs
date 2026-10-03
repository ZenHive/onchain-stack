defmodule Onchain.RPCSimulateTest do
  use ExUnit.Case, async: true

  alias Onchain.Block.Withdrawal
  alias Onchain.Filter.Log
  alias Onchain.Hex
  alias Onchain.RPC
  alias Onchain.RPC.Simulate
  alias Onchain.RPC.Simulate.AccountOverride
  alias Onchain.RPC.Simulate.BlockOverride
  alias Onchain.RPC.Simulate.BlockResult
  alias Onchain.RPC.Simulate.BlockStateCall
  alias Onchain.RPC.Simulate.Call
  alias Onchain.RPC.Simulate.CallError
  alias Onchain.RPC.Simulate.CallFailure
  alias Onchain.RPC.Simulate.CallSuccess
  alias Onchain.RPC.Simulate.Payload
  alias Onchain.Transaction.V2

  @moduletag :capture_log

  @from <<0x11::160>>
  @to <<0x22::160>>
  @from_hex "0x" <> String.duplicate("0", 38) <> "11"
  @to_hex "0x" <> String.duplicate("0", 38) <> "22"
  @word_1 "0x" <> String.duplicate("0", 62) <> "01"
  @word_2 "0x" <> String.duplicate("0", 62) <> "02"
  @word_5 "0x" <> String.duplicate("0", 62) <> "05"
  @word_7 "0x" <> String.duplicate("0", 62) <> "07"
  @tx_hash "0x" <> String.duplicate("cd", 32)
  @access_list_hash "0x" <> String.duplicate("ef", 32)
  @revert_data "0x08c379a0" <> String.duplicate("00", 28) <> "11"

  test "encodes blockStateCalls, overrides, flags and the block parameter" do
    assert {:ok, [%BlockResult{calls: []}]} =
             RPC.eth_simulate_v1(full_payload(), stub([%{"calls" => []}], block: 18_000_000))

    assert_request("eth_simulateV1", [full_params(), "0x112a880"])

    assert {:ok, [%BlockResult{calls: []}]} =
             RPC.eth_simulate_v1(full_payload(), stub([%{"calls" => []}], block: :safe))

    assert_request("eth_simulateV1", [full_params(), "safe"])

    assert {:ok, [%BlockResult{calls: []}]} = RPC.eth_simulate_v1(balance_payload(), stub([%{"calls" => []}]))
    assert_request("eth_simulateV1", [balance_params(), "latest"])
  end

  test "preserves block order and sends an explicit false flag" do
    payload = %Payload{
      block_state_calls: [
        %BlockStateCall{calls: [%Call{value: 1}]},
        %BlockStateCall{calls: [%Call{value: 2}]}
      ],
      validation: false
    }

    assert {:ok, [%BlockResult{}, %BlockResult{}]} =
             RPC.eth_simulate_v1(payload, stub([%{"calls" => []}, %{"calls" => []}]))

    assert_request("eth_simulateV1", [
      %{
        "blockStateCalls" => [%{"calls" => [%{"value" => "0x1"}]}, %{"calls" => [%{"value" => "0x2"}]}],
        "validation" => false
      },
      "latest"
    ])
  end

  test "rejects invalid payloads and blocks before a request" do
    assert {:error, {:invalid_field, "stateOverrides", {:conflicting_storage_override, @from}}} =
             RPC.eth_simulate_v1(conflict_payload(), refusing_stub())

    assert {:error, {:invalid_field, "calls", {:invalid_field, "from", {:invalid_address, @from_hex}}}} =
             RPC.eth_simulate_v1(hex_address_payload(), refusing_stub())

    assert {:error, {:invalid_field, "calls", {:invalid_field, "gas", {:invalid_quantity, -1}}}} =
             RPC.eth_simulate_v1(negative_gas_payload(), refusing_stub())

    assert {:error, :invalid_block_state_calls} =
             RPC.eth_simulate_v1(%Payload{block_state_calls: :nope}, refusing_stub())

    assert {:error, {:invalid_block, "nope"}} = RPC.eth_simulate_v1(balance_payload(), refusing_stub(block: "nope"))
    refute_received :requested
  end

  test "decodes success, per-call failure, logs, full transactions and the access-list hash" do
    assert {:ok, [%BlockResult{block: block, calls: [success, failure], block_access_list_hash: hash}]} =
             RPC.eth_simulate_v1(balance_payload(), stub([decoded_block()]))

    assert hash == Hex.decode_word!(@access_list_hash)
    assert block.number == 16
    assert [%V2{} = tx, @tx_hash] = block.transactions
    assert tx.signature_y_parity == false
    assert tx.signature_r == <<0::256>>
    assert tx.signature_s == <<0::256>>
    assert tx.amount == 1
    assert tx.destination == @to

    assert %CallSuccess{
             status: 1,
             return_data: <<>>,
             gas_used: 21_000,
             max_used_gas: 21_000,
             logs: [log]
           } = success

    assert %Log{
             address: @to,
             data: <<1::256>>,
             log_index: 0,
             transaction_index: 0,
             removed: false,
             topics: [<<1::256>>]
           } = log

    assert %CallFailure{
             status: 0,
             return_data: <<1, 2>>,
             gas_used: 24_211,
             max_used_gas: 24_211,
             logs: [],
             error: %CallError{code: 3, message: "execution reverted", data: data}
           } = failure

    assert data == Hex.decode_hex!(@revert_data)
  end

  test "a per-call revert stays inside the successful response" do
    failure = %{
      "status" => "0x00",
      "returnData" => "0x",
      "gasUsed" => "0x1",
      "error" => %{"code" => 3, "message" => "execution reverted"}
    }

    assert {:ok, [%BlockResult{calls: [%CallFailure{status: 0, logs: [], error: %CallError{code: 3, data: nil}}]}]} =
             RPC.eth_simulate_v1(balance_payload(), stub([%{"calls" => [failure]}]))
  end

  test "request rejection and method unsupported stay distinct from a per-call failure" do
    message = "nonce too low: next nonce 5966, tx nonce 0"

    assert {:error, %{code: -38_010, message: ^message}} =
             RPC.eth_simulate_v1(balance_payload(), error_stub(-38_010, message))

    infura = "The method eth_simulateV1 does not exist/is not available"

    assert {:error, {:method_not_found, %{code: -32_601, message: ^infura}}} =
             RPC.eth_simulate_v1(balance_payload(), error_stub(-32_601, infura))

    assert {:error, %{code: 3, message: "execution reverted"}} =
             RPC.eth_simulate_v1(balance_payload(), error_stub(3, "execution reverted", "0x08c379a0"))
  end

  test "a malformed result is a decode error naming eth_simulateV1" do
    malformed = [
      %{"calls" => []},
      [%{}],
      [%{"calls" => [%{"status" => "0x2"}]}],
      [%{"calls" => [%{"status" => "0x1"}]}]
    ]

    for result <- malformed do
      assert {:error, message} = RPC.eth_simulate_v1(balance_payload(), stub(result))
      assert message =~ "eth_simulateV1"
    end
  end

  test "request_error_codes is the beta.7 list and excludes method-not-found" do
    assert Simulate.request_error_codes() == [
             -32_000,
             -32_602,
             -32_005,
             -32_015,
             -32_016,
             -32_603,
             -38_010,
             -38_011,
             -38_012,
             -38_013,
             -38_014,
             -38_015,
             -38_020,
             -38_021,
             -38_022,
             -38_023,
             -38_024,
             -38_025,
             -38_026
           ]

    refute -32_601 in Simulate.request_error_codes()
  end

  defp full_payload do
    %Payload{
      block_state_calls: [
        %BlockStateCall{
          calls: [
            %Call{
              from: @from,
              to: @to,
              gas: 21_000,
              value: 1,
              input: <<1, 2>>,
              nonce: 7,
              type: 2,
              gas_price: 9,
              max_fee_per_gas: 2,
              max_priority_fee_per_gas: 1,
              max_fee_per_blob_gas: 4,
              access_list: [{@to, [<<1::256>>]}],
              blob_versioned_hashes: [<<7::256>>]
            }
          ],
          state_overrides: %{
            @from => %AccountOverride{
              balance: 1_000_000_000_000_000_000,
              nonce: 7,
              code: <<0x60, 0x00>>,
              state: %{<<1::256>> => <<5::256>>},
              move_precompile_to_address: @to
            },
            @to => %AccountOverride{state_diff: %{<<1::256>> => <<5::256>>}}
          },
          block_overrides: %BlockOverride{
            number: 16,
            prev_randao: <<2::256>>,
            time: 32,
            gas_limit: 30_000_000,
            fee_recipient: @from,
            base_fee_per_gas: 1,
            withdrawals: [%Withdrawal{index: 1, validator_index: 2, address: @to, amount: 3}],
            blob_base_fee: 3
          }
        }
      ],
      trace_transfers: true,
      validation: false,
      return_full_transactions: true
    }
  end

  defp full_params do
    %{
      "blockStateCalls" => [
        %{
          "blockOverrides" => %{
            "baseFeePerGas" => "0x1",
            "blobBaseFee" => "0x3",
            "feeRecipient" => @from_hex,
            "gasLimit" => "0x1c9c380",
            "number" => "0x10",
            "prevRandao" => @word_2,
            "time" => "0x20",
            "withdrawals" => [
              %{"address" => @to_hex, "amount" => "0x3", "index" => "0x1", "validatorIndex" => "0x2"}
            ]
          },
          "calls" => [
            %{
              "accessList" => [%{"address" => @to_hex, "storageKeys" => [@word_1]}],
              "blobVersionedHashes" => [@word_7],
              "from" => @from_hex,
              "gas" => "0x5208",
              "gasPrice" => "0x9",
              "input" => "0x0102",
              "maxFeePerBlobGas" => "0x4",
              "maxFeePerGas" => "0x2",
              "maxPriorityFeePerGas" => "0x1",
              "nonce" => "0x7",
              "to" => @to_hex,
              "type" => "0x2",
              "value" => "0x1"
            }
          ],
          "stateOverrides" => %{
            @from_hex => %{
              "balance" => "0xde0b6b3a7640000",
              "code" => "0x6000",
              "movePrecompileToAddress" => @to_hex,
              "nonce" => "0x7",
              "state" => %{@word_1 => @word_5}
            },
            @to_hex => %{"stateDiff" => %{@word_1 => @word_5}}
          }
        }
      ],
      "returnFullTransactions" => true,
      "traceTransfers" => true,
      "validation" => false
    }
  end

  defp balance_payload do
    %Payload{
      block_state_calls: [
        %BlockStateCall{
          calls: [%Call{from: @from, to: @to, value: 1, gas: 21_000}],
          state_overrides: %{@from => %AccountOverride{balance: 1_000_000_000_000_000_000}}
        }
      ],
      trace_transfers: true,
      validation: false
    }
  end

  defp balance_params do
    %{
      "blockStateCalls" => [
        %{
          "calls" => [%{"from" => @from_hex, "gas" => "0x5208", "to" => @to_hex, "value" => "0x1"}],
          "stateOverrides" => %{@from_hex => %{"balance" => "0xde0b6b3a7640000"}}
        }
      ],
      "traceTransfers" => true,
      "validation" => false
    }
  end

  defp negative_gas_payload do
    %Payload{block_state_calls: [%BlockStateCall{calls: [%Call{gas: -1}]}]}
  end

  defp conflict_payload do
    account = %AccountOverride{state: %{<<1::256>> => <<5::256>>}, state_diff: %{<<1::256>> => <<5::256>>}}

    %Payload{block_state_calls: [%BlockStateCall{state_overrides: %{@from => account}}]}
  end

  defp hex_address_payload do
    %Payload{block_state_calls: [%BlockStateCall{calls: [%Call{from: @from_hex}]}]}
  end

  defp decoded_block do
    %{
      "number" => "0x10",
      "transactions" => [full_transaction(), @tx_hash],
      "blockAccessListHash" => @access_list_hash,
      "calls" => [success_call(), failure_call()]
    }
  end

  defp full_transaction do
    %{
      "type" => "0x2",
      "chainId" => "0x1",
      "nonce" => "0x0",
      "maxPriorityFeePerGas" => "0x0",
      "maxFeePerGas" => "0x0",
      "gas" => "0x5208",
      "to" => @to_hex,
      "value" => "0x1",
      "input" => "0x",
      "accessList" => [],
      "yParity" => "0x0",
      "r" => "0x0",
      "s" => "0x0",
      "hash" => @tx_hash
    }
  end

  defp success_call do
    %{
      "status" => "0x1",
      "returnData" => "0x",
      "gasUsed" => "0x5208",
      "maxUsedGas" => "0x5208",
      "logs" => [
        %{
          "address" => @to_hex,
          "data" => @word_1,
          "topics" => [@word_1],
          "logIndex" => "0x0",
          "transactionIndex" => "0x0",
          "removed" => false,
          "blockTimestamp" => "0x20"
        }
      ]
    }
  end

  defp failure_call do
    %{
      "status" => "0x0",
      "returnData" => "0x0102",
      "gasUsed" => "0x5e93",
      "maxUsedGas" => "0x5e93",
      "logs" => [],
      "error" => %{"code" => 3, "message" => "execution reverted", "data" => @revert_data}
    }
  end

  defp stub(result, extra \\ []), do: response_opts(%{"result" => result}, extra)

  defp error_stub(code, message, data \\ nil) do
    error = %{"code" => code, "message" => message}
    error = if data, do: Map.put(error, "data", data), else: error
    response_opts(%{"error" => error}, [])
  end

  defp refusing_stub(extra \\ []) do
    pid = self()

    plug = fn conn ->
      send(pid, :requested)
      Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => []})
    end

    Keyword.merge([rpc_url: "http://stub.invalid", req_options: [plug: plug]], extra)
  end

  defp response_opts(response, extra) do
    pid = self()

    plug = fn conn ->
      request = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
      send(pid, {:request, request})
      Req.Test.json(conn, Map.merge(response, %{"jsonrpc" => "2.0", "id" => request["id"]}))
    end

    Keyword.merge([rpc_url: "http://stub.invalid", req_options: [plug: plug]], extra)
  end

  defp assert_request(method, params) do
    assert_receive {:request, %{"method" => ^method, "params" => ^params}}
  end
end
