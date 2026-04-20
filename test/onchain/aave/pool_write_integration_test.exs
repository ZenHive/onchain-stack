defmodule Onchain.Aave.Pool.WriteIntegrationTest do
  # async: false — tests modify shared on-chain state (supply/withdraw/borrow/repay must be sequential)
  use ExUnit.Case, async: false

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.Faucet
  alias Onchain.Aave.Pool
  alias Onchain.ERC20
  alias Onchain.RPC

  @moduletag :integration
  # Borrow/repay test can hit up to 8 wait_for_receipt calls (each up to 60s).
  # Budget: 8 × 60s = 480s worst case + RPC overhead → 600s (10 min).
  @moduletag timeout: 600_000

  @sepolia_chain_id 11_155_111

  # Aave Sepolia testnet tokens (from BGD Labs aave-address-book src/AaveV3Sepolia.sol)
  @aave_sepolia_weth "0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c"
  @aave_sepolia_usdc "0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8"

  # Gas limits per operation type
  @gas_limit_weth_deposit 60_000
  @gas_limit_faucet_mint 200_000
  @gas_limit_erc20_approve 120_000
  @gas_limit_pool_supply 400_000
  @gas_limit_pool_withdraw 400_000
  @gas_limit_pool_borrow 500_000
  @gas_limit_pool_repay 400_000

  # Amounts (raw integers — WETH has 18 decimals, USDC has 6)
  @weth_supply_amount 10_000_000_000_000_000
  @usdc_borrow_amount 1_000_000
  # WETH deposit: wrap 0.1 ETH when balance drops below 0.05 ETH
  @weth_deposit_threshold 50_000_000_000_000_000
  @weth_deposit_amount 100_000_000_000_000_000
  @faucet_mint_threshold_usdc 10_000_000
  @faucet_mint_amount_usdc 1_000_000_000

  # max uint256 — used by Aave to signal "repay full debt" / "approve unlimited"
  @max_uint256 Bitwise.bsl(1, 256) - 1

  # --- Test-local helpers ---

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

  # Sends a transaction and waits for its receipt. Asserts status == 1 (success).
  defp send_and_wait!(tx_hash, rpc_url) do
    assert String.starts_with?(tx_hash, "0x"), "Expected tx hash, got: #{tx_hash}"

    assert {:ok, receipt} = Onchain.SignerCase.wait_for_receipt(tx_hash, rpc_url: rpc_url)

    assert receipt.status == 1,
           "Transaction reverted: #{tx_hash}"

    receipt
  end

  # Wraps Sepolia ETH into WETH via deposit() if WETH balance is below threshold.
  # WETH9Mock's mint() is owner-only — the faucet can't mint it.
  defp deposit_weth_if_needed(threshold, amount, rpc_url, key, address) do
    {:ok, balance} = ERC20.balance_of(@aave_sepolia_weth, address, rpc_url: rpc_url)

    if balance < threshold do
      # deposit() selector: 0xd0e30db0 (no arguments, ETH sent as value)
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

  # Mints tokens from the Aave Sepolia faucet if balance is below threshold.
  # Works for TestnetERC20 tokens (USDC, DAI, etc.) but NOT WETH.
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

  defp account_data(address, rpc_url) do
    Pool.get_user_account_data!(address, network: :sepolia, rpc_url: rpc_url)
  end

  # Asserts two Decimal values are within a relative tolerance (e.g. "0.05" = 5%).
  # Uses min base of 1 to avoid division by zero. Accounts for oracle price jitter
  # between reads on testnet.
  @oracle_jitter_tolerance "0.05"
  defp assert_approximately_restored(actual, expected, label) do
    diff = actual |> Decimal.sub(expected) |> Decimal.abs()
    base = expected |> Decimal.abs() |> Decimal.max(Decimal.new(1))
    pct = Decimal.div(diff, base)

    refute Decimal.gt?(pct, Decimal.new(@oracle_jitter_tolerance)),
           "#{label}: #{actual} differs from #{expected} by #{Decimal.round(Decimal.mult(pct, 100), 1)}% (max #{Decimal.mult(Decimal.new(@oracle_jitter_tolerance), 100)}%)"
  end

  # --- Tests ---

  setup do
    key = Onchain.SignerCase.signer_key!()
    rpc_url = Onchain.SignerCase.sepolia_rpc_url!()
    address = Onchain.SignerCase.signer_address!()

    {:ok, key: key, rpc_url: rpc_url, address: address}
  end

  describe "supply and withdraw round trip on Sepolia" do
    @tag :sepolia_send
    test "supply WETH then withdraw restores collateral", ctx do
      %{key: key, rpc_url: rpc_url, address: address} = ctx

      # 1. Wrap Sepolia ETH into WETH if balance is low
      deposit_weth_if_needed(
        @weth_deposit_threshold,
        @weth_deposit_amount,
        rpc_url,
        key,
        address
      )

      # 2. Approve Sepolia Pool to spend WETH
      {:ok, pool_addr} = Contracts.address(:pool, network: :sepolia)

      {:ok, approve_hash} =
        ERC20.approve(
          @aave_sepolia_weth,
          pool_addr,
          @weth_supply_amount,
          rpc_url |> send_opts(key, address) |> Keyword.put(:gas_limit, @gas_limit_erc20_approve)
        )

      send_and_wait!(approve_hash, rpc_url)

      # 3. Snapshot account data before supply
      pre_supply = account_data(address, rpc_url)

      # 4. Supply WETH to pool
      {:ok, supply_hash} =
        Pool.supply(
          @aave_sepolia_weth,
          @weth_supply_amount,
          address,
          pool_opts(rpc_url, key, address, @gas_limit_pool_supply)
        )

      send_and_wait!(supply_hash, rpc_url)

      # 5. Assert collateral increased
      post_supply = account_data(address, rpc_url)

      assert Decimal.gt?(post_supply.total_collateral_base, pre_supply.total_collateral_base),
             "Collateral should increase after supply: #{post_supply.total_collateral_base} <= #{pre_supply.total_collateral_base}"

      # 6. Withdraw same amount
      {:ok, withdraw_hash} =
        Pool.withdraw(
          @aave_sepolia_weth,
          @weth_supply_amount,
          address,
          pool_opts(rpc_url, key, address, @gas_limit_pool_withdraw)
        )

      send_and_wait!(withdraw_hash, rpc_url)

      # 7. Assert collateral decreased from post-supply snapshot
      post_withdraw = account_data(address, rpc_url)

      assert Decimal.lt?(post_withdraw.total_collateral_base, post_supply.total_collateral_base),
             "Collateral should decrease after withdraw: #{post_withdraw.total_collateral_base} >= #{post_supply.total_collateral_base}"

      # 8. Assert collateral restored to approximately pre-supply level
      assert_approximately_restored(
        post_withdraw.total_collateral_base,
        pre_supply.total_collateral_base,
        "Collateral not restored after withdraw"
      )
    end
  end

  describe "borrow and repay variable debt round trip on Sepolia" do
    @tag :sepolia_send
    test "borrow USDC then repay reduces debt", ctx do
      %{key: key, rpc_url: rpc_url, address: address} = ctx

      # 1. Wrap Sepolia ETH into WETH and mint USDC from faucet if balance is low
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

      # 2. Snapshot account data before supplying collateral for this round trip
      pre_supply = account_data(address, rpc_url)

      # 3. Approve and supply WETH as collateral
      {:ok, pool_addr} = Contracts.address(:pool, network: :sepolia)

      {:ok, approve_hash} =
        ERC20.approve(
          @aave_sepolia_weth,
          pool_addr,
          @weth_supply_amount,
          rpc_url |> send_opts(key, address) |> Keyword.put(:gas_limit, @gas_limit_erc20_approve)
        )

      send_and_wait!(approve_hash, rpc_url)

      {:ok, supply_hash} =
        Pool.supply(
          @aave_sepolia_weth,
          @weth_supply_amount,
          address,
          pool_opts(rpc_url, key, address, @gas_limit_pool_supply)
        )

      send_and_wait!(supply_hash, rpc_url)

      # 4. Snapshot account data before borrow
      pre_borrow = account_data(address, rpc_url)

      # 5. Borrow USDC (variable rate)
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

      # 6. Assert debt increased
      post_borrow = account_data(address, rpc_url)

      assert Decimal.gt?(post_borrow.total_debt_base, pre_borrow.total_debt_base),
             "Debt should increase after borrow: #{post_borrow.total_debt_base} <= #{pre_borrow.total_debt_base}"

      # 7. Approve Pool to spend USDC — max_uint256 covers accumulated debt from prior runs
      {:ok, approve_usdc_hash} =
        ERC20.approve(
          @aave_sepolia_usdc,
          pool_addr,
          @max_uint256,
          rpc_url |> send_opts(key, address) |> Keyword.put(:gas_limit, @gas_limit_erc20_approve)
        )

      send_and_wait!(approve_usdc_hash, rpc_url)

      # 8. Repay USDC (variable rate) — max uint256 repays full variable debt for this asset
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

      # 9. Assert debt fully unwound — post_repay debt should be at most pre_borrow level
      #    (max_uint256 clears all USDC variable debt, possibly including pre-existing)
      post_repay = account_data(address, rpc_url)

      assert Decimal.lt?(post_repay.total_debt_base, post_borrow.total_debt_base),
             "Debt should decrease after repay: #{post_repay.total_debt_base} >= #{post_borrow.total_debt_base}"

      refute Decimal.gt?(post_repay.total_debt_base, pre_borrow.total_debt_base),
             "Debt not fully unwound: post_repay #{post_repay.total_debt_base} > pre_borrow #{pre_borrow.total_debt_base}"

      # 10. Withdraw collateral to clean up — prevents state drift across test runs
      {:ok, withdraw_hash} =
        Pool.withdraw(
          @aave_sepolia_weth,
          @weth_supply_amount,
          address,
          pool_opts(rpc_url, key, address, @gas_limit_pool_withdraw)
        )

      send_and_wait!(withdraw_hash, rpc_url)

      # 11. Assert collateral restored to approximately pre-supply level
      post_cleanup = account_data(address, rpc_url)

      assert_approximately_restored(
        post_cleanup.total_collateral_base,
        pre_supply.total_collateral_base,
        "Collateral not restored after cleanup withdraw"
      )
    end
  end
end
