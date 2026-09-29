defmodule Cartouche.WeiTest do
  use ExUnit.Case, async: true

  alias Cartouche.Wei

  doctest Wei

  describe "spec boundaries (Phase 1.2)" do
    test "zero is the lower boundary in all three clauses" do
      assert Wei.to_wei(0) == 0
      assert Wei.to_wei({0, :wei}) == 0
      assert Wei.to_wei({0, :gwei}) == 0
    end

    test "large non-negative integer round-trips through identity clauses" do
      large = 0xFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF
      assert Wei.to_wei(large) == large
      assert Wei.to_wei({large, :wei}) == large
    end

    test ":gwei multiplier applies as documented" do
      assert Wei.to_wei({1, :gwei}) == 1_000_000_000
      assert Wei.to_wei({2, :gwei}) == 2_000_000_000
    end

    test "negative inputs are out of contract and raise FunctionClauseError" do
      assert_raise FunctionClauseError, fn -> Wei.to_wei(-1) end
      assert_raise FunctionClauseError, fn -> Wei.to_wei({-1, :wei}) end
      assert_raise FunctionClauseError, fn -> Wei.to_wei({-1, :gwei}) end
    end

    test "maybe_to_wei/1 passes through bare wei amounts" do
      assert Wei.maybe_to_wei(42) == 42
    end
  end

  describe "to_wei/1 - :eth denomination (Task 74)" do
    test "whole-integer eth converts to wei" do
      assert Wei.to_wei({1, :eth}) == 1_000_000_000_000_000_000
    end

    test "whole-integer eth zero is the lower boundary" do
      assert Wei.to_wei({0, :eth}) == 0
    end

    test "fractional Decimal eth converts exactly to wei" do
      assert Wei.to_wei({Decimal.new("1.5"), :eth}) == 1_500_000_000_000_000_000
    end

    test "Decimal eth converts at the one-wei boundary" do
      assert Wei.to_wei({Decimal.new("0.000000000000000001"), :eth}) == 1
    end

    test "Decimal eth below one wei raises instead of rounding" do
      assert_raise ArgumentError, fn ->
        Wei.to_wei({Decimal.new("0.0000000000000000001"), :eth})
      end
    end

    test "negative integer eth is out of contract and raises FunctionClauseError" do
      assert_raise FunctionClauseError, fn -> Wei.to_wei({-1, :eth}) end
    end

    test "negative Decimal eth raises" do
      assert_raise ArgumentError, fn -> Wei.to_wei({Decimal.new("-1"), :eth}) end
    end

    test "float eth is rejected without silent coercion" do
      # dynamic/1 erases the static type (Elixir 1.20+): the float tuple is an
      # intentional out-of-contract input, and the contract is enforced at
      # runtime via FunctionClauseError, not by the compile-time type checker.
      assert_raise FunctionClauseError, fn -> Wei.to_wei(dynamic({1.5, :eth})) end
    end
  end

  @spec dynamic(term()) :: term()
  defp dynamic(value), do: value
end
