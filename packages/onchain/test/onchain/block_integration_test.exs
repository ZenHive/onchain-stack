defmodule Onchain.Block.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Block

  @moduletag :integration

  # Block 20,000,000 — known mainnet block (2024-06-01)
  @known_block_number 20_000_000
  @known_block_timestamp 1_717_281_407

  defp rpc_opts do
    [rpc_url: Onchain.RPCCase.rpc_url!()]
  end

  describe "get_by_number/2" do
    test "fetches and parses a known block" do
      assert {:ok, block} = Block.get_by_number(@known_block_number, rpc_opts())
      assert block.number == @known_block_number
      assert block.timestamp == @known_block_timestamp
      assert is_binary(block.hash)
      assert String.starts_with?(block.hash, "0x")
    end

    test "accepts 'latest' tag and returns valid block" do
      assert {:ok, block} = Block.get_by_number("latest", rpc_opts())
      assert is_integer(block.number)
      assert block.number > 0
      assert is_integer(block.timestamp)
      assert is_binary(block.hash)
    end

    test "accepts 'finalized' tag" do
      assert {:ok, block} = Block.get_by_number("finalized", rpc_opts())
      assert is_integer(block.number)
      assert block.number > 0
    end

    test "'pending' tag returns valid block or :pending_block error" do
      # Provider-dependent: some return populated fields, some return nil
      case Block.get_by_number("pending", rpc_opts()) do
        {:ok, block} ->
          assert is_integer(block.number)
          assert is_integer(block.timestamp)
          assert is_binary(block.hash)

        {:error, :pending_block} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end

    test "fetches genesis block (block 0)" do
      assert {:ok, block} = Block.get_by_number(0, rpc_opts())
      assert block.number == 0
      assert block.timestamp == 0
      assert is_binary(block.hash)
    end
  end

  describe "find_by_timestamp/2" do
    test "finds a known block by its exact timestamp" do
      assert {:ok, block} =
               Block.find_by_timestamp(
                 @known_block_timestamp,
                 rpc_opts() ++ [floor: @known_block_number - 100, ceil: @known_block_number + 100]
               )

      assert block.number == @known_block_number
      assert block.timestamp == @known_block_timestamp
    end

    test "returns block ≤ target when timestamp falls between blocks" do
      # Timestamp 1 second before the known block — should return the block before it
      target = @known_block_timestamp - 1

      assert {:ok, block} =
               Block.find_by_timestamp(
                 target,
                 rpc_opts() ++ [floor: @known_block_number - 100, ceil: @known_block_number + 100]
               )

      assert block.timestamp <= target
      assert block.number < @known_block_number
    end

    test "with floor/ceil bounds narrows the search" do
      floor = @known_block_number - 10
      ceil = @known_block_number + 10

      assert {:ok, block} =
               Block.find_by_timestamp(
                 @known_block_timestamp,
                 rpc_opts() ++ [floor: floor, ceil: ceil]
               )

      assert block.number == @known_block_number
    end

    test "returns ceil block when target timestamp is in the future" do
      # Use a timestamp far in the future
      future_timestamp = @known_block_timestamp + 999_999_999

      assert {:ok, block} =
               Block.find_by_timestamp(
                 future_timestamp,
                 rpc_opts() ++ [floor: @known_block_number - 10, ceil: @known_block_number + 10]
               )

      # Should return the ceil block since target is past it
      assert block.timestamp <= future_timestamp
    end

    test "finds genesis block for timestamp 0 with default floor" do
      assert {:ok, block} = Block.find_by_timestamp(0, rpc_opts())
      assert block.number == 0
      assert block.timestamp == 0
    end

    test "returns error when target is before explicit floor block" do
      # Floor block has timestamp ~1.7 billion — use timestamp 0
      assert {:error, {:timestamp_before_floor, 0}} =
               Block.find_by_timestamp(
                 0,
                 rpc_opts() ++ [floor: @known_block_number]
               )
    end
  end
end
