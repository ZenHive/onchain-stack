defmodule Onchain.BangHelperTest do
  use ExUnit.Case, async: true

  # Test modules that use defbang with known return values

  defmodule PatternA do
    @moduledoc false
    import Onchain.BangHelper, only: [defbang: 1]

    def greet(name) when is_binary(name), do: {:ok, "hello #{name}"}
    def greet(_name), do: {:error, :invalid_name}

    def fail(name) when is_binary(name), do: {:error, :not_found}
    def fail(_name), do: {:ok, :never}

    defbang(greet!(name))
    defbang(fail!(name))
  end

  defmodule PatternADefaults do
    @moduledoc false
    import Onchain.BangHelper, only: [defbang: 1]

    def fetch(key, default \\ "none")
    def fetch(key, default) when is_binary(key), do: {:ok, "#{key}=#{default}"}
    def fetch(_key, _default), do: {:error, :invalid_key}

    def fail_fetch(key, default \\ "none")
    def fail_fetch(key, _default) when is_binary(key), do: {:error, {:missing, key}}
    def fail_fetch(_key, _default), do: {:ok, :never}

    defbang(fetch!(key, default \\ "none"))
    defbang(fail_fetch!(key, default \\ "none"))
  end

  defmodule PatternBC do
    @moduledoc false
    import Onchain.BangHelper, only: [defbang: 2]

    def parse(input) do
      case input do
        "good" -> {:ok, %{parsed: true}}
        "bad_parse" -> {:error, {:parse_error, "syntax error on line 1"}}
        "bad_file" -> {:error, {:file_error, "no such file"}}
        "unknown" -> {:error, :unexpected_thing}
      end
    end

    defbang(parse!(input),
      errors: [parse_error: "Parse failed", file_error: "File error"],
      fallback: "Unknown error"
    )
  end

  defmodule PatternBNoFallback do
    @moduledoc false
    import Onchain.BangHelper, only: [defbang: 2]

    def run(input) do
      case input do
        "ok" -> {:ok, :done}
        "fail" -> {:error, {:timeout, "timed out"}}
      end
    end

    defbang(run!(input), errors: [timeout: "Timed out"])
  end

  describe "Pattern A (simple)" do
    test "unwraps {:ok, result}" do
      assert "hello world" = PatternA.greet!("world")
    end

    test "raises on {:error, reason} with function name in message" do
      error = assert_raise(RuntimeError, fn -> PatternA.fail!("x") end)
      assert error.message =~ "fail failed:"
      assert error.message =~ ":not_found"
    end
  end

  describe "Pattern A with defaults" do
    test "uses default argument" do
      assert "key=none" = PatternADefaults.fetch!("key")
    end

    test "overrides default argument" do
      assert "key=val" = PatternADefaults.fetch!("key", "val")
    end

    test "raises with defaults" do
      error = assert_raise(RuntimeError, fn -> PatternADefaults.fail_fetch!("k") end)
      assert error.message =~ "fail_fetch failed:"
    end
  end

  describe "Pattern B/C (tagged errors + fallback)" do
    test "unwraps {:ok, result}" do
      assert %{parsed: true} = PatternBC.parse!("good")
    end

    test "raises with tagged :parse_error message" do
      error = assert_raise(RuntimeError, fn -> PatternBC.parse!("bad_parse") end)
      assert error.message =~ "Parse failed"
      assert error.message =~ "syntax error on line 1"
    end

    test "raises with tagged :file_error message" do
      error = assert_raise(RuntimeError, fn -> PatternBC.parse!("bad_file") end)
      assert error.message =~ "File error"
      assert error.message =~ "no such file"
    end

    test "raises with fallback on untagged error" do
      error = assert_raise(RuntimeError, fn -> PatternBC.parse!("unknown") end)
      assert error.message =~ "Unknown error"
      assert error.message =~ ":unexpected_thing"
    end
  end

  describe "Pattern B without fallback" do
    test "unwraps {:ok, result}" do
      assert :done = PatternBNoFallback.run!("ok")
    end

    test "raises with tagged message" do
      error = assert_raise(RuntimeError, fn -> PatternBNoFallback.run!("fail") end)
      assert error.message =~ "Timed out"
      assert error.message =~ "timed out"
    end
  end
end
