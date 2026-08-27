defmodule Onchain.ENSIntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.ENS

  @moduletag :integration

  @vitalik_address "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"

  defp rpc_opts, do: [rpc_url: Onchain.RPCCase.rpc_url!()]

  describe "resolver/2" do
    test "returns resolver address for vitalik.eth" do
      assert {:ok, resolver} = ENS.resolver("vitalik.eth", rpc_opts())
      assert is_binary(resolver)
      assert String.starts_with?(resolver, "0x")
      assert String.length(resolver) == 42
    end

    test "returns no_resolver for non-existent name" do
      assert {:error, {:no_resolver, _}} =
               ENS.resolver("thisnamedoesnotexist12345678.eth", rpc_opts())
    end
  end

  describe "resolver!/2" do
    test "returns resolver address directly" do
      resolver = ENS.resolver!("vitalik.eth", rpc_opts())
      assert is_binary(resolver)
      assert String.starts_with?(resolver, "0x")
      assert String.length(resolver) == 42
    end
  end

  describe "resolve/2" do
    test "resolves vitalik.eth to known address" do
      assert {:ok, @vitalik_address} = ENS.resolve("vitalik.eth", rpc_opts())
    end

    test "handles case-insensitive names" do
      assert {:ok, @vitalik_address} = ENS.resolve("Vitalik.ETH", rpc_opts())
    end

    test "returns no_resolver for non-existent name" do
      assert {:error, {:no_resolver, _}} =
               ENS.resolve("thisnamedoesnotexist12345678.eth", rpc_opts())
    end
  end

  describe "resolve!/2" do
    test "returns address directly" do
      assert @vitalik_address == ENS.resolve!("vitalik.eth", rpc_opts())
    end
  end

  describe "address/3 (multi-coin, ENSIP-9/10)" do
    # Exercises the live ENSIP-10 extended-resolver path end to end: wildcard
    # resolver discovery -> supportsInterface(0x9061b923) -> resolve(dnsName,
    # addr(node, coinType)). The EIP-3668 CCIP-Read round-trip itself is covered
    # offline in test/onchain/ens_ccip_test.exs.
    test "resolves vitalik.eth ETH address (coin type 60) to raw bytes" do
      expected = Onchain.Hex.decode!(@vitalik_address)
      assert {:ok, ^expected} = ENS.address("vitalik.eth", 60, rpc_opts())
    end

    test "address!/3 returns the raw bytes directly" do
      expected = Onchain.Hex.decode!(@vitalik_address)
      assert ^expected = ENS.address!("vitalik.eth", 60, rpc_opts())
    end

    test "returns no_address for a non-existent name" do
      # address/3 takes the ENSIP-10 wildcard path, which finds a (wildcard) resolver
      # and then gets empty addr(node, 60) bytes -> {:no_address, _}. Distinct from the
      # non-wildcard resolver/2 + resolve/2 paths, which return {:no_resolver, _}.
      assert {:error, {:no_address, _}} =
               ENS.address("thisnamedoesnotexist12345678.eth", 60, rpc_opts())
    end
  end

  describe "reverse/2" do
    test "resolves vitalik's address back to vitalik.eth" do
      assert {:ok, "vitalik.eth"} = ENS.reverse(@vitalik_address, rpc_opts())
    end

    test "accepts lowercase address" do
      lower = String.downcase(@vitalik_address)
      assert {:ok, "vitalik.eth"} = ENS.reverse(lower, rpc_opts())
    end

    test "rejects invalid address" do
      assert {:error, {:invalid_address, "not_an_address"}} = ENS.reverse("not_an_address")
    end
  end

  describe "reverse!/2" do
    test "returns name directly" do
      assert "vitalik.eth" == ENS.reverse!(@vitalik_address, rpc_opts())
    end
  end

  describe "text!/3" do
    test "retrieves text record directly or raises" do
      case ENS.text("vitalik.eth", "avatar", rpc_opts()) do
        {:ok, _} ->
          avatar = ENS.text!("vitalik.eth", "avatar", rpc_opts())
          assert is_binary(avatar)

        {:error, {:empty_record, _}} ->
          assert_raise RuntimeError, ~r/text lookup failed/, fn ->
            ENS.text!("vitalik.eth", "nonexistent_key_xyz123", rpc_opts())
          end
      end
    end
  end

  describe "text/3" do
    test "retrieves avatar text record for vitalik.eth" do
      case ENS.text("vitalik.eth", "avatar", rpc_opts()) do
        {:ok, avatar} ->
          assert is_binary(avatar)
          assert avatar != ""

        {:error, {:empty_record, _}} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end

    test "retrieves url text record for vitalik.eth" do
      case ENS.text("vitalik.eth", "url", rpc_opts()) do
        {:ok, url} ->
          assert is_binary(url)
          assert url != ""

        {:error, {:empty_record, _}} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end

    test "returns empty_record for non-existent key" do
      assert {:error, {:empty_record, {"vitalik.eth", "nonexistent_key_xyz123"}}} =
               ENS.text("vitalik.eth", "nonexistent_key_xyz123", rpc_opts())
    end
  end

  describe "contenthash!/2" do
    test "retrieves contenthash directly when set" do
      case ENS.contenthash("vitalik.eth", rpc_opts()) do
        {:ok, _} ->
          hash = ENS.contenthash!("vitalik.eth", rpc_opts())
          assert is_binary(hash)
          assert byte_size(hash) > 0

        {:error, {:empty_record, _}} ->
          # Raise path covered by unit tests; integration test is opportunistic
          :ok
      end
    end
  end

  describe "contenthash/2" do
    test "retrieves contenthash for a name that has one set" do
      case ENS.contenthash("vitalik.eth", rpc_opts()) do
        {:ok, hash} ->
          assert is_binary(hash)
          assert byte_size(hash) > 0

        {:error, {:empty_record, _}} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end
  end

  describe "pubkey!/2" do
    test "retrieves pubkey directly when set" do
      case ENS.pubkey("vitalik.eth", rpc_opts()) do
        {:ok, _} ->
          {x, y} = ENS.pubkey!("vitalik.eth", rpc_opts())
          assert byte_size(x) == 32
          assert byte_size(y) == 32

        {:error, {:empty_record, _}} ->
          # Raise path covered by unit tests; integration test is opportunistic
          :ok
      end
    end
  end

  describe "pubkey/2" do
    test "retrieves pubkey or returns empty for vitalik.eth" do
      case ENS.pubkey("vitalik.eth", rpc_opts()) do
        {:ok, {x, y}} ->
          assert byte_size(x) == 32
          assert byte_size(y) == 32

        {:error, {:empty_record, _}} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end
  end

  describe "abi!/3" do
    test "queries ABI record directly when set" do
      case ENS.abi("vitalik.eth", 1, rpc_opts()) do
        {:ok, _} ->
          {content_type, data} = ENS.abi!("vitalik.eth", 1, rpc_opts())
          assert is_integer(content_type)
          assert is_binary(data)

        {:error, {:empty_record, _}} ->
          # Raise path covered by unit tests; integration test is opportunistic
          :ok
      end
    end
  end

  describe "abi/3" do
    test "queries ABI record for vitalik.eth" do
      case ENS.abi("vitalik.eth", 1, rpc_opts()) do
        {:ok, {content_type, data}} ->
          assert is_integer(content_type)
          assert is_binary(data)

        {:error, {:empty_record, _}} ->
          :ok

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
    end
  end
end
