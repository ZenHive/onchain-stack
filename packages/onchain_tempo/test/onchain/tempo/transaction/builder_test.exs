defmodule Onchain.Tempo.Transaction.BuilderTest do
  use ExUnit.Case, async: true

  alias Onchain.Tempo.Transaction
  alias Onchain.Tempo.Transaction.Builder

  # Hardhat default account #0 — testnet only, no security concern.
  @private_key "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
  @recipient "0x70997970c51812dc3a010c7d01b50e0d17dc79c8"
  @token "0x20c0000000000000000000000000000000000000"
  @chain_id 42_431
  @amount 1_000_000
  @rpc_url "https://rpc.example.test"

  describe "build_signed_transfer/1" do
    test "builds a signed 0x76 transaction that deserializes and matches the payment call" do
      assert {:ok, tx_hex} = Builder.build_signed_transfer(valid_opts())
      assert String.starts_with?(tx_hex, "0x76")

      assert {:ok, tx} = Transaction.deserialize(tx_hex)
      assert tx.chain_id == @chain_id

      # Explicit :gas_limit is honored verbatim (gas_limit is field index 3).
      assert :binary.decode_unsigned(Enum.at(tx.fields, 3)) == 500_000

      assert {:ok, match} =
               Transaction.find_payment_call(tx, @token,
                 amount: Integer.to_string(@amount),
                 recipient: @recipient
               )

      assert match.amount == @amount
    end

    test "returns an error when a required option is missing" do
      opts = Keyword.delete(valid_opts(), :private_key)

      assert {:error, "missing required option: private_key"} =
               Builder.build_signed_transfer(opts)
    end

    test "returns an error on invalid private key hex" do
      opts = Keyword.put(valid_opts(), :private_key, "0xnothex")

      assert {:error, "invalid private_key: expected 32-byte hex string"} =
               Builder.build_signed_transfer(opts)
    end

    test "returns an error on invalid recipient address" do
      opts = Keyword.put(valid_opts(), :recipient, "0xnothex")

      assert {:error, "invalid recipient: expected 20-byte hex address"} =
               Builder.build_signed_transfer(opts)
    end

    test "returns an error on invalid fee token address" do
      opts = Keyword.put(valid_opts(), :fee_token, "0xnothex")

      assert {:error, "invalid fee_token: expected 20-byte hex address"} =
               Builder.build_signed_transfer(opts)
    end

    test "returns an error on invalid amount" do
      opts = Keyword.put(valid_opts(), :amount, "1000000")

      assert {:error, "invalid amount: expected non-negative integer"} =
               Builder.build_signed_transfer(opts)
    end

    test "returns an error on invalid explicit nonce" do
      opts = Keyword.put(valid_opts(), :nonce, "bad-nonce")

      assert {:error, "invalid nonce: expected non-negative integer"} =
               Builder.build_signed_transfer(opts)
    end
  end

  describe "build_fee_payer_transfer/1" do
    test "builds a transaction with fee payer placeholder" do
      assert {:ok, tx_hex} = Builder.build_fee_payer_transfer(valid_opts())
      assert String.starts_with?(tx_hex, "0x76")

      assert {:ok, tx} = Transaction.deserialize(tx_hex)
      assert Transaction.has_fee_payer_placeholder?(tx)
      assert Transaction.fee_token_empty?(tx)
    end
  end

  describe "build_signed_multicall/1" do
    test "returns error for missing calls option" do
      opts = [
        private_key: @private_key,
        chain_id: @chain_id,
        rpc_url: @rpc_url,
        fee_token: @token,
        nonce: 0
      ]

      assert {:error, "missing required option: calls"} =
               Builder.build_signed_multicall(opts)
    end

    test "returns error for empty calls list" do
      opts = [
        private_key: @private_key,
        calls: [],
        chain_id: @chain_id,
        rpc_url: @rpc_url,
        fee_token: @token,
        nonce: 0
      ]

      assert {:error, "invalid calls: expected non-empty list"} =
               Builder.build_signed_multicall(opts)
    end
  end

  # Explicit gas_limit keeps these tests hermetic (no eth_estimateGas RPC) and
  # exercises the explicit-override path. The estimation path is covered in
  # BuilderEstimateTest (stubbed) and the Moderato integration suite (live).
  describe "build_fee_payer_multicall/1" do
    test "builds a fee-payer multicall with placeholder fields" do
      token_bin = Base.decode16!("20c0000000000000000000000000000000000000", case: :lower)
      calls = [[token_bin, <<>>, Base.decode16!("a9059cbb", case: :lower)]]

      opts = [
        private_key: @private_key,
        calls: calls,
        chain_id: @chain_id,
        rpc_url: @rpc_url,
        nonce: 0,
        gas_limit: 500_000
      ]

      assert {:ok, tx_hex} = Builder.build_fee_payer_multicall(opts)
      assert {:ok, tx} = Transaction.deserialize(tx_hex)
      assert Transaction.has_fee_payer_placeholder?(tx)
      assert Transaction.fee_token_empty?(tx)
    end

    test "returns error for empty calls list" do
      opts = [private_key: @private_key, calls: [], chain_id: @chain_id, rpc_url: @rpc_url, nonce: 0]

      assert {:error, "invalid calls: expected non-empty list"} =
               Builder.build_fee_payer_multicall(opts)
    end

    test "returns error for a malformed call entry" do
      token_bin = Base.decode16!("20c0000000000000000000000000000000000000", case: :lower)

      opts = [
        private_key: @private_key,
        calls: [[token_bin]],
        chain_id: @chain_id,
        rpc_url: @rpc_url,
        nonce: 0
      ]

      assert {:error, "invalid calls: each call must be [to, value, input] binaries"} =
               Builder.build_fee_payer_multicall(opts)
    end
  end

  describe "input normalization and error branches" do
    test "accepts raw-binary private key and addresses" do
      opts = [
        private_key: Base.decode16!("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", case: :lower),
        token: Base.decode16!("20c0000000000000000000000000000000000000", case: :lower),
        recipient: Base.decode16!("70997970c51812dc3a010c7d01b50e0d17dc79c8", case: :lower),
        amount: @amount,
        chain_id: @chain_id,
        rpc_url: @rpc_url,
        nonce: 0,
        gas_limit: 500_000
      ]

      assert {:ok, "0x76" <> _} = Builder.build_signed_transfer(opts)
    end

    test "rejects a 64-char non-hex private key" do
      opts = Keyword.put(valid_opts(), :private_key, String.duplicate("z", 64))

      assert {:error, "invalid private_key: expected 32-byte hex string"} =
               Builder.build_signed_transfer(opts)
    end

    test "rejects a 40-char non-hex address" do
      opts = Keyword.put(valid_opts(), :recipient, "0x" <> String.duplicate("z", 40))

      assert {:error, "invalid recipient: expected 20-byte hex address"} =
               Builder.build_signed_transfer(opts)
    end

    test "rejects an empty rpc_url" do
      opts = Keyword.put(valid_opts(), :rpc_url, "")

      assert {:error, "invalid rpc_url: expected non-empty string"} =
               Builder.build_signed_transfer(opts)
    end
  end

  defp valid_opts do
    [
      private_key: @private_key,
      token: @token,
      recipient: @recipient,
      amount: @amount,
      chain_id: @chain_id,
      rpc_url: @rpc_url,
      nonce: 0,
      gas_limit: 500_000
    ]
  end
end
