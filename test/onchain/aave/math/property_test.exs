defmodule Onchain.Aave.Math.PropertyTest do
  @moduledoc """
  Domain coverage and Solidity-golden checks for every public V3/V4 math op.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Onchain.Aave.Math
  alias Onchain.Aave.Math.V4
  alias Onchain.Aave.MathDomains
  alias Onchain.Aave.MathOracle

  @goldens MathOracle.load_goldens!()

  describe "domain coverage" do
    test "every public op is exercised across zero, unit, boundary, overflow-adjacent and rounding inputs" do
      required = MapSet.new(MathDomains.required_classes())
      coverage = MathDomains.coverage_by_op()

      missing =
        Enum.reduce(MathDomains.public_ops(), [], fn {protocol, op} = key, acc ->
          have = Map.get(coverage, key, MapSet.new())
          gap = MapSet.difference(required, have)

          if MapSet.size(gap) == 0 do
            acc
          else
            [{protocol, op, MapSet.to_list(gap)} | acc]
          end
        end)

      assert missing == [], "ops missing domain classes: #{inspect(missing)}"
    end
  end

  describe "Solidity goldens" do
    test "every bytecode vector matches pinned official-wrapper output" do
      mismatches =
        Enum.reduce(MathDomains.bytecode_vectors(), [], fn vector, acc ->
          elixir = MathOracle.apply_elixir(vector.protocol, vector.op, vector.args)
          golden = MathOracle.golden_expected(@goldens, vector)

          if elixir == golden do
            acc
          else
            [{vector.protocol, vector.op, vector.args, elixir, golden} | acc]
          end
        end)

      assert mismatches == [], "elixir diverged from Solidity goldens: #{inspect(mismatches)}"
    end
  end

  describe "display conversions" do
    test "match documented Aave scales, not the production module" do
      for %{op: op, args: args} <- MathDomains.display_vectors() do
        actual = MathOracle.apply_elixir(:v3, op, args)
        expected = MathOracle.display_expected(op, args)
        assert Decimal.eq?(actual, expected), "#{op} #{inspect(args)}"
      end
    end
  end

  describe "algebraic bounds" do
    property "V4 wad_mul_up is never below wad_mul_down" do
      check all(
              a <- integer(0..MathDomains.max_wad()),
              b <- integer(0..MathDomains.max_wad()),
              max_runs: 80
            ) do
        assert V4.wad_mul_up(a, b) >= V4.wad_mul_down(a, b)
        assert (V4.wad_mul_up(a, b) - V4.wad_mul_down(a, b)) in [0, 1]
      end
    end

    property "V4 ray_mul_up is never below ray_mul_down" do
      check all(
              a <- integer(0..MathDomains.max_ray()),
              b <- integer(0..MathDomains.max_ray()),
              max_runs: 80
            ) do
        assert V4.ray_mul_up(a, b) >= V4.ray_mul_down(a, b)
        assert (V4.ray_mul_up(a, b) - V4.ray_mul_down(a, b)) in [0, 1]
      end
    end

    property "zero_floor_sub never goes negative and is zero when a <= b" do
      check all(
              a <- integer(0..1_000_000),
              b <- integer(0..1_000_000),
              max_runs: 80
            ) do
        result = V4.zero_floor_sub(a, b)
        assert result >= 0

        if a <= b do
          assert result == 0
        else
          assert result == a - b
        end
      end
    end

    property "min/2 returns an operand and is the smaller" do
      check all(
              a <- integer(0..MathDomains.max_wad()),
              b <- integer(0..MathDomains.max_wad()),
              max_runs: 80
            ) do
        result = V4.min(a, b)
        assert result in [a, b]
        assert result <= a
        assert result <= b
      end
    end

    property "linear interest at zero elapsed is exactly RAY" do
      check all(
              rate <- integer(0..MathDomains.max_rate()),
              last <- integer(0..2_000_000_000),
              max_runs: 40
            ) do
        assert Math.calculate_linear_interest(rate, last, last) == MathDomains.ray()
        assert V4.calculate_linear_interest(rate, last, last) == MathDomains.ray()
      end
    end

    property "ray_to_wad is a left inverse of wad_to_ray" do
      check all(a <- integer(0..MathDomains.max_wad()), max_runs: 80) do
        assert Math.ray_to_wad(Math.wad_to_ray(a)) == a
      end
    end
  end
end
