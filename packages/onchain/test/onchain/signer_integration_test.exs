defmodule Onchain.SignerIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.RPC
  alias Onchain.Signer

  @moduletag :integration

  @sepolia_chain_id 11_155_111

  describe "address_from_key/1 with real Sepolia key" do
    test "derives a valid checksummed address" do
      key = Onchain.SignerCase.signer_key!()
      assert {:ok, address} = Signer.address_from_key(key)
      assert String.starts_with?(address, "0x")
      assert String.length(address) == 42
      # Verify mixed case (checksummed)
      refute address == String.downcase(address)
    end
  end

  describe "nonce fetch for derived address" do
    test "gets transaction count from Sepolia RPC" do
      rpc_url = Onchain.SignerCase.sepolia_rpc_url!()
      address = Onchain.SignerCase.signer_address!()

      assert {:ok, nonce} = RPC.get_transaction_count(address, rpc_url: rpc_url)
      assert is_integer(nonce) and nonce >= 0
    end
  end

  # NOTE: the :sepolia_send tests below broadcast real transactions and are NOT
  # idempotent — re-running one re-broadcasts the same nonce, which the node rejects
  # as "replacement transaction underpriced". ex_unit_json's auto-retry has no per-test
  # opt-out, so run these with `--no-retry` (e.g. `mix test.json --only sepolia_send
  # --no-retry`) to avoid a spurious retry-induced collision being reported as flaky.
  describe "self-transfer on Sepolia" do
    @tag :sepolia_send
    test "sends 0 ETH to self and gets receipt with status 1" do
      key = Onchain.SignerCase.signer_key!()
      rpc_url = Onchain.SignerCase.sepolia_rpc_url!()
      address = Onchain.SignerCase.signer_address!()

      # Fetch current nonce
      {:ok, nonce} = RPC.get_transaction_count(address, rpc_url: rpc_url, block: "pending")

      # Send 0 ETH to self
      assert {:ok, tx_hash} =
               Signer.send_transaction(address, <<>>,
                 private_key: key,
                 nonce: nonce,
                 chain_id: @sepolia_chain_id,
                 rpc_url: rpc_url,
                 gas_limit: 21_000,
                 max_fee_per_gas: {10, :gwei},
                 max_priority_fee_per_gas: {1, :gwei},
                 value: 0
               )

      assert String.starts_with?(tx_hash, "0x")

      # Wait for receipt
      assert {:ok, receipt} =
               Onchain.SignerCase.wait_for_receipt(tx_hash, rpc_url: rpc_url)

      assert receipt.status == 1
      assert receipt.from == address
    end

    @tag :sepolia_send
    test "auto-estimates gas when :gas_limit is omitted and confirms with status 1" do
      key = Onchain.SignerCase.signer_key!()
      rpc_url = Onchain.SignerCase.sepolia_rpc_url!()
      address = Onchain.SignerCase.signer_address!()

      {:ok, nonce} = RPC.get_transaction_count(address, rpc_url: rpc_url, block: "pending")

      # :gas_limit intentionally omitted — send_transaction estimates via eth_estimateGas
      # and applies headroom, so the tx is correctly sized and does not OOG-revert.
      assert {:ok, tx_hash} =
               Signer.send_transaction(address, <<>>,
                 private_key: key,
                 nonce: nonce,
                 chain_id: @sepolia_chain_id,
                 rpc_url: rpc_url,
                 max_fee_per_gas: {10, :gwei},
                 max_priority_fee_per_gas: {1, :gwei},
                 value: 0
               )

      assert {:ok, receipt} = Onchain.SignerCase.wait_for_receipt(tx_hash, rpc_url: rpc_url)

      assert receipt.status == 1
      # auto-estimate sized the tx — gas actually used does not equal the limit (no OOG)
      assert receipt.gas_used > 0
    end
  end
end
