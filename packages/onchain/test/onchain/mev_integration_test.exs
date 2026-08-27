defmodule Onchain.MEVIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.MEV

  @moduletag :integration

  # A syntactically valid 0x-hex blob that is NOT a real signed transaction. A
  # Flashbots-style relay parses the request envelope, then rejects the payload
  # at the JSON-RPC layer — exactly what proves the round trip without spending
  # gas or needing a funded key.
  @bogus_raw_tx "0x02" <> String.duplicate("ab", 64)
  @timeout_ms 15_000

  describe "send_private_transaction/2 against a real relay" do
    test "round-trips the request and parses the relay's JSON-RPC response" do
      relay = mev_relay_url!()

      result =
        MEV.send_private_transaction(@bogus_raw_tx,
          endpoint: relay,
          headers: auth_headers(),
          timeout: @timeout_ms
        )

      case result do
        {:ok, hash} ->
          assert String.starts_with?(hash, "0x")

        {:error, {:rpc_error, %{code: code} = map}} when is_integer(code) ->
          # Relay accepted the request shape and rejected the bogus tx at the
          # JSON-RPC layer (e.g. invalid/underpriced). Round trip confirmed.
          assert is_binary(Map.get(map, :message))

        {:error, {:rpc_error, map}} ->
          flunk("""
          Relay did not return a JSON-RPC response (no :code) — transport failure?

          Got: #{inspect(map)}

          Point MEV_RELAY_URL at a Flashbots-style relay that accepts
          eth_sendPrivateTransaction without searcher auth, e.g.
            export MEV_RELAY_URL="https://rpc.flashbots.net"
          Set MEV_AUTH_HEADER if your relay requires an X-Flashbots-Signature.
          """)
      end
    end
  end

  defp mev_relay_url! do
    System.get_env("MEV_RELAY_URL") ||
      ExUnit.Assertions.flunk("""
      Missing MEV relay URL!

      Set this environment variable to a Flashbots-style private relay:
        export MEV_RELAY_URL="https://rpc.flashbots.net"

      Optionally set relay auth (passed through as a request header):
        export MEV_AUTH_HEADER="X-Flashbots-Signature: 0xaddr:0xsig"
      """)
  end

  # Parses an optional "Header-Name: value" env var into the :headers shape.
  defp auth_headers do
    case System.get_env("MEV_AUTH_HEADER") do
      nil ->
        []

      raw ->
        case String.split(raw, ":", parts: 2) do
          [name, value] -> [{String.trim(name), String.trim(value)}]
          _ -> []
        end
    end
  end
end
