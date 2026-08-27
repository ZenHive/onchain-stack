defmodule Onchain.ERC1155Test do
  # async: false — EthCallStub mutates global :cartouche, Cartouche.RPC config
  use ExUnit.Case, async: false
  use Onchain.EthCallStub

  alias Onchain.ERC1155

  # Valid address for param validation tests (doesn't need to be a real contract)
  @valid_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

  describe "balance_of/4" do
    test "returns error for invalid owner address" do
      assert {:error, {:invalid_address, "not_an_address"}} =
               ERC1155.balance_of(@valid_address, "not_an_address", 1)
    end

    test "returns error for invalid contract address" do
      {:ok, owner_bin} = Onchain.Address.validate(@valid_address)

      assert {:error, {:invalid_address, "bad_contract"}} =
               ERC1155.balance_of("bad_contract", owner_bin, 1)
    end
  end

  describe "balance_of!/4" do
    test "raises on invalid owner address" do
      assert_raise RuntimeError, ~r/balance_of failed/, fn ->
        ERC1155.balance_of!(@valid_address, "not_an_address", 1)
      end
    end
  end

  describe "balance_of_batch/4" do
    test "returns error when owners is not a list" do
      assert {:error, {:invalid_input, _}} =
               ERC1155.balance_of_batch(@valid_address, "single_address", [1])
    end

    test "returns error when token_ids is not a list" do
      assert {:error, {:invalid_input, _}} =
               ERC1155.balance_of_batch(@valid_address, [@valid_address], 1)
    end

    test "returns error when owners and token_ids have different lengths" do
      assert {:error, {:length_mismatch, %{owners: 2, token_ids: 1}}} =
               ERC1155.balance_of_batch(@valid_address, [@valid_address, @valid_address], [1])
    end

    test "returns error for invalid owner address in batch" do
      assert {:error, {:invalid_address, "bad_owner"}} =
               ERC1155.balance_of_batch(@valid_address, ["bad_owner"], [1])
    end

    test "returns error for invalid contract address" do
      {:ok, addr_bin} = Onchain.Address.validate(@valid_address)

      assert {:error, {:invalid_address, "bad_contract"}} =
               ERC1155.balance_of_batch("bad_contract", [addr_bin], [1])
    end
  end

  describe "balance_of_batch!/4" do
    test "raises on length mismatch" do
      assert_raise RuntimeError, ~r/balance_of_batch failed/, fn ->
        ERC1155.balance_of_batch!(@valid_address, [@valid_address, @valid_address], [1])
      end
    end
  end

  describe "uri/3" do
    test "returns error for invalid contract address" do
      assert {:error, {:invalid_address, "bad_contract"}} =
               ERC1155.uri("bad_contract", 1)
    end
  end

  describe "uri!/3" do
    test "raises on invalid contract address" do
      assert_raise RuntimeError, ~r/uri failed/, fn ->
        ERC1155.uri!("bad_contract", 1)
      end
    end
  end

  describe "approved_for_all?/4" do
    test "returns error for invalid owner address" do
      assert {:error, {:invalid_address, "bad_owner"}} =
               ERC1155.approved_for_all?(@valid_address, "bad_owner", @valid_address)
    end

    test "returns error for invalid operator address" do
      assert {:error, {:invalid_address, "bad_operator"}} =
               ERC1155.approved_for_all?(@valid_address, @valid_address, "bad_operator")
    end

    test "returns error for invalid contract address" do
      {:ok, addr_bin} = Onchain.Address.validate(@valid_address)

      assert {:error, {:invalid_address, "bad_contract"}} =
               ERC1155.approved_for_all?("bad_contract", addr_bin, addr_bin)
    end

    test "returns the decoded approval bool on success" do
      Onchain.EthCallStub.queue_response("bool", true)

      assert {:ok, true} =
               ERC1155.approved_for_all?(@valid_address, @valid_address, @valid_address, rpc_url: "http://stub.invalid")
    end
  end

  describe "approved_for_all!/4" do
    test "raises on invalid owner address" do
      assert_raise RuntimeError, ~r/approved_for_all\? failed/, fn ->
        ERC1155.approved_for_all!(@valid_address, "bad_owner", @valid_address)
      end
    end

    test "returns the decoded approval bool on success" do
      Onchain.EthCallStub.queue_response("bool", true)

      assert true =
               ERC1155.approved_for_all!(@valid_address, @valid_address, @valid_address, rpc_url: "http://stub.invalid")
    end
  end
end
