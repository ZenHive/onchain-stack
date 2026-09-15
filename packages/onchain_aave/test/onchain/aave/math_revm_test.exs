defmodule Onchain.Aave.MathRevmTest do
  @moduledoc """
  Cross-validates `Onchain.Aave.Math` against the canonical Aave V3 Solidity
  bodies executed inside revm.

  Runs per-function deterministic vectors plus StreamData property-based random
  inputs (zero-tolerance equality). The wrapper bytecode lives in
  `test/fixtures/wad_ray_wrapper.bin`; its SHA256 is pinned in
  `test/fixtures/wad_ray_wrapper.json` and verified at setup time.

  ## Coverage / runtime tradeoff

  Each live `Onchain.EVM` call is a DirtyIo NIF that ExUnit cannot interrupt.
  The original shape (one fork per vector, `max_runs: 200`,
  `timeout: :infinity`) took 3055s for this file on a healthy archive node
  (2026-08-23) and hung without bound on a flapping RPC.

  Default (`mix test.json --include integration` / `--only math_revm`):

    * one `simulate_batch` fork per test (all vectors share the fork)
    * 20 random samples per property (`@default_property_runs`)
    * 10_000 ms per RPC request (`:timeout_ms`, the interrupt that
      actually stops a DirtyIo NIF)
    * 60_000 ms ExUnit per-test backstop (never `:infinity`)

  Wall-clock ceiling for **this module** on a healthy archive node: **3
  minutes**. A dead or black-holed RPC fails the affected test within one
  `:timeout_ms` (plus a few seconds of connect slack), not as a hang.

  Exhaustive variant (original 200 samples per property, still one fork
  per test — typically still under the 3-minute ceiling):

      MATH_REVM_EXHAUSTIVE=1 mix test.json --only math_revm

  Domain-class coverage that does not need a live fork lives in
  `Onchain.Aave.Math.PropertyTest` (unit, `mix ci`).
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Onchain.Aave.Math
  alias Onchain.ABI
  alias Onchain.EVM
  alias Onchain.RPCCase

  @default_property_runs 20
  @exhaustive_property_runs 200
  @rpc_timeout_ms 10_000
  @test_timeout_ms 60_000
  @black_hole_rpc "http://192.0.2.1:8545"
  @refused_rpc "http://127.0.0.1:1"
  @black_hole_timeout_ms 1_000
  @rpc_fail_bound_ms 5_000

  @moduletag :integration
  @moduletag :math_revm
  @moduletag timeout: @test_timeout_ms

  # Fake address where the wrapper bytecode is injected via state_overrides.
  @wrapper_address "0x000000000000000000000000000000000000beef"

  @fixtures_dir Path.expand("../../fixtures", __DIR__)
  @bin_path Path.join(@fixtures_dir, "wad_ray_wrapper.bin")
  @meta_path Path.join(@fixtures_dir, "wad_ray_wrapper.json")

  # --- Aave V3 constants (must match Math module + Solidity wrapper) ---
  @ray 1_000_000_000_000_000_000_000_000_000
  @half_ray 500_000_000_000_000_000_000_000_000
  @wad 1_000_000_000_000_000_000
  @half_wad 500_000_000_000_000_000
  @wad_ray_ratio 1_000_000_000
  @seconds_per_year 31_536_000

  # --- Property bounds (chosen to stay safely below Aave's overflow reverts) ---
  # 10 * RAY ≈ 1e28; 10_000 * RAY ≈ 1e31; 10_000 * WAD ≈ 1e22.
  # rayMul/wadMul overflow trips when a*b > 2^256 − HALF. All bounds below
  # keep a*b ≤ 1e63, which is ~14 orders of magnitude from uint256 max.
  @max_ray_amount 10_000 * @ray
  @max_wad_amount 10_000 * @wad
  @max_rate 10 * @ray
  @max_elapsed 10 * @seconds_per_year

  setup_all do
    rpc_url = RPCCase.rpc_url!()

    bin_hex = @bin_path |> File.read!() |> String.trim()
    meta = @meta_path |> File.read!() |> Jason.decode!()

    expected_sha = meta["wrapper"]["bin_sha256"]
    actual_sha = :sha256 |> :crypto.hash(bin_hex) |> Base.encode16(case: :lower)

    if expected_sha != actual_sha do
      flunk("""
      wad_ray_wrapper.bin checksum mismatch!
        expected: #{expected_sha}
        actual:   #{actual_sha}

      Regenerate fixtures — see test/fixtures/README.md.
      """)
    end

    opts = [
      rpc_url: rpc_url,
      block: "latest",
      timeout_ms: @rpc_timeout_ms,
      state_overrides: %{@wrapper_address => %{"code" => "0x" <> bin_hex}}
    ]

    {:ok, opts: opts}
  end

  describe "runtime bounds" do
    test "does not set an infinite ExUnit timeout", %{timeout: timeout} do
      assert timeout == @test_timeout_ms
    end

    test "a wrong elixir result is reported as a divergence", ctx do
      assert_raise ExUnit.AssertionError, ~r/divergence/, fn ->
        assert_same_as_revm(ctx, "rayMul(uint256,uint256)", [@ray, @ray], fn -> 0 end)
      end
    end

    @tag timeout: 15_000
    test "black-hole archive RPC fails within the per-call timeout" do
      ctx = %{opts: [rpc_url: @black_hole_rpc, block: "latest", timeout_ms: @black_hole_timeout_ms]}
      started = System.monotonic_time(:millisecond)

      assert_raise ExUnit.AssertionError, ~r/timed out|unreachable/i, fn ->
        call_wrapper(ctx, "rayMul(uint256,uint256)", [@ray, @ray])
      end

      elapsed = System.monotonic_time(:millisecond) - started

      assert elapsed < @rpc_fail_bound_ms,
             "black-hole RPC hung #{elapsed}ms; expected failure within #{@rpc_fail_bound_ms}ms"
    end

    @tag timeout: 15_000
    test "refused archive RPC fails loudly instead of hanging" do
      ctx = %{opts: [rpc_url: @refused_rpc, block: "latest", timeout_ms: @rpc_timeout_ms]}
      started = System.monotonic_time(:millisecond)

      assert_raise ExUnit.AssertionError, ~r/timed out|unreachable/i, fn ->
        call_wrapper(ctx, "rayMul(uint256,uint256)", [@ray, @ray])
      end

      elapsed = System.monotonic_time(:millisecond) - started

      assert elapsed < @rpc_fail_bound_ms,
             "refused RPC hung #{elapsed}ms; expected failure within #{@rpc_fail_bound_ms}ms"
    end
  end

  # --- rayMul ---

  describe "rayMul" do
    test "deterministic vectors agree with revm", ctx do
      assert_same_as_revm_batch(
        ctx,
        "rayMul(uint256,uint256)",
        [
          [@ray, @ray],
          [0, 0],
          [0, @ray],
          [@ray, 0],
          [1, @half_ray],
          [1, @half_ray - 1],
          [1, @half_ray + 1],
          [div(@ray, 2), div(@ray, 2)],
          [3 * @ray, 5 * @ray],
          [@ray - 1, @ray - 1]
        ],
        fn [a, b] -> Math.ray_mul(a, b) end
      )
    end

    property "matches Solidity for random ray inputs", ctx do
      check all(
              pairs <-
                list_of(
                  tuple({integer(0..@max_ray_amount), integer(0..@max_ray_amount)}),
                  length: property_runs()
                ),
              max_runs: 1
            ) do
        assert_same_as_revm_batch(
          ctx,
          "rayMul(uint256,uint256)",
          Enum.map(pairs, fn {a, b} -> [a, b] end),
          fn [a, b] -> Math.ray_mul(a, b) end
        )
      end
    end
  end

  # --- rayDiv ---

  describe "rayDiv" do
    test "deterministic vectors agree with revm", ctx do
      assert_same_as_revm_batch(
        ctx,
        "rayDiv(uint256,uint256)",
        [
          [@ray, @ray],
          [0, @ray],
          [0, 123],
          [2 * @ray, @ray],
          [@ray, 2 * @ray],
          [7 * @ray, 7 * @ray],
          [1, 3],
          [1, 2],
          [@ray - 1, 2 * @ray]
        ],
        fn [a, b] -> Math.ray_div(a, b) end
      )
    end

    property "matches Solidity for random ray inputs", ctx do
      check all(
              pairs <-
                list_of(
                  tuple({integer(0..@max_ray_amount), integer(1..@max_ray_amount)}),
                  length: property_runs()
                ),
              max_runs: 1
            ) do
        assert_same_as_revm_batch(
          ctx,
          "rayDiv(uint256,uint256)",
          Enum.map(pairs, fn {a, b} -> [a, b] end),
          fn [a, b] -> Math.ray_div(a, b) end
        )
      end
    end
  end

  # --- wadMul ---

  describe "wadMul" do
    test "deterministic vectors agree with revm", ctx do
      assert_same_as_revm_batch(
        ctx,
        "wadMul(uint256,uint256)",
        [
          [@wad, @wad],
          [0, 0],
          [0, @wad],
          [@wad, 0],
          [1, @half_wad],
          [1, @half_wad - 1],
          [1, @half_wad + 1],
          [div(@wad, 2), div(@wad, 2)],
          [3 * @wad, 5 * @wad]
        ],
        fn [a, b] -> Math.wad_mul(a, b) end
      )
    end

    property "matches Solidity for random wad inputs", ctx do
      check all(
              pairs <-
                list_of(
                  tuple({integer(0..@max_wad_amount), integer(0..@max_wad_amount)}),
                  length: property_runs()
                ),
              max_runs: 1
            ) do
        assert_same_as_revm_batch(
          ctx,
          "wadMul(uint256,uint256)",
          Enum.map(pairs, fn {a, b} -> [a, b] end),
          fn [a, b] -> Math.wad_mul(a, b) end
        )
      end
    end
  end

  # --- wadDiv ---

  describe "wadDiv" do
    test "deterministic vectors agree with revm", ctx do
      assert_same_as_revm_batch(
        ctx,
        "wadDiv(uint256,uint256)",
        [
          [@wad, @wad],
          [0, @wad],
          [0, 123],
          [2 * @wad, @wad],
          [@wad, 2 * @wad],
          [7 * @wad, 7 * @wad],
          [1, 3],
          [1, 2],
          [@wad - 1, 2 * @wad]
        ],
        fn [a, b] -> Math.wad_div(a, b) end
      )
    end

    property "matches Solidity for random wad inputs", ctx do
      check all(
              pairs <-
                list_of(
                  tuple({integer(0..@max_wad_amount), integer(1..@max_wad_amount)}),
                  length: property_runs()
                ),
              max_runs: 1
            ) do
        assert_same_as_revm_batch(
          ctx,
          "wadDiv(uint256,uint256)",
          Enum.map(pairs, fn {a, b} -> [a, b] end),
          fn [a, b] -> Math.wad_div(a, b) end
        )
      end
    end
  end

  # --- rayToWad ---

  describe "rayToWad" do
    test "deterministic vectors agree with revm", ctx do
      assert_same_as_revm_batch(
        ctx,
        "rayToWad(uint256)",
        [
          [0],
          [@ray],
          [2 * @ray],
          [div(@wad_ray_ratio, 2)],
          [div(@wad_ray_ratio, 2) - 1],
          [div(@wad_ray_ratio, 2) + 1],
          [2 * @ray - 1],
          [@ray + div(@wad_ray_ratio, 2)],
          [123_456_789_000_000_000_000_000_000]
        ],
        fn [a] -> Math.ray_to_wad(a) end
      )
    end

    property "matches Solidity for random ray inputs", ctx do
      check all(values <- list_of(integer(0..@max_ray_amount), length: property_runs()), max_runs: 1) do
        assert_same_as_revm_batch(
          ctx,
          "rayToWad(uint256)",
          Enum.map(values, &[&1]),
          fn [a] -> Math.ray_to_wad(a) end
        )
      end
    end
  end

  # --- wadToRay ---

  describe "wadToRay" do
    test "deterministic vectors agree with revm", ctx do
      assert_same_as_revm_batch(
        ctx,
        "wadToRay(uint256)",
        [[0], [1], [@wad], [2 * @wad], [123_456_789], [999_999_999_999_999_999]],
        fn [a] -> Math.wad_to_ray(a) end
      )
    end

    property "matches Solidity for random wad inputs", ctx do
      check all(values <- list_of(integer(0..@max_wad_amount), length: property_runs()), max_runs: 1) do
        assert_same_as_revm_batch(
          ctx,
          "wadToRay(uint256)",
          Enum.map(values, &[&1]),
          fn [a] -> Math.wad_to_ray(a) end
        )
      end
    end
  end

  # --- calculateLinearInterest ---

  describe "calculateLinearInterest" do
    test "deterministic vectors agree with revm", ctx do
      last = 1_700_000_000

      assert_same_as_revm_batch(
        ctx,
        "calculateLinearInterestAt(uint256,uint256,uint256)",
        [
          [0, last, last],
          [0, last, last + 10 * @seconds_per_year],
          [5 * div(@ray, 100), last, last],
          [5 * div(@ray, 100), last, last + @seconds_per_year],
          [5 * div(@ray, 100), last, last + div(@seconds_per_year, 2)],
          [div(@ray, 10), last, last + 1],
          [@ray, last, last + 12 * 86_400]
        ],
        fn [rate, lut, cur] -> Math.calculate_linear_interest(rate, lut, cur) end
      )
    end

    property "matches Solidity for random rate/elapsed inputs", ctx do
      check all(
              triples <-
                list_of(
                  tuple({integer(0..@max_rate), integer(0..2_000_000_000), integer(0..@max_elapsed)}),
                  length: property_runs()
                ),
              max_runs: 1
            ) do
        assert_same_as_revm_batch(
          ctx,
          "calculateLinearInterestAt(uint256,uint256,uint256)",
          Enum.map(triples, fn {rate, last, elapsed} -> [rate, last, last + elapsed] end),
          fn [rate, lut, cur] -> Math.calculate_linear_interest(rate, lut, cur) end
        )
      end
    end
  end

  # --- calculateCompoundedInterest ---

  describe "calculateCompoundedInterest" do
    test "deterministic vectors agree with revm", ctx do
      last = 1_700_000_000

      assert_same_as_revm_batch(
        ctx,
        "calculateCompoundedInterest(uint256,uint256,uint256)",
        [
          [0, last, last + @seconds_per_year],
          [5 * div(@ray, 100), last, last],
          [5 * div(@ray, 100), last, last + 86_400],
          [5 * div(@ray, 100), last, last + @seconds_per_year],
          [div(@ray, 10), last, last + 7 * 86_400],
          [@ray, last, last + 1]
        ],
        fn [rate, lut, cur] -> Math.calculate_compounded_interest(rate, lut, cur) end
      )
    end

    property "matches Solidity for random rate/elapsed inputs", ctx do
      check all(
              triples <-
                list_of(
                  tuple({integer(0..@max_rate), integer(0..2_000_000_000), integer(0..@max_elapsed)}),
                  length: property_runs()
                ),
              max_runs: 1
            ) do
        assert_same_as_revm_batch(
          ctx,
          "calculateCompoundedInterest(uint256,uint256,uint256)",
          Enum.map(triples, fn {rate, last, elapsed} -> [rate, last, last + elapsed] end),
          fn [rate, lut, cur] -> Math.calculate_compounded_interest(rate, lut, cur) end
        )
      end
    end
  end

  # --- Helpers --------------------------------------------------------------

  @spec property_runs() :: pos_integer()
  defp property_runs do
    case System.get_env("MATH_REVM_EXHAUSTIVE") do
      "1" -> @exhaustive_property_runs
      _ -> @default_property_runs
    end
  end

  @spec assert_same_as_revm(
          %{:opts => keyword(), optional(atom()) => term()},
          String.t(),
          [non_neg_integer()],
          (-> non_neg_integer())
        ) :: :ok
  defp assert_same_as_revm(ctx, signature, args, elixir_fun) do
    assert_same_as_revm_batch(ctx, signature, [args], fn _ -> elixir_fun.() end)
  end

  @spec assert_same_as_revm_batch(
          %{:opts => keyword(), optional(atom()) => term()},
          String.t(),
          [[non_neg_integer()]],
          ([non_neg_integer()] -> non_neg_integer())
        ) :: :ok
  defp assert_same_as_revm_batch(ctx, signature, args_list, elixir_fun) do
    elixir_values = Enum.map(args_list, elixir_fun)
    revm_values = call_wrapper_batch(ctx, signature, args_list)

    [args_list, elixir_values, revm_values]
    |> Enum.zip()
    |> Enum.each(fn {args, elixir, revm} ->
      if elixir == revm do
        :ok
      else
        flunk("""
        #{signature} divergence!
          args:   #{inspect(args)}
          elixir: #{elixir}
          revm:   #{revm}
        """)
      end
    end)
  end

  @spec call_wrapper(
          %{:opts => keyword(), optional(atom()) => term()},
          String.t(),
          [non_neg_integer()]
        ) :: non_neg_integer()
  defp call_wrapper(ctx, signature, args) do
    [value] = call_wrapper_batch(ctx, signature, [args])
    value
  end

  @spec call_wrapper_batch(
          %{:opts => keyword(), optional(atom()) => term()},
          String.t(),
          [[non_neg_integer()]]
        ) :: [non_neg_integer()]
  defp call_wrapper_batch(ctx, signature, args_list) do
    calls =
      Enum.map(args_list, fn args ->
        {@wrapper_address, ABI.encode_call!(signature, args)}
      end)

    case EVM.simulate_batch(calls, ctx.opts) do
      {:ok, results} ->
        decode_batch_results!(signature, args_list, results)

      {:error, {:timeout, reason}} ->
        flunk("""
        archive RPC timed out for #{signature}
          reason: #{inspect(reason)}
        """)

      {:error, {:fork_error, reason}} ->
        flunk("""
        archive RPC unreachable for #{signature}
          reason: #{inspect(reason)}
        """)

      {:error, reason} ->
        flunk("""
        revm batch failed for #{signature}
          reason: #{inspect(reason)}
        """)
    end
  end

  @spec decode_batch_results!(String.t(), [[non_neg_integer()]], [EVM.tx_result()]) :: [non_neg_integer()]
  defp decode_batch_results!(signature, args_list, results) do
    args_list
    |> Enum.zip(results)
    |> Enum.map(fn {args, result} ->
      if result.success do
        [value] = ABI.decode_response!("(uint256)", result.output)
        value
      else
        flunk("""
        revm call reverted for #{signature}
          args:   #{inspect(args)}
          output: #{inspect(result.output)}
        """)
      end
    end)
  end
end
