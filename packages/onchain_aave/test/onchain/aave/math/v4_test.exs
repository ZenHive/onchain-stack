defmodule Onchain.Aave.Math.V4Test do
  use ExUnit.Case, async: true

  alias Onchain.Aave.Math.V4

  @wad 1_000_000_000_000_000_000
  @ray 1_000_000_000_000_000_000_000_000_000
  @percentage_factor 10_000
  @health_factor_liquidation_threshold 1_000_000_000_000_000_000

  describe "wad rounding" do
    test "multiplies with explicit down and up rounding" do
      assert V4.wad_mul_down(1, @wad - 1) == 0
      assert V4.wad_mul_up(1, @wad - 1) == 1
      assert V4.wad_mul_down(3 * @wad, 5 * @wad) == 15 * @wad
      assert V4.wad_mul_up(3 * @wad, 5 * @wad) == 15 * @wad
    end

    test "divides with explicit down and up rounding" do
      assert V4.wad_div_down(1, 2) == div(@wad, 2)
      assert V4.wad_div_up(1, 3) == div(@wad, 3) + 1
      assert V4.wad_div_down(2 * @wad, @wad) == 2 * @wad
      assert V4.wad_div_up(2 * @wad, @wad) == 2 * @wad
    end
  end

  describe "ray rounding" do
    test "multiplies with explicit down and up rounding" do
      assert V4.ray_mul_down(1, @ray - 1) == 0
      assert V4.ray_mul_up(1, @ray - 1) == 1
      assert V4.ray_mul_down(3 * @ray, 5 * @ray) == 15 * @ray
      assert V4.ray_mul_up(3 * @ray, 5 * @ray) == 15 * @ray
    end

    test "divides with explicit down and up rounding" do
      assert V4.ray_div_down(1, 2) == div(@ray, 2)
      assert V4.ray_div_up(1, 3) == div(@ray, 3) + 1
      assert V4.ray_div_down(2 * @ray, @ray) == 2 * @ray
      assert V4.ray_div_up(2 * @ray, @ray) == 2 * @ray
    end
  end

  describe "unit conversions" do
    test "casts values to and from wad/ray scales" do
      assert V4.to_wad(3) == 3 * @wad
      assert V4.to_ray(3) == 3 * @ray
      assert V4.from_wad_down(3 * @wad + @wad - 1) == 3
      assert V4.from_ray_up(3 * @ray + 1) == 4
      assert V4.bps_to_wad(125) == 125 * div(@wad, @percentage_factor)
      assert V4.bps_to_ray(125) == 125 * div(@ray, @percentage_factor)
      assert V4.round_ray_up(3 * @ray + 1) == 4 * @ray
    end
  end

  describe "calculate_linear_interest/3" do
    test "matches V4 MathUtils linear interest formula" do
      rate = div(5 * @ray, 100)
      last_update_timestamp = 1_700_000_000
      current_timestamp = last_update_timestamp + 31_536_000

      assert V4.calculate_linear_interest(rate, last_update_timestamp, current_timestamp) ==
               @ray + rate
    end
  end

  describe "integer helpers" do
    test "min/2 returns the smaller value" do
      assert V4.min(3, 5) == 3
      assert V4.min(5, 3) == 3
      assert V4.min(4, 4) == 4
    end

    test "zero_floor_sub/2 floors the difference at zero" do
      assert V4.zero_floor_sub(5, 3) == 2
      assert V4.zero_floor_sub(3, 5) == 0
      assert V4.zero_floor_sub(5, 5) == 0
    end

    test "add/2 accepts non-negative results and rejects underflow" do
      assert V4.add(5, 3) == 8
      assert V4.add(5, -3) == 2
      assert V4.add(3, -3) == 0

      assert_raise FunctionClauseError, fn -> V4.add(3, -5) end
    end

    test "mul_div_up/3 rounds the quotient up" do
      assert V4.mul_div_up(7, 3, 5) == 5
      assert V4.mul_div_up(10, 2, 5) == 4
    end
  end

  describe "calculate_liquidation_bonus/4" do
    test "returns max bonus at or below max-bonus health factor" do
      assert V4.calculate_liquidation_bonus(
               div(@health_factor_liquidation_threshold, 2),
               5_000,
               div(@health_factor_liquidation_threshold, 2),
               11_000
             ) == 11_000
    end

    test "linearly interpolates between min and max bonus above max-bonus health factor" do
      health_factor_for_max_bonus = div(@health_factor_liquidation_threshold, 2)
      liquidation_bonus_factor = 5_000
      health_factor = div(3 * @health_factor_liquidation_threshold, 4)
      max_liquidation_bonus = 11_000

      assert V4.calculate_liquidation_bonus(
               health_factor_for_max_bonus,
               liquidation_bonus_factor,
               health_factor,
               max_liquidation_bonus
             ) == 10_750
    end
  end
end
