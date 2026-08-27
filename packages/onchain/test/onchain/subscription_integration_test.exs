defmodule Onchain.SubscriptionIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Subscription

  @moduletag :integration
  @moduletag :websocket

  # Ethereum block time is ~12s; wait up to 30s for a block
  @new_heads_timeout_ms 30_000

  # USDC mainnet — a high-activity ERC-20 that emits Transfer events every block.
  @usdc_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @erc20_transfer_topic "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

  defp ws_url! do
    System.get_env("ETHEREUM_WS_URL") ||
      ExUnit.Assertions.flunk("""
      Missing Ethereum WebSocket URL!

      Set this environment variable:
        export ETHEREUM_WS_URL="ws://localhost:8546"

      Or use a provider:
        export ETHEREUM_WS_URL="wss://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"
      """)
  end

  describe "newHeads subscription" do
    @tag timeout: 60_000
    test "receives at least one new block header" do
      url = ws_url!()

      {:ok, sub} = Subscription.connect(url)
      on_exit(fn -> Subscription.close(sub) end)

      {:ok, sub_id} = Subscription.subscribe(sub, :new_heads)

      assert is_binary(sub_id)
      assert String.starts_with?(sub_id, "0x")

      # Wait for a new block
      head =
        receive do
          {:subscription, {:new_heads, ^sub_id, head}} -> head
        after
          @new_heads_timeout_ms ->
            flunk("No newHeads event received within #{@new_heads_timeout_ms}ms")
        end

      assert is_integer(head.number)
      assert head.number > 0
      assert is_binary(head.hash)
      assert String.starts_with?(head.hash, "0x")
      assert is_integer(head.gas_used)
      assert is_integer(head.timestamp)
      assert is_binary(head.miner)

      assert {:ok, true} = Subscription.unsubscribe(sub, sub_id)
    end
  end

  describe "subscribe and unsubscribe lifecycle (bang variants)" do
    @tag timeout: 60_000
    test "can subscribe!, receive events, unsubscribe!, and close cleanly" do
      url = ws_url!()

      sub = Subscription.connect!(url)
      on_exit(fn -> Subscription.close(sub) end)

      sub_id = Subscription.subscribe!(sub, :new_heads)

      # Wait for one block to confirm subscription is active
      receive do
        {:subscription, {:new_heads, ^sub_id, _head}} -> :ok
      after
        @new_heads_timeout_ms ->
          flunk("No event received before unsubscribe test")
      end

      # Unsubscribe via bang variant
      assert true == Subscription.unsubscribe!(sub, sub_id)

      # After unsubscribe, no more events should arrive (wait a few seconds)
      receive do
        {:subscription, {:new_heads, ^sub_id, _}} ->
          # Events in flight are acceptable; drain them
          :ok
      after
        3_000 -> :ok
      end
    end
  end

  describe "logs subscription" do
    @tag timeout: 60_000
    test "receives USDC Transfer event logs" do
      url = ws_url!()

      {:ok, sub} = Subscription.connect(url)
      on_exit(fn -> Subscription.close(sub) end)

      {:ok, sub_id} =
        Subscription.subscribe(sub, {:logs, %{address: @usdc_address, topics: [@erc20_transfer_topic]}})

      assert is_binary(sub_id)

      log =
        receive do
          {:subscription, {:logs, ^sub_id, log}} -> log
        after
          @new_heads_timeout_ms ->
            flunk("No USDC Transfer log received within #{@new_heads_timeout_ms}ms")
        end

      assert log.address == @usdc_address
      assert [@erc20_transfer_topic | _] = log.topics
      assert is_integer(log.block_number)
      assert is_integer(log.log_index)
      assert is_binary(log.transaction_hash)
      assert log.removed == false

      assert {:ok, true} = Subscription.unsubscribe(sub, sub_id)
    end
  end

  # Requires a node that broadcasts mempool (e.g. a local full node).
  # blockwatch-one returns hashes (no `full` flag passed); a non-conforming
  # provider that returns full tx objects would surface as
  # {:parse_error, sub_id, {:invalid_tx_hash, _}} rather than crash.
  describe "pendingTransactions subscription" do
    @tag timeout: 60_000
    test "receives at least one pending transaction hash" do
      url = ws_url!()

      {:ok, sub} = Subscription.connect(url)
      on_exit(fn -> Subscription.close(sub) end)

      {:ok, sub_id} = Subscription.subscribe(sub, :pending_transactions)
      assert is_binary(sub_id)
      assert String.starts_with?(sub_id, "0x")

      hash =
        receive do
          {:subscription, {:pending_transactions, ^sub_id, hash}} -> hash
        after
          @new_heads_timeout_ms ->
            flunk("No pendingTransactions event received within #{@new_heads_timeout_ms}ms")
        end

      assert is_binary(hash)
      assert String.starts_with?(hash, "0x")
      assert String.length(hash) == 66

      assert {:ok, true} = Subscription.unsubscribe(sub, sub_id)
    end
  end

  describe "custom handler" do
    @tag timeout: 60_000
    test "delivers events via custom handler function" do
      url = ws_url!()
      test_pid = self()

      handler = fn event ->
        send(test_pid, {:custom_handler, event})
      end

      {:ok, sub} = Subscription.connect(url, handler: handler)
      on_exit(fn -> Subscription.close(sub) end)

      {:ok, sub_id} = Subscription.subscribe(sub, :new_heads)

      receive do
        {:custom_handler, {:new_heads, ^sub_id, head}} ->
          assert is_integer(head.number)
      after
        @new_heads_timeout_ms ->
          flunk("Custom handler did not receive event")
      end
    end
  end
end
