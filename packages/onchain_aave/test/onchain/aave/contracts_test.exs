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

  # Representative V4 singleton keys spanning each category (infra, position
  # manager, hub, spoke, per-spoke oracle).
  @v4_singletons %{
    v4_access_manager: "0x08aE3BE30958cDd1847ec58fFfd4C451a87fDF01",
    v4_config_engine: "0xe8096f931734286a95b6A63eFFCEFD3C56F3f6a9",
    v4_treasury_spoke: "0xB9B0b8616f6Bf6841972a52058132BE08d723155",
    v4_giver_position_manager: "0x17A54b8d6D9C68e7fa1C7112AC998EA1BA51d11e",
    v4_native_token_gateway: "0xe68ab4F90Fe026B9873F5F276eD2d7efBbbE42Be",
    v4_core_hub: "0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9",
    v4_prime_hub: "0x943827DCA022D0F354a8a8c332dA1e5Eb9f9F931",
    v4_plus_hub: "0x06002e9c4412CB7814a791eA3666D905871E536A",
    v4_main_spoke: "0x94e7A5dCbE816e498b89aB752661904E2F56c485",
    v4_lombard_btc_spoke: "0x7EC68b5695e803e98a21a9A05d744F28b0a7753D",
    v4_main_spoke_oracle: "0x99B2B6CEa9C3D2fd8F4d90f86741C44B212a6127",
    v4_ethena_correlated_spoke_oracle: "0x9b91a0943CADf554742E8Fb358B1cC4ae4F85F01"
  }

  describe "address/2 with V4 singleton keys" do
    test "resolves each representative V4 singleton to its expected address" do
      for {key, expected} <- @v4_singletons do
        assert {:ok, ^expected} = Contracts.address(key), "Failed for #{key}"
      end
    end

    test "all V4 singleton keys resolve to valid checksummed addresses" do
      {:ok, keys} = Contracts.v4_contracts()

      for key <- keys do
        assert {:ok, addr} = Contracts.address(key), "Failed for #{key}"
        assert Onchain.Address.valid?(addr)
        assert {:ok, ^addr} = Onchain.Address.checksum(addr)
      end
    end

    test "V4 keys are not available on V3-only networks" do
      assert {:error, {:unknown_contract, :v4_core_hub}} =
               Contracts.address(:v4_core_hub, network: :arbitrum)
    end

    test "unknown V4 key returns unknown_contract" do
      assert {:error, {:unknown_contract, :v4_nonexistent}} =
               Contracts.address(:v4_nonexistent)
    end

    test "does not break V3 lookups" do
      assert {:ok, "0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"} = Contracts.address(:pool)
    end

    test "address!/2 resolves V4 keys" do
      assert "0xCca852Bc40e560adC3b1Cc58CA5b55638ce826c9" = Contracts.address!(:v4_core_hub)
    end
  end

  describe "v4_tokenization_spoke/3" do
    test "resolves representative spokes across all three hubs" do
      assert {:ok, "0x7320CF22Ac095bA2a2e0a652F77efB836c2E751b"} =
               Contracts.v4_tokenization_spoke(:core, :weth)

      assert {:ok, "0x900fD46d565d1ac8995928c0179052ec02a6D0E1"} =
               Contracts.v4_tokenization_spoke(:prime, :gho)

      assert {:ok, "0x90774889c22D2F2Adf44da1f04C7c95542590df4"} =
               Contracts.v4_tokenization_spoke(:plus, :pt_susde)
    end

    test "same asset across hubs maps to distinct addresses" do
      {:ok, core_usdc} = Contracts.v4_tokenization_spoke(:core, :usdc)
      {:ok, prime_usdc} = Contracts.v4_tokenization_spoke(:prime, :usdc)
      {:ok, plus_usdc} = Contracts.v4_tokenization_spoke(:plus, :usdc)

      assert [core_usdc, prime_usdc, plus_usdc] |> Enum.uniq() |> length() == 3
    end

    test "every registered tokenization spoke is a valid checksummed address" do
      hubs = [core: 17, prime: 7, plus: 7]

      total =
        for {hub, _count} <- hubs, reduce: 0 do
          acc ->
            assets = tokenization_assets(hub)

            for asset <- assets do
              assert {:ok, addr} = Contracts.v4_tokenization_spoke(hub, asset),
                     "Failed for #{hub}/#{asset}"

              assert Onchain.Address.valid?(addr)
              assert {:ok, ^addr} = Onchain.Address.checksum(addr)
            end

            acc + length(assets)
        end

      assert total == 31
    end

    test "unknown hub returns unknown_hub" do
      assert {:error, {:unknown_hub, :bogus}} = Contracts.v4_tokenization_spoke(:bogus, :weth)
    end

    test "unknown asset in a known hub returns unknown_tokenization_spoke" do
      assert {:error, {:unknown_tokenization_spoke, {:core, :bogus}}} =
               Contracts.v4_tokenization_spoke(:core, :bogus)
    end

    test "asset present in one hub but absent in another returns unknown_tokenization_spoke" do
      # :aave is a Core spoke only; Prime has no AAVE tokenization spoke.
      assert {:ok, _} = Contracts.v4_tokenization_spoke(:core, :aave)

      assert {:error, {:unknown_tokenization_spoke, {:prime, :aave}}} =
               Contracts.v4_tokenization_spoke(:prime, :aave)
    end

    test "unsupported network returns error" do
      assert {:error, {:unsupported_network, :arbitrum}} =
               Contracts.v4_tokenization_spoke(:core, :weth, network: :arbitrum)
    end
  end

  describe "v4_contracts/1" do
    test "lists all 34 V4 singleton keys on ethereum" do
      assert {:ok, keys} = Contracts.v4_contracts()
      assert length(keys) == 34
      assert :v4_core_hub in keys
      assert :v4_main_spoke_oracle in keys
    end

    test "V3-only networks have no V4 singletons" do
      assert {:error, {:unsupported_network, :arbitrum}} =
               Contracts.v4_contracts(network: :arbitrum)
    end
  end

  # Asset keys per hub, mirroring the V4_SCOPING.md Tokenization Spoke tables.
  defp tokenization_assets(:core),
    do: ~w(aave cbbtc eurc frxusd gho lbtc link rlusd rseth usdc usdg usdt wbtc weeth weth wsteth xaut)a

  defp tokenization_assets(:prime), do: ~w(cbbtc gho usdc usdt wbtc weth wsteth)a
  defp tokenization_assets(:plus), do: ~w(gho pt_susde pt_usde susde usdc usde usdt)a
end
