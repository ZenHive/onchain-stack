defmodule Onchain.Tempo.Transaction.BuilderEstimateTest do
  # async: false — toggles the global `config :cartouche, Cartouche.RPC, plug: ...`
  # seam to stub the eth_estimateGas transport (Onchain.RPC -> Cartouche.RPC.send_rpc
  # -> Req). cartouche 0.5.0 replaced the removed `:cartouche, :client` Finch seam
  # with this Req.Test plug seam.
  use ExUnit.Case, async: false

  alias Onchain.Tempo.Transaction
  alias Onchain.Tempo.Transaction.Builder

  @private_key "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
  @recipient "0x70997970c51812dc3a010c7d01b50e0d17dc79c8"
  @token "0x20c0000000000000000000000000000000000000"
  @chain_id 42_431
  @amount 1_000_000
  @rpc_url "https://rpc.example.test"

  # RLP field index for gas_limit in the 0x76 envelope.
  @gas_limit_index 3

  # Fixed eth_estimateGas result so the headroom math is deterministic.
  @estimate_gas 50_000

  # Req.Test plug stubbing the eth_estimateGas transport. Echoes the request id and
  # returns the fixed result.
  defp stub_plug(conn) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    %{"id" => id} = Jason.decode!(body)
    result = "0x" <> Integer.to_string(@estimate_gas, 16)
    Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => id, "result" => result})
  end

  # Req.Test plug simulating a transport failure; onchain re-wraps it into
  # {:error, {:rpc_error, _}}.
  defp error_plug(conn), do: Req.Test.transport_error(conn, :timeout)

  defp with_plug(plug, fun) do
    prev = Application.get_env(:cartouche, Cartouche.RPC)
    Application.put_env(:cartouche, Cartouche.RPC, plug: plug)
    on_exit(fn -> restore_plug(prev) end)
    fun.()
  end

  defp restore_plug(nil), do: Application.delete_env(:cartouche, Cartouche.RPC)
  defp restore_plug(prev), do: Application.put_env(:cartouche, Cartouche.RPC, prev)

  defp estimate_opts do
    [
      private_key: @private_key,
      token: @token,
      recipient: @recipient,
      amount: @amount,
      chain_id: @chain_id,
      rpc_url: @rpc_url,
      nonce: 0
    ]
  end

  defp gas_limit_of(tx_hex) do
    {:ok, tx} = Transaction.deserialize(tx_hex)
    :binary.decode_unsigned(Enum.at(tx.fields, @gas_limit_index))
  end

  describe "gas estimation when :gas_limit is omitted" do
    test "sizes the tx from eth_estimateGas with the 1.25x headroom" do
      with_plug(&stub_plug/1, fn ->
        assert {:ok, tx_hex} = Builder.build_signed_transfer(estimate_opts())

        # ceil(50_000 * 5 / 4) = 62_500
        expected = div(@estimate_gas * 5 + 3, 4)
        assert gas_limit_of(tx_hex) == expected
      end)
    end

    test "applies estimation on the fee-payer path too" do
      with_plug(&stub_plug/1, fn ->
        assert {:ok, tx_hex} = Builder.build_fee_payer_transfer(estimate_opts())
        assert gas_limit_of(tx_hex) == div(@estimate_gas * 5 + 3, 4)
      end)
    end

    test "sums per-call estimates for a multicall" do
      with_plug(&stub_plug/1, fn ->
        calldata = Base.decode16!("a9059cbb", case: :lower)
        token_bin = Base.decode16!("20c0000000000000000000000000000000000000", case: :lower)
        calls = [[token_bin, <<>>, calldata], [token_bin, <<>>, calldata]]

        opts =
          estimate_opts()
          |> Keyword.delete(:token)
          |> Keyword.delete(:recipient)
          |> Keyword.delete(:amount)
          |> Keyword.merge(calls: calls, fee_token: @token)

        assert {:ok, tx_hex} = Builder.build_signed_multicall(opts)
        # Two calls summed, then headroom: ceil(100_000 * 5 / 4) = 125_000
        assert gas_limit_of(tx_hex) == div(@estimate_gas * 2 * 5 + 3, 4)
      end)
    end

    test "fetches the nonce from RPC when :nonce is also omitted" do
      with_plug(&stub_plug/1, fn ->
        opts = Keyword.delete(estimate_opts(), :nonce)
        assert {:ok, "0x76" <> _} = Builder.build_signed_transfer(opts)
      end)
    end

    test "propagates a failed estimate instead of falling back to a default" do
      with_plug(&error_plug/1, fn ->
        assert {:error, {:rpc_error, _}} = Builder.build_signed_transfer(estimate_opts())
      end)
    end
  end
end
