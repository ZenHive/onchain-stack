defmodule Onchain.Aave.Types.BaseCurrencyInfoTest do
  use ExUnit.Case, async: true

  alias Onchain.Aave.Types.BaseCurrencyInfo

  # Dynamic dispatch defeats the type checker for negative tests
  @doc false
  defp dynamic_from_raw(module, arg), do: module.from_raw(arg)

  describe "struct" do
    test "enforces all 4 keys" do
      assert_raise ArgumentError, ~r/the following keys must also be given/, fn ->
        struct!(BaseCurrencyInfo, %{})
      end
    end

    test "creates struct with all fields" do
      data = %BaseCurrencyInfo{
        market_reference_currency_unit: 100_000_000,
        market_reference_currency_price_in_usd: Decimal.new("1.0"),
        network_base_token_price_in_usd: Decimal.new("2000.0"),
        network_base_token_price_decimals: 8
      }

      assert %BaseCurrencyInfo{} = data
      assert data.market_reference_currency_unit == 100_000_000
    end
  end

  describe "from_raw/1" do
    test "converts known values" do
      # unit=10^8, market_ref_price=10^8 (1.0 USD), eth_price=200_000_000_000 (~$2000), decimals=8
      raw = {100_000_000, 100_000_000, 200_000_000_000, 8}

      result = BaseCurrencyInfo.from_raw(raw)

      assert %BaseCurrencyInfo{} = result
      assert result.market_reference_currency_unit == 100_000_000
      assert Decimal.eq?(result.market_reference_currency_price_in_usd, Decimal.new("1"))
      assert Decimal.eq?(result.network_base_token_price_in_usd, Decimal.new("2000"))
      assert result.network_base_token_price_decimals == 8
    end

    test "handles zero values" do
      result = BaseCurrencyInfo.from_raw({0, 0, 0, 0})

      assert %BaseCurrencyInfo{} = result
      assert result.market_reference_currency_unit == 0
      assert Decimal.eq?(result.market_reference_currency_price_in_usd, Decimal.new(0))
      assert Decimal.eq?(result.network_base_token_price_in_usd, Decimal.new(0))
      assert result.network_base_token_price_decimals == 0
    end

    test "scales network base token price using returned decimals" do
      raw = {100_000_000, 100_000_000, 123_456, 4}

      result = BaseCurrencyInfo.from_raw(raw)

      assert Decimal.eq?(result.network_base_token_price_in_usd, Decimal.new("12.3456"))
      assert result.network_base_token_price_decimals == 4
    end

    test "raises FunctionClauseError for non-tuple input" do
      assert_raise FunctionClauseError, fn ->
        dynamic_from_raw(BaseCurrencyInfo, [100, 100, 200, 8])
      end
    end

    test "raises FunctionClauseError for non-integer values" do
      assert_raise FunctionClauseError, fn ->
        dynamic_from_raw(BaseCurrencyInfo, {"100", 100, 200, 8})
      end
    end

    test "raises FunctionClauseError for wrong tuple size" do
      assert_raise FunctionClauseError, fn ->
        dynamic_from_raw(BaseCurrencyInfo, {100, 100, 200})
      end
    end
  end
end
