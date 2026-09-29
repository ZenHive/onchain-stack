defmodule Cartouche.FilterTest do
  use ExUnit.Case, async: true
  use Cartouche.Hex

  import ExUnit.CaptureLog

  alias Cartouche.Filter.Log

  doctest Cartouche.Filter

  # Req function plugs (`fun(conn) -> conn`). These run inside the `Cartouche.Filter`
  # GenServer process that issues the request, so `Process.get/put` here reads and
  # writes that filter process's dictionary — which the expiry test asserts on.
  defmodule ExpiredFilterClient do
    @moduledoc false
    def call(conn) do
      %{"method" => method, "params" => params, "id" => id} =
        conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

      response =
        case {method, params} do
          {"eth_newFilter", _} ->
            filter_id =
              case Process.get(:new_filter_count, 0) do
                0 -> "0xf11735"
                _ -> "0xf11736"
              end

            Process.put(:new_filter_count, Process.get(:new_filter_count, 0) + 1)
            %{jsonrpc: "2.0", result: filter_id, id: id}

          {"eth_getFilterChanges", ["0xf11735"]} ->
            Process.put(:expired_seen, true)
            %{jsonrpc: "2.0", error: %{code: -32_000, message: "filter not found"}, id: id}

          {"eth_getFilterChanges", ["0xf11736"]} ->
            %{jsonrpc: "2.0", result: Cartouche.Test.Client.eth_getFilterChanges("0xf11735"), id: id}

          {"eth_uninstallFilter", _} ->
            %{jsonrpc: "2.0", result: true, id: id}
        end

      Req.Test.json(conn, response)
    end
  end

  defmodule ReferenceTypeEventClient do
    @moduledoc false

    @indexed_topic :binary.copy(<<0xAB>>, 32)

    def call(conn) do
      %{"method" => method, "id" => id} =
        conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

      response =
        case method do
          "eth_newFilter" ->
            %{jsonrpc: "2.0", result: "0xref", id: id}

          "eth_getFilterChanges" ->
            %{jsonrpc: "2.0", result: [reference_type_log()], id: id}

          "eth_uninstallFilter" ->
            %{jsonrpc: "2.0", result: true, id: id}
        end

      Req.Test.json(conn, response)
    end

    defp reference_type_log do
      event = ABI.FunctionSelector.decode("Message(string indexed tag, uint256 value)")
      data = ABI.encode("(uint256)", [{7}])

      %{
        "address" => Cartouche.Hex.encode_hex(<<3::160>>),
        "blockHash" => Cartouche.Hex.encode_hex(<<4::256>>),
        "blockNumber" => "0x1",
        "data" => Cartouche.Hex.encode_hex(data),
        "logIndex" => "0x0",
        "removed" => false,
        "topics" => [
          Cartouche.Hex.encode_hex(ABI.Event.event_signature(event)),
          Cartouche.Hex.encode_hex(@indexed_topic)
        ],
        "transactionHash" => Cartouche.Hex.encode_hex(<<5::256>>),
        "transactionIndex" => "0x0"
      }
    end
  end

  test "add a filter and get events" do
    extra_data = %{some_key: "some value"}

    {:ok, _filter_pid} =
      Cartouche.Filter.start_link(
        name: MyFilter,
        address: <<1::160>>,
        events: ["Transfer(address indexed from, address indexed to, uint amount)"],
        check_delay: 300,
        extra_data: extra_data
      )

    Cartouche.Filter.listen(MyFilter)

    :timer.sleep(600)

    log =
      %{
        "address" => "0xb5a5f22694352c15b00323844ad545abb2b11028",
        "blockHash" => "0x99e8663c7b6d8bba3c7627a17d774238eae3e793dee30008debb2699666657de",
        "blockNumber" => "0x5d12ab",
        "data" => "0x00000000000000000000000000000000000000000000000000000004a817c800",
        "logIndex" => "0x0",
        "removed" => false,
        "topics" => [
          "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
          "0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8",
          "0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea"
        ],
        "transactionHash" => "0xa74c2432c9cf7dbb875a385a2411fd8f13ca9ec12216864b1a1ead3c99de99cd",
        "transactionIndex" => "0x3"
      }
      |> Log.deserialize()
      |> Map.put(:extra_data, extra_data)

    assert_received {:event,
                     {"Transfer",
                      %{
                        "amount" => 20_000_000_000,
                        "from" => ~h[b2b7c1795f19fbc28fda77a95e59edbb8b3709c8],
                        "to" => ~h[7795126b3ae468f44c901287de98594198ce38ea]
                      }}, ^log}

    assert_received {:log, ^log}
  end

  test "indexed reference-type event params surface the topic hash" do
    {:ok, _filter_pid} =
      Cartouche.Filter.start_link(
        name: ReferenceTypeFilter,
        events: ["Message(string indexed tag, uint256 value)"],
        check_delay: 20,
        rpc_opts: [req_options: [plug: &ReferenceTypeEventClient.call/1]]
      )

    Cartouche.Filter.listen(ReferenceTypeFilter)

    assert_receive {:event,
                    {"Message",
                     %{
                       "tag" => {:indexed_hash, indexed_topic},
                       "value" => 7
                     }}, log},
                   500

    assert indexed_topic == :binary.copy(<<0xAB>>, 32)
    assert %Log{topics: [_event_signature, ^indexed_topic]} = log
    assert_receive {:log, ^log}, 500
  end

  test "recreates filter when ethereum node reports expired filter" do
    extra_data = %{some_key: "some value"}

    log =
      %{
        "address" => "0xb5a5f22694352c15b00323844ad545abb2b11028",
        "blockHash" => "0x99e8663c7b6d8bba3c7627a17d774238eae3e793dee30008debb2699666657de",
        "blockNumber" => "0x5d12ab",
        "data" => "0x00000000000000000000000000000000000000000000000000000004a817c800",
        "logIndex" => "0x0",
        "removed" => false,
        "topics" => [
          "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef",
          "0x000000000000000000000000b2b7c1795f19fbc28fda77a95e59edbb8b3709c8",
          "0x0000000000000000000000007795126b3ae468f44c901287de98594198ce38ea"
        ],
        "transactionHash" => "0xa74c2432c9cf7dbb875a385a2411fd8f13ca9ec12216864b1a1ead3c99de99cd",
        "transactionIndex" => "0x3"
      }
      |> Log.deserialize()
      |> Map.put(:extra_data, extra_data)

    {:ok, filter_pid} =
      Cartouche.Filter.start_link(
        name: ExpiredFilter,
        address: <<1::160>>,
        events: ["Transfer(address indexed from, address indexed to, uint amount)"],
        check_delay: 20,
        extra_data: extra_data,
        rpc_opts: [req_options: [plug: &ExpiredFilterClient.call/1]]
      )

    Cartouche.Filter.listen(ExpiredFilter)

    assert_receive {:event, {"Transfer", _}, ^log}, 500
    assert_receive {:log, ^log}, 500

    assert {:dictionary, dictionary} = Process.info(filter_pid, :dictionary)
    assert Keyword.get(dictionary, :expired_seen) == true
    assert Keyword.get(dictionary, :new_filter_count, 0) >= 2
  end

  defmodule UninstallClient do
    @moduledoc false

    def call(conn) do
      %{"method" => method, "params" => params, "id" => id} =
        conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

      send(Process.whereis(:cartouche_filter_uninstall), {method, params})

      result =
        case method do
          "eth_newFilter" -> "0xdeadf11e"
          "eth_newBlockFilter" -> "0xdeadb10c"
          "eth_newPendingTransactionFilter" -> "0xdeadpend"
          "eth_getFilterChanges" -> []
          "eth_uninstallFilter" -> true
        end

      Req.Test.json(conn, %{jsonrpc: "2.0", result: result, id: id})
    end
  end

  defmodule UninstallFailureClient do
    @moduledoc false

    def call(conn) do
      %{"method" => method, "id" => id} =
        conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

      response =
        case method do
          "eth_newFilter" ->
            %{jsonrpc: "2.0", result: "0xfailf11e", id: id}

          "eth_getFilterChanges" ->
            %{jsonrpc: "2.0", result: [], id: id}

          "eth_uninstallFilter" ->
            %{jsonrpc: "2.0", error: %{code: -32_000, message: "filter not found"}, id: id}
        end

      Req.Test.json(conn, response)
    end
  end

  defmodule BlockFilterClient do
    @moduledoc false

    def call(conn) do
      %{"method" => method, "id" => id} =
        conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

      result =
        case method do
          "eth_newBlockFilter" -> "0xb10cf11e"
          "eth_getFilterChanges" -> ["0xdc0818cf78f21a8e70579cb46a43643f78291264dda342ae31049421c82d21ae"]
          "eth_uninstallFilter" -> true
        end

      Req.Test.json(conn, %{jsonrpc: "2.0", result: result, id: id})
    end
  end

  defmodule PendingFilterClient do
    @moduledoc false

    def call(conn) do
      %{"method" => method, "id" => id} =
        conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

      result =
        case method do
          "eth_newPendingTransactionFilter" -> "0xpend1ng"
          "eth_getFilterChanges" -> ["0x88df016429689c079f3b2f6ad39fa052532c56795b733da78a91ebe6a713944b"]
          "eth_uninstallFilter" -> true
        end

      Req.Test.json(conn, %{jsonrpc: "2.0", result: result, id: id})
    end
  end

  defmodule ExpiredBlockFilterClient do
    @moduledoc false

    def call(conn) do
      %{"method" => method, "params" => params, "id" => id} =
        conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

      response =
        case {method, params} do
          {"eth_newBlockFilter", _} ->
            filter_id =
              case Process.get(:new_filter_count, 0) do
                0 -> "0xb10c035"
                _ -> "0xb10c036"
              end

            Process.put(:new_filter_count, Process.get(:new_filter_count, 0) + 1)
            %{jsonrpc: "2.0", result: filter_id, id: id}

          {"eth_getFilterChanges", ["0xb10c035"]} ->
            Process.put(:expired_seen, true)
            %{jsonrpc: "2.0", error: %{code: -32_000, message: "filter not found"}, id: id}

          {"eth_getFilterChanges", ["0xb10c036"]} ->
            %{
              jsonrpc: "2.0",
              result: ["0xdc0818cf78f21a8e70579cb46a43643f78291264dda342ae31049421c82d21ae"],
              id: id
            }

          {"eth_uninstallFilter", _} ->
            %{jsonrpc: "2.0", result: true, id: id}
        end

      Req.Test.json(conn, response)
    end
  end

  test "uninstalls the node-side filter with the issued filter id on stop" do
    Process.register(self(), :cartouche_filter_uninstall)

    {:ok, pid} =
      Cartouche.Filter.start_link(
        name: UninstallFilter,
        address: <<1::160>>,
        check_delay: 10_000,
        rpc_opts: [req_options: [plug: &UninstallClient.call/1]]
      )

    assert_receive {"eth_newFilter", _}, 500
    assert :ok = GenServer.stop(pid)
    assert_receive {"eth_uninstallFilter", ["0xdeadf11e"]}
  end

  test "a failed uninstall is logged and does not crash shutdown" do
    log =
      capture_log(fn ->
        {:ok, pid} =
          Cartouche.Filter.start_link(
            name: UninstallFailureFilter,
            address: <<1::160>>,
            check_delay: 10_000,
            rpc_opts: [req_options: [plug: &UninstallFailureClient.call/1]]
          )

        assert :ok = GenServer.stop(pid)
      end)

    assert log =~ "uninstall"
    assert log =~ "0xfailf11e"
  end

  test "block filters deliver hash lists to listeners" do
    {:ok, _pid} =
      Cartouche.Filter.start_link(
        name: BlockHashFilter,
        kind: :block,
        check_delay: 20,
        rpc_opts: [req_options: [plug: &BlockFilterClient.call/1]]
      )

    Cartouche.Filter.listen(BlockHashFilter)

    assert_receive {:hashes, [hash]}, 500
    assert hash == Cartouche.Hex.decode_word!("0xdc0818cf78f21a8e70579cb46a43643f78291264dda342ae31049421c82d21ae")
  end

  test "pending-transaction filters deliver hash lists to listeners" do
    {:ok, _pid} =
      Cartouche.Filter.start_link(
        name: PendingHashFilter,
        kind: :pending,
        check_delay: 20,
        rpc_opts: [req_options: [plug: &PendingFilterClient.call/1]]
      )

    Cartouche.Filter.listen(PendingHashFilter)

    assert_receive {:hashes, [hash]}, 500
    assert hash == Cartouche.Hex.decode_word!("0x88df016429689c079f3b2f6ad39fa052532c56795b733da78a91ebe6a713944b")
  end

  test "recreates a block filter when the node reports it expired" do
    {:ok, filter_pid} =
      Cartouche.Filter.start_link(
        name: ExpiredBlockFilter,
        kind: :block,
        check_delay: 20,
        rpc_opts: [req_options: [plug: &ExpiredBlockFilterClient.call/1]]
      )

    Cartouche.Filter.listen(ExpiredBlockFilter)

    assert_receive {:hashes, [hash]}, 500
    assert byte_size(hash) == 32

    assert {:dictionary, dictionary} = Process.info(filter_pid, :dictionary)
    assert Keyword.get(dictionary, :expired_seen) == true
    assert Keyword.get(dictionary, :new_filter_count, 0) >= 2
  end

  test "starts a log filter without an address" do
    {:ok, pid} =
      Cartouche.Filter.start_link(
        name: AddresslessFilter,
        check_delay: 10_000
      )

    assert Process.alive?(pid)
    assert :ok = GenServer.stop(pid)
  end

  defmodule ExpiredPendingFilterClient do
    @moduledoc false

    def call(conn) do
      %{"method" => method, "params" => params, "id" => id} =
        conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

      response =
        case {method, params} do
          {"eth_newPendingTransactionFilter", _} ->
            filter_id =
              case Process.get(:new_filter_count, 0) do
                0 -> "0xpend035"
                _ -> "0xpend036"
              end

            Process.put(:new_filter_count, Process.get(:new_filter_count, 0) + 1)
            %{jsonrpc: "2.0", result: filter_id, id: id}

          {"eth_getFilterChanges", ["0xpend035"]} ->
            Process.put(:expired_seen, true)
            %{jsonrpc: "2.0", error: %{code: -32_000, message: "filter not found"}, id: id}

          {"eth_getFilterChanges", ["0xpend036"]} ->
            %{
              jsonrpc: "2.0",
              result: ["0x88df016429689c079f3b2f6ad39fa052532c56795b733da78a91ebe6a713944b"],
              id: id
            }

          {"eth_uninstallFilter", _} ->
            %{jsonrpc: "2.0", result: true, id: id}
        end

      Req.Test.json(conn, response)
    end
  end

  test "recreates a pending-transaction filter when the node reports it expired" do
    {:ok, filter_pid} =
      Cartouche.Filter.start_link(
        name: ExpiredPendingFilter,
        kind: :pending,
        check_delay: 20,
        rpc_opts: [req_options: [plug: &ExpiredPendingFilterClient.call/1]]
      )

    Cartouche.Filter.listen(ExpiredPendingFilter)

    assert_receive {:hashes, [hash]}, 500
    assert byte_size(hash) == 32

    assert {:dictionary, dictionary} = Process.info(filter_pid, :dictionary)
    assert Keyword.get(dictionary, :expired_seen) == true
    assert Keyword.get(dictionary, :new_filter_count, 0) >= 2
  end

  defmodule StallingUninstallServer do
    @moduledoc false
    # A real socket, not a `Req.Test` plug: plugs are invoked in-process, so
    # `receive_timeout` never applies to them and they cannot exercise the
    # shutdown-budget bound in `Cartouche.Filter.uninstall_filter/1`.
    # Answers `eth_newFilter` immediately, then stalls forever on
    # `eth_uninstallFilter` so only the client-side timeout ends the call.

    @spec start() :: {:ok, String.t()}
    def start do
      {:ok, listen} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])
      {:ok, port} = :inet.port(listen)
      spawn_link(fn -> accept_loop(listen) end)
      {:ok, "http://127.0.0.1:#{port}"}
    end

    defp accept_loop(listen) do
      case :gen_tcp.accept(listen) do
        {:ok, socket} ->
          pid = spawn(fn -> serve(socket) end)
          :ok = :gen_tcp.controlling_process(socket, pid)
          accept_loop(listen)

        {:error, :closed} ->
          :ok
      end
    end

    defp serve(socket) do
      with {:ok, body} <- read_request(socket) do
        request = Jason.decode!(body)

        if request["method"] == "eth_uninstallFilter" do
          # Never reply. The filter must give up on its own timeout.
          Process.sleep(:infinity)
        else
          respond(socket, request["id"], "0xdeadf11e")
        end
      end
    end

    defp respond(socket, id, result) do
      json = Jason.encode!(%{jsonrpc: "2.0", id: id, result: result})

      :gen_tcp.send(
        socket,
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(json)}\r\nConnection: close\r\n\r\n" <>
          json
      )

      :gen_tcp.close(socket)
    end

    defp read_request(socket, acc \\ "") do
      case :gen_tcp.recv(socket, 0, 5_000) do
        {:ok, chunk} -> take_complete_request(socket, acc <> chunk)
        {:error, _} = error -> error
      end
    end

    defp take_complete_request(socket, acc) do
      case String.split(acc, "\r\n\r\n", parts: 2) do
        [headers, body] ->
          if byte_size(body) >= content_length(headers), do: {:ok, body}, else: read_request(socket, acc)

        _ ->
          read_request(socket, acc)
      end
    end

    defp content_length(headers) do
      headers
      |> String.split("\r\n")
      |> Enum.find_value(0, fn line ->
        case String.split(String.downcase(line), ":", parts: 2) do
          ["content-length", value] -> String.to_integer(String.trim(value))
          _ -> nil
        end
      end)
    end
  end

  test "a stalled uninstall gives up inside the supervisor shutdown budget" do
    {:ok, url} = StallingUninstallServer.start()

    log =
      capture_log(fn ->
        {:ok, pid} =
          Cartouche.Filter.start_link(
            name: StalledUninstallFilter,
            address: <<1::160>>,
            check_delay: 10_000,
            rpc_opts: [ethereum_node: url, req_options: [plug: nil]]
          )

        # A supervisor gives a trapping child 5_000 ms before killing it; the
        # uninstall must return well inside that, not after the 30_000 ms
        # transport default.
        {elapsed, :ok} = :timer.tc(fn -> GenServer.stop(pid, :normal, 4_500) end)
        assert div(elapsed, 1_000) < 4_000
      end)

    assert log =~ "uninstall"
    assert log =~ "0xdeadf11e"
  end

  test "rejects an unknown filter kind" do
    assert_raise ArgumentError, ~r/unknown filter kind/, fn ->
      Cartouche.Filter.start_link(name: BadKindFilter, kind: :nope)
    end
  end
