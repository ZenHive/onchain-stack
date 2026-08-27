defmodule OnchainJs.RuntimeTest do
  use ExUnit.Case, async: false

  alias OnchainJs.Runtime
  alias OnchainJs.RuntimeSupervisor

  @moduletag :integration

  describe "lifecycle" do
    test "start_link/1, eval/2, stop/1 round-trip" do
      assert {:ok, rt} = Runtime.start_link()
      assert is_pid(rt)
      assert Process.alive?(rt)

      assert {:ok, 2} = Runtime.eval(rt, "1 + 1")

      assert :ok = Runtime.stop(rt)
      refute Process.alive?(rt)
    end
  end

  describe "apply_browser_stubs/1" do
    setup do
      {:ok, rt} = Runtime.start_link()
      on_exit(fn -> if Process.alive?(rt), do: Runtime.stop(rt) end)
      {:ok, rt: rt}
    end

    test "stubs self/window so that self === globalThis", %{rt: rt} do
      assert :ok = Runtime.apply_browser_stubs(rt)

      assert {:ok, true} =
               Runtime.eval(rt, "typeof self === 'object' && self === globalThis")

      assert {:ok, true} =
               Runtime.eval(rt, "typeof window === 'object' && window === globalThis")

      assert {:ok, "OnchainJs"} = Runtime.eval(rt, "navigator.userAgent")
      assert {:ok, "https:"} = Runtime.eval(rt, "location.protocol")
    end
  end

  describe "eval/3 and call/3,4" do
    setup do
      {:ok, rt} = Runtime.start_link()
      on_exit(fn -> if Process.alive?(rt), do: Runtime.stop(rt) end)
      {:ok, rt: rt}
    end

    test "eval/3 supports :vars", %{rt: rt} do
      assert {:ok, "ONCHAINJS"} =
               Runtime.eval(rt, "name.toUpperCase()", vars: %{"name" => "onchainJs"})
    end

    test "call/3 invokes a registered global function", %{rt: rt} do
      assert {:ok, _} =
               Runtime.eval(rt, "function add(a, b) { return a + b }")

      assert {:ok, 5} = Runtime.call(rt, "add", [2, 3])
    end

    test "call/4 forwards options (e.g. :timeout)", %{rt: rt} do
      assert {:ok, _} =
               Runtime.eval(rt, "function ident(x) { return x }")

      assert {:ok, "abc"} = Runtime.call(rt, "ident", ["abc"], timeout: 5_000)
    end
  end

  describe "supervised lifecycle" do
    test "DynamicSupervisor.start_child/2 spawns a runtime; terminate_child/2 stops it" do
      assert {:ok, pid} =
               DynamicSupervisor.start_child(RuntimeSupervisor, {Runtime, []})

      assert is_pid(pid)
      assert Process.alive?(pid)

      assert {:ok, 4} = Runtime.eval(pid, "2 + 2")

      assert :ok = DynamicSupervisor.terminate_child(RuntimeSupervisor, pid)
      refute Process.alive?(pid)
    end
  end
end
