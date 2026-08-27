defmodule Onchain.ERC1155.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.ERC1155

  @moduletag :integration

  # OpenSea Shared Storefront (Conduit) on Ethereum mainnet — large, stable ERC-1155
  @opensea_storefront "0x495f947276749Ce646f68AC8c248420045cb7b5e"

  # A known token ID from the OpenSea Shared Storefront
  # This is a high-supply edition token that should remain queryable
  @token_id 0x495F947276749CE646F68AC8C248420045CB7B5E000000000000010000000001

  # A valid address to test approval queries against
  @test_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

  defp rpc_opts do
    [rpc_url: Onchain.RPCCase.rpc_url!()]
  end

  describe "uri/3" do
    test "returns a URI string for a known token" do
      assert {:ok, uri} = ERC1155.uri(@opensea_storefront, @token_id, rpc_opts())
      assert is_binary(uri)
      assert String.length(uri) > 0
    end
  end

  describe "uri!/3" do
    test "returns URI directly" do
      uri = ERC1155.uri!(@opensea_storefront, @token_id, rpc_opts())
      assert is_binary(uri)
    end
  end

  describe "balance_of/4" do
    test "returns non-negative integer for any address/token pair" do
      assert {:ok, balance} =
               ERC1155.balance_of(@opensea_storefront, @test_address, @token_id, rpc_opts())

      assert is_integer(balance)
      assert balance >= 0
    end
  end

  describe "balance_of!/4" do
    test "returns balance directly" do
      balance = ERC1155.balance_of!(@opensea_storefront, @test_address, @token_id, rpc_opts())
      assert is_integer(balance)
      assert balance >= 0
    end
  end

  describe "balance_of_batch/4" do
    test "returns list of balances for batch query" do
      assert {:ok, balances} =
               ERC1155.balance_of_batch(
                 @opensea_storefront,
                 [@test_address, @test_address],
                 [@token_id, @token_id],
                 rpc_opts()
               )

      assert is_list(balances)
      assert [_, _] = balances
      assert Enum.all?(balances, &is_integer/1)
    end
  end

  describe "balance_of_batch!/4" do
    test "returns balances directly" do
      balances =
        ERC1155.balance_of_batch!(
          @opensea_storefront,
          [@test_address],
          [@token_id],
          rpc_opts()
        )

      assert is_list(balances)
      assert [_] = balances
    end
  end

  describe "approved_for_all?/4" do
    test "returns boolean for two addresses" do
      assert {:ok, approved} =
               ERC1155.approved_for_all?(
                 @opensea_storefront,
                 @test_address,
                 @test_address,
                 rpc_opts()
               )

      assert is_boolean(approved)
    end
  end

  describe "approved_for_all!/4" do
    test "returns boolean directly" do
      approved =
        ERC1155.approved_for_all!(
          @opensea_storefront,
          @test_address,
          @test_address,
          rpc_opts()
        )

      assert is_boolean(approved)
    end
  end
end
