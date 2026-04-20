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
end
