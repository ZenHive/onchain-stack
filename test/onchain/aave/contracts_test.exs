defmodule Onchain.Aave.ContractsTest do
  use ExUnit.Case, async: true

  alias Onchain.Aave.Contracts

  @known_contracts [:pool_addresses_provider, :pool, :oracle, :ui_pool_data_provider]
  @all_networks [:ethereum, :arbitrum, :optimism, :base, :polygon, :avalanche, :sepolia]
  @mainnet_networks [:ethereum, :arbitrum, :optimism, :base, :polygon, :avalanche]

  describe "address/1" do
    test "returns checksummed address for each known contract" do
      for key <- @known_contracts do
        assert {:ok, addr} = Contracts.address(key)
        assert String.starts_with?(addr, "0x")
        assert String.length(addr) == 42
      end
    end

    test "pool returns expected address" do
      assert {:ok, "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"} = Contracts.address(:pool)
    end

    test "pool_addresses_provider returns expected address" do
      assert {:ok, "0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e"} =
               Contracts.address(:pool_addresses_provider)
    end

    test "oracle returns expected address" do
      assert {:ok, "0x54586bE62E3c3580375aE3723C145253060Ca0C2"} = Contracts.address(:oracle)
    end

    test "ui_pool_data_provider returns expected address" do
      assert {:ok, "0x56b7A1012765C285afAC8b8F25C69Bf10ccfE978"} =
               Contracts.address(:ui_pool_data_provider)
    end

    test "returns error for unknown contract" do
      assert {:error, {:unknown_contract, :nonexistent}} = Contracts.address(:nonexistent)
    end

    test "all returned addresses are valid checksummed" do
      for key <- @known_contracts do
        {:ok, addr} = Contracts.address(key)
        assert Onchain.Address.valid?(addr)
        # Verify checksumming is idempotent
        assert {:ok, ^addr} = Onchain.Address.checksum(addr)
      end
    end
  end

  describe "address/2 with network option" do
    test "explicit network: :ethereum works" do
      assert {:ok, _addr} = Contracts.address(:pool, network: :ethereum)
    end

    test "unsupported network returns error" do
      assert {:error, {:unsupported_network, :solana}} =
               Contracts.address(:pool, network: :solana)
    end
  end

  describe "address/2 multi-network" do
    test "all networks return valid checksummed addresses for all contracts" do
      for network <- @all_networks, contract <- @known_contracts do
        assert {:ok, addr} = Contracts.address(contract, network: network),
               "Failed for #{network}/#{contract}"

        assert String.starts_with?(addr, "0x")
        assert String.length(addr) == 42
        assert {:ok, ^addr} = Onchain.Address.checksum(addr)
      end
    end

    test "arbitrum pool matches expected CREATE2 address" do
      assert {:ok, "0x794a61358D6845594F94dc1DB02A252b5b4814aD"} =
               Contracts.address(:pool, network: :arbitrum)
    end

    test "base pool has different address from CREATE2 chains" do
      assert {:ok, base_pool} = Contracts.address(:pool, network: :base)
      assert {:ok, arb_pool} = Contracts.address(:pool, network: :arbitrum)
      refute base_pool == arb_pool
    end

    test "CREATE2 chains share pool address" do
      create2_networks = [:arbitrum, :optimism, :polygon, :avalanche]

      pool_addrs =
        Enum.map(create2_networks, fn net ->
          {:ok, addr} = Contracts.address(:pool, network: net)
          addr
        end)

      assert pool_addrs |> Enum.uniq() |> length() == 1
    end
  end

  describe "address!/1" do
    test "returns address directly" do
      assert "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2" = Contracts.address!(:pool)
    end

    test "raises on unknown contract" do
      assert_raise RuntimeError, ~r/address lookup failed/, fn ->
        Contracts.address!(:nonexistent)
      end
    end

    test "raises on unsupported network" do
      assert_raise RuntimeError, ~r/address lookup failed/, fn ->
        Contracts.address!(:pool, network: :solana)
      end
    end
  end

  describe "networks/0" do
    test "returns all 7 supported networks" do
      networks = Contracts.networks()
      assert length(networks) == 7

      for network <- @all_networks do
        assert network in networks
      end
    end
  end

  describe "contracts/0" do
    test "returns all 4 contract keys" do
      assert {:ok, keys} = Contracts.contracts()
      assert length(keys) == 4

      for key <- @known_contracts do
        assert key in keys
      end
    end
  end

  describe "contracts/1 with network option" do
    test "explicit network: :ethereum works" do
      assert {:ok, keys} = Contracts.contracts(network: :ethereum)
      assert length(keys) == 4
    end

    test "mainnet networks have exactly the 4 core contract keys" do
      for network <- @mainnet_networks do
        assert {:ok, keys} = Contracts.contracts(network: network)
        assert length(keys) == 4, "#{network} has #{length(keys)} keys, expected 4: #{inspect(keys)}"

        for key <- @known_contracts do
          assert key in keys, "Missing #{key} for #{network}"
        end
      end
    end

    test "sepolia has exactly 5 contract keys (4 core + faucet)" do
      assert {:ok, keys} = Contracts.contracts(network: :sepolia)
      assert length(keys) == 5, "Sepolia has #{length(keys)} keys, expected 5: #{inspect(keys)}"

      for key <- @known_contracts do
        assert key in keys, "Missing #{key} for sepolia"
      end

      assert :faucet in keys
    end

    test "sepolia has faucet contract" do
      assert {:ok, addr} = Contracts.address(:faucet, network: :sepolia)
      assert String.starts_with?(addr, "0x")
      assert String.length(addr) == 42
      assert {:ok, ^addr} = Onchain.Address.checksum(addr)
    end

    test "unsupported network returns error" do
      assert {:error, {:unsupported_network, :solana}} = Contracts.contracts(network: :solana)
    end
  end
end
