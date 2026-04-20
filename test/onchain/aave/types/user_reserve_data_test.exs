defmodule Onchain.Aave.Types.UserReserveDataTest do
  use ExUnit.Case, async: true

  alias Onchain.Aave.Types.UserReserveData

  # WETH address as 20-byte binary
  @weth_bin <<192, 42, 170, 57, 178, 35, 254, 141, 10, 14, 92, 79, 39, 234, 217, 8, 60, 117, 108, 194>>

  # Dynamic dispatch defeats the type checker for negative tests
  @doc false
  defp dynamic_from_raw(module, arg), do: module.from_raw(arg)

  describe "struct" do
    test "enforces all 4 keys" do
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(UserReserveData, %{})
      end
    end

    test "creates struct with all fields" do
      data = %UserReserveData{
        underlying_asset: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
        scaled_a_token_balance: 1_000_000,
        usage_as_collateral_enabled_on_user: true,
        scaled_variable_debt: 500_000
      }

      assert %UserReserveData{} = data
      assert data.usage_as_collateral_enabled_on_user == true
    end
  end

  describe "from_raw/1" do
    test "converts known values with checksummed address" do
      raw = {@weth_bin, 70_235_330_262_070_608_987, true, 0}

      result = UserReserveData.from_raw(raw)

      assert %UserReserveData{} = result
      assert result.underlying_asset == "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
      assert result.scaled_a_token_balance == 70_235_330_262_070_608_987
      assert result.usage_as_collateral_enabled_on_user == true
      assert result.scaled_variable_debt == 0
    end

    test "handles zero balances" do
      result = UserReserveData.from_raw({@weth_bin, 0, false, 0})

      assert %UserReserveData{} = result
      assert result.scaled_a_token_balance == 0
      assert result.usage_as_collateral_enabled_on_user == false
      assert result.scaled_variable_debt == 0
    end

    test "handles debt position" do
      result = UserReserveData.from_raw({@weth_bin, 134_162_006_789, true, 149_638_856_949})

      assert result.scaled_a_token_balance == 134_162_006_789
      assert result.scaled_variable_debt == 149_638_856_949
    end

    test "raises FunctionClauseError for non-binary address" do
      assert_raise FunctionClauseError, fn ->
        UserReserveData.from_raw({"0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", 0, true, 0})
      end
    end

    test "raises FunctionClauseError for wrong address length" do
      assert_raise FunctionClauseError, fn ->
        UserReserveData.from_raw({<<1, 2, 3>>, 0, true, 0})
      end
    end

    test "raises FunctionClauseError for non-boolean collateral flag" do
      assert_raise FunctionClauseError, fn ->
        dynamic_from_raw(UserReserveData, {@weth_bin, 0, 1, 0})
      end
    end

    test "raises FunctionClauseError for non-tuple input" do
      assert_raise FunctionClauseError, fn ->
        dynamic_from_raw(UserReserveData, [@weth_bin, 0, true, 0])
      end
    end
  end
end
