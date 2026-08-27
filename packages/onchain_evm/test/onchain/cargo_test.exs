defmodule Onchain.CargoTest do
  use ExUnit.Case, async: false

  alias Onchain.Cargo

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)
    :ok
  end

  describe "run/2 degradation" do
    test "skips cargo test when cargo is not on PATH" do
      assert :ok = Cargo.run(:test, find_executable: missing_cargo())
      assert_receive {:mix_shell, :info, [msg]}
      assert msg =~ "[skip] cargo test: cargo not found on PATH."
    end

    test "skips cargo clippy when cargo is not on PATH" do
      assert :ok = Cargo.run(:clippy, find_executable: missing_cargo())
      assert_receive {:mix_shell, :info, [msg]}
      assert msg =~ "[skip] cargo clippy: cargo not found on PATH."
    end

    test "skips cargo clippy when the clippy component is missing" do
      cmd = fn
        _cargo, ["clippy", "--version"], _opts -> {"no such command: `clippy`", 1}
        _cargo, args, _opts -> flunk("unexpected cargo invocation: #{inspect(args)}")
      end

      assert :ok = Cargo.run(:clippy, find_executable: find_cargo(), cmd: cmd)
      assert_receive {:mix_shell, :info, [msg]}
      assert msg =~ "[skip] cargo clippy: clippy component not installed."
    end
  end

  describe "run/2 failure" do
    test "raises when cargo test fails in a crate" do
      cmd = fn _cargo, ["test" | _], _opts -> {"FAILED", 1} end

      assert_raise Mix.Error, ~r/cargo test failed in native\/onchain_evm \(exit 1\)/, fn ->
        Cargo.run(:test, find_executable: find_cargo(), cmd: cmd)
      end
    end

    test "raises when cargo clippy fails in a crate" do
      cmd = fn
        _cargo, ["clippy", "--version"], _opts -> {"clippy 0.1.0", 0}
        _cargo, ["clippy" | _], _opts -> {"error: clippy::unwrap_used", 1}
      end

      assert_raise Mix.Error, ~r/cargo clippy failed in native\/onchain_evm \(exit 1\)/, fn ->
        Cargo.run(:clippy, find_executable: find_cargo(), cmd: cmd)
      end
    end
  end

  describe "run/2 success" do
    test "runs cargo test against both crates" do
      cmd = recording_cmd()

      assert :ok = Cargo.run(:test, find_executable: find_cargo(), cmd: cmd)
      assert invocations() == test_invocations()
    end

    test "runs clippy --all-targets -D warnings against both crates" do
      cmd = recording_cmd()

      assert :ok = Cargo.run(:clippy, find_executable: find_cargo(), cmd: cmd)

      assert invocations() == [
               {["clippy", "--version"], [into: "", stderr_to_stdout: true]} | clippy_invocations()
             ]
    end
  end

  describe "lint selection" do
    test "both crates deny unwrap_used and do not deny expect_used" do
      for crate <- Cargo.crates() do
        toml = File.read!(Path.join(crate, "Cargo.toml"))
        assert toml =~ ~r/(?m)^unwrap_used = "deny"$/
        refute toml =~ ~r/expect_used\s*=\s*"deny"/

        lib = File.read!(Path.join(crate, "src/lib.rs"))
        assert lib =~ "#![cfg_attr(test, allow(clippy::unwrap_used))]"
      end
    end
  end

  describe "mix alias wiring" do
    test "precommit.full runs cargo test then clippy; dispatch and precommit do not" do
      aliases = Mix.Project.config()[:aliases]
      full = alias_fun_names(aliases[:"precommit.full"])

      assert :cargo_test in full
      assert :cargo_clippy in full
      assert Enum.find_index(full, &(&1 == :cargo_test)) < Enum.find_index(full, &(&1 == :cargo_clippy))

      refute :cargo_test in alias_fun_names(aliases[:"check.dispatch"])
      refute :cargo_clippy in alias_fun_names(aliases[:"check.dispatch"])
      refute :cargo_test in alias_fun_names(aliases[:precommit])
      refute :cargo_clippy in alias_fun_names(aliases[:precommit])
    end
  end

  defp find_cargo, do: fn "cargo" -> "/usr/bin/cargo" end
  defp missing_cargo, do: fn "cargo" -> nil end

  defp recording_cmd do
    pid = self()

    cmd = fn _cargo, args, opts ->
      send(pid, {:cargo, args, into_tag(Keyword.take(opts, [:into, :stderr_to_stdout]))})
      {"", 0}
    end

    cmd
  end

  defp into_tag(opts) do
    case Keyword.get(opts, :into) do
      "" -> [into: "", stderr_to_stdout: Keyword.get(opts, :stderr_to_stdout)]
      %IO.Stream{} -> [into: :stdio, stderr_to_stdout: Keyword.get(opts, :stderr_to_stdout)]
      other -> [into: other, stderr_to_stdout: Keyword.get(opts, :stderr_to_stdout)]
    end
  end

  defp invocations(acc \\ []) do
    receive do
      {:cargo, args, opts} -> invocations(acc ++ [{args, opts}])
    after
      0 -> acc
    end
  end

  defp test_invocations do
    for crate <- Cargo.crates() do
      {["test", "--manifest-path", Path.join(crate, "Cargo.toml")], [into: :stdio, stderr_to_stdout: true]}
    end
  end

  defp clippy_invocations do
    for crate <- Cargo.crates() do
      {[
         "clippy",
         "--manifest-path",
         Path.join(crate, "Cargo.toml"),
         "--all-targets",
         "--",
         "-D",
         "warnings"
       ], [into: :stdio, stderr_to_stdout: true]}
    end
  end

  defp alias_fun_names(steps) when is_list(steps) do
    Enum.flat_map(steps, fn
      step when is_function(step) -> [:erlang.fun_info(step)[:name]]
      _step -> []
    end)
  end

  defp alias_fun_names(_), do: []
end
