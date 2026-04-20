defmodule Onchain.Aave.FaucetTest do
  use ExUnit.Case, async: true

  alias Onchain.Aave.Faucet

  # Known valid Sepolia addresses (checksummed)
  @valid_token "0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c"
  @valid_to "0x1234567890AbcdEF1234567890aBcdef12345678"

  describe "mint/4" do
    test "returns error for invalid token address" do
      assert {:error, {:invalid_address, "not_an_address"}} =
               Faucet.mint("not_an_address", @valid_to, 1000, network: :sepolia)
    end

    test "returns error for invalid recipient address" do
      assert {:error, {:invalid_address, "bad"}} =
               Faucet.mint(@valid_token, "bad", 1000, network: :sepolia)
    end

    test "returns error when faucet not available on network" do
      assert {:error, {:unknown_contract, :faucet}} =
               Faucet.mint(@valid_token, @valid_to, 1000, network: :ethereum)
    end

    test "returns error for all mainnet networks" do
      for network <- [:ethereum, :arbitrum, :optimism, :base, :polygon, :avalanche] do
        assert {:error, {:unknown_contract, :faucet}} =
                 Faucet.mint(@valid_token, @valid_to, 1000, network: network),
               "Expected :unknown_contract error for #{network}"
      end
    end
  end

  describe "mint!/4" do
    test "raises on invalid token address" do
      assert_raise RuntimeError, ~r/invalid_address/, fn ->
        Faucet.mint!("not_an_address", @valid_to, 1000, network: :sepolia)
      end
    end

    test "raises when faucet not available on network" do
      assert_raise RuntimeError, ~r/unknown_contract/, fn ->
        Faucet.mint!(@valid_token, @valid_to, 1000, network: :ethereum)
      end
    end
  end
end
