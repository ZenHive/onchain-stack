defmodule Onchain.Tempo.Integration.ModeratoTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Onchain.Tempo.Faucet
  alias Onchain.Tempo.RPC
  alias Onchain.Tempo.TIP20
  alias Onchain.Tempo.Transaction
  alias Onchain.Tempo.Transaction.Builder

  @moduletag :integration

  # Canonical pathUSD TIP-20 stablecoin on Moderato (6 decimals).
  @path_usd Base.decode16!("20c0000000000000000000000000000000000000", case: :lower)
  @chain_id 42_431

  setup do
    case Faucet.fresh_funded_wallet() do
      {:ok, wallet} ->
        {:ok, wallet: wallet, rpc_url: Faucet.rpc_url()}

      {:error, reason} ->
        flunk("""
        Could not fund a Moderato testnet wallet: #{reason}

        These integration tests require Moderato to be reachable and the
        `tempo_fundAddress` JSON-RPC method to succeed. Override the RPC URL
        with TEMPO_RPC_URL if needed.

        Skip this suite by running without --include integration.
        """)
    end
  end

  test "Builder fetches a real nonce and produces a deserializable 0x76 tx", %{wallet: w, rpc_url: rpc} do
    {:ok, raw} =
      Builder.build_signed_transfer(
        private_key: w.private_key,
        token: @path_usd,
        recipient: w.address_bin,
        amount: 1,
        chain_id: @chain_id,
        rpc_url: rpc,
        fee_token: @path_usd
      )

    assert "0x76" <> _ = raw

    {:ok, tx} = Transaction.deserialize(raw)
    assert tx.chain_id == @chain_id
    assert [_one_call] = tx.calls
  end

  test "fetch_receipt returns :not_found error for a nonexistent tx hash", %{rpc_url: rpc} do
    fake_hash = "0x" <> String.duplicate("de", 32)
    assert {:error, "Transaction not found on-chain"} = RPC.fetch_receipt(fake_hash, rpc)
  end

  test "broadcast_sync confirms a self-transfer of 1 micro-pathUSD", %{wallet: w, rpc_url: rpc} do
    {:ok, raw} =
      Builder.build_signed_transfer(
        private_key: w.private_key,
        token: @path_usd,
        recipient: w.address_bin,
        amount: 1,
        chain_id: @chain_id,
        rpc_url: rpc,
        fee_token: @path_usd
      )

    assert {:ok, "0x" <> _hash, %{status: 1, logs: logs}} = RPC.broadcast_sync(raw, rpc)
    refute Enum.empty?(logs)
  end

  test "cold transfer to a fresh recipient confirms with auto-estimated gas", %{wallet: w, rpc_url: rpc} do
    # Fresh recipient => cold storage init on the transfer path, where a static
    # 500k default OOG-reverts. With :gas_limit omitted the Builder estimates per
    # tx via eth_estimateGas (+headroom), so the cold transfer must confirm.
    fresh_recipient = :crypto.strong_rand_bytes(20)

    {:ok, raw} =
      Builder.build_signed_transfer(
        private_key: w.private_key,
        token: @path_usd,
        recipient: fresh_recipient,
        amount: 1,
        chain_id: @chain_id,
        rpc_url: rpc,
        fee_token: @path_usd
      )

    assert {:ok, "0x" <> _hash, %{status: 1}} = RPC.broadcast_sync(raw, rpc)
  end

  test "simulate of a co-signed transferWithMemo succeeds with adequate gas", %{wallet: w, rpc_url: rpc} do
    cosigned = cosigned_transfer_with_memo(w, rpc, gas_limit: nil)

    # adequate gas (auto-estimated with headroom) → the tx would succeed on-chain.
    case RPC.simulate(cosigned, rpc) do
      {:ok, :success} ->
        :ok

      {:ok, :unsupported} ->
        flunk("Moderato did not implement eth_simulateV1; the wire format cannot be verified")

      other ->
        flunk("Expected {:ok, :success} for a well-funded transfer, got: #{inspect(other)}")
    end
  end

  test "simulate of a co-signed transferWithMemo fails when gas is too low", %{wallet: w, rpc_url: rpc} do
    # 21_000 is far below what a TIP-20 transfer on Tempo needs (~280k), so the
    # node rejects the under-gassed transaction as invalid (`eth_simulateV1`
    # error -38013 "intrinsic gas too low"), which simulate/3 reports as a revert.
    # This is exactly the gas-draining DoS the pre-broadcast check defends against:
    # a client under-sizes gas_limit so the tx cannot succeed, and the fee payer
    # would otherwise pay gas for a transaction that goes nowhere.
    cosigned = cosigned_transfer_with_memo(w, rpc, gas_limit: 21_000)

    case RPC.simulate(cosigned, rpc) do
      {:ok, {:revert, _detail}} ->
        :ok

      {:ok, :unsupported} ->
        flunk("Moderato did not implement eth_simulateV1; the wire format cannot be verified")

      other ->
        flunk("Expected {:ok, {:revert, _}} for an under-gassed transfer, got: #{inspect(other)}")
    end
  end

  # Builds a real fee-payer co-signed transferWithMemo from the funded wallet.
  # A random fee-payer key is fine: with `validation: false` the node does not
  # verify signatures or the fee payer's balance during simulation.
  defp cosigned_transfer_with_memo(wallet, rpc, opts) do
    memo = :crypto.strong_rand_bytes(32)
    calldata = TIP20.transfer_with_memo_calldata(wallet.address_bin, 1, memo)
    call = [@path_usd, <<>>, calldata]

    build_opts =
      then([private_key: wallet.private_key, calls: [call], chain_id: @chain_id, rpc_url: rpc], fn base ->
        case Keyword.get(opts, :gas_limit) do
          nil -> base
          gas -> Keyword.put(base, :gas_limit, gas)
        end
      end)

    {:ok, raw} = Builder.build_fee_payer_multicall(build_opts)
    {:ok, tx} = Transaction.deserialize(raw)
    {:ok, cosigned} = Transaction.cosign_fee_payer(tx, :crypto.strong_rand_bytes(32), @path_usd)
    cosigned.raw
  end
end
