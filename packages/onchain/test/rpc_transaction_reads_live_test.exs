defmodule Onchain.RPCTransactionReadsLiveTest do
  use ExUnit.Case, async: false

  import Onchain.Test.Live

  alias Onchain.Hex
  alias Onchain.Receipt
  alias Onchain.RPC
  alias Onchain.Transaction.Info
  alias Onchain.Transaction.V1
  alias Onchain.Transaction.V2

  @moduletag :integration

  # Observed 2026-10-01. Block 20_000_000 index 0.
  # The archive node returns `blockTimestamp`. Alchemy mainnet sometimes omits
  # the key, including across methods for one transaction, so that field may be nil.
  # The same endpoint also answers a burst of these reads with
  # `{:error, {:unavailable, %{code: -32001}}}` after about 10s, then serves the
  # identical call. Retry only that tag; the decoded body still has to match.
  @type2_hash "0xbb4b3fc2b746877dce70862850602f1d19bd890ab4db47e6b7ee1da1fe578a0d"
  @type2_block_hash "0xd24fd73f794058a3807db926d8898c6481e902b7edb91ce0d479d6760f276183"
  @type2_from "0xae2fc483527b8ef99eb5d9b44875f005ba1fae13"
  @type2_to "0x6b75d8af000000e20b7a7ddf000ba900b4009a80"
  @weth "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"

  # Legacy transaction in block 46_147. Its receipt has no `status` (pre-Byzantium);
  # the receipt assertion uses block 20_000_000.
  @legacy_hash "0x5c504ed432cb51138bcf09aa5e8a410dd4a1e204ef84bfed1be16dfba1b22060"
  @legacy_block_hash "0x4e3a3754410177e6937ef1f84bba68ea139e8d1a2258c5f85db9f1cd715a1bdd"
  @legacy_from "0xa1e4380a3b1f749673e270229993ee55f35663b4"
  @legacy_to "0x5df9b87991262f6ba471f09758cde1c0fc1de734"
  @missing_hash "0x" <> String.duplicate("00", 32)
  @type2_block 20_000_000
  @type2_receipt_count 134

  setup do
    if System.get_env("CARTOUCHE_LIVE_NODE_URL") in [nil, ""] do
      flunk(
        "export CARTOUCHE_LIVE_NODE_URL='http://127.0.0.1:8545'\nexport ETHEREUM_ALCHEMY_URL='https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY'"
      )
    end

    :ok
  end

  test "a known mainnet type-2 transaction decodes on both lanes" do
    assert_portability!(
      &until_served(fn -> RPC.eth_get_transaction_by_hash(@type2_hash, &1) end),
      archive: &type2?/1,
      alchemy: &type2?/1
    )

    assert_portability!(
      &until_served(fn -> RPC.eth_get_transaction_by_block_hash_and_index(@type2_block_hash, 0, &1) end),
      archive: &type2?/1,
      alchemy: &type2?/1
    )

    assert_portability!(
      &until_served(fn -> RPC.eth_get_transaction_by_block_number_and_index(@type2_block, 0, &1) end),
      archive: &type2?/1,
      alchemy: &type2?/1
    )
  end

  test "a known mainnet legacy transaction decodes on both lanes" do
    assert_portability!(
      &until_served(fn -> RPC.eth_get_transaction_by_hash(@legacy_hash, &1) end),
      archive: &legacy?/1,
      alchemy: &legacy?/1
    )
  end

  test "an unknown hash is not found on both lanes" do
    assert_portability!(
      &until_served(fn -> RPC.eth_get_transaction_by_hash(@missing_hash, &1) end),
      archive: &match?({:error, :not_found}, &1),
      alchemy: &match?({:error, :not_found}, &1)
    )
  end

  test "eth_getBlockReceipts for block 20_000_000 matches the single-receipt decoder on both lanes" do
    assert_portability!(
      fn opts ->
        until_served(fn ->
          with {:ok, receipts} <- RPC.eth_get_block_receipts(@type2_block, opts),
               {:ok, single} <- RPC.get_trx_receipt(@type2_hash, opts) do
            {:ok, receipts, single}
          end
        end)
      end,
      archive: &receipts?/1,
      alchemy: &receipts?/1
    )
  end

  # Alchemy's `-32001` "Unable to complete request" is a capacity blip, not a
  # refusal of the method. One immediate retry is enough (observed 2026-10-01:
  # the retry returned in 11ms after a 10s failure).
  defp until_served(fun, attempts \\ 2)
  defp until_served(fun, 1), do: fun.()

  defp until_served(fun, attempts) do
    case fun.() do
      {:error, {:unavailable, _}} -> until_served(fun, attempts - 1)
      result -> result
    end
  end

  defp type2?(
         {:ok,
          %Info{
            block_hash: block_hash,
            block_number: @type2_block,
            block_timestamp: block_timestamp,
            transaction_index: 0,
            transaction: %V2{
              chain_id: 1,
              nonce: 0x2A109E,
              gas_limit: 0x6FF2D,
              max_priority_fee_per_gas: 0,
              max_fee_per_gas: 0x12643FF14,
              amount: 0x3E987A00,
              signature_y_parity: false,
              access_list: [{weth, _} | _]
            }
          } = info}
       )
       when block_timestamp in [nil, 0x665BA27F] do
    info.hash == word(@type2_hash) and info.from == address(@type2_from) and
      block_hash == word(@type2_block_hash) and info.transaction.destination == address(@type2_to) and
      weth == address(@weth)
  end

  defp type2?(_answer), do: false

  defp legacy?(
         {:ok,
          %Info{
            block_hash: block_hash,
            block_number: 0xB443,
            block_timestamp: block_timestamp,
            transaction_index: 0,
            transaction:
              %V1{
                nonce: 0,
                gas_price: 0x2D79883D2000,
                gas_limit: 0x5208,
                value: 0x7A69,
                data: <<>>,
                v: 0x1C,
                r: 0x88FF6CF0FEFD94DB46111149AE4BFC179E9B94721FFFD821D38D16464B3F71D0,
                s: 0x45E0AFF800961CFCE805DAEF7016B9B675C137A6A41A548F7B60A3484C06A33A
              } = transaction
          } = info}
       )
       when block_timestamp in [nil, 0x55C42659] do
    info.hash == word(@legacy_hash) and info.from == address(@legacy_from) and
      block_hash == word(@legacy_block_hash) and transaction.to == address(@legacy_to)
  end

  defp legacy?(_answer), do: false

  defp receipts?({:ok, receipts, %Receipt{} = single}) when is_list(receipts) do
    hash = word(@type2_hash)

    length(receipts) == @type2_receipt_count and
      match?(
        %Receipt{transaction_hash: ^hash, transaction_index: 0, block_number: @type2_block},
        List.first(receipts)
      ) and
      Enum.find(receipts, &(&1.transaction_hash == hash)) === single
  end

  defp receipts?(_answer), do: false

  defp word(hex), do: Hex.decode_word!(hex)
  defp address(hex), do: Hex.decode_address!(hex)
end
