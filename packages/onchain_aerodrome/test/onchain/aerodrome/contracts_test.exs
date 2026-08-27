defmodule Onchain.Aerodrome.ContractsTest do
  use ExUnit.Case, async: true

  alias Onchain.Aerodrome.Contracts

  describe "address/2" do
    test "resolves a known contract to a checksummed address" do
      assert {:ok, "0x69dD9db6d8f8E7d83887A704f447b1a584b599A1"} = Contracts.address(:lp_sugar)
    end

    test "defaults to the :base network" do
      assert Contracts.address(:voter) == Contracts.address(:voter, network: :base)
    end

    test "rejects an unknown contract key" do
      assert {:error, {:unknown_contract, :nope}} = Contracts.address(:nope)
    end

    test "rejects an unsupported network" do
      assert {:error, {:unsupported_network, :optimism}} =
               Contracts.address(:lp_sugar, network: :optimism)
    end
  end

  describe "address!/2" do
    test "returns the address directly" do
      assert Contracts.address!(:lp_sugar) == "0x69dD9db6d8f8E7d83887A704f447b1a584b599A1"
    end

    test "raises on an unknown key" do
      assert_raise RuntimeError, ~r/address lookup failed/, fn -> Contracts.address!(:nope) end
    end
  end

  describe "cl_factories/1" do
    test "returns all three Slipstream factories" do
      assert {:ok, factories} = Contracts.cl_factories()
      assert length(factories) == 3
      assert Contracts.address!(:cl_factory) in factories
    end

    test "rejects an unsupported network" do
      assert {:error, {:unsupported_network, :optimism}} =
               Contracts.cl_factories(network: :optimism)
    end
  end

  describe "chain_id/1" do
    test "Base is 8453" do
      assert {:ok, 8453} = Contracts.chain_id()
    end

    test "rejects an unsupported network" do
      assert {:error, {:unsupported_network, :optimism}} = Contracts.chain_id(network: :optimism)
    end
  end

  describe "networks/0 and contracts/1" do
    test "Base is the only supported network" do
      assert Contracts.networks() == [:base]
    end

    test "lists the registry keys" do
      assert {:ok, keys} = Contracts.contracts()
      assert :lp_sugar in keys
      assert :token_sugar in keys
      assert :slipstream_helper in keys
    end

    test "rejects an unsupported network" do
      assert {:error, {:unsupported_network, :optimism}} = Contracts.contracts(network: :optimism)
    end
  end

  describe "constants/0" do
    test "carries the verified pagination caps" do
      assert %{max_lps: 500, max_positions: 200, max_tokens: 2000} = Contracts.constants()
    end

    test "epoch is one week" do
      assert %{epoch_seconds: 604_800} = Contracts.constants()
    end

    test "the default unstaked fee is 10% expressed in pips" do
      %{default_unstaked_fee_pips: pips, unstaked_fee_denominator: denom} = Contracts.constants()
      assert pips / denom == 0.1
    end
  end
end
