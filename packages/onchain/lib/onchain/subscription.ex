defmodule Onchain.Subscription do
  @moduledoc """
  Real-time Ethereum subscriptions via `eth_subscribe` over WebSocket.

  Wraps [zen_websocket](https://hex.pm/packages/zen_websocket) with Ethereum-specific
  subscription management. Supports three subscription types: new block headers,
  pending transactions, and filtered event logs.

  ## Does

  - Connect to a WebSocket-capable Ethereum endpoint (`connect/2`)
  - Subscribe to `newHeads`, `newPendingTransactions`, and `logs` (`subscribe/3`)
  - Parse subscription notifications into normalized Elixir maps
  - Deliver parsed events via handler function or process messages
  - Unsubscribe and clean up resources (`unsubscribe/2`, `close/1`)

  ## Does Not

  - Persist or index events (see rexex for durable indexing)
  - Convert HTTP RPC URLs to WebSocket URLs (consumer provides `wss://` directly)
  - Manage reconnection subscriptions (delegates reconnection to zen_websocket)

  ## Event Delivery

  Events are delivered via a handler function passed to `connect/2`. The default
  handler sends `{:subscription, event}` messages to the calling process.

  Event shapes:
  - `{:new_heads, subscription_id, head_map}`
  - `{:pending_transactions, subscription_id, tx_hash}`
  - `{:logs, subscription_id, log_map}`
  - `{:parse_error, subscription_id, reason}` — malformed notification; `reason` is a
    tagged tuple from the internal parser
    (`{:invalid_head, _}` | `{:invalid_tx_hash, _}` | `{:invalid_log, _}`)

  ## Subscribe Race Buffering

  The race between `eth_subscribe`'s RPC reply (which returns the `subscription_id`)
  and the Agent registration of that id is closed by buffering: notifications that
  arrive for an unregistered `subscription_id` are queued only while an
  `eth_subscribe` is in flight; unsolicited sub_ids are dropped. Per-id cap is
  `100` entries (oldest dropped on overflow with a `Logger.warning`); distinct
  sub_id keys are capped at `16` (oldest key evicted on overflow). On registration,
  buffered notifications are flushed FIFO through the same handler path before
  `subscribe/3` returns.

  Cross-buffer / post-registration ordering is best-effort: a notification that
  arrives between the atomic register-and-drain step and the synchronous flush is
  dispatched immediately and may interleave with buffered events. Acceptable for
  self-contained, independent notifications (heads, hashes, logs).

  Handler exceptions during flush propagate (consistent with fire-and-forget
  `dispatch_event/4` semantics). Remaining buffered events for that flush are lost;
  Agent state remains consistent.

  ## Error Format

  - Connection failures: `{:error, {:connection_error, reason}}`
  - RPC errors: `{:error, {:rpc_error, %{code: integer, message: string}}}`
  - Invalid subscription type: `{:error, {:invalid_subscription_type, type}}`

  ## Functions

  | Function | Purpose |
  |----------|---------|
  | `connect/2` | Open WebSocket connection to Ethereum node |
  | `connect!/2` | Same, raises on error |
  | `subscribe/3` | Subscribe to a notification type |
  | `subscribe!/3` | Same, raises on error |
  | `unsubscribe/2` | Cancel a subscription by ID |
  | `unsubscribe!/2` | Same, raises on error |
  | `close/1` | Close connection and free resources |
  """

  use Descripex, namespace: "/subscription"

  alias Onchain.Subscription.Parser
  alias ZenWebsocket.Client
  alias ZenWebsocket.JsonRpc

  require Logger

  @enforce_keys [:client, :agent]
  defstruct [:client, :agent, :handler]

  # Per-sub_id cap on the pre-registration buffer. Generous enough for ~1s of
  # mainnet pendingTransactions burst at 100 tx/s; not so high that a misbehaving
  # server can wedge memory.
  @max_pending_per_sub_id 100

  # Cap on distinct sub_ids in the pending map while eth_subscribe is in flight.
  # Prevents a server from growing the key set with never-subscribed ids during the
  # race window; oldest key is evicted on overflow.
  @max_pending_distinct_sub_ids 16

  @type subscription_type :: :new_heads | :pending_transactions | {:logs, map()}

  @type head :: %{
          number: non_neg_integer(),
          hash: String.t(),
          parent_hash: String.t(),
          timestamp: non_neg_integer(),
          miner: String.t(),
          gas_limit: non_neg_integer(),
          gas_used: non_neg_integer(),
          base_fee_per_gas: non_neg_integer() | nil,
          logs_bloom: String.t(),
          transactions_root: String.t(),
          state_root: String.t(),
          receipts_root: String.t()
        }

  @type log :: %{
          address: String.t(),
          topics: [String.t()],
          data: String.t(),
          block_number: non_neg_integer(),
          transaction_hash: String.t(),
          log_index: non_neg_integer(),
          transaction_index: non_neg_integer(),
          removed: boolean()
        }

  @type event ::
          {:new_heads, String.t(), head()}
          | {:pending_transactions, String.t(), String.t()}
          | {:logs, String.t(), log()}
          | {:parse_error, String.t(), term()}

  @type handler :: (event() -> any())

  @type t :: %__MODULE__{
          client: Client.t(),
          agent: pid(),
          handler: handler()
        }

  # --- connect ---

  api(:connect, "Open a WebSocket connection to an Ethereum node.",
    params: [
      ws_url: [kind: :value, description: "WebSocket URL (wss:// or ws://)"],
      opts: [
        kind: :value,
        default: [],
        description:
          "Options: :handler (event callback fn), plus zen_websocket options (:retry_count, :retry_delay, :max_backoff)"
      ]
    ],
    returns: %{
      type: "{:ok, %Onchain.Subscription{}} | {:error, term()}",
      description: "Subscription handle for subscribe/unsubscribe/close calls"
    }
  )

  @spec connect(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def connect(ws_url, opts \\ []) do
    {user_handler, ws_opts} = Keyword.pop(opts, :handler)
    caller = self()

    {:ok, agent} = Agent.start_link(fn -> %{registry: %{}, pending: %{}, in_flight: 0} end)

    handler = user_handler || default_handler(caller)

    internal_handler = build_internal_handler(agent, handler)

    ws_opts =
      ws_opts
      |> Keyword.put(:handler, internal_handler)
      |> Keyword.put_new(:on_disconnect, fn _pid -> stop_agent(agent) end)

    case Client.connect(ws_url, ws_opts) do
      {:ok, client} ->
        {:ok, %__MODULE__{client: client, agent: agent, handler: handler}}

      {:error, reason} ->
        stop_agent(agent)
        {:error, {:connection_error, reason}}
    end
  end

  api(:connect!, "Open a WebSocket connection. Raises on error.",
    params: [
      ws_url: [kind: :value, description: "WebSocket URL (wss:// or ws://)"],
      opts: [kind: :value, default: [], description: "Same options as connect/2"]
    ],
    returns: %{type: "%Onchain.Subscription{}", description: "Subscription handle"}
  )

  @spec connect!(String.t(), keyword()) :: t()
  def connect!(ws_url, opts \\ []) do
    case connect(ws_url, opts) do
      {:ok, sub} -> sub
      {:error, reason} -> raise "Subscription connect failed: #{inspect(reason)}"
    end
  end

  # --- subscribe ---

  api(:subscribe, "Subscribe to an Ethereum notification type.",
    params: [
      sub: [kind: :value, description: "Subscription handle from connect/2"],
      type: [
        kind: :value,
        description: "Subscription type: :new_heads, :pending_transactions, or {:logs, filter_map}"
      ],
      opts: [kind: :value, default: [], description: "Reserved for future options"]
    ],
    returns: %{
      type: "{:ok, subscription_id} | {:error, term()}",
      description: "Subscription ID for unsubscribe"
    }
  )

  @spec subscribe(t(), subscription_type(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def subscribe(sub, type, opts \\ [])

  def subscribe(%__MODULE__{} = sub, :new_heads, _opts) do
    do_subscribe(sub, :new_heads, ["newHeads"])
  end

  def subscribe(%__MODULE__{} = sub, :pending_transactions, _opts) do
    do_subscribe(sub, :pending_transactions, ["newPendingTransactions"])
  end

  def subscribe(%__MODULE__{} = sub, {:logs, filter}, _opts) when is_map(filter) do
    eth_filter = build_log_filter(filter)
    do_subscribe(sub, {:logs, filter}, ["logs", eth_filter])
  end

  def subscribe(%__MODULE__{}, type, _opts) do
    {:error, {:invalid_subscription_type, type}}
  end

  api(:subscribe!, "Subscribe to an Ethereum notification type. Raises on error.",
    params: [
      sub: [kind: :value, description: "Subscription handle from connect/2"],
      type: [kind: :value, description: "Same types as subscribe/3"],
      opts: [kind: :value, default: [], description: "Reserved for future options"]
    ],
    returns: %{type: "String.t()", description: "Subscription ID"}
  )

  @spec subscribe!(t(), subscription_type(), keyword()) :: String.t()
  def subscribe!(%__MODULE__{} = sub, type, opts \\ []) do
    case subscribe(sub, type, opts) do
      {:ok, sub_id} -> sub_id
      {:error, reason} -> raise "Subscription failed: #{inspect(reason)}"
    end
  end

  # --- unsubscribe ---

  api(:unsubscribe, "Cancel a subscription by ID.",
    params: [
      sub: [kind: :value, description: "Subscription handle"],
      subscription_id: [kind: :value, description: "Subscription ID from subscribe/3"]
    ],
    returns: %{
      type: "{:ok, boolean()} | {:error, term()}",
      description: "true if unsubscribed successfully"
    }
  )

  @spec unsubscribe(t(), String.t()) :: {:ok, boolean()} | {:error, term()}
  def unsubscribe(%__MODULE__{client: client, agent: agent}, subscription_id) do
    {:ok, request} = JsonRpc.build_request("eth_unsubscribe", [subscription_id])

    case Client.send_message(client, Jason.encode!(request)) do
      {:ok, %{"result" => result}} ->
        remove_subscription(agent, subscription_id)
        {:ok, result}

      {:ok, %{"error" => %{"code" => code, "message" => message}}} ->
        {:error, {:rpc_error, %{code: code, message: message}}}

      {:error, reason} ->
        {:error, {:connection_error, reason}}

      :ok ->
        remove_subscription(agent, subscription_id)
        {:ok, true}
    end
  end

  api(:unsubscribe!, "Cancel a subscription by ID. Raises on error.",
    params: [
      sub: [kind: :value, description: "Subscription handle"],
      subscription_id: [kind: :value, description: "Subscription ID"]
    ],
    returns: %{type: "boolean()", description: "true if unsubscribed"}
  )

  @spec unsubscribe!(t(), String.t()) :: boolean()
  def unsubscribe!(%__MODULE__{} = sub, subscription_id) do
    case unsubscribe(sub, subscription_id) do
      {:ok, result} -> result
      {:error, reason} -> raise "Unsubscribe failed: #{inspect(reason)}"
    end
  end

  # --- close ---

  api(:close, "Close the WebSocket connection and free resources.",
    params: [
      sub: [kind: :value, description: "Subscription handle"]
    ],
    returns: %{type: ":ok", description: "Always returns :ok"}
  )

  @spec close(t()) :: :ok
  def close(%__MODULE__{client: client, agent: agent}) do
    Client.close(client)
    stop_agent(agent)
    :ok
  end

  # Stops the Agent if it's still alive. Used by close/1 and on_disconnect callback.
  @spec stop_agent(pid()) :: :ok
  defp stop_agent(agent) do
    if Process.alive?(agent), do: Agent.stop(agent)
    :ok
  end

  # --- Internal helpers ---

  # Sends eth_subscribe, atomically registers the sub_id → type mapping, drains
  # any notifications that were buffered in the race window, and dispatches them
  # FIFO through the connection's handler before returning.
  @spec do_subscribe(t(), subscription_type(), list()) ::
          {:ok, String.t()} | {:error, term()}
  defp do_subscribe(%__MODULE__{client: client, agent: agent, handler: handler}, type, params) do
    {:ok, request} = JsonRpc.build_request("eth_subscribe", params)
    Agent.update(agent, fn state -> %{state | in_flight: state.in_flight + 1} end)

    try do
      case Client.send_message(client, Jason.encode!(request)) do
        {:ok, %{"result" => subscription_id}} when is_binary(subscription_id) ->
          drained = register_and_drain(agent, subscription_id, type)
          Enum.each(drained, &dispatch_event(type, subscription_id, &1, handler))
          {:ok, subscription_id}

        {:ok, %{"error" => %{"code" => code, "message" => message}}} ->
          {:error, {:rpc_error, %{code: code, message: message}}}

        {:error, reason} ->
          {:error, {:connection_error, reason}}

        other ->
          {:error, {:unexpected_response, other}}
      end
    after
      Agent.update(agent, fn state -> %{state | in_flight: max(state.in_flight - 1, 0)} end)
    end
  end

  # Default handler sends events as messages to the calling process.
  @spec default_handler(pid()) :: handler()
  defp default_handler(caller) do
    fn event -> send(caller, {:subscription, event}) end
  end

  # Builds the internal zen_websocket handler that bridges decoded WebSocket
  # messages to parsed, typed events delivered via the consumer's handler.
  #
  # Made `def` (with `@doc false`) so the dispatch path can be unit-tested
  # without spinning up a real WebSocket connection.
  @doc false
  @spec build_internal_handler(pid(), handler()) :: (term() -> any())
  def build_internal_handler(agent, handler) do
    fn
      {:message, %{} = decoded} ->
        dispatch_decoded(decoded, agent, handler)

      {:message, text} when is_binary(text) ->
        Logger.debug("Subscription: ignoring non-JSON text frame: #{inspect(text)}")
        :ok

      {:binary, _bin} ->
        :ok

      {:unmatched_response, response} ->
        Logger.debug("Subscription: unmatched JSON-RPC response: #{inspect(response)}")
        :ok

      {:protocol_error, reason} ->
        Logger.warning("Subscription: zen_websocket protocol error: #{inspect(reason)}")
        :ok

      _other ->
        :ok
    end
  end

  # Dispatches a decoded JSON-RPC message. Only handles subscription notifications;
  # request-response messages (eth_subscribe confirmations) are handled by send_message.
  @spec dispatch_decoded(map(), pid(), handler()) :: any()
  defp dispatch_decoded(decoded, agent, handler) do
    case JsonRpc.match_response(decoded) do
      {:notification, "eth_subscription", %{"subscription" => sub_id, "result" => result}} ->
        case lookup_or_buffer(agent, sub_id, result) do
          :buffered -> :ok
          {:registered, type} -> dispatch_event(type, sub_id, result, handler)
        end

      _other ->
        :ok
    end
  end

  # Atomically: if `sub_id` is registered, return `{:registered, type}` so the caller
  # can dispatch immediately; otherwise push `result` onto the per-sub_id pending
  # buffer and return `:buffered`. See @moduledoc "Subscribe Race Buffering".
  @doc false
  @spec lookup_or_buffer(pid(), String.t(), term()) :: :buffered | {:registered, subscription_type()}
  def lookup_or_buffer(agent, sub_id, result) do
    Agent.get_and_update(agent, fn state ->
      case Map.get(state.registry, sub_id) do
        nil when state.in_flight == 0 ->
          {:buffered, state}

        nil ->
          {:buffered, %{state | pending: push_bounded(state.pending, sub_id, result)}}

        type ->
          {{:registered, type}, state}
      end
    end)
  end

  # Atomically register the sub_id → type mapping AND pop any buffered notifications
  # for that sub_id. Returns the buffered list in arrival (FIFO) order; the caller
  # is expected to iterate and dispatch through the connection's handler.
  @doc false
  @spec register_and_drain(pid(), String.t(), subscription_type()) :: [term()]
  def register_and_drain(agent, sub_id, type) do
    Agent.get_and_update(agent, fn state ->
      {pending, new_pending} = Map.pop(state.pending, sub_id, [])
      new_state = %{state | registry: Map.put(state.registry, sub_id, type), pending: new_pending}
      {Enum.reverse(pending), new_state}
    end)
  end

  # Removes a sub_id from both registry and pending buffer (cleanup on unsubscribe).
  @doc false
  @spec remove_subscription(pid(), String.t()) :: :ok
  def remove_subscription(agent, sub_id) do
    Agent.update(agent, fn state ->
      %{state | registry: Map.delete(state.registry, sub_id), pending: Map.delete(state.pending, sub_id)}
    end)
  end

  # Prepends `result` onto pending[sub_id], dropping the oldest entry if the per-sub_id
  # cap is exceeded. Pending is kept as a stack (newest first); FIFO order is restored
  # by Enum.reverse on drain. Overflow emits a Logger.warning every time.
  @spec push_bounded(map(), String.t(), term()) :: map()
  defp push_bounded(pending, sub_id, result) do
    pending = evict_oldest_pending_key(pending, sub_id)
    current = Map.get(pending, sub_id, [])
    next = [result | current]

    if length(next) > @max_pending_per_sub_id do
      Logger.warning(
        "Subscription: pending buffer for sub_id #{inspect(sub_id)} exceeded #{@max_pending_per_sub_id} entries; dropping oldest"
      )

      {kept, _dropped} = Enum.split(next, @max_pending_per_sub_id)
      Map.put(pending, sub_id, kept)
    else
      Map.put(pending, sub_id, next)
    end
  end

  # When the distinct sub_id cap is reached, evict the oldest pending key (map insertion
  # order) before accepting a notification for a new sub_id.
  @spec evict_oldest_pending_key(map(), String.t()) :: map()
  defp evict_oldest_pending_key(pending, sub_id) do
    if Map.has_key?(pending, sub_id) or map_size(pending) < @max_pending_distinct_sub_ids do
      pending
    else
      {oldest_id, _} = Enum.at(pending, 0)

      Logger.warning(
        "Subscription: distinct pending sub_id cap (#{@max_pending_distinct_sub_ids}) exceeded; evicting #{inspect(oldest_id)}"
      )

      Map.delete(pending, oldest_id)
    end
  end

  # Parses and delivers a subscription event based on its type.
  @spec dispatch_event(subscription_type(), String.t(), term(), handler()) :: any()
  defp dispatch_event({:logs, _filter}, sub_id, result, handler) do
    case Parser.parse_event(:logs, result) do
      {:ok, parsed} -> handler.({:logs, sub_id, parsed})
      {:error, reason} -> handler.({:parse_error, sub_id, reason})
    end
  end

  defp dispatch_event(type, sub_id, result, handler) when is_atom(type) do
    case Parser.parse_event(type, result) do
      {:ok, parsed} -> handler.({type, sub_id, parsed})
      {:error, reason} -> handler.({:parse_error, sub_id, reason})
    end
  end

  # Converts a user-friendly filter map to the Ethereum JSON-RPC format.
  # Keys: :address (string or list), :topics (list of topic filters)
  @spec build_log_filter(map()) :: map()
  defp build_log_filter(filter) do
    Enum.reduce(filter, %{}, fn
      {:address, addr}, acc -> Map.put(acc, "address", addr)
      {:topics, topics}, acc -> Map.put(acc, "topics", topics)
      {key, val}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), val)
      {key, val}, acc -> Map.put(acc, key, val)
    end)
  end
end
