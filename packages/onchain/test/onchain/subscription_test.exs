defmodule Onchain.SubscriptionTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Onchain.Subscription

  @fake_client %ZenWebsocket.Client{
    gun_pid: nil,
    stream_ref: nil,
    state: :disconnected,
    url: nil,
    monitor_ref: nil,
    server_pid: nil
  }

  defp start_agent! do
    {:ok, agent} = Agent.start_link(fn -> %{registry: %{}, pending: %{}, in_flight: 0} end)
    on_exit(fn -> if Process.alive?(agent), do: Agent.stop(agent) end)
    agent
  end

  defp mark_subscribe_in_flight!(agent) do
    Agent.update(agent, fn state -> %{state | in_flight: state.in_flight + 1} end)
  end

  defp register!(agent, sub_id, type) do
    Agent.update(agent, fn state -> %{state | registry: Map.put(state.registry, sub_id, type)} end)
  end

  describe "subscribe/3 type validation" do
    test "rejects invalid subscription type" do
      agent = start_agent!()
      sub = %Subscription{client: @fake_client, agent: agent, handler: fn _ -> :ok end}

      assert {:error, {:invalid_subscription_type, :invalid}} = Subscription.subscribe(sub, :invalid)
      assert {:error, {:invalid_subscription_type, "newHeads"}} = Subscription.subscribe(sub, "newHeads")
    end
  end

  describe "bang variants raise on error" do
    test "subscribe!/2 raises when send_message fails on disconnected client" do
      agent = start_agent!()
      sub = %Subscription{client: @fake_client, agent: agent, handler: fn _ -> :ok end}

      assert_raise RuntimeError, ~r/Subscription failed/, fn ->
        Subscription.subscribe!(sub, :new_heads)
      end
    end

    test "unsubscribe!/2 raises when send_message fails on disconnected client" do
      agent = start_agent!()
      sub = %Subscription{client: @fake_client, agent: agent, handler: fn _ -> :ok end}

      assert_raise RuntimeError, ~r/Unsubscribe failed/, fn ->
        Subscription.unsubscribe!(sub, "0xfake")
      end
    end
  end

  describe "connect!/2" do
    test "raises on connection failure" do
      assert_raise RuntimeError, ~r/Subscription connect failed/, fn ->
        Subscription.connect!("ws://localhost:1", retry_count: 0, timeout: 100)
      end
    end
  end

  describe "close/1" do
    test "stops the agent and returns :ok" do
      agent = start_agent!()
      sub = %Subscription{client: @fake_client, agent: agent, handler: fn _ -> :ok end}

      assert :ok = Subscription.close(sub)
      refute Process.alive?(agent)
    end

    test "handles already-stopped agent gracefully" do
      agent = start_agent!()
      Agent.stop(agent)

      sub = %Subscription{client: @fake_client, agent: agent, handler: fn _ -> :ok end}

      assert :ok = Subscription.close(sub)
    end
  end

  # zen_websocket delivers JSON text frames to the handler already decoded into
  # maps (introduced in 0.4.x, re-confirmed against 0.8.0's docs pass). These
  # tests pin the dispatch path to that contract.
  describe "build_internal_handler/2 — zen_websocket decoded-frame contract" do
    setup do
      agent = start_agent!()

      caller = self()
      handler = fn event -> send(caller, {:event, event}) end

      internal = Subscription.build_internal_handler(agent, handler)

      {:ok, agent: agent, internal: internal}
    end

    test "dispatches :new_heads notification when message is a decoded map", ctx do
      register!(ctx.agent, "0xsub_heads", :new_heads)

      ctx.internal.(
        {:message,
         %{
           "method" => "eth_subscription",
           "params" => %{
             "subscription" => "0xsub_heads",
             "result" => %{
               "number" => "0x10",
               "hash" => "0xhash",
               "parentHash" => "0xparent",
               "timestamp" => "0x65",
               "miner" => "0x0000000000000000000000000000000000000001",
               "gasLimit" => "0x1c9c380",
               "gasUsed" => "0x5208",
               "baseFeePerGas" => "0x7",
               "logsBloom" => "0x00",
               "transactionsRoot" => "0xtxroot",
               "stateRoot" => "0xstateroot",
               "receiptsRoot" => "0xrcptroot"
             }
           }
         }}
      )

      assert_receive {:event, {:new_heads, "0xsub_heads", head}}, 100
      assert head.number == 16
      assert head.hash == "0xhash"
      assert head.timestamp == 101
    end

    test "dispatches :pending_transactions notification (string hash)", ctx do
      register!(ctx.agent, "0xsub_pending", :pending_transactions)
      hash = "0x" <> String.duplicate("a", 64)

      ctx.internal.(
        {:message,
         %{
           "method" => "eth_subscription",
           "params" => %{"subscription" => "0xsub_pending", "result" => hash}
         }}
      )

      assert_receive {:event, {:pending_transactions, "0xsub_pending", ^hash}}, 100
    end

    test "dispatches :logs notification", ctx do
      register!(ctx.agent, "0xsub_logs", {:logs, %{}})

      ctx.internal.(
        {:message,
         %{
           "method" => "eth_subscription",
           "params" => %{
             "subscription" => "0xsub_logs",
             "result" => %{
               "address" => "0x0000000000000000000000000000000000000002",
               "topics" => ["0xtopic1"],
               "data" => "0xdeadbeef",
               "blockNumber" => "0x10",
               "transactionHash" => "0xtxhash",
               "logIndex" => "0x0",
               "transactionIndex" => "0x0",
               "removed" => false
             }
           }
         }}
      )

      assert_receive {:event, {:logs, "0xsub_logs", log}}, 100
      assert log.block_number == 16
      assert log.topics == ["0xtopic1"]
      refute log.removed
    end

    test "dispatches {:parse_error, sub_id, {:invalid_head, _}} on malformed :new_heads result", ctx do
      register!(ctx.agent, "0xsub_heads", :new_heads)

      ctx.internal.(
        {:message,
         %{
           "method" => "eth_subscription",
           "params" => %{"subscription" => "0xsub_heads", "result" => "not a map"}
         }}
      )

      assert_receive {:event, {:parse_error, "0xsub_heads", {:invalid_head, "not a map"}}}, 100
    end

    test "dispatches {:parse_error, sub_id, {:invalid_log, _}} on malformed :logs result", ctx do
      register!(ctx.agent, "0xsub_logs", {:logs, %{}})

      ctx.internal.(
        {:message,
         %{
           "method" => "eth_subscription",
           "params" => %{"subscription" => "0xsub_logs", "result" => "not a map"}
         }}
      )

      assert_receive {:event, {:parse_error, "0xsub_logs", {:invalid_log, "not a map"}}}, 100
    end

    test "drops unsolicited sub_id when no eth_subscribe is in flight", ctx do
      ctx.internal.(
        {:message,
         %{
           "method" => "eth_subscription",
           "params" => %{"subscription" => "0xunsolicited", "result" => %{"spam" => true}}
         }}
      )

      refute_receive {:event, _}, 50
      assert Agent.get(ctx.agent, & &1.pending) == %{}
    end

    test "buffers notification when subscription_id is not yet registered", ctx do
      mark_subscribe_in_flight!(ctx.agent)

      ctx.internal.(
        {:message,
         %{
           "method" => "eth_subscription",
           "params" => %{"subscription" => "0xfuture", "result" => %{"hello" => "world"}}
         }}
      )

      # No event delivered yet — it's buffered
      refute_receive {:event, _}, 50

      # The pending buffer holds the result
      pending = Agent.get(ctx.agent, & &1.pending)
      assert pending["0xfuture"] == [%{"hello" => "world"}]
    end
  end

  describe "buffered notification flush on registration" do
    setup do
      agent = start_agent!()

      caller = self()
      handler = fn event -> send(caller, {:event, event}) end

      internal = Subscription.build_internal_handler(agent, handler)

      {:ok, agent: agent, internal: internal, handler: handler}
    end

    test "register_and_drain returns buffered results in FIFO order", ctx do
      mark_subscribe_in_flight!(ctx.agent)

      # Buffer two pending-tx hashes for an unregistered sub_id
      hash1 = "0x" <> String.duplicate("a", 64)
      hash2 = "0x" <> String.duplicate("b", 64)

      ctx.internal.(
        {:message, %{"method" => "eth_subscription", "params" => %{"subscription" => "0xfuture", "result" => hash1}}}
      )

      ctx.internal.(
        {:message, %{"method" => "eth_subscription", "params" => %{"subscription" => "0xfuture", "result" => hash2}}}
      )

      # Registration drains them FIFO
      drained = Subscription.register_and_drain(ctx.agent, "0xfuture", :pending_transactions)
      assert drained == [hash1, hash2]

      # Buffer is now empty for that sub_id
      assert Agent.get(ctx.agent, & &1.pending) == %{}

      # Registry has the new entry
      assert Agent.get(ctx.agent, & &1.registry) == %{"0xfuture" => :pending_transactions}
    end

    test "buffered notifications dispatch through handler when flushed manually", ctx do
      mark_subscribe_in_flight!(ctx.agent)
      hash = "0x" <> String.duplicate("c", 64)

      ctx.internal.(
        {:message, %{"method" => "eth_subscription", "params" => %{"subscription" => "0xfuture", "result" => hash}}}
      )

      refute_receive {:event, _}, 30

      # Manually flush — same code path do_subscribe runs after RPC reply
      drained = Subscription.register_and_drain(ctx.agent, "0xfuture", :pending_transactions)
      Enum.each(drained, fn r -> ctx.handler.({:pending_transactions, "0xfuture", r}) end)

      assert_receive {:event, {:pending_transactions, "0xfuture", ^hash}}, 100
    end

    test "register_and_drain on a sub_id with no buffered notifications returns []", ctx do
      assert [] == Subscription.register_and_drain(ctx.agent, "0xempty", :new_heads)
      assert Agent.get(ctx.agent, & &1.registry) == %{"0xempty" => :new_heads}
    end
  end

  describe "buffer overflow" do
    setup do
      agent = start_agent!()

      caller = self()
      handler = fn event -> send(caller, {:event, event}) end

      internal = Subscription.build_internal_handler(agent, handler)

      {:ok, agent: agent, internal: internal}
    end

    test "drops oldest entry and emits Logger.warning when buffer exceeds 100 entries", ctx do
      mark_subscribe_in_flight!(ctx.agent)

      log =
        capture_log(fn ->
          for n <- 1..101 do
            ctx.internal.(
              {:message,
               %{
                 "method" => "eth_subscription",
                 "params" => %{"subscription" => "0xbuf", "result" => "0x#{n}"}
               }}
            )
          end
        end)

      assert log =~ "exceeded 100 entries"

      # Buffer is capped at 100; oldest ("0x1") was dropped
      pending = Agent.get(ctx.agent, & &1.pending)
      assert length(pending["0xbuf"]) == 100
      assert hd(pending["0xbuf"]) == "0x101"
      refute "0x1" in pending["0xbuf"]
    end

    test "evicts oldest distinct pending sub_id when key cap exceeded during subscribe race", ctx do
      mark_subscribe_in_flight!(ctx.agent)

      log =
        capture_log(fn ->
          for n <- 1..17 do
            ctx.internal.(
              {:message,
               %{
                 "method" => "eth_subscription",
                 "params" => %{"subscription" => "0xkey#{n}", "result" => n}
               }}
            )
          end
        end)

      assert log =~ "distinct pending sub_id cap"

      pending = Agent.get(ctx.agent, & &1.pending)
      assert map_size(pending) == 16
      refute Map.has_key?(pending, "0xkey1")
      assert pending["0xkey17"] == [17]
    end
  end

  describe "remove_subscription/2" do
    test "removes sub_id from both registry and pending" do
      agent = start_agent!()

      Agent.update(agent, fn _ ->
        %{registry: %{"0xa" => :new_heads}, pending: %{"0xa" => ["one"], "0xb" => ["two"]}, in_flight: 0}
      end)

      Subscription.remove_subscription(agent, "0xa")

      state = Agent.get(agent, & &1)
      assert state.registry == %{}
      assert state.pending == %{"0xb" => ["two"]}
    end
  end

  describe "frame ignoring" do
    setup do
      agent = start_agent!()
      caller = self()
      handler = fn event -> send(caller, {:event, event}) end
      internal = Subscription.build_internal_handler(agent, handler)
      {:ok, agent: agent, internal: internal}
    end

    test "ignores non-JSON text frames", ctx do
      ctx.internal.({:message, "not json"})
      refute_receive {:event, _}, 50
    end

    test "ignores binary frames", ctx do
      ctx.internal.({:binary, <<1, 2, 3>>})
      refute_receive {:event, _}, 50
    end

    test "ignores unmatched_response", ctx do
      ctx.internal.({:unmatched_response, %{"id" => 99, "result" => "late"}})
      refute_receive {:event, _}, 50
    end

    test "does not crash on protocol_error", ctx do
      assert :ok = ctx.internal.({:protocol_error, :badframe})
      refute_receive {:event, _}, 50
    end

    test "ignores unknown handler tuples", ctx do
      assert :ok = ctx.internal.({:wat, :unexpected})
      refute_receive {:event, _}, 50
    end
  end
end
