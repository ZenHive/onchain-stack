defmodule Onchain.RPC.CodeIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.RPC

  @moduletag :integration

  # WETH contract on mainnet — guaranteed to have bytecode
  @weth_address "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

  # Vitalik's address — well-known EOA
  @eoa_address "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"

  @test_block 20_000_000

  defp rpc_opts, do: [rpc_url: Onchain.RPCCase.rpc_url!()]

  describe "eth_get_code/2" do
    test "returns bytecode for known contract (WETH)" do
      assert {:ok, code} = RPC.eth_get_code(@weth_address, rpc_opts())
      assert is_binary(code)
      assert String.starts_with?(code, "0x")
      # WETH has substantial bytecode
      assert byte_size(code) > 2
    end

    test "returns 0x for known EOA" do
      # Query at historical block — EOAs can gain code via EIP-7702 delegation
      opts = Keyword.put(rpc_opts(), :block, @test_block)
      assert {:ok, "0x"} = RPC.eth_get_code(@eoa_address, opts)
    end

    test "accepts :block option" do
      opts = Keyword.put(rpc_opts(), :block, @test_block)
      assert {:ok, code} = RPC.eth_get_code(@weth_address, opts)
      assert is_binary(code)
      assert String.starts_with?(code, "0x")
      assert byte_size(code) > 2
    end
  end

  describe "eth_get_code!/2" do
    test "returns bytecode directly" do
      code = RPC.eth_get_code!(@weth_address, rpc_opts())
      assert is_binary(code)
      assert byte_size(code) > 2
    end

    test "returns 0x for EOA without raising" do
      # Query at historical block — EOAs can gain code via EIP-7702 delegation
      opts = Keyword.put(rpc_opts(), :block, @test_block)
      assert "0x" == RPC.eth_get_code!(@eoa_address, opts)
    end
  end
end
