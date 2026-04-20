defmodule Onchain.Aave.OracleTest do
  use ExUnit.Case, async: true

  alias Onchain.Aave.Oracle

  @valid_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

  describe "get_asset_price/2" do
    test "returns error for invalid address" do
      assert {:error, {:invalid_address, "bad"}} = Oracle.get_asset_price("bad")
    end
  end

  describe "get_asset_price!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/get_asset_price failed/, fn ->
        Oracle.get_asset_price!("bad")
      end
    end
  end

  describe "get_asset_prices/2" do
    test "returns error when any address is invalid" do
      assert {:error, {:invalid_address, "bad"}} =
               Oracle.get_asset_prices([@valid_address, "bad"])
    end
  end

  describe "get_asset_prices!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/get_asset_prices failed/, fn ->
        Oracle.get_asset_prices!(["bad"])
      end
    end
  end

  describe "get_source_of_asset/2" do
    test "returns error for invalid address" do
      assert {:error, {:invalid_address, "bad"}} = Oracle.get_source_of_asset("bad")
    end
  end

  describe "get_source_of_asset!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/get_source_of_asset failed/, fn ->
        Oracle.get_source_of_asset!("bad")
      end
    end
  end

  describe "get_latest_round_data/2" do
    test "returns error for invalid aggregator address" do
      assert {:error, {:invalid_address, "bad"}} = Oracle.get_latest_round_data("bad")
    end
  end

  describe "get_latest_round_data!/2" do
    test "raises on invalid address" do
      assert_raise RuntimeError, ~r/get_latest_round_data failed/, fn ->
        Oracle.get_latest_round_data!("bad")
      end
    end
  end
end
