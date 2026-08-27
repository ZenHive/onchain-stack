defmodule Onchain.DecimalTest do
  use ExUnit.Case, async: true

  # Alias to avoid collision with the Decimal library
  alias Onchain.Decimal, as: D

  describe "to_decimal/2" do
    test "ETH: 1.5 ETH from wei (18 decimals)" do
      assert Decimal.equal?(D.to_decimal(1_500_000_000_000_000_000, 18), Decimal.new("1.5"))
    end

    test "USDC: 1 USDC (6 decimals)" do
      assert Decimal.equal?(D.to_decimal(1_000_000, 6), Decimal.new("1"))
    end

    test "WBTC: 1 WBTC (8 decimals)" do
      assert Decimal.equal?(D.to_decimal(100_000_000, 8), Decimal.new("1"))
    end

    test "zero value" do
      assert Decimal.equal?(D.to_decimal(0, 18), Decimal.new("0"))
    end

    test "zero decimals returns value unchanged" do
      assert Decimal.equal?(D.to_decimal(42, 0), Decimal.new("42"))
    end

    test "negative value (int256 exists in Ethereum)" do
      result = D.to_decimal(-1_500_000_000_000_000_000, 18)
      assert Decimal.equal?(result, Decimal.new("-1.5"))
    end

    test "large uint256-scale value" do
      # 2^128 wei ≈ 340282366920938463463 ETH
      large = Integer.pow(2, 128)
      result = D.to_decimal(large, 18)
      assert Decimal.equal?(result, Decimal.div(Decimal.new(large), Decimal.new(Integer.pow(10, 18))))
    end

    test "1 wei (smallest ETH unit)" do
      result = D.to_decimal(1, 18)
      assert Decimal.equal?(result, Decimal.new("0.000000000000000001"))
    end

    test "raises on non-integer value" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(D, :to_decimal, ["100", 18]) end
    end

    test "raises on non-integer decimals" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(D, :to_decimal, [100, "6"]) end
    end

    test "raises on negative decimals" do
      assert_raise FunctionClauseError, fn -> D.to_decimal(100, -1) end
    end
  end

  describe "div_pow10/2" do
    test "integer input" do
      assert Decimal.equal?(D.div_pow10(1000, 2), Decimal.new("10"))
    end

    test "Decimal input" do
      assert Decimal.equal?(D.div_pow10(Decimal.new("1000.5"), 2), Decimal.new("10.005"))
    end

    test "n=0 returns value unchanged (integer)" do
      assert Decimal.equal?(D.div_pow10(42, 0), Decimal.new("42"))
    end

    test "n=0 returns value unchanged (Decimal)" do
      assert Decimal.equal?(D.div_pow10(Decimal.new("42.5"), 0), Decimal.new("42.5"))
    end

    test "zero value" do
      assert Decimal.equal?(D.div_pow10(0, 5), Decimal.new("0"))
    end

    test "negative integer" do
      assert Decimal.equal?(D.div_pow10(-1000, 2), Decimal.new("-10"))
    end

    test "large n produces small result" do
      assert Decimal.equal?(D.div_pow10(1, 18), Decimal.new("0.000000000000000001"))
    end

    test "raises on non-integer n" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(D, :div_pow10, [100, "2"]) end
    end

    test "raises on negative n" do
      assert_raise FunctionClauseError, fn -> D.div_pow10(100, -1) end
    end
  end

  describe "to_basis_points/1" do
    test "standard: 0.5% = 50 basis points" do
      assert D.to_basis_points(Decimal.new("0.005")) == 50
    end

    test "1 basis point" do
      assert D.to_basis_points(Decimal.new("0.0001")) == 1
    end

    test "100% = 10000 basis points" do
      assert D.to_basis_points(Decimal.new("1")) == 10_000
    end

    test "zero" do
      assert D.to_basis_points(Decimal.new("0")) == 0
    end

    test "truncates toward zero: 0.00051 → 5 (not 6)" do
      assert D.to_basis_points(Decimal.new("0.00051")) == 5
    end

    test "negative rate" do
      assert D.to_basis_points(Decimal.new("-0.005")) == -50
    end

    test "negative truncation toward zero: -0.00051 → -5 (not -6)" do
      assert D.to_basis_points(Decimal.new("-0.00051")) == -5
    end

    test "raises on non-Decimal input" do
      # credo:disable-for-next-line Credo.Check.Refactor.Apply
      assert_raise FunctionClauseError, fn -> apply(D, :to_basis_points, [0.005]) end
    end
  end

  describe "roundtrip" do
    test "to_decimal then back to integer" do
      original = 1_500_000_000_000_000_000
      decimals = 18
      result = D.to_decimal(original, decimals)

      recovered =
        result
        |> Decimal.mult(Decimal.new(Integer.pow(10, decimals)))
        |> Decimal.round(0)
        |> Decimal.to_integer()

      assert recovered == original
    end

    test "div_pow10 equals to_decimal for integer inputs" do
      value = 1_500_000_000_000_000_000
      n = 18
      assert Decimal.equal?(D.div_pow10(value, n), D.to_decimal(value, n))
    end
  end
end
