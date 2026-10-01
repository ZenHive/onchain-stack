defmodule Onchain.Aave.DebtToken.WriteIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.DebtToken
  alias Onchain.Aave.Faucet
  alias Onchain.Aave.Pool
  alias Onchain.ERC20
  alias Onchain.RPC

  @moduletag :integration
  @moduletag timeout: 600_000

  @sepolia_chain_id 11_155_111

  @aave_sepolia_weth "0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c"
  @aave_sepolia_usdc "0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8"

  @gas_limit_weth_deposit 60_000
  @gas_limit_faucet_mint 200_000
  @gas_limit_erc20_approve 120_000
  @gas_limit_pool_supply 400_000
  @gas_limit_pool_borrow 500_000
  @gas_limit_pool_repay 400_000
  @gas_limit_pool_withdraw 400_000
  @gas_limit_approve_delegation 120_000

  @weth_supply_amount 10_000_000_000_000_000
  @usdc_borrow_amount 1_000_000
  @weth_deposit_threshold 50_000_000_000_000_000
  @weth_deposit_amount 100_000_000_000_000_000
  @faucet_mint_threshold_usdc 10_000_000
  @faucet_mint_amount_usdc 1_000_000_000
  @delegation_amount 500_000

  @max_uint256 Bitwise.bsl(1, 256) - 1

  # Delegatee address — no contract deployment required for allowance tests
  @delegatee "0xF380B8F1e63e2BEd7CA329CA1FdDbC39B52cC0d3"

  defp send_opts(rpc_url, key, address) do
    {:ok, nonce} = RPC.get_transaction_count(address, rpc_url: rpc_url, block: "pending")

    [
      private_key: key,
      chain_id: @sepolia_chain_id,
      rpc_url: rpc_url,
      nonce: nonce,
      max_fee_per_gas: {10, :gwei},
      max_priority_fee_per_gas: {1, :gwei}
    ]
  end

  defp pool_opts(rpc_url, key, address, gas_limit) do
    rpc_url
    |> send_opts(key, address)
    |> Keyword.put(:network, :sepolia)
    |> Keyword.put(:gas_limit, gas_limit)
  end

  defp debt_token_opts(rpc_url, key, address) do
    rpc_url
    |> send_opts(key, address)
    |> Keyword.put(:gas_limit, @gas_limit_approve_delegation)
  end

  defp send_and_wait!(tx_hash, rpc_url) do
    assert String.starts_with?(tx_hash, "0x"), "Expected tx hash, got: #{tx_hash}"

    assert {:ok, receipt} = Onchain.SignerCase.wait_for_receipt(tx_hash, rpc_url: rpc_url)

    assert receipt.status == 1,
           "Transaction reverted: #{tx_hash}"

    receipt
  end

  defp deposit_weth_if_needed(threshold, amount, rpc_url, key, address) do
    {:ok, balance} = ERC20.balance_of(@aave_sepolia_weth, address, rpc_url: rpc_url)

    if balance < threshold do
      opts =
        rpc_url
        |> send_opts(key, address)
        |> Keyword.put(:gas_limit, @gas_limit_weth_deposit)
        |> Keyword.put(:value, amount)

      {:ok, tx_hash} =
        Onchain.Signer.send_transaction(
          @aave_sepolia_weth,
          {:raw, Onchain.Hex.decode!("0xd0e30db0")},
          opts
        )

      send_and_wait!(tx_hash, rpc_url)
    end
  end

  defp faucet_mint_if_needed(token, amount, threshold, rpc_url, key, address) do
    {:ok, balance} = ERC20.balance_of(token, address, rpc_url: rpc_url)

    if balance < threshold do
      opts =
        rpc_url
        |> send_opts(key, address)
        |> Keyword.put(:gas_limit, @gas_limit_faucet_mint)
        |> Keyword.put(:network, :sepolia)

      {:ok, tx_hash} = Faucet.mint(token, address, amount, opts)
      send_and_wait!(tx_hash, rpc_url)
    end
  end

  defp supply_weth_collateral!(amount, rpc_url, key, address) do
    {:ok, pool_addr} = Contracts.address(:pool, network: :sepolia)

    {:ok, approve_hash} =
      ERC20.approve(
        @aave_sepolia_weth,
        pool_addr,
        amount,
        rpc_url |> send_opts(key, address) |> Keyword.put(:gas_limit, @gas_limit_erc20_approve)
      )

    send_and_wait!(approve_hash, rpc_url)

    {:ok, supply_hash} =
      Pool.supply(
        @aave_sepolia_weth,
        amount,
        address,
        pool_opts(rpc_url, key, address, @gas_limit_pool_supply)
      )

    send_and_wait!(supply_hash, rpc_url)
  end

  setup do
    key = Onchain.SignerCase.signer_key!()
    rpc_url = Onchain.SignerCase.sepolia_rpc_url!()
    address = Onchain.SignerCase.signer_address!()

    {:ok, key: key, rpc_url: rpc_url, address: address}
  end

  describe "approve_delegation and borrow_allowance round trip on Sepolia" do
    @tag :sepolia_send
    test "delegates variable debt allowance then revokes with zero", ctx do
      %{key: key, rpc_url: rpc_url, address: address} = ctx

      deposit_weth_if_needed(
        @weth_deposit_threshold,
        @weth_deposit_amount,
        rpc_url,
        key,
        address
      )

      faucet_mint_if_needed(
        @aave_sepolia_usdc,
        @faucet_mint_amount_usdc,
        @faucet_mint_threshold_usdc,
        rpc_url,
        key,
        address
      )

      supply_weth_collateral!(@weth_supply_amount, rpc_url, key, address)

      {:ok, borrow_hash} =
        Pool.borrow(
          @aave_sepolia_usdc,
          @usdc_borrow_amount,
          address,
          rpc_url
          |> pool_opts(key, address, @gas_limit_pool_borrow)
          |> Keyword.put(:interest_rate_mode, :variable)
        )

      send_and_wait!(borrow_hash, rpc_url)

      {:ok, variable_debt_token} =
        DebtToken.debt_token_address(@aave_sepolia_usdc, :variable,
          network: :sepolia,
          rpc_url: rpc_url
        )

      assert {:ok, 0} =
               DebtToken.borrow_allowance(variable_debt_token, address, @delegatee, rpc_url: rpc_url)

      {:ok, approve_hash} =
        DebtToken.approve_delegation(
          variable_debt_token,
          @delegatee,
          @delegation_amount,
          debt_token_opts(rpc_url, key, address)
        )

      send_and_wait!(approve_hash, rpc_url)

      assert {:ok, @delegation_amount} =
               DebtToken.borrow_allowance(variable_debt_token, address, @delegatee, rpc_url: rpc_url)

      {:ok, revoke_hash} =
        DebtToken.approve_delegation(
          variable_debt_token,
          @delegatee,
          0,
          debt_token_opts(rpc_url, key, address)
        )

      send_and_wait!(revoke_hash, rpc_url)

      assert {:ok, 0} =
               DebtToken.borrow_allowance(variable_debt_token, address, @delegatee, rpc_url: rpc_url)

      {:ok, pool_addr} = Contracts.address(:pool, network: :sepolia)

      {:ok, approve_usdc_hash} =
        ERC20.approve(
          @aave_sepolia_usdc,
          pool_addr,
          @max_uint256,
          rpc_url |> send_opts(key, address) |> Keyword.put(:gas_limit, @gas_limit_erc20_approve)
        )

      send_and_wait!(approve_usdc_hash, rpc_url)

      {:ok, repay_hash} =
        Pool.repay(
          @aave_sepolia_usdc,
          @max_uint256,
          address,
          rpc_url
          |> pool_opts(key, address, @gas_limit_pool_repay)
          |> Keyword.put(:interest_rate_mode, :variable)
        )

      send_and_wait!(repay_hash, rpc_url)

      {:ok, withdraw_hash} =
        Pool.withdraw(
          @aave_sepolia_weth,
          @weth_supply_amount,
          address,
          pool_opts(rpc_url, key, address, @gas_limit_pool_withdraw)
        )

      send_and_wait!(withdraw_hash, rpc_url)
    end
  end
end
