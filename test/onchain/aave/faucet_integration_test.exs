defmodule Onchain.Aave.Faucet.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.Faucet
  alias Onchain.ERC20
  alias Onchain.RPC

  @moduletag :integration
  # 1 wait_for_receipt (up to 60s) + balance reads + nonce fetch → 120s comfortable
  @moduletag timeout: 120_000

  @sepolia_chain_id 11_155_111

  # Aave Sepolia testnet USDC — a TestnetERC20 that the faucet can mint
  # (WETH is a WETH9Mock whose mint() is owner-only, not callable via faucet)
  @aave_sepolia_usdc "0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8"

  # Mint a small amount: 1 USDC (6 decimals)
  @mint_amount 1_000_000

  setup do
    key = Onchain.SignerCase.signer_key!()
    rpc_url = Onchain.SignerCase.sepolia_rpc_url!()
    address = Onchain.SignerCase.signer_address!()

    {:ok, key: key, rpc_url: rpc_url, address: address}
  end

  describe "mint/4 on Sepolia" do
    @tag :sepolia_send
    test "mints USDC and increases balance", ctx do
      %{key: key, rpc_url: rpc_url, address: address} = ctx

      # 1. Record balance before mint
      {:ok, balance_before} = ERC20.balance_of(@aave_sepolia_usdc, address, rpc_url: rpc_url)

      # 2. Get nonce and build opts
      {:ok, nonce} = RPC.get_transaction_count(address, rpc_url: rpc_url, block: "pending")

      opts = [
        private_key: key,
        chain_id: @sepolia_chain_id,
        rpc_url: rpc_url,
        nonce: nonce,
        network: :sepolia,
        max_fee_per_gas: {10, :gwei},
        max_priority_fee_per_gas: {1, :gwei}
      ]

      # 3. Mint
      {:ok, tx_hash} = Faucet.mint(@aave_sepolia_usdc, address, @mint_amount, opts)
      assert String.starts_with?(tx_hash, "0x")

      # 4. Wait for receipt and verify success
      {:ok, receipt} = Onchain.SignerCase.wait_for_receipt(tx_hash, rpc_url: rpc_url)
      assert receipt.status == 1, "Faucet mint reverted: #{tx_hash}"

      # 5. Verify balance increased
      {:ok, balance_after} = ERC20.balance_of(@aave_sepolia_usdc, address, rpc_url: rpc_url)
      assert balance_after >= balance_before + @mint_amount
    end
  end
end
