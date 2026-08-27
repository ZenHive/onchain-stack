defmodule Onchain.Contract.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Contract

  @moduletag :integration

  # USDC on Ethereum mainnet
  @usdc_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

  # Known USDC holder — Circle's treasury (holds large USDC balance)
  @usdc_holder "0x55FE002aefF02F77364de339a1292923A15844B8"

  defp rpc_opts do
    [rpc_url: Onchain.RPCCase.rpc_url!()]
  end

  describe "call/5 with ERC-20 balanceOf" do
    test "returns decoded balance for known USDC holder" do
      {:ok, holder_bin} = Onchain.Address.validate(@usdc_holder)

      {:ok, [balance]} =
        Contract.call(
          @usdc_address,
          "balanceOf(address)",
          [holder_bin],
          "(uint256)",
          rpc_opts()
        )

      assert is_integer(balance)
      assert balance > 0, "Expected USDC holder to have balance > 0, got #{balance}"
    end
  end

  describe "call/5 with ERC-20 decimals" do
    test "returns 6 for USDC decimals (no params)" do
      {:ok, [decimals]} =
        Contract.call(
          @usdc_address,
          "decimals()",
          [],
          "(uint8)",
          rpc_opts()
        )

      assert decimals == 6
    end
  end

  describe "call/5 with binary address" do
    test "accepts 20-byte binary contract address" do
      {:ok, usdc_bin} = Onchain.Address.validate(@usdc_address)

      {:ok, [decimals]} =
        Contract.call(
          usdc_bin,
          "decimals()",
          [],
          "(uint8)",
          rpc_opts()
        )

      assert decimals == 6
    end
  end

  describe "call!/5" do
    test "returns values directly for known contract" do
      [decimals] =
        Contract.call!(
          @usdc_address,
          "decimals()",
          [],
          "(uint8)",
          rpc_opts()
        )

      assert decimals == 6
    end
  end

  describe "call/5 error cases" do
    test "returns error for call to non-contract address" do
      # EOA address — eth_call to a non-contract returns empty data
      eoa = "0x0000000000000000000000000000000000000001"

      result =
        Contract.call(
          eoa,
          "decimals()",
          [],
          "(uint8)",
          rpc_opts()
        )

      # eth_call to a non-contract typically returns 0x → ABI decode failure,
      # but some RPC providers return an RPC error directly
      case result do
        {:error, {:decode_error, _}} -> :ok
        {:error, {:rpc_error, _}} -> :ok
        {:error, other} -> flunk("Unexpected error type: #{inspect(other)}")
        {:ok, _} -> flunk("Expected error for call to non-contract address")
      end
    end
  end
end
