defmodule Cartouche.RPCTest do
  use ExUnit.Case, async: false
  use Cartouche.Hex

  import ExUnit.CaptureLog

  alias Cartouche.RPC.Capabilities
  alias Cartouche.RPC.Configuration
  alias Cartouche.Test.Signer
  alias Cartouche.Transaction.Call
  alias Cartouche.Transaction.V1
  alias Cartouche.Transaction.V2
  alias Cartouche.Transaction.V_2930

  doctest Cartouche.RPC

  defmodule UnencodableStruct do
    @moduledoc false
    defstruct [:value]
  end

  # Each mock is a Req function plug (`fun(conn) -> conn`). It runs in the process
  # that calls `Req.request/1` — the test pid for direct calls here — so wire
  # captures via `send(self(), ...)` and `Process.get/put` work with no Req.Test
  # ownership ceremony. Request bodies are read with `Req.Test.raw_body/1`
  # (idempotent — it reads the adapter's stored body, not a consumable stream),
  # and responses are returned with `Req.Test.json/2`.
  @doc false
  def decode_id(conn) do
    conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!() |> Map.fetch!("id")
  end

  defp respond_with_result(conn, result) do
    Req.Test.json(conn, %{"jsonrpc" => "2.0", "result" => result, "id" => decode_id(conn)})
  end

  # The oracle for "this unsigned envelope encodes to the payload that actually
  # gets signed": sign the filled transaction the way a caller would, attach the
  # signature, recover. If the envelope's unsigned representation is wrong,
  # signing and recovery hash different bytes and the addresses diverge — which
  # is exactly the wrong-address hazard, not a shape mismatch a struct assertion
  # would catch.
  defp assert_signs_back_to_signer(filled, attach, recover, sign_opts \\ []) do
    signer_proc = Signer.start_signer()

    {:ok, signature} = Cartouche.Signer.sign(Cartouche.Transaction.encode(filled), signer_proc, sign_opts)
    assert {:ok, recovered} = recover.(attach.(signature))

    assert Cartouche.Hex.to_address(recovered) ==
             Cartouche.Hex.to_address(Cartouche.Signer.address(signer_proc))
  end

  defp unsigned_filled_v2_json do
    %{
      "type" => "0x2",
      "chainId" => "0x1",
      "nonce" => "0x7",
      "maxPriorityFeePerGas" => "0x3b9aca00",
      "maxFeePerGas" => "0x174876e800",
      "gasPrice" => "0x174876e800",
      "gas" => "0x5208",
      "to" => "0x0000000000000000000000000000000000000001",
      "value" => "0x2",
      "input" => "0x010203",
      "accessList" => []
    }
  end

  defp unsigned_filled_v1_json do
    %{
      "type" => "0x0",
      "chainId" => "0x2a",
      "nonce" => "0x9",
      "gasPrice" => "0x174876e800",
      "gas" => "0x5208",
      "to" => "0x0000000000000000000000000000000000000001",
      "value" => "0x2",
      "input" => "0x010203"
    }
  end

  defmodule CaptureClient do
    @moduledoc false
    # Delegates to `Cartouche.Test.Client` so doctest fixtures still work,
    # and `send`s the decoded JSON-RPC request body back to the test pid
    # registered as `:cartouche_rpc_capture` for wire-format assertions.
    def call(conn) do
      decoded = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
      send(:cartouche_rpc_capture, {:rpc_request, decoded})
      Cartouche.Test.Client.call(conn)
    end
  end

  defmodule PanicClient do
    @moduledoc false

    @panic_data "0x" <> Base.encode16(<<0x4E487B71::32, 0::248, 0x11>>)

    def call(conn) do
      id = Cartouche.RPCTest.decode_id(conn)

      Req.Test.json(conn, %{
        "jsonrpc" => "2.0",
        "error" => %{"code" => 3, "message" => "execution reverted", "data" => @panic_data},
        "id" => id
      })
    end
  end

  defmodule PanicCodeClient do
    @moduledoc false

    def call(conn) do
      id = Cartouche.RPCTest.decode_id(conn)
      panic_code = Process.get(:panic_code)
      panic_data = "0x" <> Base.encode16(<<0x4E487B71::32, 0::248, panic_code>>)

      Req.Test.json(conn, %{
        "jsonrpc" => "2.0",
        "error" => %{"code" => 3, "message" => "execution reverted", "data" => panic_data},
        "id" => id
      })
    end
  end

  defmodule NonHexRevertClient do
    @moduledoc false

    def call(conn) do
      id = Cartouche.RPCTest.decode_id(conn)

      Req.Test.json(conn, %{
        "jsonrpc" => "2.0",
        "error" => %{"code" => 3, "message" => "execution reverted", "data" => "not hex"},
        "id" => id
      })
    end
  end

  defmodule OverloadedErrorClient do
    @moduledoc false

    @revert_data "0x" <> Base.encode16(ABI.encode("Overloaded(address)", [<<1::160>>]))

    def call(conn) do
      id = Cartouche.RPCTest.decode_id(conn)

      Req.Test.json(conn, %{
        "jsonrpc" => "2.0",
        "error" => %{"code" => 3, "message" => "execution reverted", "data" => @revert_data},
        "id" => id
      })
    end
  end

  defmodule InvalidJsonRpcClient do
    @moduledoc false

    def call(conn) do
      id = Cartouche.RPCTest.decode_id(conn)
      Req.Test.json(conn, %{"jsonrpc" => "2.0", "unexpected" => nil, "id" => id})
    end
  end

  defmodule TransportErrorClient do
    @moduledoc false

    def call(conn), do: Req.Test.transport_error(conn, :closed)
  end

  defmodule UnsupportedBaseFeeClient do
    @moduledoc false

    def call(conn) do
      id = Cartouche.RPCTest.decode_id(conn)

      # Recorded from Infura mainnet on 2026-08-23.
      Req.Test.json(conn, %{
        "jsonrpc" => "2.0",
        "error" => %{"code" => -32_601, "message" => "The method eth_baseFee does not exist/is not available"},
        "id" => id
      })
    end
  end

  describe "block-param wire encoding" do
    setup do
      Process.register(self(), :cartouche_rpc_capture)
      prev = Application.get_env(:cartouche, Cartouche.RPC)
      Application.put_env(:cartouche, Cartouche.RPC, plug: &CaptureClient.call/1)
      on_exit(fn -> Application.put_env(:cartouche, Cartouche.RPC, prev) end)
      :ok
    end

    test "get_block_by_number/2 encodes integer as lowercase quantity string" do
      {:ok, %Cartouche.Block{}} = Cartouche.RPC.get_block_by_number(55)

      assert_received {:rpc_request, %{"method" => "eth_getBlockByNumber", "params" => ["0x37", false]}}
    end

    test "get_block_by_number/2 passes string tag through unchanged" do
      {:ok, %Cartouche.Block{}} = Cartouche.RPC.get_block_by_number("latest")
      assert_received {:rpc_request, %{"params" => ["latest", false]}}
    end

    test "get_block_by_number/2 passes hex string through unchanged" do
      {:ok, %Cartouche.Block{}} = Cartouche.RPC.get_block_by_number("0x37")
      assert_received {:rpc_request, %{"params" => ["0x37", false]}}
    end

    test "get_balance/2 normalizes integer :block_number opt" do
      addr = ~h[0x407d73d8a49eeb85d32cf465507dd71d507100c1]
      {:ok, _} = Cartouche.RPC.get_balance(addr, block_number: 55)

      assert_received {:rpc_request, %{"method" => "eth_getBalance", "params" => [_addr_hex, "0x37"]}}
    end

    test "get_nonce/2 normalizes integer :block_number opt zero to '0x0'" do
      addr = ~h[0x407d73d8a49eeb85d32cf465507dd71d507100c1]
      {:ok, _} = Cartouche.RPC.get_nonce(addr, block_number: 0)

      assert_received {:rpc_request, %{"method" => "eth_getTransactionCount", "params" => [_addr_hex, "0x0"]}}
    end

    test "fee_history/1 normalizes integer :newest_block opt" do
      {:ok, %Cartouche.FeeHistory{}} = Cartouche.RPC.fee_history(newest_block: 55)

      assert_received {:rpc_request, %{"method" => "eth_feeHistory", "params" => [1, "0x37", []]}}
    end

    test "create_access_list/2 reuses call encoding and returns a V_2930-ready access list" do
      call = Call.new(<<1::160>>, <<0, 1>>, from: <<4::160>>, gas: 21_000, value: 7)

      assert {:ok, %{access_list: [{<<1::160>>, [<<2::256>>]}], gas_used: 26_026} = result} =
               Cartouche.RPC.create_access_list(call, from: <<5::160>>, block_number: 55)

      assert_received {:rpc_request,
                       %{
                         "method" => "eth_createAccessList",
                         "params" => [
                           %{
                             "from" => "0x0000000000000000000000000000000000000004",
                             "to" => "0x0000000000000000000000000000000000000001",
                             "gas" => "0x5208",
                             "value" => "0x7",
                             "data" => "0x0001"
                           },
                           "0x37"
                         ]
                       }}

      transaction = V_2930.new(0, 1, result.gas_used, call.destination, 0, call.data, result.access_list, :mainnet)

      assert {:ok, ^transaction} = transaction |> V_2930.encode() |> V_2930.decode()
    end

    test "create_access_list/2 accepts atom and hex-string block selectors" do
      call = Call.new(<<1::160>>, <<>>)

      for {block_number, expected} <- [{:latest, "latest"}, {"0x37", "0x37"}] do
        assert {:ok, %{gas_used: 26_026}} = Cartouche.RPC.create_access_list(call, block_number: block_number)
        assert_received {:rpc_request, %{"method" => "eth_createAccessList", "params" => [_call, ^expected]}}
      end
    end

    test "create_access_list/2 retains an execution error alongside the access list" do
      call = Call.new(<<10::160>>, <<>>)

      assert {:ok,
              %{
                access_list: [{<<1::160>>, [<<2::256>>]}],
                gas_used: 24_043,
                error: "execution reverted"
              }} = Cartouche.RPC.create_access_list(call)
    end

    test "fee reads use their spec method names and decode quantities" do
      assert {:ok, 1_000_000_000} = Cartouche.RPC.base_fee()
      assert_received {:rpc_request, %{"method" => "eth_baseFee", "params" => []}}

      assert {:ok, 42} = Cartouche.RPC.blob_base_fee()
      assert_received {:rpc_request, %{"method" => "eth_blobBaseFee", "params" => []}}
    end

    test "node introspection reads deserialize their structured results" do
      assert {:ok, %Configuration{} = config} = Cartouche.RPC.eth_config()
      assert config.current.chain_id == 1
      assert config.current.fork_id == <<0x07C9462E::32>>
      assert config.current.blob_schedule.base_fee_update_fraction == 11_684_671
      assert config.current.precompiles["P256VERIFY"] == <<0x100::160>>
      assert_received {:rpc_request, %{"method" => "eth_config", "params" => []}}

      assert {:ok, %Capabilities{} = capabilities} = Cartouche.RPC.eth_capabilities()
      assert capabilities.head.number == 42
      assert capabilities.head.hash == <<1::256>>
      assert capabilities.blocks.disabled == false
      assert capabilities.blocks.oldest_block == 0
      assert_received {:rpc_request, %{"method" => "eth_capabilities", "params" => []}}
    end
  end

  describe "structured RPC deserializers" do
    test "configuration tolerates omitted optional fields and unknown additions" do
      assert %Configuration{
               current: %Configuration.Fork{
                 activation_time: nil,
                 blob_schedule: nil,
                 chain_id: 1,
                 fork_id: nil,
                 precompiles: nil,
                 system_contracts: nil
               },
               next: nil,
               last: nil
             } =
               Configuration.deserialize(%{
                 "current" => %{"chainId" => "0x1", "futureForkField" => %{"enabled" => true}},
                 "futureResponseField" => "ignored"
               })

      assert %Configuration{current: %Configuration.Fork{chain_id: nil}} =
               Configuration.deserialize(%{"current" => %{}})
    end

    test "capabilities tolerates omitted optional fields and unknown additions" do
      assert %Capabilities{
               head: %Capabilities.Head{number: 42, hash: nil},
               state: %Capabilities.Resource{disabled: true, oldest_block: nil, delete_strategy: nil},
               tx: nil,
               logs: nil,
               receipts: nil,
               blocks: nil,
               stateproofs: nil
             } =
               Capabilities.deserialize(%{
                 "head" => %{"number" => "0x2a", "futureHeadField" => true},
                 "state" => %{"disabled" => true, "futureResourceField" => "ignored"},
                 "futureResponseField" => []
               })

      assert %Capabilities{
               head: nil,
               stateproofs: %Capabilities.Resource{
                 delete_strategy: %Capabilities.DeleteStrategy{type: "window", retention_blocks: 128}
               }
             } =
               Capabilities.deserialize(%{
                 "stateproofs" => %{
                   "disabled" => false,
                   "deleteStrategy" => %{"type" => "window", "retentionBlocks" => "0x80"}
                 }
               })
    end
  end

  describe "send_rpc/3 response handling" do
    setup do
      Process.register(self(), :cartouche_rpc_capture)
      prev = Application.get_env(:cartouche, Cartouche.RPC)
      Application.put_env(:cartouche, Cartouche.RPC, plug: &CaptureClient.call/1)
      on_exit(fn -> Application.put_env(:cartouche, Cartouche.RPC, prev) end)
      :ok
    end

    test "invalid JSON-RPC responses return the sentinel error" do
      assert {:error, %{code: -999, message: "invalid JSON-RPC response"}} =
               Cartouche.RPC.send_rpc("net_version", [], req_options: [plug: &InvalidJsonRpcClient.call/1])
    end

    test "invalid hex results return :invalid_hex" do
      assert :invalid_hex =
               Cartouche.RPC.send_rpc("net_version", [],
                 decode: :hex,
                 req_options: [plug: &Cartouche.Test.InvalidHexResultClient.call/1]
               )
    end

    test "invalid params errors log the outbound request" do
      log =
        capture_log(fn ->
          assert {:error, %{code: -32_602, message: "Failed to decode transaction"}} =
                   1
                   |> V1.new({100, :gwei}, 100_000, <<13::160>>, {2, :wei}, <<1, 2, 3>>)
                   |> Cartouche.RPC.call_trx()
        end)

      assert log =~ "Invalid JSON-PRC request"
      assert log =~ "eth_call"
    end

    test "known Panic(uint256) revert data is decoded without custom ABI metadata" do
      assert {:error, %{code: 3, message: "execution reverted", revert: <<0x4E487B71::32, 0::248, 0x11>>} = error} =
               Cartouche.RPC.call_trx(
                 V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>),
                 req_options: [plug: &PanicClient.call/1]
               )

      refute Map.has_key?(error, :error_abi)
    end

    test "custom revert errors expose ABI name and decoded params" do
      assert {:error, %{error_abi: "Cool(uint256,string)", error_params: [1, "cat"]}} =
               1
               |> V1.new({100, :gwei}, 100_000, <<11::160>>, {2, :wei}, <<1, 2, 3>>)
               |> Cartouche.RPC.call_trx(errors: ["Cool(uint256,string)"])
    end

    test "overloaded custom errors map decoded names back by selector" do
      assert {:error, %{error_abi: "Overloaded(address)", error_params: [<<1::160>>]}} =
               Cartouche.RPC.call_trx(
                 V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>),
                 req_options: [plug: &OverloadedErrorClient.call/1],
                 errors: ["Overloaded(uint256)", "Overloaded(address)"]
               )
    end

    test "Panic(uint256) reverts keep the raw revert bytes for recognized panic codes" do
      for code <- [0x00, 0x01, 0x11, 0x12, 0x21, 0x22, 0x31, 0x32, 0x41, 0x51] do
        Process.put(:panic_code, code)

        assert {:error, %{revert: <<0x4E487B71::32, 0::248, ^code>>} = error} =
                 Cartouche.RPC.call_trx(
                   V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>),
                   req_options: [plug: &PanicCodeClient.call/1]
                 )

        refute Map.has_key?(error, :error_abi)
      end
    end

    test "Panic(uint256) private descriptions match Solidity panic codes" do
      source = File.read!("lib/cartouche/rpc.ex")

      assert source =~
               ~s|defp classify_decoded_error("Panic", [0x12], _errors, _data), do: {:ok, "division or modulo by zero", nil}|

      assert source =~
               ~s|defp classify_decoded_error("Panic", [0x21], _errors, _data), do: {:ok, "failed to convert value to enum", nil}|
    end

    test "non-hex revert data keeps only the base RPC error fields" do
      assert {:error, %{code: 3, message: "execution reverted"} = error} =
               Cartouche.RPC.call_trx(
                 V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>),
                 req_options: [plug: &NonHexRevertClient.call/1]
               )

      refute Map.has_key?(error, :revert)
      refute Map.has_key?(error, :error_abi)
    end

    test "transport errors are normalized before JSON-RPC decoding" do
      assert {:error, "[Cartouche] HTTP client error: :closed"} =
               Cartouche.RPC.send_rpc("net_version", [], req_options: [plug: &TransportErrorClient.call/1])
    end

    test "an unsupported fee method preserves the node's observed error" do
      assert {:error, %{code: -32_601, message: "The method eth_baseFee does not exist/is not available"}} =
               Cartouche.RPC.base_fee(req_options: [plug: &UnsupportedBaseFeeClient.call/1])
    end
  end

  describe "send_rpc/3 invalid params" do
    test "returns invalid_params for non-UTF-8 binary method" do
      assert {:error, {:invalid_params, %Jason.EncodeError{}}} = Cartouche.RPC.send_rpc(<<255>>, [])
    end

    test "returns invalid_params for tuple params" do
      assert {:error, {:invalid_params, %Protocol.UndefinedError{}}} =
               Cartouche.RPC.send_rpc("net_version", [{:tuple, :param}])
    end

    test "returns invalid_params for atom-keyed map params with non-JSON values" do
      assert {:error, {:invalid_params, %Protocol.UndefinedError{}}} =
               Cartouche.RPC.send_rpc("net_version", [%{not_a_json_key: self()}])
    end

    test "returns invalid_params for custom structs without Jason encoders" do
      assert {:error, {:invalid_params, %Protocol.UndefinedError{}}} =
               Cartouche.RPC.send_rpc("net_version", [%UnencodableStruct{value: 1}])
    end
  end

  describe "call params and tracing helpers" do
    setup do
      Process.register(self(), :cartouche_rpc_capture)
      prev = Application.get_env(:cartouche, Cartouche.RPC)
      Application.put_env(:cartouche, Cartouche.RPC, plug: &CaptureClient.call/1)
      on_exit(fn -> Application.put_env(:cartouche, Cartouche.RPC, prev) end)
      :ok
    end

    test "trace_call_many/2 accepts explicit per-transaction from overrides" do
      trx = V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)
      from = <<2::160>>

      assert {:ok, [_trace | _]} = Cartouche.RPC.trace_call_many([{trx, from}], block_number: 55)

      assert_received {:rpc_request,
                       %{
                         "method" => "trace_callMany",
                         "params" => [
                           [
                             [
                               %{"from" => "0x0000000000000000000000000000000000000002"},
                               ["trace"]
                             ]
                           ],
                           "0x37"
                         ]
                       }}
    end

    test "trace_call_many/2 uses the shared :from option for bare transactions" do
      trx = V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)

      assert {:ok, [_trace | _]} = Cartouche.RPC.trace_call_many([trx], from: <<3::160>>)

      assert_received {:rpc_request,
                       %{
                         "method" => "trace_callMany",
                         "params" => [
                           [
                             [
                               %{"from" => "0x0000000000000000000000000000000000000003"},
                               ["trace"]
                             ]
                           ],
                           "latest"
                         ]
                       }}
    end

    test "debug_trace_call/2 normalizes integer block params" do
      trx = V1.new(1, {100, :gwei}, 100_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>)

      assert {:ok, %Cartouche.DebugTrace{}} = Cartouche.RPC.debug_trace_call(trx, block_number: 55)

      assert_received {:rpc_request, %{"method" => "debug_traceCall", "params" => [_call, "0x37"]}}
    end

    test "call_trx/2 sends Call params without transaction fee fields" do
      call = Call.new(<<1::160>>, <<0, 1>>, from: <<4::160>>, gas: 21_000, value: 7)

      assert {:ok, <<0xCC>>} = Cartouche.RPC.call_trx(call, from: <<5::160>>, block_number: 55)

      assert_received {:rpc_request,
                       %{
                         "method" => "eth_call",
                         "params" => [
                           %{
                             "from" => "0x0000000000000000000000000000000000000004",
                             "to" => "0x0000000000000000000000000000000000000001",
                             "gas" => "0x5208",
                             "value" => "0x7",
                             "data" => "0x0001"
                           },
                           "0x37"
                         ]
                       }}
    end

    test "call_trx/2 attaches trace output when revert tracing succeeds" do
      assert {:error, %{code: 3, message: "execution reverted", revert: <<61, 115, 139, 46>>, trace: _}} =
               1
               |> V1.new({100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>)
               |> Cartouche.RPC.call_trx(trace_reverts: true)
    end

    test "call_trx/2 uses debug tracing when requested" do
      assert {:error, %{code: 3, message: "execution reverted", trace: %Cartouche.DebugTrace{}}} =
               1
               |> V1.new({100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>)
               |> Cartouche.RPC.call_trx(trace_reverts: true, debug_trace: true)
    end
  end

  describe "prepare_trx/3 branches" do
    test "execute_trx/3 prepares, signs, and broadcasts a legacy transaction" do
      signer_proc = Signer.start_signer()

      assert {:ok, trx_id} =
               Cartouche.RPC.execute_trx(<<1::160>>, <<>>,
                 gas_price: {50, :gwei},
                 gas_limit: 100_000,
                 value: 0,
                 nonce: 5,
                 signer: signer_proc,
                 chain_id: :goerli
               )

      assert <<5, _gas_price::64, 100_000::24, _to::binary-size(20)>> = trx_id
    end

    test "mismatched explicit transaction type and gas options raise" do
      assert_raise RuntimeError, "mismatched transaction type and gas price settings", fn ->
        Cartouche.RPC.prepare_trx(<<1::160>>, <<>>, trx_type: :v1, base_fee: {1, :gwei})
      end
    end

    test "surfaces missing fee history data when base fee cannot be resolved" do
      defmodule MissingFeeHistoryClient do
        @moduledoc false

        def call(conn) do
          id = Cartouche.RPCTest.decode_id(conn)
          Req.Test.json(conn, %{"jsonrpc" => "2.0", "result" => %{}, "id" => id})
        end
      end

      assert_raise FunctionClauseError, fn ->
        Cartouche.RPC.prepare_trx(<<1::160>>, <<>>, req_options: [plug: &MissingFeeHistoryClient.call/1])
      end
    end
  end

  describe "revert-error classification" do
    # The compiler-defined `Error(string)` is never in the caller's `:errors`
    # list; hieroglyph decodes it through a built-in fallback that fires for any
    # candidate list. Attributing it back to a candidate labelled a plain
    # `require(x, "msg")` revert with an unrelated ABI entry.
    test "an Error(string) revert is labelled Error(string), not a caller-supplied entry" do
      assert {:error, %{error_abi: "Error(string)", error_params: ["Dai/insufficient-balance"]}} =
               1
               |> V1.new({100, :gwei}, 100_000, <<14::160>>, {2, :wei}, <<1, 2, 3>>)
               |> Cartouche.RPC.call_trx(errors: ["Cool(uint256,string)"])
    end

    test "an Error(string) revert is decoded with no caller-supplied :errors" do
      assert {:error, %{error_abi: "Error(string)", error_params: ["Dai/insufficient-balance"]}} =
               1
               |> V1.new({100, :gwei}, 100_000, <<14::160>>, {2, :wei}, <<1, 2, 3>>)
               |> Cartouche.RPC.call_trx()
    end

    test "a custom error still maps to its own ABI entry" do
      assert {:error, %{error_abi: "Cool(uint256,string)", error_params: [1, "cat"]}} =
               1
               |> V1.new({100, :gwei}, 100_000, <<11::160>>, {2, :wei}, <<1, 2, 3>>)
               |> Cartouche.RPC.call_trx(errors: ["Cool(uint256,string)"])
    end

    test "an unlisted custom-error selector is not attributed to an unrelated entry" do
      assert {:error, revert_error} =
               1
               |> V1.new({100, :gwei}, 100_000, <<10::160>>, {2, :wei}, <<1, 2, 3>>)
               |> Cartouche.RPC.call_trx(errors: ["Cool(uint256,string)"])

      refute Map.has_key?(revert_error, :error_abi)
      refute Map.has_key?(revert_error, :error_params)
      assert revert_error.revert == <<0x3D, 0x73, 0x8B, 0x2E>>
    end
  end

  describe "node-custody passthroughs" do
    test "fill_transaction deserializes a spec-conforming unsigned tx result" do
      result = %{"tx" => unsigned_filled_v2_json()}
      plug = fn conn -> respond_with_result(conn, result) end

      assert {:ok,
              %V2{
                nonce: 7,
                gas_limit: 21_000,
                max_priority_fee_per_gas: 1_000_000_000,
                max_fee_per_gas: 100_000_000_000,
                signature_y_parity: nil,
                signature_r: nil,
                signature_s: nil
              }} =
               <<1::160>>
               |> Call.new(<<1, 2, 3>>)
               |> Cartouche.RPC.fill_transaction(req_options: [plug: plug])
    end

    test "fill_transaction keeps the chain id in an unsigned legacy signature triple" do
      result = %{"tx" => unsigned_filled_v1_json()}
      plug = fn conn -> respond_with_result(conn, result) end

      assert {:ok,
              %V1{
                nonce: 9,
                gas_limit: 21_000,
                gas_price: 100_000_000_000,
                v: 42,
                r: 0,
                s: 0
              } = transaction} =
               <<1::160>>
               |> Call.new(<<1, 2, 3>>)
               |> Cartouche.RPC.fill_transaction(req_options: [plug: plug])

      assert {:error, "transaction missing signature"} = V1.get_signature(transaction)

      # The point of keeping `chainId` in `v`: what a caller signs next must be
      # the EIP-155 `[chain_id, 0, 0]` payload, not the `[0, 0, 0]` one — a
      # signature over the latter recovers to the wrong address.
      assert Cartouche.Transaction.encode(transaction) ==
               V1.encode(V1.new(9, {100, :gwei}, 21_000, <<1::160>>, {2, :wei}, <<1, 2, 3>>, 42))
    end

    test "fill_transaction rejects an unsigned legacy tx with no chainId" do
      result = %{"tx" => Map.delete(unsigned_filled_v1_json(), "chainId")}
      plug = fn conn -> respond_with_result(conn, result) end

      assert {:error, message} =
               <<1::160>>
               |> Call.new(<<1, 2, 3>>)
               |> Cartouche.RPC.fill_transaction(req_options: [plug: plug])

      assert message =~ "failed to decode `eth_fillTransaction` response"
      assert message =~ "no usable `chainId`"
      assert message =~ "pass `chain_id:`"
    end

    # geth serializes an unsigned TYPED fill into `raw` using the canonical
    # signed encoding — a 12-field EIP-1559 body whose V/R/S are zero — not the
    # 9-field signing preimage. Decoding those bytes yields `signature_y_parity:
    # false` with two zero words, which `V2.encode/1` re-emits as a signed body;
    # signing that recovers to a different address than the one that signed it.
    # The spec-required `tx` object is the trustworthy field, so it wins.
    test "fill_transaction prefers the spec tx object over geth's ambiguous raw" do
      geth_typed_raw =
        <<0x02>> <>
          ExRLP.encode([
            1,
            7,
            1_000_000_000,
            100_000_000_000,
            21_000,
            <<1::160>>,
            2,
            <<1, 2, 3>>,
            [],
            0,
            0,
            0
          ])

      result = %{
        "raw" => Cartouche.Hex.encode_hex(geth_typed_raw),
        "tx" => Map.merge(unsigned_filled_v2_json(), %{"yParity" => "0x0", "r" => "0x0", "s" => "0x0"})
      }

      plug = fn conn -> respond_with_result(conn, result) end

      assert {:ok, %V2{nonce: 7, signature_y_parity: nil, signature_r: nil, signature_s: nil} = filled} =
               <<1::160>>
               |> Call.new(<<1, 2, 3>>)
               |> Cartouche.RPC.fill_transaction(req_options: [plug: plug])

      # The oracle: what the caller signs must be the unsigned payload, so the
      # recovered address is the signer's. Decoding geth's `raw` instead yields
      # a struct whose `encode/1` appends the zero triple, and this fails.
      assert_signs_back_to_signer(filled, fn signature -> V2.add_signature(filled, signature) end, &V2.recover_signer/1)
    end

    # geth's unsigned legacy `tx` carries no `chainId` at all — `newRPCTransaction`
    # emits it only for a replay-protected transaction — and its `raw` ends in a
    # literal `[0, 0, 0]` rather than EIP-155's `[chain_id, 0, 0]`. The caller's
    # `chain_id:` option is the only source, and it must reach `v`.
    test "fill_transaction takes the chain id from chain_id: when geth omits it" do
      geth_legacy_raw = ExRLP.encode([9, 100_000_000_000, 21_000, <<1::160>>, 2, <<1, 2, 3>>, 0, 0, 0])

      result = %{
        "raw" => Cartouche.Hex.encode_hex(geth_legacy_raw),
        "tx" => Map.delete(unsigned_filled_v1_json(), "chainId")
      }

      plug = fn conn -> respond_with_result(conn, result) end

      assert {:ok, %V1{v: 42, r: 0, s: 0} = filled} =
               <<1::160>>
               |> Call.new(<<1, 2, 3>>)
               |> Cartouche.RPC.fill_transaction(chain_id: 42, req_options: [plug: plug])

      assert_signs_back_to_signer(
        filled,
        fn signature -> V1.add_signature(filled, signature) end,
        &V1.recover_signer(&1, 42),
        chain_id: 42
      )
    end

    # `Cartouche.Chain.parse_id/1` passes every integer through, so a zero or
    # negative option would reach `v` and produce the same `[0, 0, 0]` payload
    # the response-side check refuses. Chain id 0 is not signable here either
    # way: `Signer` maps it to a pre-EIP-155 `v` of 27/28 while `V1.encode/1`
    # always emits nine fields.
    test "fill_transaction refuses a chain_id: option that is not a positive id" do
      result = %{"tx" => Map.delete(unsigned_filled_v1_json(), "chainId")}
      plug = fn conn -> respond_with_result(conn, result) end

      for chain_id <- [0, -1] do
        assert {:error, message} =
                 <<1::160>>
                 |> Call.new(<<1, 2, 3>>)
                 |> Cartouche.RPC.fill_transaction(chain_id: chain_id, req_options: [plug: plug])

        assert message =~ "`chain_id:` must be a positive chain id"
      end
    end

    test "fill_transaction reports the missing chain id against the response when no option is given" do
      result = %{"tx" => Map.delete(unsigned_filled_v1_json(), "chainId")}
      plug = fn conn -> respond_with_result(conn, result) end

      assert {:error, message} =
               <<1::160>>
               |> Call.new(<<1, 2, 3>>)
               |> Cartouche.RPC.fill_transaction(req_options: [plug: plug])

      assert message =~ "no usable `chainId`"
    end

    # A garbled `chainId` must not fall through to the caller's option — that
    # would sign for whatever network the caller guessed while the node was
    # naming a different one it could not be understood to name.
    test "fill_transaction refuses a malformed chainId instead of using the chain_id: fallback" do
      for bad <- ["bad", "0x", 42.0] do
        result = %{"tx" => Map.put(unsigned_filled_v1_json(), "chainId", bad)}
        plug = fn conn -> respond_with_result(conn, result) end

        assert {:error, message} =
                 <<1::160>>
                 |> Call.new(<<1, 2, 3>>)
                 |> Cartouche.RPC.fill_transaction(chain_id: 42, req_options: [plug: plug])

        assert message =~ "malformed `chainId`"
      end
    end

    # `unsigned_filled_v1_json/0` names chain 42. A caller that also names one
    # is stating which chain it will sign for, and `Cartouche.Signer` takes the
    # chain id from that caller rather than from the struct — so a disagreement
    # signs the EIP-155 digest for one chain over a payload encoding another,
    # and recovery lands on an address that never signed it. Taking either side
    # silently is the wrong-address hazard; both are refused.
    test "fill_transaction refuses a chain_id: option that disagrees with the response" do
      result = %{"tx" => unsigned_filled_v1_json()}
      plug = fn conn -> respond_with_result(conn, result) end

      assert {:error, message} =
               <<1::160>>
               |> Call.new(<<1, 2, 3>>)
               |> Cartouche.RPC.fill_transaction(chain_id: 1, req_options: [plug: plug])

      assert message =~ "returned `chainId` 42 but `chain_id:` was 1"
    end

    test "fill_transaction accepts a chain_id: option that agrees with the response" do
      result = %{"tx" => unsigned_filled_v1_json()}
      plug = fn conn -> respond_with_result(conn, result) end

      assert {:ok, %V1{v: 42, r: 0, s: 0}} =
               <<1::160>>
               |> Call.new(<<1, 2, 3>>)
               |> Cartouche.RPC.fill_transaction(chain_id: 42, req_options: [plug: plug])
    end

    # `Cartouche.Chain.parse_id/1` is `Map.fetch!/2` for atoms, so an unknown
    # chain atom used to escape as a `KeyError` and be reported as a failure to
    # decode the response — blaming the node for the caller's typo.
    test "fill_transaction refuses an unknown chain atom by naming the option" do
      result = %{"tx" => Map.delete(unsigned_filled_v1_json(), "chainId")}
      plug = fn conn -> respond_with_result(conn, result) end

      assert {:error, message} =
               <<1::160>>
               |> Call.new(<<1, 2, 3>>)
               |> Cartouche.RPC.fill_transaction(chain_id: :not_a_chain, req_options: [plug: plug])

      assert message =~ "`chain_id:` must be a positive chain id"
      assert message =~ ":not_a_chain"
    end

    # The raw fallback must yield something cartouche can re-encode into the same
    # bytes that get signed. A signed or half-signed envelope is neither unsigned
    # nor safe to hand back from a method documented to return an unsigned fill.
    test "fill_transaction rejects a raw transaction that is not unambiguously unsigned" do
      malformed = ExRLP.encode([9, 100_000_000_000, 21_000, <<1::160>>, 2, <<1, 2, 3>>, 0, 1, 2])
      plug = fn conn -> respond_with_result(conn, %{"raw" => Cartouche.Hex.encode_hex(malformed)}) end

      assert {:error, message} =
               <<1::160>>
               |> Call.new(<<1, 2, 3>>)
               |> Cartouche.RPC.fill_transaction(req_options: [plug: plug])

      assert message =~ "not unambiguously unsigned"
    end

    # A garbled signature word must not read as "unsigned" — the placeholders
    # would overwrite it, and the caller would sign a transaction built from a
    # response cartouche never actually understood.
    test "fill_transaction rejects a tx object with a malformed signature quantity" do
      for {field, value} <- [{"r", "not-a-quantity"}, {"s", "0x"}, {"yParity", %{}}, {"v", "2a"}] do
        result = %{"tx" => Map.put(unsigned_filled_v2_json(), field, value)}
        plug = fn conn -> respond_with_result(conn, result) end

        assert {:error, message} =
                 <<1::160>>
                 |> Call.new(<<1, 2, 3>>)
                 |> Cartouche.RPC.fill_transaction(req_options: [plug: plug])

        assert message =~ "malformed signature quantities"
        assert message =~ field
      end
    end

    test "fill_transaction rejects a genuinely signed tx object" do
      result = %{"tx" => Map.merge(unsigned_filled_v1_json(), %{"v" => "0x54", "r" => "0x1", "s" => "0x2"})}
      plug = fn conn -> respond_with_result(conn, result) end

      assert {:error, message} =
               <<1::160>>
               |> Call.new(<<1, 2, 3>>)
               |> Cartouche.RPC.fill_transaction(req_options: [plug: plug])

      assert message =~ "returned a signed `tx` object"
    end

    test "fill_transaction rejects geth's all-zero legacy raw when no tx accompanies it" do
      geth_raw = ExRLP.encode([9, 100_000_000_000, 21_000, <<1::160>>, 2, <<1, 2, 3>>, 0, 0, 0])
      result = %{"raw" => Cartouche.Hex.encode_hex(geth_raw)}
      plug = fn conn -> respond_with_result(conn, result) end

      assert {:error, message} =
               <<1::160>>
               |> Call.new(<<1, 2, 3>>)
               |> Cartouche.RPC.fill_transaction(req_options: [plug: plug])

      assert message =~ "not unambiguously unsigned"
    end

    test "fill_transaction rejects a result carrying neither tx nor raw" do
      plug = fn conn -> respond_with_result(conn, %{}) end

      assert {:error, message} =
               <<1::160>>
               |> Call.new(<<1, 2, 3>>)
               |> Cartouche.RPC.fill_transaction(req_options: [plug: plug])

      assert message =~ "neither a `tx` object nor a `raw` field"
    end

    test "get_filter_logs decodes the same Log shape as filter changes" do
      assert {:ok, [log]} = Cartouche.RPC.get_filter_logs("0xf11735")
      assert %Cartouche.Filter.Log{} = log
      assert byte_size(log.address) == 20
    end
  end
end
