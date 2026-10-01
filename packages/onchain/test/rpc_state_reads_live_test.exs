defmodule Onchain.RPCStateReadsLiveTest do
  use ExUnit.Case, async: false

  import Onchain.Test.Live

  alias Onchain.RPC
  alias Onchain.RPC.Proof
  alias Onchain.RPC.Proof.StorageProof

  @moduletag :integration
  @address "0x6b175474e89094c44da98b954eedeac495271d0f"
  @key "0x" <> String.duplicate("0", 63) <> "1"
  @historical_value 0xC989643A2D611A5D119644B
  @code_hash Onchain.Hex.decode_word!("0x4e36f96ee1667a663dfaac57c4d185a0e369a3a217e0079d49620f34f85d1ac7")
  @storage_hash Onchain.Hex.decode_word!("0x0733ee23add2327c86b8510fd171124e97aaabce36d8d91eedbc9c61bb801880")

  setup do
    # Unlike the seam's legacy localhost default, this suite requires explicit configuration.
    if System.get_env("CARTOUCHE_LIVE_NODE_URL") in [nil, ""] do
      flunk(
        "export CARTOUCHE_LIVE_NODE_URL='http://127.0.0.1:8545'\nexport ETHEREUM_ALCHEMY_URL='https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY'"
      )
    end

    :ok
  end

  test "DAI slot 1 at mainnet block 18,000,000 returns the recorded word on both lanes" do
    assert_portability!(&RPC.eth_get_storage_at(@address, "0x1", Keyword.put(&1, :block, 18_000_000)),
      archive: &match?({:ok, <<@historical_value::256>>}, &1),
      alchemy: &match?({:ok, <<@historical_value::256>>}, &1)
    )
  end

  test "latest DAI proof contains the contract domain fields on both lanes" do
    assert_portability!(&RPC.eth_get_proof(@address, [@key], &1), archive: &dai_proof?/1, alchemy: &dai_proof?/1)
  end

  test "historical proof succeeds on Alchemy while the archive node refuses its proof window" do
    assert_portability!(&RPC.eth_get_proof(@address, [@key], Keyword.put(&1, :block, 18_000_000)),
      archive: &match?({:error, %{code: -32_602, message: "distance to target block exceeds maximum proof window"}}, &1),
      alchemy: fn answer ->
        dai_proof?(answer) and
          match?(
            {:ok, %Proof{storage_hash: @storage_hash, storage_proof: [%StorageProof{value: @historical_value}]}},
            answer
          )
      end
    )
  end

  test "before deployment Alchemy returns zero storage and an account non-existence proof" do
    assert_portability!(&RPC.eth_get_storage_at(@address, "0x1", Keyword.put(&1, :block, 1)),
      archive: &match?({:ok, <<0::256>>}, &1),
      alchemy: &match?({:ok, <<0::256>>}, &1)
    )

    assert_portability!(&RPC.eth_get_proof(@address, [@key], Keyword.put(&1, :block, 1)),
      archive: &match?({:error, %{code: -32_602, message: "distance to target block exceeds maximum proof window"}}, &1),
      alchemy:
        &match?(
          {:ok,
           %Proof{
             balance: 0,
             nonce: 0,
             account_proof: [_ | _],
             storage_proof: [%StorageProof{key: 1, value: 0, proof: []}]
           }},
          &1
        )
    )
  end

  test "both methods pin the observed future-block refusals" do
    assert_portability!(&RPC.eth_get_storage_at(@address, "0x1", Keyword.put(&1, :block, "0xffffffffffffffff")),
      archive: &missing_block?/1,
      alchemy: &missing_block?/1
    )

    assert_portability!(&RPC.eth_get_proof(@address, [@key], Keyword.put(&1, :block, "0xffffffffffffffff")),
      archive: &missing_block?/1,
      alchemy: &match?({:error, %{code: -32_602, message: "invalid argument 2: blocknumber too high"}}, &1)
    )
  end

  defp dai_proof?(
         {:ok,
          %Proof{
            balance: 0,
            nonce: 1,
            code_hash: @code_hash,
            storage_proof: [%StorageProof{key: 1, value: value, proof: nodes}]
          } = proof}
       ) do
    proof.address == Onchain.Hex.decode_address!(@address) and
      byte_size(proof.storage_hash) == 32 and value > 0 and nodes != [] and proof.account_proof != []
  end

  defp dai_proof?(_answer), do: false

  defp missing_block?(answer),
    do: match?({:error, %{code: -32_001, message: "block not found: 0xffffffffffffffff"}}, answer)
end
