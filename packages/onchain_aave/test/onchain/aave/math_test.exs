defmodule Onchain.Aave.MathTest do
  use ExUnit.Case, async: true

  alias Onchain.Aave.Math

  describe "to_usd/1" do
    test "converts oracle price (10^8 scale)" do
      # ETH at ~$2,500
      assert Decimal.eq?(Math.to_usd(250_000_000_000), Decimal.new("2500"))
    end

    test "converts fractional USD value" do
      assert Decimal.eq?(Math.to_usd(123_456_789), Decimal.new("1.23456789"))
    end

    test "zero returns zero" do
      assert Decimal.eq?(Math.to_usd(0), Decimal.new(0))
    end

    test "large uint256-scale value" do
      # ~$1 trillion in Aave base currency units
      large = 100_000_000_000_000_000_000
      result = Math.to_usd(large)
      assert Decimal.eq?(result, Decimal.new("1000000000000"))
    end

    test "raises on non-integer input" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :to_usd, [1.5]) end
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :to_usd, ["123"]) end
    end
  end

  describe "to_ltv/1" do
    test "converts 80% LTV (8000 basis points)" do
      assert Decimal.eq?(Math.to_ltv(8000), Decimal.new("0.8"))
    end

    test "converts 100% (10000 basis points)" do
      assert Decimal.eq?(Math.to_ltv(10_000), Decimal.new(1))
    end

    test "converts typical liquidation threshold (8250 = 82.5%)" do
      assert Decimal.eq?(Math.to_ltv(8250), Decimal.new("0.825"))
    end

    test "zero returns zero" do
      assert Decimal.eq?(Math.to_ltv(0), Decimal.new(0))
    end

    test "raises on non-integer input" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :to_ltv, [0.8]) end
    end
  end

  describe "to_health_factor/1" do
    test "converts 1.5 health factor" do
      raw = 1_500_000_000_000_000_000
      assert Decimal.eq?(Math.to_health_factor(raw), Decimal.new("1.5"))
    end

    test "converts exactly 1.0 (liquidation boundary)" do
      raw = 1_000_000_000_000_000_000
      assert Decimal.eq?(Math.to_health_factor(raw), Decimal.new(1))
    end

    test "converts health factor > 10" do
      raw = 10_500_000_000_000_000_000
      assert Decimal.eq?(Math.to_health_factor(raw), Decimal.new("10.5"))
    end

    test "zero returns zero" do
      assert Decimal.eq?(Math.to_health_factor(0), Decimal.new(0))
    end

    test "raises on non-integer input" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :to_health_factor, [1.5]) end
    end
  end

  describe "to_ray/1" do
    test "converts 10% annual rate" do
      # 10^26 = 0.1 in ray
      raw = 100_000_000_000_000_000_000_000_000
      assert Decimal.eq?(Math.to_ray(raw), Decimal.new("0.1"))
    end

    test "converts 1 ray (10^27)" do
      raw = 1_000_000_000_000_000_000_000_000_000
      assert Decimal.eq?(Math.to_ray(raw), Decimal.new(1))
    end

    test "converts typical borrow rate (~3.5%)" do
      raw = 35_000_000_000_000_000_000_000_000
      assert Decimal.eq?(Math.to_ray(raw), Decimal.new("0.035"))
    end

    test "zero returns zero" do
      assert Decimal.eq?(Math.to_ray(0), Decimal.new(0))
    end

    test "raises on non-integer input" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :to_ray, [%Decimal{}]) end
    end
  end

  describe "to_wad/1" do
    test "converts 1 wad (10^18)" do
      raw = 1_000_000_000_000_000_000
      assert Decimal.eq?(Math.to_wad(raw), Decimal.new(1))
    end

    test "converts fractional wad" do
      raw = 500_000_000_000_000_000
      assert Decimal.eq?(Math.to_wad(raw), Decimal.new("0.5"))
    end

    test "zero returns zero" do
      assert Decimal.eq?(Math.to_wad(0), Decimal.new(0))
    end

    test "raises on non-integer input" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :to_wad, ["1"]) end
    end
  end

  describe "consistency" do
    test "to_health_factor and to_wad produce same result for same input" do
      input = 2_500_000_000_000_000_000
      assert Decimal.eq?(Math.to_health_factor(input), Math.to_wad(input))
    end

    test "to_health_factor and to_wad produce same result for zero" do
      assert Decimal.eq?(Math.to_health_factor(0), Math.to_wad(0))
    end
  end

  # --- Fixed-point arithmetic (WadRayMath / MathUtils) ---

  @ray 1_000_000_000_000_000_000_000_000_000
  @half_ray 500_000_000_000_000_000_000_000_000
  @wad 1_000_000_000_000_000_000
  @half_wad 500_000_000_000_000_000
  @wad_ray_ratio 1_000_000_000
  @seconds_per_year 31_536_000

  describe "ray_mul/2" do
    test "identity: ray_mul(@ray, x) == x" do
      x = 123_456_789_000_000_000_000_000_000
      assert Math.ray_mul(@ray, x) == x
      assert Math.ray_mul(x, @ray) == x
    end

    test "zero absorption" do
      assert Math.ray_mul(0, @ray) == 0
      assert Math.ray_mul(@ray, 0) == 0
      assert Math.ray_mul(0, 0) == 0
    end

    test "0.5 ray * 0.5 ray == 0.25 ray" do
      half = div(@ray, 2)
      quarter = div(@ray, 4)
      assert Math.ray_mul(half, half) == quarter
    end

    test "rounds up exactly at midpoint" do
      # a * b = HALF_RAY exactly (remainder == half_ray) → rounds up to 1
      # Pick a, b so that a*b = HALF_RAY: a = 1, b = HALF_RAY
      assert Math.ray_mul(1, @half_ray) == 1
      assert Math.ray_mul(@half_ray, 1) == 1
    end

    test "rounds down below midpoint" do
      # a * b = HALF_RAY - 1 → (a*b + HALF_RAY) = RAY - 1 → div by RAY = 0
      assert Math.ray_mul(1, @half_ray - 1) == 0
    end

    test "rounds up above midpoint" do
      # a * b = HALF_RAY + 1 → (a*b + HALF_RAY) = RAY + 1 → div by RAY = 1
      assert Math.ray_mul(1, @half_ray + 1) == 1
    end

    test "raises on non-integer input" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :ray_mul, [1.5, @ray]) end
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :ray_mul, [@ray, 1.5]) end
    end

    test "raises on negative input" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :ray_mul, [-1, @ray]) end
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :ray_mul, [@ray, -1]) end
    end
  end

  describe "ray_div/2" do
    test "identity: ray_div(x, @ray) == x" do
      x = 123_456_789_000_000_000_000_000_000
      assert Math.ray_div(x, @ray) == x
    end

    test "self-division: ray_div(x, x) == @ray for x > 0" do
      x = 7 * @ray
      assert Math.ray_div(x, x) == @ray
    end

    test "zero numerator" do
      assert Math.ray_div(0, @ray) == 0
      assert Math.ray_div(0, 123) == 0
    end

    test "2 ray / 1 ray == 2 ray" do
      assert Math.ray_div(2 * @ray, @ray) == 2 * @ray
    end

    test "1 / 2 ray == 0.5 ray" do
      assert Math.ray_div(@ray, 2 * @ray) == div(@ray, 2)
    end

    test "rounds half-up via div(b, 2) addition" do
      # With b = 3: (a * RAY + 1) / 3 — verify the +1 is the half-divisor term
      # For a = 1, b = 3: (1 * RAY + 1) / 3 = (RAY + 1) / 3
      expected = div(@ray + 1, 3)
      assert Math.ray_div(1, 3) == expected
    end

    test "raises on division by zero" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :ray_div, [@ray, 0]) end
    end

    test "raises on non-integer input" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :ray_div, [1.5, @ray]) end
    end

    test "raises on negative input" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :ray_div, [-1, @ray]) end
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :ray_div, [@ray, -1]) end
    end
  end

  describe "wad_mul/2" do
    test "identity: wad_mul(@wad, x) == x" do
      x = 123_456_789_000_000_000
      assert Math.wad_mul(@wad, x) == x
      assert Math.wad_mul(x, @wad) == x
    end

    test "zero absorption" do
      assert Math.wad_mul(0, @wad) == 0
      assert Math.wad_mul(@wad, 0) == 0
    end

    test "0.5 wad * 0.5 wad == 0.25 wad" do
      half = div(@wad, 2)
      quarter = div(@wad, 4)
      assert Math.wad_mul(half, half) == quarter
    end

    test "rounds up at midpoint" do
      assert Math.wad_mul(1, @half_wad) == 1
    end

    test "rounds down below midpoint" do
      assert Math.wad_mul(1, @half_wad - 1) == 0
    end

    test "rounds up above midpoint" do
      assert Math.wad_mul(1, @half_wad + 1) == 1
    end

    test "raises on non-integer input" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :wad_mul, [1.5, @wad]) end
    end

    test "raises on negative input" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :wad_mul, [-1, @wad]) end
    end
  end

  describe "wad_div/2" do
    test "identity: wad_div(x, @wad) == x" do
      x = 999_999_999_000_000_000
      assert Math.wad_div(x, @wad) == x
    end

    test "self-division: wad_div(x, x) == @wad for x > 0" do
      x = 7 * @wad
      assert Math.wad_div(x, x) == @wad
    end

    test "zero numerator" do
      assert Math.wad_div(0, @wad) == 0
    end

    test "1 / 2 wad == 0.5 wad" do
      assert Math.wad_div(@wad, 2 * @wad) == div(@wad, 2)
    end

    test "rounds half-up" do
      # (1 * WAD + div(3, 2)) / 3 = (WAD + 1) / 3
      expected = div(@wad + 1, 3)
      assert Math.wad_div(1, 3) == expected
    end

    test "raises on division by zero" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :wad_div, [@wad, 0]) end
    end
  end

  describe "ray_to_wad/1" do
    test "rescales by 10^-9" do
      # 1 ray (10^27) → 1 wad (10^18)
      assert Math.ray_to_wad(@ray) == @wad
    end

    test "zero" do
      assert Math.ray_to_wad(0) == 0
    end

    test "rounds half-up exactly at midpoint" do
      # remainder == WAD_RAY_RATIO / 2 → rounds up (>= half)
      assert Math.ray_to_wad(div(@wad_ray_ratio, 2)) == 1
    end

    test "rounds down just below midpoint" do
      assert Math.ray_to_wad(div(@wad_ray_ratio, 2) - 1) == 0
    end

    test "rounds up just above midpoint" do
      assert Math.ray_to_wad(div(@wad_ray_ratio, 2) + 1) == 1
    end

    test "rounds up just below a ray-boundary" do
      # 2 * @ray - 1 in ray → remainder @wad_ray_ratio - 1 (>= half) → rounds up to 2 * @wad
      assert Math.ray_to_wad(2 * @ray - 1) == 2 * @wad
    end

    test "raises on negative input" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :ray_to_wad, [-1]) end
    end

    test "raises on non-integer input" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :ray_to_wad, [1.5]) end
    end
  end

  describe "wad_to_ray/1" do
    test "rescales by 10^9 exactly" do
      assert Math.wad_to_ray(@wad) == @ray
    end

    test "zero" do
      assert Math.wad_to_ray(0) == 0
    end

    test "arbitrary value" do
      assert Math.wad_to_ray(123_456_789) == 123_456_789 * @wad_ray_ratio
    end

    test "ray_to_wad is left-inverse of wad_to_ray" do
      x = 123_456_789_012_345_678
      assert Math.ray_to_wad(Math.wad_to_ray(x)) == x
    end

    test "raises on negative input" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :wad_to_ray, [-1]) end
    end
  end

  describe "calculate_linear_interest/3" do
    test "zero elapsed returns RAY (factor = 1)" do
      assert Math.calculate_linear_interest(5 * div(@ray, 100), 1000, 1000) == @ray
    end

    test "one year at 5% rate returns 1.05 ray" do
      rate = 5 * div(@ray, 100)
      last = 1_700_000_000
      current = last + @seconds_per_year
      # RAY + rate * SECONDS_PER_YEAR / SECONDS_PER_YEAR = RAY + rate
      assert Math.calculate_linear_interest(rate, last, current) == @ray + rate
    end

    test "half year at 10% rate returns ~1.05 ray" do
      rate = div(@ray, 10)
      last = 1_700_000_000
      half_year = div(@seconds_per_year, 2)
      current = last + half_year
      expected = @ray + div(rate * half_year, @seconds_per_year)
      assert Math.calculate_linear_interest(rate, last, current) == expected
    end

    test "zero rate yields exactly RAY regardless of elapsed" do
      assert Math.calculate_linear_interest(0, 1000, 1000 + 10 * @seconds_per_year) == @ray
    end

    test "raises when current < last" do
      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(Math, :calculate_linear_interest, [@ray, 1000, 999])
      end
    end

    test "raises on non-integer rate" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :calculate_linear_interest, [1.5, 0, 1]) end
    end

    test "raises on negative rate" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :calculate_linear_interest, [-1, 0, 1]) end
    end
  end

  describe "calculate_compounded_interest/3" do
    test "zero elapsed returns RAY (factor = 1)" do
      rate = div(@ray, 10)
      assert Math.calculate_compounded_interest(rate, 1000, 1000) == @ray
    end

    # Pins the Elixir polynomial form against itself — proves no extra transform or
    # early-return around the core expression. Bit-exact equivalence with Solidity
    # is validated by Task 41 (revm cross-validation), not here.
    test "pins polynomial form: RAY + x + rayMul(x, x/2 + rayMul(x, x/6))" do
      rate = 5 * div(@ray, 100)
      last = 0
      elapsed = 7 * 86_400
      current = last + elapsed

      x = div(rate * elapsed, @seconds_per_year)
      expected = @ray + x + Math.ray_mul(x, div(x, 2) + Math.ray_mul(x, div(x, 6)))

      assert Math.calculate_compounded_interest(rate, last, current) == expected
    end

    test "one year at 5% rate slightly exceeds linear (compounding premium)" do
      rate = 5 * div(@ray, 100)
      last = 0
      current = @seconds_per_year

      linear = Math.calculate_linear_interest(rate, last, current)
      compounded = Math.calculate_compounded_interest(rate, last, current)

      # Compounded > linear because of the positive x²/2 + x³/6 tail
      assert compounded > linear

      # Sanity bound: at 5% annual, compounded should not exceed linear by more than 1% of RAY
      assert compounded - linear < div(@ray, 100)
    end

    test "zero rate yields exactly RAY regardless of elapsed" do
      assert Math.calculate_compounded_interest(0, 0, 10 * @seconds_per_year) == @ray
    end

    # Formula-pinning test for the 1-second case — see note on the polynomial-form test above.
    test "very small exp (1 second) at modest rate" do
      rate = 5 * div(@ray, 100)
      x = div(rate, @seconds_per_year)
      expected = @ray + x + Math.ray_mul(x, div(x, 2) + Math.ray_mul(x, div(x, 6)))

      assert Math.calculate_compounded_interest(rate, 1_700_000_000, 1_700_000_001) == expected
    end

    test "raises when current < last" do
      assert_raise FunctionClauseError, fn ->
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        apply(Math, :calculate_compounded_interest, [@ray, 1000, 999])
      end
    end

    test "raises on negative rate" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(Math, :calculate_compounded_interest, [-1, 0, 1]) end
    end
  end
end
