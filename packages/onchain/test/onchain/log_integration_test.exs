defmodule Onchain.Log.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Log
  alias Onchain.RPC

  @moduletag :integration

  @usdc_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @transfer_topic "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

  defp rpc_opts, do: [rpc_url: Onchain.RPCCase.rpc_url!()]

  describe "decode_event/2 with real logs" do
    test "decodes a fetched USDC Transfer log" do
      {:ok, latest} = RPC.block_number(rpc_opts())

      filter = %{
        address: @usdc_address,
        topics: [@transfer_topic],
        from_block: latest - 5,
        to_block: latest
      }

      {:ok, logs} = RPC.eth_get_logs(filter, rpc_opts())
      assert logs != [], "Expected at least one USDC Transfer log in last 10 blocks"

      log = hd(logs)
      signature = "Transfer(address indexed from, address indexed to, uint256 value)"

      assert {:ok, decoded} = Log.decode_event(log, signature)
      assert is_map(decoded)

      # from and to should be checksummed addresses
      assert String.starts_with?(decoded.from, "0x")
      assert String.starts_with?(decoded.to, "0x")
      assert byte_size(decoded.from) == 42
      assert byte_size(decoded.to) == 42

      # value should be a non-negative integer
      assert is_integer(decoded.value)
      assert decoded.value >= 0
    end
  end
end
