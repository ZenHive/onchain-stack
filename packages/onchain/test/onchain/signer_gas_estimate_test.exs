defmodule Onchain.Signer.GasEstimateTest do
  # Mutates global cartouche client config; cannot run async with other RPC tests.
  use ExUnit.Case, async: false

  alias Cartouche.Transaction.V2
  alias Onchain.Signer

  # Deterministic test key (also used in signer_test.exs).
  @test_key_hex "0x800509fa3e80882ad0be77c27505bdc91380f800d51ed80897d22f9fcc75f4bf"
  @test_chain_id 11_155_111
  @dummy_to "0x" <> String.duplicate("ab", 20)
  @fake_tx_hash "0x" <> String.duplicate("cd", 32)

  # Req function plug that dispatches on the JSON-RPC method, pops responses from a
  # per-process queue, records the methods seen, and captures the raw tx broadcast.
  # Injected via cartouche's `config :cartouche, Cartouche.RPC, plug:` single-call seam.
  defmodule StubClient do
    @moduledoc false

    @queue_key :onchain_signer_gas_estimate_queue
    @methods_key :onchain_signer_gas_estimate_methods
    @raw_tx_key :onchain_signer_gas_estimate_raw_tx
    @estimate_call_key :onchain_signer_gas_estimate_call

    def call(conn) do
      %{"id" => id, "method" => method, "params" => params} =
        conn |> Req.Test.raw_body() |> IO.iodata_to_binary() |> Jason.decode!()

      Process.put(@methods_key, Process.get(@methods_key, []) ++ [method])
      if method == "eth_sendRawTransaction", do: Process.put(@raw_tx_key, hd(params))
      if method == "eth_estimateGas", do: Process.put(@estimate_call_key, hd(params))

      extra =
        case pop_for(method) do
          {:error, payload} -> %{"error" => payload}
          result -> %{"result" => result}
        end

      Req.Test.json(conn, Map.merge(%{"jsonrpc" => "2.0", "id" => id}, extra))
    end

    @spec queue(keyword()) :: :ok
    def queue(responses) do
      Process.put(@queue_key, responses)
      Process.put(@methods_key, [])
      Process.delete(@raw_tx_key)
      Process.delete(@estimate_call_key)
      :ok
    end

    @spec methods() :: [String.t()]
    def methods, do: Process.get(@methods_key, [])

    @spec raw_tx() :: String.t() | nil
    def raw_tx, do: Process.get(@raw_tx_key)

    @spec estimate_call() :: map() | nil
    def estimate_call, do: Process.get(@estimate_call_key)

    defp pop_for(method) do
      tag = if method == "eth_estimateGas", do: :estimate, else: :send
      queue = Process.get(@queue_key, [])

      case Keyword.pop_first(queue, tag) do
        {nil, _} -> flunk_unexpected(method)
        {value, rest} -> Process.put(@queue_key, rest) && value
      end
    end

    defp flunk_unexpected(method), do: raise("StubClient: no queued response for #{method}")
  end

  setup_all do
    previous = Application.get_env(:cartouche, Cartouche.RPC)
    Application.put_env(:cartouche, Cartouche.RPC, plug: &StubClient.call/1)

    on_exit(fn ->
      case previous do
        nil -> Application.delete_env(:cartouche, Cartouche.RPC)
        config -> Application.put_env(:cartouche, Cartouche.RPC, config)
      end
    end)

    :ok
  end

  defp base_opts(extra) do
    Keyword.merge(
      [
        private_key: @test_key_hex,
        nonce: 0,
        chain_id: @test_chain_id,
        rpc_url: "http://stub.invalid"
      ],
      extra
    )
  end

  defp decoded_gas_limit do
    {:ok, %V2{} = tx} = StubClient.raw_tx() |> Onchain.Hex.decode!() |> V2.decode()
    tx.gas_limit
  end

  describe "auto-estimate when :gas_limit is omitted" do
    test "calls eth_estimateGas then broadcasts, returning the tx hash" do
      # 21_000 == 0x5208
      StubClient.queue(estimate: "0x5208", send: @fake_tx_hash)

      assert {:ok, @fake_tx_hash} = Signer.send_transaction(@dummy_to, <<>>, base_opts([]))
      assert StubClient.methods() == ["eth_estimateGas", "eth_sendRawTransaction"]
    end

    test "applies the 1.25x headroom multiplier to the estimate" do
      StubClient.queue(estimate: "0x5208", send: @fake_tx_hash)

      assert {:ok, _} = Signer.send_transaction(@dummy_to, <<>>, base_opts([]))
      # 21_000 * 1.25 == 26_250
      assert decoded_gas_limit() == 26_250
    end

    test "estimates with non-empty calldata (ERC-20 transfer shape)" do
      {:ok, calldata_hex} =
        Onchain.ABI.encode_call("transfer(address,uint256)", [
          Onchain.Hex.decode!(@dummy_to),
          1_000
        ])

      StubClient.queue(estimate: "0xea60", send: @fake_tx_hash)

      assert {:ok, _} =
               Signer.send_transaction(@dummy_to, Onchain.Hex.decode!(calldata_hex), base_opts([]))

      # 60_000 (0xea60) * 1.25 == 75_000
      assert decoded_gas_limit() == 75_000
      assert "eth_estimateGas" in StubClient.methods()
    end

    test "propagates an estimate error without falling back to a default gas limit" do
      StubClient.queue(estimate: {:error, %{"code" => 3, "message" => "execution reverted"}})

      assert {:error, {:rpc_error, %{code: 3}}} =
               Signer.send_transaction(@dummy_to, <<>>, base_opts([]))

      # broadcast never reached
      refute "eth_sendRawTransaction" in StubClient.methods()
    end
  end

  describe "calldata shapes" do
    test "normalizes {:raw, binary} calldata for the estimate" do
      StubClient.queue(estimate: "0x5208", send: @fake_tx_hash)

      assert {:ok, @fake_tx_hash} =
               Signer.send_transaction(@dummy_to, {:raw, <<1, 2, 3, 4>>}, base_opts([]))

      assert "eth_estimateGas" in StubClient.methods()
    end
  end

  describe "value normalization on the auto-estimate path" do
    test "a {n, :gwei} tuple :value is estimated, not crashed" do
      StubClient.queue(estimate: "0x5208", send: @fake_tx_hash)

      # build_transaction (explicit-gas_limit path) accepts tuple values via V2.new;
      # the auto-estimate path must normalize them identically rather than raise.
      assert {:ok, @fake_tx_hash} =
               Signer.send_transaction(@dummy_to, <<>>, base_opts(value: {1, :gwei}))

      assert "eth_estimateGas" in StubClient.methods()
    end

    test "forwards :access_list into the estimate call object" do
      StubClient.queue(estimate: "0x5208", send: @fake_tx_hash)

      addr = String.duplicate(<<0xAB>>, 20)
      key = String.duplicate(<<0x01>>, 32)

      assert {:ok, @fake_tx_hash} =
               Signer.send_transaction(@dummy_to, <<>>, base_opts(access_list: [{addr, [key]}]))

      # the estimate covers the exact tx being submitted, access list included
      assert StubClient.estimate_call()["accessList"] == [
               %{
                 "address" => "0x" <> String.duplicate("ab", 20),
                 "storageKeys" => ["0x" <> String.duplicate("01", 32)]
               }
             ]
    end
  end

  describe "send_transaction!/3 with auto-estimate" do
    test "returns the tx hash on success" do
      StubClient.queue(estimate: "0x5208", send: @fake_tx_hash)

      assert @fake_tx_hash = Signer.send_transaction!(@dummy_to, <<>>, base_opts([]))
    end
  end

  describe "explicit :gas_limit is honored verbatim" do
    test "skips estimation entirely and uses the caller's value" do
      StubClient.queue(send: @fake_tx_hash)

      assert {:ok, @fake_tx_hash} =
               Signer.send_transaction(@dummy_to, <<>>, base_opts(gas_limit: 333_333))

      assert StubClient.methods() == ["eth_sendRawTransaction"]
      assert decoded_gas_limit() == 333_333
    end
  end
end
