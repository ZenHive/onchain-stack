defmodule Cartouche.Test.LiveTest do
  use ExUnit.Case, async: false

  alias Cartouche.Test.Live

  @envs ~w(CARTOUCHE_LIVE_NODE_URL ETHEREUM_ALCHEMY_URL ETHEREUM_INFURA_URL CLOUDFLARE_ETHEREUM_API_URL)

  setup do
    original = Map.new(@envs, &{&1, System.get_env(&1)})
    Enum.each(@envs, &System.delete_env/1)
    on_exit(fn -> System.put_env(original) end)
  end

  test "the zero-arity lane retains its default and override" do
    assert Live.live_rpc_url() == "http://127.0.0.1:8545"
    assert Live.live_rpc_url(:archive) == Live.live_rpc_url()
    System.put_env("CARTOUCHE_LIVE_NODE_URL", "http://archive.example/private-key")
    assert Live.live_opts() == Live.live_opts(:archive)
    assert Live.live_rpc_url() == "http://archive.example/private-key"
  end

  test "each hosted lane resolves only its own variable and clears the stub plug" do
    for {endpoint, env} <- Enum.zip([:alchemy, :infura, :cloudflare], tl(@envs)) do
      System.put_env(env, "https://#{endpoint}.example/private-key")

      assert Live.live_opts(endpoint) == [
               req_options: [plug: nil],
               ethereum_node: "https://#{endpoint}.example/private-key",
               timeout: 30_000
             ]
    end
  end

  test "missing and empty hosted variables fail with an export command, never skip" do
    for {endpoint, env} <- Enum.zip([:alchemy, :infura, :cloudflare], tl(@envs)), value <- [nil, ""] do
      System.put_env(%{env => value})
      error = assert_raise ExUnit.AssertionError, fn -> Live.live_rpc_url(endpoint) end
      assert error.message =~ "export #{env}='https://your-mainnet-endpoint'"
      assert error.message =~ "a real result or its real refusal, never a skip"
    end
  end

  test "a portability claim requires archive plus distinct hosted lanes" do
    for expectations <- [
          [],
          [archive: fn _ -> true end],
          [alchemy: fn _ -> true end],
          [archive: fn _ -> true end, archive: fn _ -> true end]
        ] do
      assert_raise ExUnit.AssertionError, fn ->
        Live.assert_portability!(fn _ -> flunk("must not call RPC") end, expectations)
      end
    end

    System.put_env("ETHEREUM_ALCHEMY_URL", Live.live_rpc_url())

    assert_raise ExUnit.AssertionError, ~r/distinct URLs/, fn ->
      Live.assert_portability!(fn _ -> flunk("must not call RPC") end,
        archive: fn _ -> true end,
        alchemy: fn _ -> true end
      )
    end
  end

  test "both real RPC answers reach their predicates, including method refusals" do
    for code <- [-32_601, -32_600] do
      System.put_env("CARTOUCHE_LIVE_NODE_URL", node_url("0x1", %{"result" => "0x2a"}))
      System.put_env("ETHEREUM_ALCHEMY_URL", node_url("0x1", %{"error" => %{"code" => code, "message" => "refused"}}))

      assert [archive: {:ok, 42}, alchemy: {:error, %{code: ^code, message: "refused"}}] =
               Live.assert_portability!(&Cartouche.RPC.base_fee/1,
                 archive: &match?({:ok, 42}, &1),
                 alchemy: &match?({:error, %{code: ^code, message: "refused"}}, &1)
               )
    end
  end

  test "one call can succeed on archive and multiple hosted lanes" do
    for env <- Enum.take(@envs, 3) do
      System.put_env(env, node_url("0x1", %{"result" => "0x2a"}))
    end

    assert [archive: {:ok, 42}, alchemy: {:ok, 42}, infura: {:ok, 42}] =
             Live.assert_portability!(&Cartouche.RPC.base_fee/1,
               archive: &match?({:ok, 42}, &1),
               alchemy: &match?({:ok, 42}, &1),
               infura: &match?({:ok, 42}, &1)
             )
  end

  test "unreachable endpoint fails the chain probe without printing its URL" do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    System.put_env("ETHEREUM_ALCHEMY_URL", "http://127.0.0.1:#{port}/private-key")

    error = assert_raise ExUnit.AssertionError, fn -> Live.assert_node_available!(:alchemy) end
    assert error.message =~ "ETHEREUM_ALCHEMY_URL is unreachable"
    refute error.message =~ "private-key"
  end

  test "an unexpected archive or hosted answer fails without printing credentials" do
    System.put_env("CARTOUCHE_LIVE_NODE_URL", node_url("0x1", %{"result" => "0x2a"}))
    System.put_env("ETHEREUM_ALCHEMY_URL", node_url("0x1", %{"result" => "0x2a"}))

    for endpoint <- [:archive, :alchemy] do
      expectations = [archive: fn _ -> true end, alchemy: fn _ -> true end]
      expectations = Keyword.put(expectations, endpoint, fn _ -> false end)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          Live.assert_portability!(fn opts -> {:error, opts[:ethereum_node]} end, expectations)
        end

      assert error.message =~ "returned an unexpected answer"
      refute error.message =~ "private-key"
    end
  end

  test "mainnet pin applies to archive and hosted endpoints without exposing responses" do
    for {endpoint, env} <- [archive: "CARTOUCHE_LIVE_NODE_URL", alchemy: "ETHEREUM_ALCHEMY_URL"] do
      System.put_env(env, node_url("0xaa36a7", %{}))
      error = assert_raise ExUnit.AssertionError, fn -> Live.assert_node_available!(endpoint) end
      assert error.message =~ env
      assert error.message =~ "chain ID other than 1"
      refute error.message =~ "private-key"
    end
  end

  # Real loopback HTTP keeps plug: nil and exercises the per-endpoint transport.
  defp node_url(chain_id, answer) do
    owner = self()
    ref = make_ref()

    start_supervised!(
      {Task,
       fn ->
         {:ok, listen} = :gen_tcp.listen(0, [:binary, packet: :http_bin, active: false, ip: {127, 0, 0, 1}])
         {:ok, port} = :inet.port(listen)
         send(owner, {ref, port})
         serve(listen, chain_id, answer)
       end},
      id: ref
    )

    assert_receive {^ref, port}
    "http://127.0.0.1:#{port}/private-key"
  end

  defp serve(listen, chain_id, answer) do
    {:ok, socket} = :gen_tcp.accept(listen)
    {:ok, {:http_request, :POST, _, _}} = :gen_tcp.recv(socket, 0, 5_000)
    length = read_headers(socket, 0)
    :ok = :inet.setopts(socket, packet: :raw)
    {:ok, body} = :gen_tcp.recv(socket, length, 5_000)
    request = Jason.decode!(body)
    result = if request["method"] == "eth_chainId", do: %{"result" => chain_id}, else: answer
    json = Jason.encode!(Map.merge(result, %{"jsonrpc" => "2.0", "id" => request["id"]}))

    :ok =
      :gen_tcp.send(
        socket,
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(json)}\r\nConnection: close\r\n\r\n" <>
          json
      )

    :ok = :gen_tcp.close(socket)
    serve(listen, chain_id, answer)
  end

  defp read_headers(socket, length) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, {:http_header, _, :"Content-Length", _, value}} -> read_headers(socket, String.to_integer(value))
      {:ok, {:http_header, _, _, _, _}} -> read_headers(socket, length)
      {:ok, :http_eoh} -> length
    end
  end
end
