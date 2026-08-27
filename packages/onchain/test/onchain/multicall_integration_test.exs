defmodule Onchain.Multicall.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Multicall

  @moduletag :integration

  # USDC on Ethereum mainnet
  @usdc "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  # WETH on Ethereum mainnet
  @weth "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

  defp rpc_opts, do: [rpc_url: Onchain.RPCCase.rpc_url!()]

  describe "call_many/2" do
    test "batches 3 ERC-20 reads: USDC symbol, USDC decimals, WETH symbol" do
      calls = [
        {@usdc, "symbol()", [], "(string)"},
        {@usdc, "decimals()", [], "(uint8)"},
        {@weth, "symbol()", [], "(string)"}
      ]

      assert {:ok, results} = Multicall.call_many(calls, rpc_opts())
      assert length(results) == 3

      assert {:ok, ["USDC"]} = Enum.at(results, 0)
      assert {:ok, [6]} = Enum.at(results, 1)
      assert {:ok, ["WETH"]} = Enum.at(results, 2)
    end

    test "handles partial failure with one bad call" do
      # Valid call + call to a non-contract address (will fail)
      zero_addr = "0x0000000000000000000000000000000000000001"

      calls = [
        {@usdc, "symbol()", [], "(string)"},
        {zero_addr, "symbol()", [], "(string)"}
      ]

      assert {:ok, results} = Multicall.call_many(calls, rpc_opts())
      assert length(results) == 2

      # First call should succeed
      assert {:ok, ["USDC"]} = Enum.at(results, 0)

      # Second call should fail (non-contract address returns empty data)
      assert {:error, _} = Enum.at(results, 1)
    end

    test "results match individual Contract.call results" do
      calls = [
        {@usdc, "symbol()", [], "(string)"},
        {@usdc, "decimals()", [], "(uint8)"}
      ]

      {:ok, multicall_results} = Multicall.call_many(calls, rpc_opts())

      # Compare with individual calls
      {:ok, individual_symbol} =
        Onchain.Contract.call(@usdc, "symbol()", [], "(string)", rpc_opts())

      {:ok, individual_decimals} =
        Onchain.Contract.call(@usdc, "decimals()", [], "(uint8)", rpc_opts())

      assert {:ok, ^individual_symbol} = Enum.at(multicall_results, 0)
      assert {:ok, ^individual_decimals} = Enum.at(multicall_results, 1)
    end
  end
end
