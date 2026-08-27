defmodule Onchain.Aave.MathRevmTest do
  @moduledoc """
  Cross-validates `Onchain.Aave.Math` against the canonical Aave V3 Solidity
  bodies executed inside revm.

  Runs per-function deterministic vectors plus StreamData property-based random
  inputs (zero-tolerance equality). The wrapper bytecode lives in
  `test/fixtures/wad_ray_wrapper.bin`; its SHA256 is pinned in
  `test/fixtures/wad_ray_wrapper.json` and verified at setup time.
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Onchain.Aave.Math
  alias Onchain.ABI
  alias Onchain.EVM
  alias Onchain.RPCCase

  @moduletag :integration
  @moduletag :math_revm
  @moduletag timeout: :infinity

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
      state_overrides: %{@wrapper_address => %{"code" => "0x" <> bin_hex}}
    ]

    {:ok, opts: opts}
  end

  # --- rayMul ---

  describe "rayMul" do
    test "deterministic vectors agree with revm", ctx do
      for {a, b} <- [
            {@ray, @ray},
            {0, 0},
            {0, @ray},
            {@ray, 0},
            {1, @half_ray},
            {1, @half_ray - 1},
            {1, @half_ray + 1},
            {div(@ray, 2), div(@ray, 2)},
            {3 * @ray, 5 * @ray},
            {@ray - 1, @ray - 1}
          ] do
        assert_same_as_revm(ctx, "rayMul(uint256,uint256)", [a, b], fn -> Math.ray_mul(a, b) end)
      end
    end

    property "matches Solidity for random ray inputs", ctx do
      check all(
              a <- integer(0..@max_ray_amount),
              b <- integer(0..@max_ray_amount),
              max_runs: 200
            ) do
        assert_same_as_revm(ctx, "rayMul(uint256,uint256)", [a, b], fn -> Math.ray_mul(a, b) end)
      end
    end
  end

  # --- rayDiv ---

  describe "rayDiv" do
    test "deterministic vectors agree with revm", ctx do
      for {a, b} <- [
            {@ray, @ray},
            {0, @ray},
            {0, 123},
            {2 * @ray, @ray},
            {@ray, 2 * @ray},
            {7 * @ray, 7 * @ray},
            {1, 3},
            {1, 2},
            {@ray - 1, 2 * @ray}
          ] do
        assert_same_as_revm(ctx, "rayDiv(uint256,uint256)", [a, b], fn -> Math.ray_div(a, b) end)
      end
    end

    property "matches Solidity for random ray inputs", ctx do
      check all(
              a <- integer(0..@max_ray_amount),
              b <- integer(1..@max_ray_amount),
              max_runs: 200
            ) do
        assert_same_as_revm(ctx, "rayDiv(uint256,uint256)", [a, b], fn -> Math.ray_div(a, b) end)
      end
    end
  end

  # --- wadMul ---

  describe "wadMul" do
    test "deterministic vectors agree with revm", ctx do
      for {a, b} <- [
            {@wad, @wad},
            {0, 0},
            {0, @wad},
            {@wad, 0},
            {1, @half_wad},
            {1, @half_wad - 1},
            {1, @half_wad + 1},
            {div(@wad, 2), div(@wad, 2)},
            {3 * @wad, 5 * @wad}
          ] do
        assert_same_as_revm(ctx, "wadMul(uint256,uint256)", [a, b], fn -> Math.wad_mul(a, b) end)
      end
    end

    property "matches Solidity for random wad inputs", ctx do
      check all(
              a <- integer(0..@max_wad_amount),
              b <- integer(0..@max_wad_amount),
              max_runs: 200
            ) do
        assert_same_as_revm(ctx, "wadMul(uint256,uint256)", [a, b], fn -> Math.wad_mul(a, b) end)
      end
    end
  end

  # --- wadDiv ---

  describe "wadDiv" do
    test "deterministic vectors agree with revm", ctx do
      for {a, b} <- [
            {@wad, @wad},
            {0, @wad},
            {0, 123},
            {2 * @wad, @wad},
            {@wad, 2 * @wad},
            {7 * @wad, 7 * @wad},
            {1, 3},
            {1, 2},
            {@wad - 1, 2 * @wad}
          ] do
        assert_same_as_revm(ctx, "wadDiv(uint256,uint256)", [a, b], fn -> Math.wad_div(a, b) end)
      end
    end

    property "matches Solidity for random wad inputs", ctx do
      check all(
              a <- integer(0..@max_wad_amount),
              b <- integer(1..@max_wad_amount),
              max_runs: 200
            ) do
        assert_same_as_revm(ctx, "wadDiv(uint256,uint256)", [a, b], fn -> Math.wad_div(a, b) end)
      end
    end
  end

  # --- rayToWad ---

  describe "rayToWad" do
    test "deterministic vectors agree with revm", ctx do
      for a <- [
            0,
            @ray,
            2 * @ray,
            div(@wad_ray_ratio, 2),
            div(@wad_ray_ratio, 2) - 1,
            div(@wad_ray_ratio, 2) + 1,
            2 * @ray - 1,
            @ray + div(@wad_ray_ratio, 2),
            123_456_789_000_000_000_000_000_000
          ] do
        assert_same_as_revm(ctx, "rayToWad(uint256)", [a], fn -> Math.ray_to_wad(a) end)
      end
    end

    property "matches Solidity for random ray inputs", ctx do
      check all(a <- integer(0..@max_ray_amount), max_runs: 200) do
        assert_same_as_revm(ctx, "rayToWad(uint256)", [a], fn -> Math.ray_to_wad(a) end)
      end
    end
  end

  # --- wadToRay ---

  describe "wadToRay" do
    test "deterministic vectors agree with revm", ctx do
      for a <- [0, 1, @wad, 2 * @wad, 123_456_789, 999_999_999_999_999_999] do
        assert_same_as_revm(ctx, "wadToRay(uint256)", [a], fn -> Math.wad_to_ray(a) end)
      end
    end

    property "matches Solidity for random wad inputs", ctx do
      check all(a <- integer(0..@max_wad_amount), max_runs: 200) do
        assert_same_as_revm(ctx, "wadToRay(uint256)", [a], fn -> Math.wad_to_ray(a) end)
      end
    end
  end

  # --- calculateLinearInterest ---

  describe "calculateLinearInterest" do
    test "deterministic vectors agree with revm", ctx do
      last = 1_700_000_000
      # {rate, last, current}
      vectors = [
        {0, last, last},
        {0, last, last + 10 * @seconds_per_year},
        {5 * div(@ray, 100), last, last},
        {5 * div(@ray, 100), last, last + @seconds_per_year},
        {5 * div(@ray, 100), last, last + div(@seconds_per_year, 2)},
        {div(@ray, 10), last, last + 1},
        {@ray, last, last + 12 * 86_400}
      ]

      for {rate, lut, cur} <- vectors do
        assert_same_as_revm(
          ctx,
          "calculateLinearInterestAt(uint256,uint256,uint256)",
          [rate, lut, cur],
          fn -> Math.calculate_linear_interest(rate, lut, cur) end
        )
      end
    end

    property "matches Solidity for random rate/elapsed inputs", ctx do
      check all(
              rate <- integer(0..@max_rate),
              last <- integer(0..2_000_000_000),
              elapsed <- integer(0..@max_elapsed),
              max_runs: 200
            ) do
        cur = last + elapsed

        assert_same_as_revm(
          ctx,
          "calculateLinearInterestAt(uint256,uint256,uint256)",
          [rate, last, cur],
          fn -> Math.calculate_linear_interest(rate, last, cur) end
        )
      end
    end
  end

  # --- calculateCompoundedInterest ---

  describe "calculateCompoundedInterest" do
    test "deterministic vectors agree with revm", ctx do
      last = 1_700_000_000

      vectors = [
        {0, last, last + @seconds_per_year},
        {5 * div(@ray, 100), last, last},
        {5 * div(@ray, 100), last, last + 86_400},
        {5 * div(@ray, 100), last, last + @seconds_per_year},
        {div(@ray, 10), last, last + 7 * 86_400},
        {@ray, last, last + 1}
      ]

      for {rate, lut, cur} <- vectors do
        assert_same_as_revm(
          ctx,
          "calculateCompoundedInterest(uint256,uint256,uint256)",
          [rate, lut, cur],
          fn -> Math.calculate_compounded_interest(rate, lut, cur) end
        )
      end
    end

    property "matches Solidity for random rate/elapsed inputs", ctx do
      check all(
              rate <- integer(0..@max_rate),
              last <- integer(0..2_000_000_000),
              elapsed <- integer(0..@max_elapsed),
              max_runs: 200
            ) do
        cur = last + elapsed

        assert_same_as_revm(
          ctx,
          "calculateCompoundedInterest(uint256,uint256,uint256)",
          [rate, last, cur],
          fn -> Math.calculate_compounded_interest(rate, last, cur) end
        )
      end
    end
  end

  # --- Helpers --------------------------------------------------------------

  # Calls the revm wrapper, decodes a single uint256 return, asserts equality
  # with the Elixir function. Reverts from revm flunk loudly with the inputs
  # echoed, never silently.
  @spec assert_same_as_revm(
          %{:opts => keyword(), optional(atom()) => term()},
          String.t(),
          [non_neg_integer()],
          (-> non_neg_integer())
        ) :: :ok
  defp assert_same_as_revm(ctx, signature, args, elixir_fun) do
    elixir = elixir_fun.()
    revm = call_wrapper(ctx, signature, args)

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
  end

  @spec call_wrapper(
          %{:opts => keyword(), optional(atom()) => term()},
          String.t(),
          [non_neg_integer()]
        ) :: non_neg_integer()
  defp call_wrapper(ctx, signature, args) do
    calldata = ABI.encode_call!(signature, args)

    case EVM.simulate_call(@wrapper_address, calldata, ctx.opts) do
      {:ok, hex} ->
        [value] = ABI.decode_response!("(uint256)", hex)
        value

      {:error, reason} ->
        flunk("""
        revm call reverted for #{signature}
          args:   #{inspect(args)}
          reason: #{inspect(reason)}
        """)
    end
  end
end
