defmodule Onchain.RPCNodeIntrospectionLiveTest do
  use ExUnit.Case, async: false

  import Onchain.Test.Live

  @moduletag :integration

  @known_block 20_000_000
  @known_block_hash "0xd24fd73f794058a3807db926d8898c6481e902b7edb91ce0d479d6760f276183"
  @known_transaction_count 134

  # Observed on Alchemy mainnet, 2026-10-01, HTTP 400. Keep the refusal verbatim.
  @alchemy_peer_count_refusal "net_peerCount is not available on the ETH_MAINNET. For more information see our docs: https://docs.alchemy.com/alchemy/documentation/apis/ethereum"

  test "eth_syncing is false on a synced archive node and on Alchemy" do
    assert_portability!(&Onchain.RPC.eth_syncing/1,
      archive: &synced?/1,
      alchemy: &synced?/1
    )
  end

  test "tagged block transaction counts match the known mainnet block on both endpoints" do
    assert_portability!(&Onchain.RPC.eth_get_block_transaction_count_by_hash(@known_block_hash, &1),
      archive: &known_count?/1,
      alchemy: &known_count?/1
    )

    assert_portability!(&Onchain.RPC.eth_get_block_transaction_count_by_number(@known_block, &1),
      archive: &known_count?/1,
      alchemy: &known_count?/1
    )
  end

  test "net_listening returns true on archive and Alchemy" do
    assert_portability!(&Onchain.RPC.net_listening/1,
      archive: &listening?/1,
      alchemy: &listening?/1
    )
  end

  test "net_peerCount is served by the archive node and refused by Alchemy verbatim" do
    assert_portability!(&Onchain.RPC.net_peer_count/1,
      archive: &peer_count?/1,
      alchemy: &alchemy_peer_count_refusal?/1
    )
  end

  test "web3_clientVersion returns a client string on archive and Alchemy" do
    assert_portability!(&Onchain.RPC.web3_client_version/1,
      archive: &client_version?/1,
      alchemy: &client_version?/1
    )
  end

  defp synced?({:ok, false}), do: true
  defp synced?(_answer), do: false

  defp known_count?({:ok, @known_transaction_count}), do: true
  defp known_count?(_answer), do: false

  defp listening?({:ok, true}), do: true
  defp listening?(_answer), do: false

  defp peer_count?({:ok, count}) when is_integer(count) and count >= 0, do: true
  defp peer_count?(_answer), do: false

  defp alchemy_peer_count_refusal?({:error, {:method_not_found, %{code: -32_600, message: @alchemy_peer_count_refusal}}}),
    do: true

  defp alchemy_peer_count_refusal?(_answer), do: false

  defp client_version?({:ok, version}) when is_binary(version) and version != "", do: true
  defp client_version?(_answer), do: false
end
