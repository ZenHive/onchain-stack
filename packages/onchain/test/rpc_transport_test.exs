defmodule Cartouche.RPCTransportTest do
  use ExUnit.Case, async: false

  @retry [max_retries: 1, backoff_ms: 0]
  @url "http://stub.invalid"

  setup do
    keys = [:ethereum_node, :req_options, Cartouche.RPC]
    previous = Map.new(keys, &{&1, Application.fetch_env(:cartouche, &1)})

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, config} -> Application.put_env(:cartouche, key, config)
          :error -> Application.delete_env(:cartouche, key)
        end
      end
    end)

    :ok
  end

  test "typed calls retry transport failures before decoding" do
    opts = options([{:transport_error, :closed}, {:result, "0x2a"}])
    assert {:ok, 42} = Cartouche.RPC.eth_block_number(Keyword.put(opts, :retry, @retry))
    assert Process.get(:rpc_transport_responses) == []
  end

  test "typed calls preserve transport errors without opt-in and stop at the retry limit" do
    opts = options([{:transport_error, :closed}, {:result, "0x2a"}])
    assert {:error, "[Cartouche] HTTP client error: :closed"} = Cartouche.RPC.eth_block_number(opts)
    assert [{:result, "0x2a"}] = Process.get(:rpc_transport_responses)

    opts = options([{:transport_error, :closed}, {:transport_error, :timeout}])

    assert {:error, "[Cartouche] HTTP client error: :timeout"} =
             Cartouche.RPC.eth_block_number(Keyword.put(opts, :retry, @retry))
  end

  test "non-JSON gateway failures retry only when opted in" do
    opts = options([{:http_error, 503, "upstream unavailable"}, {:result, "0x2a"}])
    assert {:ok, 42} = Cartouche.RPC.eth_block_number(Keyword.put(opts, :retry, @retry))

    opts = options([{:http_error, 503, "upstream unavailable"}, {:result, "0x2a"}])

    assert {:error, %Req.Response{status: 503, body: "upstream unavailable"}} =
             Cartouche.RPC.eth_block_number(opts)
  end

  test "invalid retry policy returns an error without sending" do
    opts = options([])

    for policy <- [true, [max_retries: -1], [backoff_ms: -1]] do
      assert {:error, {:invalid_retry_policy, ^policy}} =
               Cartouche.RPC.eth_block_number(Keyword.put(opts, :retry, policy))
    end
  end

  test "typed decode errors do not resend the request" do
    opts = options([{:result, "bad"}, {:result, "0x2a"}])

    assert {:error, _} =
             Cartouche.RPC.send_rpc(
               "eth_blockNumber",
               [],
               opts ++ [retry: @retry, decode: fn _ -> raise "bad decode" end]
             )

    assert [{:result, "0x2a"}] = Process.get(:rpc_transport_responses)
  end

  for {code, message, tag} <- [
        {-32_601, "Method not found", :method_not_found},
        {-32_600, "Unsupported method: eth_baseFee on ETH_MAINNET", :method_not_found},
        {-32_600, "trace_block is not available on the Free tier - upgrade", :namespace_unavailable},
        {-32_001, "Unable to complete request at this time.", :unavailable}
      ] do
    test "shared refusal classification: #{code} #{tag} #{message}" do
      for status <- [200, 503] do
        opts = options([{:rpc_error, unquote(code), unquote(message), status}, {:result, "0x2a"}])

        assert {:error, {unquote(tag), %{code: unquote(code), message: unquote(message)}}} =
                 Cartouche.RPC.eth_block_number(Keyword.put(opts, :retry, @retry))

        assert [{:result, "0x2a"}] = Process.get(:rpc_transport_responses)
      end
    end
  end

  test "unclassified JSON-RPC codes retain raw maps and are final" do
    for code <- [3, -32_000, -32_016, -32_602, -32_600, -32_001] do
      opts = options([{:rpc_error, code, "unchanged", 200}, {:result, "0x2a"}])

      assert {:error, %{code: ^code, message: "unchanged"}} =
               Cartouche.RPC.eth_block_number(Keyword.put(opts, :retry, @retry))

      assert [{:result, "0x2a"}] = Process.get(:rpc_transport_responses)
    end
  end

  test "non-2xx JSON-RPC errors with a code remain final, even when unclassified" do
    opts = options([{:rpc_error, -32_602, "Invalid params", 400}, {:result, "0x2a"}])

    assert {:error, %Req.Response{status: 400}} =
             Cartouche.RPC.eth_block_number(Keyword.put(opts, :retry, @retry))

    assert [{:result, "0x2a"}] = Process.get(:rpc_transport_responses)
  end

  test "a non-2xx batch array keeps the historical raw transport error" do
    opts = options([{:rpc_error, -32_601, "Method not found", 400}])

    assert {:error, {:rpc_error, %{message: message}}} =
             Onchain.RPC.batch([{"eth_blockNumber", []}], opts)

    assert message =~ "Method not found"
  end

  test "a non-2xx top-level JSON-RPC refusal is classified" do
    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => nil,
        "error" => %{"code" => -32_601, "message" => "Method not found"}
      })

    opts = options([{:http_error, 400, body}])

    assert {:error, {:method_not_found, %{code: -32_601, message: "Method not found"}}} =
             Onchain.RPC.batch([{"eth_blockNumber", []}], opts)
  end

  test "mev preserves classified refusals and still wraps other JSON-RPC maps" do
    Application.put_env(:cartouche, Cartouche.RPC, plug: &__MODULE__.mev_plug/1)
    raw_tx = "0x" <> String.duplicate("ab", 50)

    Process.put(:mev_rpc_error, {-32_601, "Method not found"})

    assert {:error, {:method_not_found, %{code: -32_601, message: "Method not found"}}} =
             Onchain.MEV.send_private_transaction(raw_tx, endpoint: @url)

    Process.put(:mev_rpc_error, {-32_000, "execution reverted"})

    assert {:error, {:rpc_error, %{code: -32_000, message: "execution reverted"}}} =
             Onchain.MEV.send_private_transaction(raw_tx, endpoint: @url)
  end

  @spec mev_plug(Plug.Conn.t()) :: Plug.Conn.t()
  def mev_plug(conn) do
    body = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()
    {code, message} = Process.get(:mev_rpc_error)

    Req.Test.json(conn, %{
      "jsonrpc" => "2.0",
      "id" => body["id"],
      "error" => %{"code" => code, "message" => message}
    })
  end

  test "batch retries use the same transport and classified application errors are final" do
    opts = options([{:transport_error, :closed}, {:result, "0x2a"}])

    assert {:ok, ["0x2a"]} =
             Onchain.RPC.batch([{"eth_blockNumber", []}], Keyword.put(opts, :retry, @retry))

    opts = options([{:rpc_error, -32_601, "Method not found", 200}, {:result, "0x2a"}])

    assert {:error, {:method_not_found, %{code: -32_601}}} =
             Cartouche.RPC.send_batch([{"unknown", []}], Keyword.put(opts, :retry, @retry))

    assert [{:result, "0x2a"}] = Process.get(:rpc_transport_responses)
  end

  test "single and batch use the same app defaults and per-call overrides" do
    previous_owner = Application.get_env(:onchain, Onchain.RPC)
    previous_req = Application.get_env(:onchain, :req_options)

    on_exit(fn ->
      restore_env(:onchain, Onchain.RPC, previous_owner)
      restore_env(:onchain, :req_options, previous_req)
    end)

    Application.put_env(:onchain, Onchain.RPC,
      plug: fn _conn -> flunk("onchain owner config is not the JSON-RPC transport") end
    )

    Application.put_env(:onchain, :req_options,
      plug: fn _conn -> flunk("onchain req_options are not the JSON-RPC transport") end
    )

    Application.put_env(:cartouche, :ethereum_node, "http://configured.invalid")
    Application.put_env(:cartouche, Cartouche.RPC, plug: fn _ -> flunk("global options must override owner") end)

    Application.put_env(:cartouche, :req_options,
      plug: fn conn ->
        assert conn.host == "configured.invalid"
        respond(conn, {:result, "0x2a"})
      end
    )

    assert {:ok, 42} = Cartouche.RPC.eth_block_number()
    assert {:ok, ["0x2a"]} = Onchain.RPC.batch([{"eth_blockNumber", []}])

    for call <- [&Cartouche.RPC.eth_block_number/1, &Onchain.RPC.batch([{"eth_blockNumber", []}], &1)] do
      opts = [
        rpc_url: @url,
        ethereum_node: "http://ignored.invalid",
        req_options: [
          plug: fn conn ->
            assert conn.host == "stub.invalid"
            respond(conn, {:result, "0x2a"})
          end
        ]
      ]

      assert {:ok, _} = call.(opts)
    end
  end

  test "missing URL fails explicitly for both modules and batch" do
    Application.delete_env(:cartouche, :ethereum_node)
    assert {:error, {:missing_option, :ethereum_node}} = Cartouche.RPC.eth_block_number()
    assert {:error, {:missing_option, :ethereum_node}} = Onchain.RPC.block_number()
    assert {:error, {:missing_option, :ethereum_node}} = Onchain.RPC.batch([{"eth_blockNumber", []}])
  end

  test "typed calls and batches each emit one span, including retries" do
    handler = {__MODULE__, make_ref()}
    events = for suffix <- [:start, :stop], do: [:onchain, :rpc, :request, suffix]
    :ok = :telemetry.attach_many(handler, events, &__MODULE__.handle_event/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)

    for {method, call} <- [
          {"eth_blockNumber", &Cartouche.RPC.eth_block_number/1},
          {"batch", &Onchain.RPC.batch([{"eth_blockNumber", []}], &1)}
        ] do
      opts = options([{:transport_error, :closed}, {:result, "0x2a"}])
      assert {:ok, _} = call.(Keyword.put(opts, :retry, @retry))
      assert_receive {[:onchain, :rpc, :request, :start], %{system_time: _}, %{method: ^method}}
      assert_receive {[:onchain, :rpc, :request, :stop], %{duration: _}, %{method: ^method, status: :ok}}
      refute_receive {[:onchain, :rpc, :request, :start], _, _}
    end
  end

  @spec handle_event([atom()], map(), map(), pid()) :: term()
  def handle_event(event, measurements, metadata, pid), do: send(pid, {event, measurements, metadata})

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)

  defp options(responses) do
    Process.put(:rpc_transport_responses, responses)

    [
      rpc_url: @url,
      req_options: [
        plug: fn conn ->
          [response | rest] = Process.get(:rpc_transport_responses)
          Process.put(:rpc_transport_responses, rest)
          respond(conn, response)
        end
      ]
    ]
  end

  defp respond(conn, {:transport_error, reason}), do: Req.Test.transport_error(conn, reason)

  defp respond(conn, {:http_error, status, body}), do: Plug.Conn.send_resp(conn, status, body)

  defp respond(conn, response) do
    body = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

    {status, field} =
      case response do
        {:result, value} -> {200, %{"result" => value}}
        {:rpc_error, code, message, status} -> {status, %{"error" => %{"code" => code, "message" => message}}}
      end

    reply = fn request -> Map.merge(%{"jsonrpc" => "2.0", "id" => request["id"]}, field) end
    result = if is_list(body), do: Enum.map(body, reply), else: reply.(body)
    conn |> Plug.Conn.put_status(status) |> Req.Test.json(result)
  end
end
