defmodule Onchain.RPC.EthGetLogsIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.RPC

  @moduletag :integration

  # USDC on Ethereum mainnet — high-volume Transfer events
  @usdc_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @transfer_topic "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

  defp rpc_opts, do: [rpc_url: Onchain.RPCCase.rpc_url!()]

  describe "eth_get_logs/2" do
    test "fetches recent USDC Transfer events" do
      # Get a recent block to query a small range
      {:ok, latest} = RPC.block_number(rpc_opts())
      # Free Alchemy tier limits to 10-block range
      from_block = latest - 5

      filter = %{
        address: @usdc_address,
        topics: [@transfer_topic],
        from_block: from_block,
        to_block: latest
      }

      assert {:ok, logs} = RPC.eth_get_logs(filter, rpc_opts())
      assert is_list(logs)

      # USDC is high-volume — should have at least one Transfer in 5 blocks
      assert logs != [], "Expected at least one USDC Transfer log in last 5 blocks"

      # Verify log structure
      log = hd(logs)
      assert is_binary(log.address)
      assert String.starts_with?(log.address, "0x")
      assert is_list(log.topics)
      assert is_binary(log.data)
      assert is_integer(log.block_number)
      assert log.block_number >= from_block
      assert is_binary(log.transaction_hash)
      assert is_integer(log.log_index)
      assert is_integer(log.transaction_index)
      assert is_boolean(log.removed)
    end

    test "returns empty list for filter with no matches" do
      {:ok, latest} = RPC.block_number(rpc_opts())

      # Query a single block with a non-existent topic
      filter = %{
        address: @usdc_address,
        topics: ["0x0000000000000000000000000000000000000000000000000000000000000001"],
        from_block: latest,
        to_block: latest
      }

      assert {:ok, []} = RPC.eth_get_logs(filter, rpc_opts())
    end
  end

  describe "eth_get_logs!/2" do
    test "returns logs directly" do
      {:ok, latest} = RPC.block_number(rpc_opts())

      filter = %{
        address: @usdc_address,
        topics: [@transfer_topic],
        from_block: latest - 5,
        to_block: latest
      }

      logs = RPC.eth_get_logs!(filter, rpc_opts())
      assert is_list(logs)
    end
  end
end
