defmodule Onchain.Tempo.Integration.SigningInvariantsTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias Cartouche.Hash
  alias Onchain.RPC
  alias Onchain.Tempo.Faucet
  alias Onchain.Tempo.RPC, as: TempoRPC
  alias Onchain.Tempo.Transaction
  alias Onchain.Tempo.Transaction.Builder

  @moduletag :integration

  @path_usd Base.decode16!("20c0000000000000000000000000000000000000", case: :lower)
  @chain_id 42_431

  setup do
    case Faucet.fresh_funded_wallet() do
      {:ok, wallet} ->
        {:ok, wallet: wallet, rpc_url: Faucet.rpc_url()}

      {:error, reason} ->
        flunk("""
        Could not fund a Moderato testnet wallet: #{reason}

        These tests require Moderato to be reachable and tempo_fundAddress
        to succeed. Override the RPC URL with TEMPO_RPC_URL if needed.
        """)
    end
  end

  test "live success: keccak(raw) is the tx hash and recovered sender is receipt.from", %{
    wallet: w,
    rpc_url: rpc
  } do
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

    {:ok, tx} = Transaction.deserialize(raw)
    {:ok, sender} = Transaction.sender(tx)
    assert sender == w.address_bin
    assert tx_hash(raw) == keccak_raw(raw)

    assert {:ok, hash, %{status: 1}} = TempoRPC.broadcast_sync(raw, rpc)
    assert hash == keccak_raw(raw)

    assert {:ok, onchain} = RPC.get_transaction_by_hash(hash, rpc_url: rpc)
    assert onchain.type == 0x76
    assert onchain.chain_id == @chain_id
    assert normalize_addr(onchain.from) == "0x" <> Base.encode16(sender, case: :lower)
    assert onchain.hash == hash
  end

  test "live error: malformed 0x76 envelope is rejected", %{rpc_url: rpc} do
    case TempoRPC.broadcast_async("0x76ff", rpc) do
      {:error, msg} ->
        assert msg =~ "failed to decode signed transaction" or msg =~ "-32602"

      other ->
        flunk("expected a decode error for 0x76ff, got: #{inspect(other)}")
    end
  end

  defp keccak_raw("0x" <> hex) do
    {:ok, bin} = Base.decode16(hex, case: :mixed)
    "0x" <> Base.encode16(Hash.keccak(bin), case: :lower)
  end

  defp tx_hash(raw), do: keccak_raw(raw)

  defp normalize_addr("0x" <> rest), do: "0x" <> String.downcase(rest)
  defp normalize_addr(<<addr::binary-size(20)>>), do: "0x" <> Base.encode16(addr, case: :lower)
  defp normalize_addr(other) when is_binary(other), do: String.downcase(other)
end
