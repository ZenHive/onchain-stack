defmodule Cartouche.Filter do
  @moduledoc """
  Poll an Ethereum node-side filter and deliver results to registered listeners.

  Log filters (`kind: :log`, the default) decode matching logs and dispatch
  `{:event, {name, params}, log}` plus `{:log, log}`. Block and pending-transaction
  filters (`kind: :block` / `kind: :pending`) dispatch `{:hashes, hashes}` with
  32-byte hash lists. The GenServer uninstalls its node-side filter on shutdown.
  """

  use GenServer
  use Cartouche.Hex

  alias Cartouche.Filter.Log
  alias Cartouche.RPC

  require Logger

  @check_delay 3000
  @kinds [:log, :block, :pending]

  # Shutdown-budget ceiling for the `terminate/2` uninstall — see
  # `uninstall_filter/1`.
  @uninstall_timeout 2_000

  @doc """
  Starts a `Cartouche.Filter` GenServer that polls an Ethereum node-side filter.

  ## Options

    * `:name` — registered name for the GenServer (defaults to `__MODULE__`)
    * `:kind` — `:log` (default), `:block`, or `:pending`
    * `:address` — contract address to filter on (log filters; omit to match any)
    * `:topics` — list of topic filters (log filters)
    * `:events` — list of `ABI.FunctionSelector.t()` or signature strings;
      events are decoded and dispatched as `{:event, {name, params}, log}`
    * `:rpc_opts` — keyword list forwarded to `Cartouche.RPC` calls
    * `:extra_data` — opaque value attached to every log/event message
    * `:check_delay` — milliseconds between filter polls (default 3000)
  """
  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    kind = Keyword.get(opts, :kind, :log)

    if kind not in @kinds do
      raise ArgumentError, "unknown filter kind: #{inspect(kind)}"
    end

    name = Keyword.get(opts, :name, __MODULE__)
    address = Keyword.get(opts, :address)
    topics = Keyword.get(opts, :topics, [])
    events = Keyword.get(opts, :events, [])
    rpc_opts = Keyword.get(opts, :rpc_opts, [])
    extra_data = Keyword.get(opts, :extra_data)
    check_delay = Keyword.get(opts, :check_delay, @check_delay)

    decoders = event_decoders(events)
    all_topics = Enum.map(decoders, fn {topic, _} -> topic end) ++ topics

    GenServer.start_link(
      __MODULE__,
      %{
        kind: kind,
        address: address,
        topics: all_topics,
        name: name,
        listeners: [],
        decoders: decoders,
        check_delay: check_delay,
        rpc_opts: rpc_opts,
        extra_data: extra_data
      },
      name: name
    )
  end

  @doc """
  Registers the calling process as a listener on `filter`.

  Log filters send `{:event, {name, params}, log}` for matched, decoded events
  and `{:log, log}` for every raw log. Block and pending filters send
  `{:hashes, hashes}` with a list of 32-byte hashes.
  """
  @spec listen(GenServer.server()) :: :ok
  def listen(filter) do
    GenServer.cast(filter, {:listen, self()})
  end

  @doc false
  @impl true
  def init(%{check_delay: check_delay} = state) do
    Process.flag(:trap_exit, true)
    state = set_filter(state)
    Process.send_after(self(), :check_filter, check_delay)
    {:ok, state}
  end

  @doc false
  @impl true
  def terminate(_reason, state) do
    uninstall_filter(state)
    :ok
  end

  @doc false
  @impl true
  def handle_cast({:listen, pid}, %{listeners: listeners} = state) do
    {:noreply, Map.put(state, :listeners, [pid | listeners])}
  end

  @doc false
  @impl true
  def handle_info(:check_filter, %{check_delay: check_delay} = state) do
    Process.send_after(self(), :check_filter, check_delay)
    {:noreply, poll_filter(state)}
  end

  @spec event_decoders(list()) :: %{binary() => function()}
  defp event_decoders(events) do
    for event <- events, into: %{} do
      function_selector =
        case event do
          %ABI.FunctionSelector{
            types: [%{name: "_topic", type: {:uint, 256}, indexed: true} | rest_types]
          } ->
            %{event | types: rest_types}

          %ABI.FunctionSelector{} ->
            event

          event_abi when is_binary(event_abi) ->
            ABI.FunctionSelector.decode(event_abi)
        end

      {ABI.Event.event_signature(function_selector),
       fn event_topics, event_data ->
         ABI.Event.decode_event(event_data, event_topics, function_selector)
       end}
    end
  end

  @spec set_filter(map()) :: map()
  defp set_filter(%{kind: :block, rpc_opts: rpc_opts} = state) do
    {:ok, filter_id} = RPC.new_block_filter(rpc_opts)
    Map.put(state, :filter_id, filter_id)
  end

  defp set_filter(%{kind: :pending, rpc_opts: rpc_opts} = state) do
    {:ok, filter_id} = RPC.new_pending_transaction_filter(rpc_opts)
    Map.put(state, :filter_id, filter_id)
  end

  defp set_filter(%{kind: :log, address: nil, topics: topics, rpc_opts: rpc_opts} = state) do
    {:ok, filter_id} =
      RPC.send_rpc("eth_newFilter", [%{"topics" => Enum.map(topics, &Hex.encode_hex/1)}], rpc_opts)

    Map.put(state, :filter_id, filter_id)
  end

  defp set_filter(%{kind: :log, address: address, topics: topics, rpc_opts: rpc_opts} = state) do
    {:ok, filter_id} =
      RPC.send_rpc(
        "eth_newFilter",
        [
          %{
            "address" => Hex.encode_hex(address),
            "topics" => Enum.map(topics, &Hex.encode_hex/1)
          }
        ],
        rpc_opts
      )

    Map.put(state, :filter_id, filter_id)
  end

  @spec poll_filter(map()) :: map()
  defp poll_filter(%{filter_id: filter_id, name: name, rpc_opts: rpc_opts} = state) do
    case RPC.send_rpc("eth_getFilterChanges", [filter_id], rpc_opts) do
      {:ok, raw} ->
        dispatch_changes(state, raw)

      {:error, %{code: -32_000}} ->
        Logger.error("[Filter #{name}] Filter expired, restarting... Note: some logs may have been lost.")
        set_filter(state)

      {:error, error} ->
        Logger.error("[Filter #{name}] Error getting filter changes: #{inspect(error)}")
        state
    end
  end

  @spec dispatch_changes(map(), list()) :: map()
  defp dispatch_changes(%{kind: :log} = state, raw_logs) do
    %{listeners: listeners, decoders: decoders, extra_data: extra_data} = state

    {logs, events} =
      raw_logs
      |> Enum.map(&Log.deserialize/1)
      |> Enum.map(fn log -> %{log | extra_data: extra_data} end)
      |> parse_events(decoders)

    for listener <- listeners, {event, log} <- events do
      send(listener, {:event, event, log})
    end

    for listener <- listeners, log <- logs do
      send(listener, {:log, log})
    end

    state
  end

  defp dispatch_changes(%{kind: kind, listeners: listeners} = state, raw_hashes) when kind in [:block, :pending] do
    hashes = Enum.map(raw_hashes, &Hex.decode_word!/1)

    if hashes != [] do
      for listener <- listeners do
        send(listener, {:hashes, hashes})
      end
    end

    state
  end

  @spec uninstall_filter(map()) :: :ok
  defp uninstall_filter(%{filter_id: filter_id, rpc_opts: rpc_opts} = state) when not is_nil(filter_id) do
    # The uninstall runs inside `terminate/2`, so it spends the caller's shutdown
    # budget: a supervisor gives a trapping child `:shutdown` ms (5_000 by
    # default) before killing it. `send_rpc/3` otherwise inherits the 30_000 ms
    # transport default, so an unresponsive node would hold the tree open past
    # that budget and be killed mid-call — the failure would never be logged.
    # Bound it well inside the default budget; a caller that set its own
    # `:timeout` in `:rpc_opts` keeps it.
    rpc_opts = Keyword.put_new(rpc_opts, :timeout, @uninstall_timeout)

    case RPC.send_rpc("eth_uninstallFilter", [filter_id], rpc_opts) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("[Filter #{state.name}] Failed to uninstall filter #{inspect(filter_id)}: #{inspect(reason)}")
        :ok
    end
  rescue
    # Uninstall runs from terminate/2; any exception here would crash a
    # supervisor shutdown. The node-side filter then ages out on its own.
    # reach:disable-next-line bare_rescue
    exception ->
      Logger.warning(
        "[Filter #{state.name}] Failed to uninstall filter #{inspect(filter_id)}: #{Exception.message(exception)}"
      )

      :ok
  end

  defp uninstall_filter(_state), do: :ok

  @spec parse_events([Log.t()], %{binary() => function()}) :: {[Log.t()], [{{atom(), [term()]}, Log.t()}]}
  defp parse_events(logs, decoders) do
    events = do_parse_events(logs, decoders, [])
    {logs, Enum.reverse(events)}
  end

  @spec do_parse_events([Log.t()], %{binary() => function()}, [{{atom(), [term()]}, Log.t()}]) ::
          [{{atom(), [term()]}, Log.t()}]
  defp do_parse_events([], _, events), do: events

  defp do_parse_events([log | rest_logs], decoders, acc_events) do
    [topic_0 | _topic_rest] = log.topics

    case Map.get(decoders, topic_0) do
      nil ->
        do_parse_events(rest_logs, decoders, acc_events)

      decoder_fn ->
        case decoder_fn.(log.topics, log.data) do
          {:ok, event_name, event_params} ->
            do_parse_events(rest_logs, decoders, [{{event_name, event_params}, log} | acc_events])

          {:error, error} ->
            Logger.error("Error decoding log: #{error}")
            do_parse_events(rest_logs, decoders, acc_events)
        end
    end
  end
end
