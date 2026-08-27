defmodule Onchain.EthCallStub do
  @moduledoc false

  # Shared eth_call success-response stub for unit tests that need a real
  # ABI-encoded eth_call result without a live RPC endpoint. Injects a Req plug
  # at cartouche's transport seam — single-call RPC flows through
  # Cartouche.RPC.send_rpc/3, so `config :cartouche, Cartouche.RPC, plug:` is
  # the seam (mirrors Onchain.RPC.RevertTest's inline StubClient).
  #
  # Usage: `use Onchain.EthCallStub` inside an `async: false` ExUnit.Case, then
  # call `queue_response/2` before invoking the wrapper under test.

  @stub_key :onchain_eth_call_stub_response

  defmacro __using__(_opts) do
    quote do
      setup_all do
        previous = Application.get_env(:cartouche, Cartouche.RPC)
        Application.put_env(:cartouche, Cartouche.RPC, plug: &Onchain.EthCallStub.call/1)

        on_exit(fn ->
          case previous do
            nil -> Application.delete_env(:cartouche, Cartouche.RPC)
            config -> Application.put_env(:cartouche, Cartouche.RPC, config)
          end
        end)

        :ok
      end
    end
  end

  @doc false
  @spec call(Plug.Conn.t()) :: Plug.Conn.t()
  def call(conn) do
    %{"id" => id} = conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

    case Process.get(@stub_key) do
      nil -> raise "Onchain.EthCallStub: no response queued"
      hex_result -> Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => id, "result" => hex_result})
    end
  end

  @doc false
  # Builds an eth_call-shaped result hex by ABI-encoding `value` against a
  # throwaway `stub(<type>)` selector and stripping the 4-byte function
  # selector — the parameter encoding for a call and for a `(type)` return
  # tuple are byte-identical, so this yields exactly what `Onchain.ABI.decode_response/3`
  # expects from a real eth_call result.
  @spec queue_response(String.t(), term()) :: :ok
  def queue_response(type, value) do
    calldata = Onchain.ABI.encode_call!("stub(#{type})", [value])
    <<"0x", _selector::binary-size(8), rest::binary>> = calldata
    Process.put(@stub_key, "0x" <> rest)
    :ok
  end

  @doc false
  # Queue a raw 0x-prefixed hex result (for non-canonical / adversarial payloads).
  @spec queue_hex(String.t()) :: :ok
  def queue_hex(hex) when is_binary(hex) do
    Process.put(@stub_key, hex)
    :ok
  end
end