end

defmodule Cartouche.Filter.IntegrationTest do
  use ExUnit.Case, async: true

  import Cartouche.Test.Live, only: [live_opts: 0]

  @moduletag :integration

  # Same mainnet anchor `rpc_integration_test.exs` pins. WETH9 transfers in this
  # block make `eth_getFilterLogs` deterministically non-empty, so the payload
  # shape is actually exercised instead of an empty list vacuously satisfying it.
  @weth9 "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"
  @anchor_block "0x112A880"

  # Mainnet produces a block roughly every 12 s, so a minute without one is a
  # node problem worth failing on, not a flake.
  @block_poll_attempts 30
  @block_poll_interval 2_000

  setup_all do
    Cartouche.Test.Live.assert_node_available!()
    :ok
  end

  test "log filter over a historical range decodes real logs, then uninstalls" do
    opts = live_opts()

    params = %{"address" => @weth9, "fromBlock" => @anchor_block, "toBlock" => @anchor_block}
    assert {:ok, id} = Cartouche.RPC.send_rpc("eth_newFilter", [params], opts)
    assert is_binary(id)

    # A freshly created filter has no *changes* yet — the backlog is what
    # `eth_getFilterLogs` returns, and that is where the shape is provable.
    assert {:ok, changes} = Cartouche.RPC.send_rpc("eth_getFilterChanges", [id], opts)
    assert is_list(changes)

    assert {:ok, logs} = Cartouche.RPC.get_filter_logs(id, opts)
    assert logs != [], "expected WETH9 logs in block #{@anchor_block}; is the node an archive node?"

    Enum.each(logs, fn log ->
      assert %Cartouche.Filter.Log{} = log
      assert byte_size(log.address) == 20
      assert byte_size(log.block_hash) == 32
      assert byte_size(log.transaction_hash) == 32
      assert log.block_number == 18_000_000
      assert Enum.all?(log.topics, &(byte_size(&1) == 32))
    end)

    assert {:ok, true} = Cartouche.RPC.send_rpc("eth_uninstallFilter", [id], opts)
  end

  test "block filter yields block hashes as the chain advances, then uninstalls" do
    opts = live_opts()
    assert {:ok, id} = Cartouche.RPC.new_block_filter(opts)
    assert is_binary(id)

    hashes = poll_until_non_empty(id, opts, @block_poll_attempts)

    assert hashes != [],
           "no new block in #{div(@block_poll_attempts * @block_poll_interval, 1_000)}s — the node is not following the chain"

    Enum.each(hashes, fn hash -> assert byte_size(Cartouche.Hex.decode_word!(hash)) == 32 end)

    assert {:ok, true} = Cartouche.RPC.send_rpc("eth_uninstallFilter", [id], opts)
  end

  test "pending-transaction filter installs and uninstalls; payload shape asserted only when the node shares its mempool" do
    opts = live_opts()
    assert {:ok, id} = Cartouche.RPC.new_pending_transaction_filter(opts)
    assert is_binary(id)

    assert {:ok, hashes} = Cartouche.RPC.send_rpc("eth_getFilterChanges", [id], opts)

    # Recorded observation, not a skip: most hosted archive endpoints install
    # the filter but never surface mempool contents to an external caller, so an
    # empty list is the node's real answer here. When the node does share it,
    # the payload must decode as 32-byte hashes.
    case hashes do
      [] ->
        assert hashes == []

      [_ | _] ->
        Enum.each(hashes, fn hash -> assert byte_size(Cartouche.Hex.decode_word!(hash)) == 32 end)
    end

    assert {:ok, true} = Cartouche.RPC.send_rpc("eth_uninstallFilter", [id], opts)
  end

  @spec poll_until_non_empty(String.t(), Keyword.t(), non_neg_integer()) :: [String.t()]
  defp poll_until_non_empty(_id, _opts, 0), do: []

  defp poll_until_non_empty(id, opts, remaining) do
    assert {:ok, hashes} = Cartouche.RPC.send_rpc("eth_getFilterChanges", [id], opts)

    if hashes == [] do
      Process.sleep(@block_poll_interval)
      poll_until_non_empty(id, opts, remaining - 1)
    else
      hashes
    end
  end
end
