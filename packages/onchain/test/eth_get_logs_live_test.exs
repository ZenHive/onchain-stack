defmodule Onchain.RPC.EthGetLogsLiveTest do
  use ExUnit.Case, async: false

  import Onchain.Test.Live

  alias Onchain.Filter.Log

  @moduletag :integration

  # USDC Transfer in mainnet block 18_000_000, log index 8.
  # Observed 2026-09-30 on the archive node, Alchemy, and Infura: 13 logs in that
  # one-block filter, this log first.
  @usdc_address Base.decode16!("a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", case: :lower)
  @transfer_topic Base.decode16!("ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef", case: :lower)
  @known_tx Base.decode16!("6742cd57e6aefce4b96887bb3090371ac49414c6b45a21e43d9e41e0ea9ed5ab", case: :lower)
  @known_block 18_000_000

  @one_block %{
    address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    topics: ["0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"],
    from_block: @known_block,
    to_block: @known_block
  }

  # Inclusive 18_000_000..18_000_010 is 11 blocks. Alchemy's free tier caps
  # eth_getLogs at 10. Observed 2026-09-30, HTTP 400, code -32600. The suggested
  # window is computed from fromBlock and is stable for this range.
  @over_cap %{@one_block | to_block: 18_000_010}

  @alchemy_range_cap "Under the Free tier plan, you can make eth_getLogs requests with up to a 10 block range. " <>
                       "Based on your parameters, this block range should work: [0x112a880, 0x112a889]. " <>
                       "Upgrade to PAYG for expanded block range."

  test "one-block USDC logs succeed on archive and Alchemy" do
    assert_portability!(fn opts -> Onchain.RPC.eth_get_logs(@one_block, opts) end,
      archive: &known_usdc_transfer?/1,
      alchemy: &known_usdc_transfer?/1
    )
  end

  test "an 11-block USDC range succeeds on archive and records Alchemy's block-range cap" do
    assert_portability!(fn opts -> Onchain.RPC.eth_get_logs(@over_cap, opts) end,
      archive: &archive_range_logs?/1,
      alchemy: &alchemy_range_cap?/1
    )
  end

  defp known_usdc_transfer?({:ok, logs}) when is_list(logs) do
    Enum.any?(logs, fn
      %Log{
        address: @usdc_address,
        block_number: @known_block,
        log_index: 8,
        transaction_hash: @known_tx,
        topics: [@transfer_topic | _],
        removed: false
      } ->
        true

      _ ->
        false
    end)
  end

  defp known_usdc_transfer?(_answer), do: false

  defp archive_range_logs?({:ok, logs}) when is_list(logs) and logs != [] do
    Enum.all?(logs, fn
      %Log{block_number: block} -> block in @known_block..18_000_010
      _ -> false
    end)
  end

  defp archive_range_logs?(_answer), do: false

  defp alchemy_range_cap?({:error, %Req.Response{status: 400, body: body}}) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"code" => -32_600, "message" => @alchemy_range_cap}}} -> true
      _ -> false
    end
  end

  defp alchemy_range_cap?(_answer), do: false
end
