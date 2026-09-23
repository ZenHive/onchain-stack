defmodule Onchain.Aave.Contracts.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.Contracts
  alias Onchain.ABI
  alias Onchain.RPC

  @moduletag :integration

  defp sepolia_rpc_opts do
    [rpc_url: Onchain.SignerCase.sepolia_rpc_url!()]
  end

  describe "Sepolia on-chain address verification" do
    test "PoolAddressesProvider.getPool() matches stored :pool for Sepolia" do
      {:ok, provider_addr} = Contracts.address(:pool_addresses_provider, network: :sepolia)
      {:ok, calldata} = ABI.encode_call("getPool()", [])
      {:ok, hex_result} = RPC.eth_call(provider_addr, calldata, sepolia_rpc_opts())
      {:ok, [pool_addr_raw]} = ABI.decode_response("(address)", hex_result)

      {:ok, pool_on_chain} = Onchain.Address.checksum(pool_addr_raw)
      {:ok, pool_stored} = Contracts.address(:pool, network: :sepolia)

      assert Onchain.Address.equal?(pool_on_chain, pool_stored),
             "On-chain pool #{pool_on_chain} != stored #{pool_stored}"
    end

    test "PoolAddressesProvider.getPriceOracle() matches stored :oracle for Sepolia" do
      {:ok, provider_addr} = Contracts.address(:pool_addresses_provider, network: :sepolia)
      {:ok, calldata} = ABI.encode_call("getPriceOracle()", [])
      {:ok, hex_result} = RPC.eth_call(provider_addr, calldata, sepolia_rpc_opts())
      {:ok, [oracle_addr_raw]} = ABI.decode_response("(address)", hex_result)

      {:ok, oracle_on_chain} = Onchain.Address.checksum(oracle_addr_raw)
      {:ok, oracle_stored} = Contracts.address(:oracle, network: :sepolia)

      assert Onchain.Address.equal?(oracle_on_chain, oracle_stored),
             "On-chain oracle #{oracle_on_chain} != stored #{oracle_stored}"
    end
  end

  defp base_sepolia_rpc_opts do
    [rpc_url: Onchain.SignerCase.base_sepolia_rpc_url!()]
  end

  describe "Base Sepolia on-chain address verification" do
    test "PoolAddressesProvider.getPool() matches stored :pool for Base Sepolia" do
      {:ok, provider_addr} = Contracts.address(:pool_addresses_provider, network: :base_sepolia)
      {:ok, calldata} = ABI.encode_call("getPool()", [])
      {:ok, hex_result} = RPC.eth_call(provider_addr, calldata, base_sepolia_rpc_opts())
      {:ok, [pool_addr_raw]} = ABI.decode_response("(address)", hex_result)

      {:ok, pool_on_chain} = Onchain.Address.checksum(pool_addr_raw)
      {:ok, pool_stored} = Contracts.address(:pool, network: :base_sepolia)

      assert Onchain.Address.equal?(pool_on_chain, pool_stored),
             "On-chain pool #{pool_on_chain} != stored #{pool_stored}"
    end

    test "PoolAddressesProvider.getPriceOracle() matches stored :oracle for Base Sepolia" do
      {:ok, provider_addr} = Contracts.address(:pool_addresses_provider, network: :base_sepolia)
      {:ok, calldata} = ABI.encode_call("getPriceOracle()", [])
      {:ok, hex_result} = RPC.eth_call(provider_addr, calldata, base_sepolia_rpc_opts())
      {:ok, [oracle_addr_raw]} = ABI.decode_response("(address)", hex_result)

      {:ok, oracle_on_chain} = Onchain.Address.checksum(oracle_addr_raw)
      {:ok, oracle_stored} = Contracts.address(:oracle, network: :base_sepolia)

      assert Onchain.Address.equal?(oracle_on_chain, oracle_stored),
             "On-chain oracle #{oracle_on_chain} != stored #{oracle_stored}"
    end

    test "UiPoolDataProvider.getReservesList(provider) returns reserves on Base Sepolia" do
      {:ok, ui_pool_data_provider} = Contracts.address(:ui_pool_data_provider, network: :base_sepolia)
      {:ok, provider_addr} = Contracts.address(:pool_addresses_provider, network: :base_sepolia)
      {:ok, provider_addr_bin} = Onchain.Address.validate(provider_addr)
      {:ok, calldata} = ABI.encode_call("getReservesList(address)", [provider_addr_bin])
      {:ok, hex_result} = RPC.eth_call(ui_pool_data_provider, calldata, base_sepolia_rpc_opts())
      {:ok, [reserves]} = ABI.decode_response("(address[])", hex_result)

      assert reserves != [], "Base Sepolia market has no reserves"
      assert Enum.all?(reserves, &Onchain.Address.valid?/1)
    end

    test "Faucet is unpermissioned and mint(token,to,amount) simulates on Base Sepolia" do
      {:ok, faucet_addr} = Contracts.address(:faucet, network: :base_sepolia)
      {:ok, calldata} = ABI.encode_call("isPermissioned()", [])
      {:ok, hex_result} = RPC.eth_call(faucet_addr, calldata, base_sepolia_rpc_opts())
      {:ok, [permissioned]} = ABI.decode_response("(bool)", hex_result)
      refute permissioned, "Base Sepolia faucet is permissioned; Faucet.mint/4 would revert"

      # Read-only simulation of the exact call Onchain.Aave.Faucet.mint/4 signs —
      # proves the ABI and the USDC reserve (address-book USDC_UNDERLYING) line up.
      {:ok, usdc_bin} = Onchain.Address.validate("0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f")
      {:ok, to_bin} = Onchain.Address.validate("0x1111111111111111111111111111111111111111")
      amount = 1_000_000
      {:ok, calldata} = ABI.encode_call("mint(address,address,uint256)", [usdc_bin, to_bin, amount])
      {:ok, hex_result} = RPC.eth_call(faucet_addr, calldata, base_sepolia_rpc_opts())
      {:ok, [minted]} = ABI.decode_response("(uint256)", hex_result)
      assert minted == amount
    end
  end

  describe "on-chain address verification" do
    test "PoolAddressesProvider.getPool() matches stored :pool address" do
      {:ok, provider_addr} = Contracts.address(:pool_addresses_provider)
      {:ok, calldata} = ABI.encode_call("getPool()", [])
      {:ok, hex_result} = RPC.eth_call(provider_addr, calldata, Onchain.RPCCase.rpc_opts!())
      {:ok, [pool_addr_raw]} = ABI.decode_response("(address)", hex_result)

      {:ok, pool_on_chain} = Onchain.Address.checksum(pool_addr_raw)
      {:ok, pool_stored} = Contracts.address(:pool)

      assert Onchain.Address.equal?(pool_on_chain, pool_stored),
             "On-chain pool #{pool_on_chain} != stored #{pool_stored}"
    end

    test "PoolAddressesProvider.getPriceOracle() matches stored :oracle address" do
      {:ok, provider_addr} = Contracts.address(:pool_addresses_provider)
      {:ok, calldata} = ABI.encode_call("getPriceOracle()", [])
      {:ok, hex_result} = RPC.eth_call(provider_addr, calldata, Onchain.RPCCase.rpc_opts!())
      {:ok, [oracle_addr_raw]} = ABI.decode_response("(address)", hex_result)

      {:ok, oracle_on_chain} = Onchain.Address.checksum(oracle_addr_raw)
      {:ok, oracle_stored} = Contracts.address(:oracle)

      assert Onchain.Address.equal?(oracle_on_chain, oracle_stored),
             "On-chain oracle #{oracle_on_chain} != stored #{oracle_stored}"
    end

    test "Pool.getUserAccountData() returns position for known borrower" do
      # Active Aave V3 position with collateral + debt
      user = "0xF380B8F1e63e2BEd7CA329CA1FdDbC39B52cC0d3"
      {:ok, user_bin} = Onchain.Address.validate(user)
      {:ok, pool_addr} = Contracts.address(:pool)
      {:ok, calldata} = ABI.encode_call("getUserAccountData(address)", [user_bin])
      {:ok, hex_result} = RPC.eth_call(pool_addr, calldata, Onchain.RPCCase.rpc_opts!())

      {:ok, [collateral, debt, available, liq_threshold, ltv, health_factor]} =
        ABI.decode_response("(uint256,uint256,uint256,uint256,uint256,uint256)", hex_result)

      # All values are non-negative integers
      assert collateral > 0, "Expected collateral > 0"
      assert debt > 0, "Expected debt > 0 (active borrow position)"
      assert available >= 0
      assert liq_threshold > 0 and liq_threshold <= 10_000
      assert ltv > 0 and ltv <= 10_000
      assert health_factor > 0

      # Sanity: health factor should be > 1 (not liquidatable)
      hf_decimal = Onchain.Decimal.to_decimal(health_factor, 18)
      assert Decimal.gt?(hf_decimal, Decimal.new(1)), "Expected health factor > 1, got #{hf_decimal}"
    end

    test "UiPoolDataProvider.getReservesList(provider) returns non-empty list" do
      {:ok, ui_pool_data_provider} = Contracts.address(:ui_pool_data_provider)
      {:ok, provider_addr} = Contracts.address(:pool_addresses_provider)
      {:ok, provider_addr_bin} = Onchain.Address.validate(provider_addr)
      {:ok, calldata} = ABI.encode_call("getReservesList(address)", [provider_addr_bin])
      {:ok, hex_result} = RPC.eth_call(ui_pool_data_provider, calldata, Onchain.RPCCase.rpc_opts!())
      {:ok, [reserves]} = ABI.decode_response("(address[])", hex_result)

      assert is_list(reserves)
      assert reserves != []
      assert Enum.all?(reserves, &Onchain.Address.valid?/1)
    end
  end
end
