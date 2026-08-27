defmodule Onchain.RPCStub do
  @moduledoc false

  # A loopback JSON-RPC server for unit tests that need to exercise the decode
  # half of a read wrapper without touching a real node.
  #
  # `start/1` returns a URL to hand to `rpc_opts/1`; the handler receives the
  # decoded JSON-RPC request and returns either a raw `eth_call` result string
  # or `{:error, error_object}` to drive the error branch. `payload_handler/2`
  # covers the common case: a selector-keyed map of canned return data, with a
  # loud flunk when a call arrives that the test did not plan for.

  import ExUnit.Assertions, only: [flunk: 1]
  import ExUnit.Callbacks, only: [on_exit: 1]

  @automatic_port 0
  @receive_all_bytes 0
  @rpc_timeout_ms 2_000
  @stub_ready_timeout_ms 1_000
  @stub_accept_timeout_ms 5_000
  @selector_start 0
  @selector_length 10

  @doc false
  @spec start((map() -> term())) :: String.t()
  def start(handler) do
    {:ok, listen} =
      :gen_tcp.listen(@automatic_port, [:binary, packet: :http_bin, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    {:ok, port} = :inet.port(listen)
    parent = self()

    pid =
      spawn_link(fn ->
        send(parent, {:stub_ready, self()})
        stub_loop(listen, handler)
      end)

    receive do
      {:stub_ready, ^pid} -> :ok
    after
      @stub_ready_timeout_ms -> flunk("JSON-RPC stub failed to start")
    end

    on_exit(fn ->
      Process.exit(pid, :kill)
      :gen_tcp.close(listen)
    end)

    "http://127.0.0.1:#{port}"
  end

  @doc false
  @spec rpc_opts(String.t()) :: keyword()
  def rpc_opts(url) do
    [rpc_url: url, timeout: @rpc_timeout_ms, req_options: [connect_options: [protocols: [:http1]]]]
  end

  @doc false
  @spec selector(String.t(), list()) :: String.t()
  def selector(signature, params) do
    {:ok, hex} = Onchain.ABI.encode_call(signature, params)
    String.slice(hex, @selector_start, @selector_length)
  end

  @doc false
  @spec encode(list(), list()) :: String.t()
  def encode(types, data) do
    "0x" <> Base.encode16(encode_raw(types, data), case: :lower)
  end

  # Raw ABI bytes rather than a hex string — needed when the encoded value is
  # itself a `bytes` member of an outer tuple (e.g. a Multicall3 sub-result).
  @doc false
  @spec encode_raw(list(), list()) :: binary()
  def encode_raw(types, data) do
    ABI.encode(types, data)
  end

  # A never-funded, well-known throwaway secp256k1 key (scalar 1). Present so
  # write-path unit tests can drive the real sign-and-encode path offline; it
  # guards nothing and controls no balance on any chain.
  @test_private_key "0x0000000000000000000000000000000000000000000000000000000000000001"

  @doc false
  @spec test_private_key() :: String.t()
  def test_private_key, do: @test_private_key

  # Signer options that reach the broadcast step without any RPC preflight:
  # an explicit `:gas_limit` skips `eth_estimateGas`, and `:nonce` skips a
  # nonce lookup, so the stub only ever sees `eth_sendRawTransaction`.
  @doc false
  @spec write_opts(String.t(), keyword()) :: keyword()
  def write_opts(url, extra \\ []) do
    Keyword.merge(
      [
        private_key: @test_private_key,
        chain_id: 1,
        nonce: 0,
        gas_limit: 200_000,
        rpc_url: url,
        timeout: @rpc_timeout_ms,
        req_options: [connect_options: [protocols: [:http1]]]
      ],
      extra
    )
  end

  # Builds a handler that answers `eth_sendRawTransaction` with `tx_hash`. When
  # `seen` is an Agent, the signed raw transaction hex is prepended to it so a
  # test can assert what was actually broadcast.
  @doc false
  @spec send_tx_handler(term(), pid() | nil) :: (map() -> term())
  def send_tx_handler(tx_hash, seen \\ nil) do
    fn
      %{"method" => "eth_sendRawTransaction", "params" => [raw | _]} ->
        if seen, do: Agent.update(seen, &[raw | &1])
        tx_hash

      %{"method" => method} ->
        flunk("stub received an unexpected JSON-RPC method: #{method}")
    end
  end

  # Builds a handler that answers `eth_call` from a selector-keyed payload map.
  # `seen` is an Agent the handler prepends each `to` address to, so a test can
  # assert which contract was addressed as well as what was decoded.
  @doc false
  @spec payload_handler(map(), pid() | nil) :: (map() -> term())
  def payload_handler(payloads, seen \\ nil) do
    fn
      %{"method" => "eth_call", "params" => [%{"data" => data, "to" => to} | _]} ->
        if seen, do: Agent.update(seen, &[to | &1])
        selector = String.slice(String.downcase(data), @selector_start, @selector_length)

        Map.get_lazy(payloads, selector, fn ->
          flunk("stub has no payload for selector #{selector} (data=#{data})")
        end)

      %{"method" => method} ->
        flunk("stub received an unexpected JSON-RPC method: #{method}")
    end
  end

  @spec stub_loop(:gen_tcp.socket(), (map() -> term())) :: :ok
  defp stub_loop(listen, handler) do
    case :gen_tcp.accept(listen, @stub_accept_timeout_ms) do
      {:ok, socket} ->
        serve_one(socket, handler)
        stub_loop(listen, handler)

      {:error, :timeout} ->
        stub_loop(listen, handler)

      {:error, :closed} ->
        :ok
    end
  end

  @spec serve_one(:gen_tcp.socket(), (map() -> term())) :: :ok
  defp serve_one(socket, handler) do
    {:ok, {:http_request, :POST, _, _}} = :gen_tcp.recv(socket, @receive_all_bytes)
    length = recv_content_length(socket, @receive_all_bytes)
    :ok = :inet.setopts(socket, packet: :raw)
    {:ok, body} = :gen_tcp.recv(socket, length)
    decoded = Jason.decode!(body)
    response = rpc_response(decoded, handler.(decoded))
    payload = Jason.encode!(response)

    :ok =
      :gen_tcp.send(socket, [
        "HTTP/1.1 200 OK\r\n",
        "content-type: application/json\r\n",
        "content-length: #{byte_size(payload)}\r\n",
        "connection: close\r\n\r\n",
        payload
      ])

    :gen_tcp.close(socket)
  end

  @spec rpc_response(map(), term()) :: map()
  defp rpc_response(decoded, {:error, error}) do
    %{"jsonrpc" => "2.0", "id" => decoded["id"], "error" => error}
  end

  defp rpc_response(decoded, result) do
    %{"jsonrpc" => "2.0", "id" => decoded["id"], "result" => result}
  end

  @spec recv_content_length(:gen_tcp.socket(), term()) :: non_neg_integer()
  defp recv_content_length(socket, acc) do
    case :gen_tcp.recv(socket, @receive_all_bytes) do
      {:ok, :http_eoh} ->
        acc

      {:ok, {:http_header, _, name, _, value}} ->
        if header_name(name) == "content-length" do
          recv_content_length(socket, String.to_integer(header_value(value)))
        else
          recv_content_length(socket, acc)
        end
    end
  end

  @spec header_name(term()) :: String.t()
  defp header_name(name) when is_atom(name), do: name |> Atom.to_string() |> String.downcase()
  defp header_name(name) when is_binary(name), do: String.downcase(name)
  defp header_name(name) when is_list(name), do: name |> List.to_string() |> String.downcase()

  @spec header_value(term()) :: String.t()
  defp header_value(value) when is_binary(value), do: value
  defp header_value(value) when is_list(value), do: List.to_string(value)
end
