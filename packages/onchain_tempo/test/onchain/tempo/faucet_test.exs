defmodule Onchain.Tempo.FaucetTest do
  use ExUnit.Case, async: false

  alias Onchain.Tempo.Faucet

  describe "rpc_url/0" do
    test "returns the Moderato default when TEMPO_RPC_URL is unset" do
      previous = System.get_env("TEMPO_RPC_URL")
      System.delete_env("TEMPO_RPC_URL")

      try do
        assert Faucet.rpc_url() == "https://rpc.moderato.tempo.xyz"
      after
        if previous, do: System.put_env("TEMPO_RPC_URL", previous)
      end
    end

    test "honours TEMPO_RPC_URL override" do
      previous = System.get_env("TEMPO_RPC_URL")
      System.put_env("TEMPO_RPC_URL", "https://my-mirror.example")

      try do
        assert Faucet.rpc_url() == "https://my-mirror.example"
      after
        if previous, do: System.put_env("TEMPO_RPC_URL", previous), else: System.delete_env("TEMPO_RPC_URL")
      end
    end
  end

  describe "fund_address/2" do
    test "returns the list of funding tx hashes on success and sends the right RPC body" do
      addr = "0x" <> String.duplicate("ab", 20)

      Req.Test.stub(:faucet_ok, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        assert decoded["method"] == "tempo_fundAddress"
        assert decoded["params"] == [addr]

        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "result" => ["0xfund1", "0xfund2"]
        })
      end)

      assert {:ok, ["0xfund1", "0xfund2"]} =
               Faucet.fund_address(addr, rpc_url: "http://localhost", req_options: [plug: {Req.Test, :faucet_ok}])
    end

    test "returns {:error, _} when the RPC body contains an error" do
      Req.Test.stub(:faucet_err, fn conn ->
        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "error" => %{"code" => -32_000, "message" => "rate limited"}
        })
      end)

      assert {:error, msg} =
               Faucet.fund_address("0xabc", rpc_url: "http://localhost", req_options: [plug: {Req.Test, :faucet_err}])

      assert msg =~ "faucet error"
      assert msg =~ "rate limited"
    end

    test "returns {:error, _} on a non-2xx response even when result key is present" do
      Req.Test.stub(:faucet_weird, fn conn ->
        conn
        |> Plug.Conn.put_status(500)
        |> Req.Test.json(%{"jsonrpc" => "2.0", "id" => 1, "result" => "should be ignored"})
      end)

      assert {:error, msg} =
               Faucet.fund_address("0xabc", rpc_url: "http://localhost", req_options: [plug: {Req.Test, :faucet_weird}])

      assert msg =~ "unexpected faucet response"
      assert msg =~ "500"
    end

    test "returns {:error, _} on transport failure" do
      Req.Test.stub(:faucet_boom, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      assert {:error, msg} =
               Faucet.fund_address("0xabc",
                 rpc_url: "http://localhost",
                 req_options: [plug: {Req.Test, :faucet_boom}, retry: false]
               )

      assert msg =~ "faucet HTTP error"
    end
  end

  describe "fresh_funded_wallet/1" do
    test "generates a keypair, calls tempo_fundAddress with its address, and returns the wallet" do
      test_pid = self()

      Req.Test.stub(:faucet_fresh, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)
        send(test_pid, {:funded_address, hd(decoded["params"])})
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => ["0xfund"]})
      end)

      assert {:ok, wallet} =
               Faucet.fresh_funded_wallet(
                 rpc_url: "http://localhost",
                 req_options: [plug: {Req.Test, :faucet_fresh}],
                 settle_ms: 0
               )

      assert byte_size(wallet.private_key) == 32
      assert byte_size(wallet.address_bin) == 20
      assert <<"0x", hex::binary-size(40)>> = wallet.address_hex
      assert {:ok, _} = Base.decode16(hex, case: :mixed)

      assert_received {:funded_address, funded}
      assert funded == wallet.address_hex
    end

    test "propagates {:error, _} from the funding RPC" do
      Req.Test.stub(:faucet_fresh_err, fn conn ->
        Req.Test.json(conn, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "error" => %{"code" => -32_000, "message" => "out of funds"}
        })
      end)

      assert {:error, msg} =
               Faucet.fresh_funded_wallet(
                 rpc_url: "http://localhost",
                 req_options: [plug: {Req.Test, :faucet_fresh_err}],
                 settle_ms: 0
               )

      assert msg =~ "out of funds"
    end

    test "polls the fee-token balanceOf via eth_call and returns once funding lands" do
      counter = :counters.new(1, [])
      test_pid = self()
      # balanceOf(address) selector.
      balance_of_selector = "0x70a08231"
      default_fee_token = "0x20c0000000000000000000000000000000000000"

      Req.Test.stub(:faucet_poll_success, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        result =
          case decoded["method"] do
            "tempo_fundAddress" ->
              send(test_pid, {:funded, hd(decoded["params"])})
              ["0xfund"]

            "eth_call" ->
              [%{"to" => to, "data" => data}, "latest"] = decoded["params"]
              send(test_pid, {:eth_call, to, data})
              n = :counters.get(counter, 1)
              :counters.add(counter, 1, 1)
              # First poll returns 0; subsequent polls return a non-zero balance.
              if n == 0, do: "0x0", else: "0xde0b6b3a7640000"
          end

        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => result})
      end)

      assert {:ok, wallet} =
               Faucet.fresh_funded_wallet(
                 rpc_url: "http://localhost",
                 req_options: [plug: {Req.Test, :faucet_poll_success}],
                 settle_ms: 500,
                 poll_interval_ms: 10
               )

      assert byte_size(wallet.private_key) == 32
      assert byte_size(wallet.address_bin) == 20
      # Polling actually ran — counter advanced past the initial zero balance.
      assert :counters.get(counter, 1) >= 2

      # The poll queried the fee token (pathUSD), not native balance, and asked
      # for the *funded* address's balanceOf.
      assert_received {:funded, funded_addr}
      assert_received {:eth_call, to, data}
      assert to == default_fee_token
      addr_no_prefix = String.downcase(String.trim_leading(funded_addr, "0x"))
      assert data == balance_of_selector <> String.duplicate("0", 24) <> addr_no_prefix
    end

    test "honours a :fee_token override for the balance poll" do
      override = "0xabc0000000000000000000000000000000000000"
      test_pid = self()

      Req.Test.stub(:faucet_fee_token_override, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        result =
          case decoded["method"] do
            "tempo_fundAddress" ->
              ["0xfund"]

            "eth_call" ->
              [%{"to" => to}, "latest"] = decoded["params"]
              send(test_pid, {:eth_call_to, to})
              "0x1"
          end

        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => result})
      end)

      assert {:ok, _wallet} =
               Faucet.fresh_funded_wallet(
                 rpc_url: "http://localhost",
                 req_options: [plug: {Req.Test, :faucet_fee_token_override}],
                 fee_token: override,
                 settle_ms: 100,
                 poll_interval_ms: 5
               )

      assert_received {:eth_call_to, ^override}
    end

    test "returns {:error, _} when the funding never confirms before settle_ms" do
      Req.Test.stub(:faucet_poll_timeout, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        result =
          case decoded["method"] do
            "tempo_fundAddress" -> ["0xfund"]
            "eth_call" -> "0x0"
          end

        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => result})
      end)

      assert {:error, msg} =
               Faucet.fresh_funded_wallet(
                 rpc_url: "http://localhost",
                 req_options: [plug: {Req.Test, :faucet_poll_timeout}],
                 settle_ms: 30,
                 poll_interval_ms: 5
               )

      assert msg =~ "timeout"
    end

    test "rejects negative :settle_ms with actionable error (fails fast, no RPC)" do
      assert {:error, msg} = Faucet.fresh_funded_wallet(settle_ms: -1)
      assert msg =~ ":settle_ms must be a non-negative integer"
      assert msg =~ "-1"
    end

    test "rejects non-integer :settle_ms with actionable error" do
      assert {:error, msg} = Faucet.fresh_funded_wallet(settle_ms: "2500")
      assert msg =~ ":settle_ms must be a non-negative integer"
    end

    test "rejects non-positive :poll_interval_ms with actionable error" do
      assert {:error, msg} =
               Faucet.fresh_funded_wallet(settle_ms: 100, poll_interval_ms: 0)

      assert msg =~ ":poll_interval_ms must be a positive integer"
      assert msg =~ "0"
    end

    test "rejects negative :poll_interval_ms with actionable error" do
      assert {:error, msg} =
               Faucet.fresh_funded_wallet(settle_ms: 100, poll_interval_ms: -50)

      assert msg =~ ":poll_interval_ms must be a positive integer"
    end

    test "ignores invalid :poll_interval_ms when settle_ms is 0 (poll skipped)" do
      # settle_ms: 0 skips polling entirely, so :poll_interval_ms is irrelevant.
      # Validation cascade reflects that — only the timeout is required to be valid.
      Req.Test.stub(:faucet_skip_poll, fn conn ->
        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => ["0xfund"]})
      end)

      assert {:ok, _wallet} =
               Faucet.fresh_funded_wallet(
                 rpc_url: "http://localhost",
                 req_options: [plug: {Req.Test, :faucet_skip_poll}],
                 settle_ms: 0,
                 poll_interval_ms: -999
               )
    end

    test "errors loudly when the balanceOf eth_call returns a malformed hex string" do
      Req.Test.stub(:faucet_malformed_hex, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        result =
          case decoded["method"] do
            "tempo_fundAddress" -> ["0xfund"]
            # Missing 0x prefix — node-side protocol violation.
            "eth_call" -> "1"
          end

        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => result})
      end)

      assert {:error, msg} =
               Faucet.fresh_funded_wallet(
                 rpc_url: "http://localhost",
                 req_options: [plug: {Req.Test, :faucet_malformed_hex}],
                 settle_ms: 100,
                 poll_interval_ms: 5
               )

      assert msg =~ "unexpected eth_call result"
    end

    test "errors loudly when the balanceOf eth_call returns a non-string value" do
      Req.Test.stub(:faucet_nonstring, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        result =
          case decoded["method"] do
            "tempo_fundAddress" -> ["0xfund"]
            "eth_call" -> 123
          end

        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => result})
      end)

      assert {:error, msg} =
               Faucet.fresh_funded_wallet(
                 rpc_url: "http://localhost",
                 req_options: [plug: {Req.Test, :faucet_nonstring}],
                 settle_ms: 100,
                 poll_interval_ms: 5
               )

      assert msg =~ "unexpected eth_call result"
    end

    test "errors loudly when the balanceOf eth_call returns a negative hex value" do
      # "0x-1" is a protocol violation; treat as malformed rather than silently
      # timing out (which is what an unguarded Integer.parse would do).
      Req.Test.stub(:faucet_negative_hex, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        decoded = Jason.decode!(body)

        result =
          case decoded["method"] do
            "tempo_fundAddress" -> ["0xfund"]
            "eth_call" -> "0x-1"
          end

        Req.Test.json(conn, %{"jsonrpc" => "2.0", "id" => 1, "result" => result})
      end)

      assert {:error, msg} =
               Faucet.fresh_funded_wallet(
                 rpc_url: "http://localhost",
                 req_options: [plug: {Req.Test, :faucet_negative_hex}],
                 settle_ms: 100,
                 poll_interval_ms: 5
               )

      assert msg =~ "unexpected eth_call result"
    end
  end
end
