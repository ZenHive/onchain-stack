defmodule Onchain.Aave.Oracle.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.Oracle

  @moduletag :integration

  # WETH on Ethereum mainnet
  @weth "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  # USDC on Ethereum mainnet
  @usdc "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

  describe "get_asset_price/2" do
    test "returns non-zero price for WETH" do
      assert {:ok, price} = Oracle.get_asset_price(@weth, Onchain.RPCCase.rpc_opts!())
      assert is_integer(price)
      assert price > 0, "Expected WETH price > 0, got #{price}"
    end

    test "returns non-zero price for USDC" do
      assert {:ok, price} = Oracle.get_asset_price(@usdc, Onchain.RPCCase.rpc_opts!())
      assert is_integer(price)
      assert price > 0, "Expected USDC price > 0, got #{price}"
    end
  end

  describe "get_asset_prices/2" do
    test "returns prices for WETH and USDC" do
      assert {:ok, prices} = Oracle.get_asset_prices([@weth, @usdc], Onchain.RPCCase.rpc_opts!())
      assert is_list(prices)
      assert length(prices) == 2

      [weth_price, usdc_price] = prices
      assert weth_price > 0
      assert usdc_price > 0
    end
  end

  describe "get_source_of_asset/2" do
    test "returns valid Chainlink aggregator for WETH" do
      assert {:ok, source} = Oracle.get_source_of_asset(@weth, Onchain.RPCCase.rpc_opts!())
      assert is_binary(source)
      assert String.starts_with?(source, "0x")
      assert byte_size(source) == 42
    end
  end

  describe "get_base_currency/1" do
    test "returns an address" do
      assert {:ok, currency} = Oracle.get_base_currency(Onchain.RPCCase.rpc_opts!())
      assert is_binary(currency)
      assert String.starts_with?(currency, "0x")
    end
  end

  describe "get_base_currency_unit/1" do
    test "returns 10^8 for Aave V3 USD base" do
      assert {:ok, unit} = Oracle.get_base_currency_unit(Onchain.RPCCase.rpc_opts!())
      # Aave V3 uses USD with 8 decimals as base currency
      assert unit == 100_000_000
    end
  end

  describe "get_fallback_oracle/1" do
    test "returns an address" do
      assert {:ok, fallback} = Oracle.get_fallback_oracle(Onchain.RPCCase.rpc_opts!())
      assert is_binary(fallback)
      assert String.starts_with?(fallback, "0x")
    end
  end

  describe "get_latest_round_data/2" do
    test "returns round data from WETH's Chainlink aggregator" do
      {:ok, source} = Oracle.get_source_of_asset(@weth, Onchain.RPCCase.rpc_opts!())

      assert {:ok, data} = Oracle.get_latest_round_data(source, Onchain.RPCCase.rpc_opts!())
      assert is_map(data)
      assert is_integer(data.round_id)
      assert is_integer(data.answer)
      assert data.answer > 0, "Expected positive Chainlink price, got #{data.answer}"
      assert is_integer(data.started_at)
      assert data.started_at > 0
      assert is_integer(data.updated_at)
      assert data.updated_at > 0
      assert is_integer(data.answered_in_round)
    end
  end
end
