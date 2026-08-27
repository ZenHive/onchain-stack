defmodule Onchain.ERC20WriteIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.ERC20
  alias Onchain.RPC

  @moduletag :integration

  @sepolia_chain_id 11_155_111

  # Circle's Sepolia USDC faucet token
  @sepolia_usdc "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"

  describe "Sepolia USDC verification" do
    test "token contract exists and returns expected symbol" do
      rpc_url = Onchain.SignerCase.sepolia_rpc_url!()
      assert {:ok, "USDC"} = ERC20.symbol(@sepolia_usdc, rpc_url: rpc_url)
    end
  end

  describe "approve/4 on Sepolia" do
    setup do
      key = Onchain.SignerCase.signer_key!()
      rpc_url = Onchain.SignerCase.sepolia_rpc_url!()
      address = Onchain.SignerCase.signer_address!()

      {:ok, key: key, rpc_url: rpc_url, address: address}
    end

    @tag :sepolia_send
    test "self-approve sets allowance", %{key: key, rpc_url: rpc_url, address: address} do
      {:ok, nonce} = RPC.get_transaction_count(address, rpc_url: rpc_url, block: "pending")

      approval_amount = 1_000_000

      assert {:ok, tx_hash} =
               ERC20.approve(@sepolia_usdc, address, approval_amount,
                 private_key: key,
                 nonce: nonce,
                 chain_id: @sepolia_chain_id,
                 rpc_url: rpc_url,
                 max_fee_per_gas: {10, :gwei},
                 max_priority_fee_per_gas: {1, :gwei}
               )

      assert String.starts_with?(tx_hash, "0x")

      assert {:ok, receipt} =
               Onchain.SignerCase.wait_for_receipt(tx_hash, rpc_url: rpc_url)

      assert receipt.status == 1

      # Verify allowance was set
      assert {:ok, allowance} =
               ERC20.allowance(@sepolia_usdc, address, address, rpc_url: rpc_url)

      assert allowance >= approval_amount
    end
  end

  describe "transfer/4 on Sepolia" do
    setup do
      key = Onchain.SignerCase.signer_key!()
      rpc_url = Onchain.SignerCase.sepolia_rpc_url!()
      address = Onchain.SignerCase.signer_address!()

      {:ok, key: key, rpc_url: rpc_url, address: address}
    end

    @tag :sepolia_send
    test "zero transfer to self succeeds", %{key: key, rpc_url: rpc_url, address: address} do
      {:ok, nonce} = RPC.get_transaction_count(address, rpc_url: rpc_url, block: "pending")

      assert {:ok, tx_hash} =
               ERC20.transfer(@sepolia_usdc, address, 0,
                 private_key: key,
                 nonce: nonce,
                 chain_id: @sepolia_chain_id,
                 rpc_url: rpc_url,
                 max_fee_per_gas: {10, :gwei},
                 max_priority_fee_per_gas: {1, :gwei}
               )

      assert String.starts_with?(tx_hash, "0x")

      assert {:ok, receipt} =
               Onchain.SignerCase.wait_for_receipt(tx_hash, rpc_url: rpc_url)

      assert receipt.status == 1
    end
  end
end
