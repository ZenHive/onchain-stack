defmodule Onchain.TransferIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Transfer

  @moduletag :integration

  # USDC contract on Ethereum mainnet
  @usdc_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

  describe "fetch/2" do
    test "fetches real USDC Transfer events from mainnet" do
      rpc_url = Onchain.RPCCase.rpc_url!()

      # Fetch a small range of recent-ish blocks known to have USDC transfers
      # Block 18_000_000 is from Sept 2023 — guaranteed to have USDC activity
      filter = %{
        address: @usdc_address,
        topics: [hd(Transfer.transfer_topics())],
        from_block: 18_000_000,
        to_block: 18_000_009
      }

      assert {:ok, transfers} = Transfer.fetch(filter, rpc_url: rpc_url)
      assert is_list(transfers)

      # Block 18_000_000-18_000_009 has USDC transfers on any archive node.
      # If empty, the RPC may be pruning old logs.
      # Range is 10 blocks (Alchemy free tier limit).
      assert transfers != [], "Expected USDC transfers in block range 18M-18M+9"

      transfer = hd(transfers)
      assert %Transfer{} = transfer
      assert transfer.token_standard == :erc20
      assert is_integer(transfer.amount)
      assert transfer.amount >= 0
      assert transfer.token_id == nil
      assert String.starts_with?(transfer.from, "0x")
      assert String.starts_with?(transfer.to, "0x")
      assert String.starts_with?(transfer.transaction_hash, "0x")
      assert transfer.block_number >= 18_000_000
      assert transfer.block_number <= 18_000_009
      # Token address should be checksummed USDC
      assert transfer.token == Onchain.Address.checksum!(@usdc_address)
    end
  end

  describe "parse_logs/1 with real data" do
    test "parses raw logs fetched via eth_get_logs" do
      rpc_url = Onchain.RPCCase.rpc_url!()

      filter = %{
        address: @usdc_address,
        topics: [hd(Transfer.transfer_topics())],
        from_block: 18_000_000,
        to_block: 18_000_009
      }

      assert {:ok, logs} = Onchain.RPC.eth_get_logs(filter, rpc_url: rpc_url)
      assert {:ok, transfers} = Transfer.parse_logs(logs)

      # Every parsed transfer should be ERC-20 (USDC is ERC-20)
      assert Enum.all?(transfers, &(&1.token_standard == :erc20))
    end
  end
end
