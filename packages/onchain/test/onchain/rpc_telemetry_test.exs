defmodule Onchain.RPC.TelemetryTest do
  use ExUnit.Case, async: false

  alias Onchain.RPC

  @event_prefix [:onchain, :rpc, :request]
  @start_event @event_prefix ++ [:start]
  @stop_event @event_prefix ++ [:stop]
  @exception_event @event_prefix ++ [:exception]
  @events [@start_event, @stop_event, @exception_event]
  @receive_timeout_ms 1_000
  @unavailable_rpc_url "http://127.0.0.1:1"
  @short_timeout_ms 50

  defmodule RaisingClient do
    @moduledoc false

    # Req function plug that raises, so the RPC span emits an :exception event.
    def call(_conn), do: raise("test RPC client failure")
  end

  setup do
    handler_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach_many(
        handler_id,
        @events,
        &__MODULE__.handle_event/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  describe "RPC request telemetry" do
    test "emits start and stop events around RPC errors" do
      method = "eth_blockNumber"

      assert {:error, {:rpc_error, %{message: _}}} =
               RPC.call(method, [], rpc_url: @unavailable_rpc_url, timeout: @short_timeout_ms)

      {start_measurements, start_metadata} = assert_rpc_event(@start_event, method)
      {stop_measurements, stop_metadata} = assert_rpc_event(@stop_event, method)

      assert is_integer(start_measurements.system_time)
      assert is_integer(start_measurements.monotonic_time)
      assert start_metadata.method == method

      assert is_integer(stop_measurements.duration)
      assert is_integer(stop_measurements.monotonic_time)
      assert stop_metadata.method == method
      assert stop_metadata.status == :error
      assert {:rpc_error, %{message: _}} = stop_metadata.error
    end

    test "emits exception event and preserves the raised exception" do
      method = "eth_blockNumber"
      previous = Application.get_env(:cartouche, Cartouche.RPC)
      Application.put_env(:cartouche, Cartouche.RPC, plug: &RaisingClient.call/1)

      on_exit(fn ->
        case previous do
          nil -> Application.delete_env(:cartouche, Cartouche.RPC)
          config -> Application.put_env(:cartouche, Cartouche.RPC, config)
        end
      end)

      assert_raise RuntimeError, "test RPC client failure", fn ->
        RPC.call(method, [], rpc_url: @unavailable_rpc_url)
      end

      {_start_measurements, start_metadata} = assert_rpc_event(@start_event, method)
      {exception_measurements, exception_metadata} = assert_rpc_event(@exception_event, method)

      assert start_metadata.method == method
      assert is_integer(exception_measurements.duration)
      assert is_integer(exception_measurements.monotonic_time)
      assert exception_metadata.method == method
      assert exception_metadata.kind == :error
      assert %RuntimeError{message: "test RPC client failure"} = exception_metadata.reason
      assert is_list(exception_metadata.stacktrace)
    end
  end

  def handle_event(event, measurements, metadata, test_pid) do
    send(test_pid, {:rpc_telemetry, event, measurements, metadata})
  end

  defp assert_rpc_event(event, method) do
    receive do
      {:rpc_telemetry, ^event, measurements, %{method: ^method} = metadata} ->
        {measurements, metadata}
    after
      @receive_timeout_ms ->
        flunk("Expected telemetry event #{inspect(event)} for #{inspect(method)}")
    end
  end
end
