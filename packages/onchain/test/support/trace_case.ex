defmodule Onchain.TraceCase do
  @moduledoc false

  # Shared :dbg trace helpers for tests that verify calldata passed to
  # Onchain.Signer.send_transaction/3.

  import ExUnit.Assertions, only: [flunk: 1]

  @trace_timeout_ms 1_000

  @doc false
  # Traces Signer.send_transaction/3, executes the given function, and returns
  # the full {to, calldata, opts} tuple from the traced call.
  def capture_signer_call(fun) do
    parent = self()

    handler = fn msg, state ->
      send(parent, {:dbg_trace, msg})
      state
    end

    Code.prepend_path(runtime_tools_ebin!())
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    apply(:dbg, :tracer, [:process, {handler, nil}])
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    apply(:dbg, :p, [self(), [:call]])
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    apply(:dbg, :tpl, [Onchain.Signer, :send_transaction, :x])

    try do
      fun.()
      receive_signer_call()
    after
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      apply(:dbg, :stop_clear, [])
      drain_dbg_messages()
    end
  end

  @doc false
  # Waits for the traced Signer.send_transaction/3 call and returns {to, calldata, opts}.
  defp receive_signer_call do
    receive do
      {:dbg_trace, {:trace, _pid, :call, {Onchain.Signer, :send_transaction, [to, calldata, opts]}}} ->
        {to, calldata, opts}

      {:dbg_trace, _other} ->
        receive_signer_call()
    after
      @trace_timeout_ms ->
        flunk("Expected traced call to Onchain.Signer.send_transaction/3")
    end
  end

  @doc false
  # Clears any buffered dbg trace messages so later tests start cleanly.
  defp drain_dbg_messages do
    receive do
      {:dbg_trace, _message} -> drain_dbg_messages()
    after
      0 -> :ok
    end
  end

  @doc false
  # Finds the OTP runtime_tools ebin path so mix test can load :dbg on demand.
  defp runtime_tools_ebin! do
    root_dir = List.to_string(:code.root_dir())

    case Path.wildcard(Path.join([root_dir, "lib", "runtime_tools-*", "ebin"])) do
      [ebin | _rest] ->
        ebin

      [] ->
        flunk("Could not locate OTP runtime_tools ebin path for :dbg tracing")
    end
  end
end
