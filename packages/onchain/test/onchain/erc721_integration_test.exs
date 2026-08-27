defmodule Onchain.ERC721.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.ERC721

  @moduletag :integration

  # Bored Ape Yacht Club on Ethereum mainnet
  @bayc_address "0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D"

  # Token ID 0 — always exists
  @token_id 0

  defp rpc_opts do
    [rpc_url: Onchain.RPCCase.rpc_url!()]
  end

  describe "name/2" do
    test "returns collection name for BAYC" do
      assert {:ok, "BoredApeYachtClub"} = ERC721.name(@bayc_address, rpc_opts())
    end
  end

  describe "name!/2" do
    test "returns collection name for BAYC" do
      assert "BoredApeYachtClub" = ERC721.name!(@bayc_address, rpc_opts())
    end
  end

  describe "symbol/2" do
    test "returns BAYC for Bored Ape Yacht Club" do
      assert {:ok, "BAYC"} = ERC721.symbol(@bayc_address, rpc_opts())
    end
  end

  describe "symbol!/2" do
    test "returns BAYC for Bored Ape Yacht Club" do
      assert "BAYC" = ERC721.symbol!(@bayc_address, rpc_opts())
    end
  end

  describe "owner_of/3" do
    test "returns a valid checksummed address for token #0" do
      assert {:ok, owner} = ERC721.owner_of(@bayc_address, @token_id, rpc_opts())
      assert is_binary(owner)
      assert String.starts_with?(owner, "0x")
      assert String.length(owner) == 42
    end
  end

  describe "owner_of!/3" do
    test "returns owner address directly" do
      owner = ERC721.owner_of!(@bayc_address, @token_id, rpc_opts())
      assert is_binary(owner)
      assert String.starts_with?(owner, "0x")
    end
  end

  describe "balance_of/3" do
    test "returns non-negative integer for any address" do
      # Use the owner of token #0 to test balance (guaranteed to own at least 1)
      {:ok, owner} = ERC721.owner_of(@bayc_address, @token_id, rpc_opts())
      assert {:ok, balance} = ERC721.balance_of(@bayc_address, owner, rpc_opts())
      assert is_integer(balance)
      assert balance > 0, "Expected BAYC #0 owner to have balance > 0, got #{balance}"
    end
  end

  describe "balance_of!/3" do
    test "returns balance directly" do
      {:ok, owner} = ERC721.owner_of(@bayc_address, @token_id, rpc_opts())
      balance = ERC721.balance_of!(@bayc_address, owner, rpc_opts())
      assert is_integer(balance)
      assert balance > 0
    end
  end

  describe "token_uri/3" do
    test "returns IPFS URI for BAYC token #0" do
      assert {:ok, uri} = ERC721.token_uri(@bayc_address, @token_id, rpc_opts())
      assert is_binary(uri)
      assert String.starts_with?(uri, "ipfs://")
    end
  end

  describe "token_uri!/3" do
    test "returns URI directly" do
      uri = ERC721.token_uri!(@bayc_address, @token_id, rpc_opts())
      assert is_binary(uri)
      assert String.starts_with?(uri, "ipfs://")
    end
  end

  describe "get_approved/3" do
    test "returns a valid address (possibly zero address) for token #0" do
      assert {:ok, approved} = ERC721.get_approved(@bayc_address, @token_id, rpc_opts())
      assert is_binary(approved)
      assert String.starts_with?(approved, "0x")
      assert String.length(approved) == 42
    end
  end

  describe "get_approved!/3" do
    test "returns approved address directly" do
      approved = ERC721.get_approved!(@bayc_address, @token_id, rpc_opts())
      assert is_binary(approved)
      assert String.starts_with?(approved, "0x")
    end
  end

  describe "approved_for_all?/4" do
    test "returns boolean for two addresses" do
      {:ok, owner} = ERC721.owner_of(@bayc_address, @token_id, rpc_opts())

      assert {:ok, approved} =
               ERC721.approved_for_all?(@bayc_address, owner, @bayc_address, rpc_opts())

      assert is_boolean(approved)
    end
  end

  describe "approved_for_all!/4" do
    test "returns boolean directly" do
      {:ok, owner} = ERC721.owner_of(@bayc_address, @token_id, rpc_opts())
      approved = ERC721.approved_for_all!(@bayc_address, owner, @bayc_address, rpc_opts())
      assert is_boolean(approved)
    end
  end
end
