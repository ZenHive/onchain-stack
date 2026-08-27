defmodule Onchain.Aave.Types.UserAccountDataTest do
  use ExUnit.Case, async: true

  alias Onchain.Aave.Types.UserAccountData

  # Dynamic dispatch defeats the type checker for negative tests
  @doc false
  defp dynamic_from_raw(module, arg), do: module.from_raw(arg)

  describe "struct" do
    test "enforces all 6 keys" do
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(UserAccountData, %{})
      end
    end

    test "creates struct with all fields" do
      data = %UserAccountData{
        total_collateral_base: Decimal.new("100.0"),
        total_debt_base: Decimal.new("50.0"),
        available_borrows_base: Decimal.new("25.0"),
        current_liquidation_threshold: Decimal.new("0.85"),
        ltv: Decimal.new("0.80"),
        health_factor: Decimal.new("1.5")
      }

      assert %UserAccountData{} = data
      assert Decimal.eq?(data.total_collateral_base, Decimal.new("100.0"))
    end
  end

  describe "from_raw/1" do
    test "converts known values using correct Math functions" do
      # 10_000_000_000 = 100.0 USD (10^8 scale)
      # 5_000_000_000  = 50.0 USD
      # 2_500_000_000  = 25.0 USD
      # 8500           = 0.85 (basis points, 10^4 scale)
      # 8000           = 0.80
      # 1_500_000_000_000_000_000 = 1.5 (10^18 scale)
      raw = [10_000_000_000, 5_000_000_000, 2_500_000_000, 8500, 8000, 1_500_000_000_000_000_000]

      result = UserAccountData.from_raw(raw)

      assert %UserAccountData{} = result
      assert Decimal.eq?(result.total_collateral_base, Decimal.new("100"))
      assert Decimal.eq?(result.total_debt_base, Decimal.new("50"))
      assert Decimal.eq?(result.available_borrows_base, Decimal.new("25"))
      assert Decimal.eq?(result.current_liquidation_threshold, Decimal.new("0.85"))
      assert Decimal.eq?(result.ltv, Decimal.new("0.8"))
      assert Decimal.eq?(result.health_factor, Decimal.new("1.5"))
    end

    test "handles all-zero values (no position)" do
      result = UserAccountData.from_raw([0, 0, 0, 0, 0, 0])

      assert %UserAccountData{} = result
      assert Decimal.eq?(result.total_collateral_base, Decimal.new(0))
      assert Decimal.eq?(result.total_debt_base, Decimal.new(0))
      assert Decimal.eq?(result.available_borrows_base, Decimal.new(0))
      assert Decimal.eq?(result.current_liquidation_threshold, Decimal.new(0))
      assert Decimal.eq?(result.ltv, Decimal.new(0))
      assert Decimal.eq?(result.health_factor, Decimal.new(0))
    end

    test "raises FunctionClauseError for non-integer input" do
      assert_raise FunctionClauseError, fn ->
        UserAccountData.from_raw(["100", 0, 0, 0, 0, 0])
      end
    end

    test "raises FunctionClauseError for float input" do
      assert_raise FunctionClauseError, fn ->
        UserAccountData.from_raw([1.0, 0, 0, 0, 0, 0])
      end
    end

    test "raises FunctionClauseError for wrong list length (too few)" do
      assert_raise FunctionClauseError, fn ->
        UserAccountData.from_raw([0, 0, 0, 0, 0])
      end
    end

    test "raises FunctionClauseError for wrong list length (too many)" do
      assert_raise FunctionClauseError, fn ->
        UserAccountData.from_raw([0, 0, 0, 0, 0, 0, 0])
      end
    end

    test "raises FunctionClauseError for non-list input" do
      assert_raise FunctionClauseError, fn ->
        dynamic_from_raw(UserAccountData, {0, 0, 0, 0, 0, 0})
      end
    end
  end
end
