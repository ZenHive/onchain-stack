defmodule Onchain.Sleuth.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.Contract
  alias Onchain.Sleuth

  @moduletag :integration

  # USDC on Ethereum mainnet
  @usdc "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  # Vitalik's address — long-held account, always non-zero on mainnet
  @vitalik "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"

  # Creation bytecode for test/fixtures/sleuth_balance_query.sol:
  # constructor(address token, address who) that staticcall's balanceOf
  # and returns the raw bytes. Compiled via `solc --optimize --bin`.
  @balance_query_bytecode "test/fixtures/sleuth_balance_query.bin" |> File.read!() |> String.trim()

  defp rpc_opts, do: [rpc_url: Onchain.RPCCase.rpc_url!()]

  defp address_bin(hex) do
    {:ok, bin} = Onchain.Address.validate(hex)
    bin
  end

  describe "query/5 against live mainnet" do
    test "reads USDC.balanceOf via deploy-as-call and matches direct Contract.call" do
      opts = rpc_opts()

      assert {:ok, [sleuth_balance]} =
               Sleuth.query(
                 @balance_query_bytecode,
                 "(address,address)",
                 {address_bin(@usdc), address_bin(@vitalik)},
                 "(uint256)",
                 opts
               )

      assert is_integer(sleuth_balance)
      assert sleuth_balance >= 0

      {:ok, [direct_balance]} =
        Contract.call(@usdc, "balanceOf(address)", [address_bin(@vitalik)], "(uint256)", opts)

      assert sleuth_balance == direct_balance
    end

    test "query!/5 returns the balance list directly" do
      opts = rpc_opts()

      assert [balance] =
               Sleuth.query!(
                 @balance_query_bytecode,
                 "(address,address)",
                 {address_bin(@usdc), address_bin(@vitalik)},
                 "(uint256)",
                 opts
               )

      assert is_integer(balance)
    end

    test "accepts :block option" do
      opts = rpc_opts()

      {:ok, latest} = Onchain.RPC.block_number(opts)
      # A few blocks back — still on an archive node, non-zero balance historically
      historic_block = latest - 10

      assert {:ok, [balance]} =
               Sleuth.query(
                 @balance_query_bytecode,
                 "(address,address)",
                 {address_bin(@usdc), address_bin(@vitalik)},
                 "(uint256)",
                 Keyword.put(opts, :block, historic_block)
               )

      assert is_integer(balance)
    end
  end
end
