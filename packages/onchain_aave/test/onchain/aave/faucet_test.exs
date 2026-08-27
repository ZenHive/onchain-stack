defmodule Onchain.Aave.FaucetTest do
  use ExUnit.Case, async: false

  alias Onchain.Aave.Contracts
  alias Onchain.Aave.Faucet
  alias Onchain.Address
  alias Onchain.RPCStub

  # Known valid Sepolia addresses (checksummed)
  @valid_token "0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c"
  @valid_to "0x1234567890AbcdEF1234567890aBcdef12345678"

  # Canned eth_sendRawTransaction result for the offline write path
  @tx_hash "0x2222222222222222222222222222222222222222222222222222222222222222"

  @mint_amount 1_000

  # First 4 bytes of keccak256("mint(address,address,uint256)")
  @mint_selector <<0xC6, 0xC3, 0xBB, 0xE6>>

  describe "mint/4" do
    test "returns error for invalid token address" do
      assert {:error, {:invalid_address, "not_an_address"}} =
               Faucet.mint("not_an_address", @valid_to, 1000, network: :sepolia)
    end

    test "returns error for invalid recipient address" do
      assert {:error, {:invalid_address, "bad"}} =
               Faucet.mint(@valid_token, "bad", 1000, network: :sepolia)
    end

    test "returns error when faucet not available on network" do
      assert {:error, {:unknown_contract, :faucet}} =
               Faucet.mint(@valid_token, @valid_to, 1000, network: :ethereum)
    end

    test "returns error for all mainnet networks" do
      for network <- [:ethereum, :arbitrum, :optimism, :base, :polygon, :avalanche] do
        assert {:error, {:unknown_contract, :faucet}} =
                 Faucet.mint(@valid_token, @valid_to, 1000, network: network),
               "Expected :unknown_contract error for #{network}"
      end
    end

    test "returns tx hash on successful mint" do
      seen = start_supervised!({Agent, fn -> [] end})
      url = RPCStub.start(RPCStub.send_tx_handler(@tx_hash, seen))

      assert {:ok, tx_hash} =
               Faucet.mint(
                 @valid_token,
                 @valid_to,
                 1000,
                 RPCStub.write_opts(url, network: :sepolia)
               )

      assert tx_hash == @tx_hash

      # Verify the signer broadcast an EIP-1559 tx (0x02 prefix)
      assert [raw] = Agent.get(seen, & &1)
      assert String.starts_with?(raw, "0x02")
    end

    test "addresses the Sepolia faucet contract with mint(address,address,uint256) calldata" do
      {to, calldata, _opts} =
        Onchain.TraceCase.capture_signer_call(fn ->
          Faucet.mint(@valid_token, @valid_to, @mint_amount, network: :sepolia)
        end)

      {:ok, faucet_addr} = Contracts.address(:faucet, network: :sepolia)
      assert to == faucet_addr

      {:ok, token_bin} = Address.validate(@valid_token)
      {:ok, to_bin} = Address.validate(@valid_to)

      assert <<@mint_selector::binary, args::binary>> = calldata
      assert args == pad_left(token_bin) <> pad_left(to_bin) <> <<@mint_amount::256>>
    end
  end

  describe "mint!/4" do
    test "raises on invalid token address" do
      assert_raise RuntimeError, ~r/invalid_address/, fn ->
        Faucet.mint!("not_an_address", @valid_to, 1000, network: :sepolia)
      end
    end

    test "raises when faucet not available on network" do
      assert_raise RuntimeError, ~r/unknown_contract/, fn ->
        Faucet.mint!(@valid_token, @valid_to, 1000, network: :ethereum)
      end
    end

    test "returns tx hash unwrapped on successful mint" do
      seen = start_supervised!({Agent, fn -> [] end})
      url = RPCStub.start(RPCStub.send_tx_handler(@tx_hash, seen))

      assert @tx_hash ==
               Faucet.mint!(
                 @valid_token,
                 @valid_to,
                 1000,
                 RPCStub.write_opts(url, network: :sepolia)
               )

      # Verify the signer broadcast an EIP-1559 tx (0x02 prefix)
      assert [raw] = Agent.get(seen, & &1)
      assert String.starts_with?(raw, "0x02")
    end

    test "raises with mint failed message on error" do
      assert_raise RuntimeError, ~r/mint failed.*missing_option/, fn ->
        Faucet.mint!(@valid_token, @valid_to, @mint_amount, network: :sepolia)
      end
    end
  end

  @doc false
  # Left-pads a binary to 32 bytes for ABI argument comparison.
  defp pad_left(bin) when byte_size(bin) <= 32 do
    padding_size = 32 - byte_size(bin)
    <<0::size(padding_size * 8), bin::binary>>
  end
end
