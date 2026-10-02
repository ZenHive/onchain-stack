defmodule FaucetTest do
  use ExUnit.Case, async: true

  alias Faucet.Test.ConfirmingSource
  alias Faucet.Test.FakeSource

  @address "0xAbC0000000000000000000000000000000000001"

  describe "ensure_min_balance/4" do
    test "reuses an existing balance and never requests" do
      agent = FakeSource.start([{:ok, 500}])

      assert {:ok, 500} = Faucet.ensure_min_balance(FakeSource, @address, 100, agent: agent)
      assert FakeSource.calls(agent) == [{:balance, @address}]
    end

    test "funds once, polls the balance until it rises, then verifies the minimum" do
      # read 10 → fund → poll 10 (unchanged) → poll 60 (confirmed) → re-read 60 ≥ 50
      agent = FakeSource.start([{:ok, 10}, {:ok, 10}, {:ok, 60}])

      assert {:ok, 60} =
               Faucet.ensure_min_balance(FakeSource, @address, 50, agent: agent, poll_interval_ms: 1, timeout_ms: 200)

      assert [{:balance, _}, {:fund, @address, 40}, {:balance, _}, {:balance, _}, {:balance, _}] =
               FakeSource.calls(agent)
    end

    test "keeps requesting while under the minimum and within budget" do
      # Each request lifts the balance by 30: 0 → 30 → 60 → 90 (≥ 75).
      agent = FakeSource.start([{:ok, 0}, {:ok, 30}, {:ok, 30}, {:ok, 60}, {:ok, 60}, {:ok, 90}])

      assert {:ok, 90} = Faucet.ensure_min_balance(FakeSource, @address, 75, agent: agent, poll_interval_ms: 1)
      assert Enum.count(FakeSource.calls(agent), &match?({:fund, _, _}, &1)) == 3
    end

    test "stops with :budget_exhausted after :max_requests requests" do
      agent = FakeSource.start([{:ok, 0}, {:ok, 1}, {:ok, 1}, {:ok, 2}, {:ok, 2}])

      assert {:error, {:budget_exhausted, %{balance: 2, required: 100, requests: 2}}} =
               Faucet.ensure_min_balance(FakeSource, @address, 100, agent: agent, max_requests: 2, poll_interval_ms: 1)
    end

    test "uses the source's wait_confirmed/3 when it exists" do
      agent = FakeSource.start([{:ok, 0}, {:ok, 100}], [{:ok, ["0xhash"]}])

      assert {:ok, 100} = Faucet.ensure_min_balance(ConfirmingSource, @address, 100, agent: agent)

      assert [{:balance, _}, {:fund, _, 100}, {:wait_confirmed, ["0xhash"], @address}, {:balance, _}] =
               FakeSource.calls(agent)
    end

    test "propagates a confirmation failure" do
      agent = FakeSource.start([{:ok, 0}], [{:ok, ["0xhash"]}])
      Agent.update(agent, &Map.put(&1, :confirm, {:error, {:reverted, %{"status" => "0x0"}}}))

      assert {:error, {:reverted, _}} = Faucet.ensure_min_balance(ConfirmingSource, @address, 100, agent: agent)
    end

    test "times out when the balance never moves" do
      agent = FakeSource.start([{:ok, 0}])

      assert {:error, :timeout} =
               Faucet.ensure_min_balance(FakeSource, @address, 100, agent: agent, timeout_ms: 20, poll_interval_ms: 5)
    end

    test "propagates balance and fund errors" do
      failing_balance = FakeSource.start([{:error, :boom}])
      assert {:error, :boom} = Faucet.ensure_min_balance(FakeSource, @address, 1, agent: failing_balance)

      failing_fund = FakeSource.start([{:ok, 0}], [{:error, {:provider_rejected, 429, "slow down"}}])

      assert {:error, {:provider_rejected, 429, _}} =
               Faucet.ensure_min_balance(FakeSource, @address, 1, agent: failing_fund)
    end

    test "rejects invalid loop options before touching the source" do
      agent = FakeSource.start([{:ok, 0}])

      assert {:error, {:invalid_option, :max_requests, 0}} =
               Faucet.ensure_min_balance(FakeSource, @address, 1, agent: agent, max_requests: 0)

      assert {:error, {:invalid_option, :timeout_ms, -1}} =
               Faucet.ensure_min_balance(FakeSource, @address, 1, agent: agent, timeout_ms: -1)

      assert {:error, {:invalid_option, :poll_interval_ms, 0}} =
               Faucet.ensure_min_balance(FakeSource, @address, 1, agent: agent, poll_interval_ms: 0)

      assert FakeSource.calls(agent) == []
    end

    test "serializes concurrent callers for the same address" do
      # Both tasks see 0 first and fund; with the lock the second waits for the
      # first to finish, so it reads the raised balance and does not fund again.
      agent = FakeSource.start([{:ok, 0}, {:ok, 100}])

      results =
        1..2
        |> Task.async_stream(fn _ -> Faucet.ensure_min_balance(FakeSource, @address, 100, agent: agent) end)
        |> Enum.map(fn {:ok, result} -> result end)

      assert results == [{:ok, 100}, {:ok, 100}]
      assert Enum.count(FakeSource.calls(agent), &match?({:fund, _, _}, &1)) == 1
    end

    test "lock: false skips the global transaction" do
      agent = FakeSource.start([{:ok, 100}])
      assert {:ok, 100} = Faucet.ensure_min_balance(FakeSource, @address, 100, agent: agent, lock: false)
    end
  end

  describe "ensure_min_balance!/4" do
    test "returns the balance" do
      agent = FakeSource.start([{:ok, 7}])
      assert Faucet.ensure_min_balance!(FakeSource, @address, 5, agent: agent) == 7
    end

    test "raises Faucet.Error naming the source, address and reason" do
      agent = FakeSource.start([{:ok, 0}, {:ok, 0}])

      error =
        assert_raise Faucet.Error, fn ->
          Faucet.ensure_min_balance!(FakeSource, @address, 9,
            agent: agent,
            max_requests: 1,
            timeout_ms: 5,
            poll_interval_ms: 1
          )
        end

      assert error.source == FakeSource
      assert Exception.message(error) =~ "Faucet.Test.FakeSource could not bring #{@address} to 9 units"
      assert Exception.message(error) =~ "timed out"
    end

    test "formats budget exhaustion and missing credentials readably" do
      exhausted = %Faucet.Error{
        source: FakeSource,
        address: "a",
        minimum: 1,
        reason: {:budget_exhausted, %{balance: 0, required: 1, requests: 3}}
      }

      assert Exception.message(exhausted) =~ "budget exhausted after 3 request(s); balance is 0"

      missing = %Faucet.Error{
        source: FakeSource,
        address: "a",
        minimum: 1,
        reason: {:missing_credential, "X", "export X"}
      }

      assert Exception.message(missing) =~ "missing X. export X"
    end
  end

  describe "fund/3 and balance/3" do
    test "delegate straight to the source" do
      agent = FakeSource.start([{:ok, 3}], [{:ok, ["r1"]}])
      assert {:ok, ["r1"]} = Faucet.fund(FakeSource, @address, agent: agent)
      assert {:ok, 3} = Faucet.balance(FakeSource, @address, agent: agent)
    end
  end

  describe "discoverability" do
    test "every public function in the annotated modules carries Descripex hints" do
      for module <- [Faucet, Faucet.Wait, Faucet.JSONRPC, Faucet.EVM, Faucet.ForkOverride] do
        {:docs_v1, _, _, _, _, _, docs} = Code.fetch_docs(module)

        undocumented =
          for {{:function, name, arity}, _, _, doc, meta} <- docs,
              doc != :hidden,
              name not in [:describe, :__descripex_modules__],
              not Map.has_key?(meta, :hints),
              do: {module, name, arity}

        assert undocumented == []
      end

      assert [%{module: _} | _] = Faucet.describe()
    end
  end
end
