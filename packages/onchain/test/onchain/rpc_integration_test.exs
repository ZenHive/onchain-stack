defmodule Onchain.RPC.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.ABI
  alias Onchain.RPC

  @moduletag :integration

  @weth_address "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  @zero_address "0x0000000000000000000000000000000000000000"

  # EOA with known activity (Vitalik's address)
  @eoa_address "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"

  defp rpc_opts do
    [rpc_url: Onchain.RPCCase.rpc_url!()]
  end

  describe "block_number/1" do
    test "returns current block number as positive integer" do
      assert {:ok, block} = RPC.block_number(rpc_opts())
      assert is_integer(block)
      assert block > 0
    end
  end

  describe "chain_id/1" do
    test "returns mainnet chain ID" do
      assert {:ok, 1} = RPC.chain_id(rpc_opts())
    end
  end

  describe "get_balance/2" do
    test "returns balance for zero address as non-negative integer" do
      assert {:ok, balance} = RPC.get_balance(@zero_address, rpc_opts())
      assert is_integer(balance)
      assert balance >= 0
    end
  end

  describe "eth_call/3" do
    test "WETH totalSupply returns non-empty hex" do
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])
      assert {:ok, hex_result} = RPC.eth_call(@weth_address, calldata, rpc_opts())
      assert is_binary(hex_result)
      assert String.starts_with?(hex_result, "0x")
      # totalSupply returns data, not just "0x"
      assert byte_size(hex_result) > 2
    end

    test "call to EOA returns 0x (not an error)" do
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])
      assert {:ok, "0x"} = RPC.eth_call(@eoa_address, calldata, rpc_opts())
    end
  end

  describe "eth_estimate_gas/2" do
    test "sizes a WETH transfer within a sane range" do
      {:ok, calldata} =
        ABI.encode_call("transfer(address,uint256)", [
          Onchain.Hex.decode!(@eoa_address),
          1
        ])

      assert {:ok, gas} =
               RPC.eth_estimate_gas(
                 %{from: @eoa_address, to: @weth_address, data: calldata},
                 rpc_opts()
               )

      # A plain ERC-20 transfer is ~30k–90k; assert it's a sane, OOG-safe size.
      assert is_integer(gas)
      assert gas in 21_000..120_000
    end

    test "estimates a bare ETH transfer near the 21k floor" do
      assert {:ok, gas} =
               RPC.eth_estimate_gas(%{from: @eoa_address, to: @zero_address}, rpc_opts())

      assert gas >= 21_000
    end
  end

  describe "get_block_by_number/2" do
    test "fetches a known block and returns decoded map" do
      assert {:ok, block} = RPC.get_block_by_number(20_000_000, rpc_opts())
      assert is_map(block)
      assert block.number == 20_000_000
      assert is_integer(block.timestamp)
      assert is_binary(block.hash)
    end

    test "accepts 'latest' tag" do
      assert {:ok, block} = RPC.get_block_by_number("latest", rpc_opts())
      assert is_map(block)
      assert is_integer(block.number)
    end

    test "accepts 'finalized' tag" do
      assert {:ok, block} = RPC.get_block_by_number("finalized", rpc_opts())
      assert is_map(block)
      assert is_integer(block.number)
    end

    test "accepts hex block number" do
      assert {:ok, block} = RPC.get_block_by_number("0x1312d00", rpc_opts())
      assert block.number == 20_000_000
    end
  end

  # --- Bang variant integration tests ---

  describe "block_number!/1" do
    test "returns block number directly" do
      block = RPC.block_number!(rpc_opts())
      assert is_integer(block)
      assert block > 0
    end
  end

  describe "chain_id!/1" do
    test "returns chain ID directly" do
      assert 1 == RPC.chain_id!(rpc_opts())
    end
  end

  describe "get_balance!/2" do
    test "returns balance directly" do
      balance = RPC.get_balance!(@zero_address, rpc_opts())
      assert is_integer(balance)
      assert balance >= 0
    end
  end

  describe "eth_call!/3" do
    test "returns hex result directly" do
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])
      hex = RPC.eth_call!(@weth_address, calldata, rpc_opts())
      assert is_binary(hex)
      assert String.starts_with?(hex, "0x")
    end
  end

  describe "get_block_by_number!/2" do
    test "returns block map directly" do
      block = RPC.get_block_by_number!(20_000_000, rpc_opts())
      assert is_map(block)
      assert block.number == 20_000_000
    end
  end

  describe "get_transaction_count!/2" do
    test "returns nonce directly" do
      nonce = RPC.get_transaction_count!(@eoa_address, rpc_opts())
      assert is_integer(nonce)
      assert nonce > 0
    end
  end

  describe "eth_get_code!/2" do
    test "returns code directly for contract" do
      code = RPC.eth_get_code!(@weth_address, rpc_opts())
      assert is_binary(code)
      assert String.starts_with?(code, "0x")
      assert byte_size(code) > 2
    end
  end

  describe "eth_get_logs!/2" do
    test "returns logs directly for valid filter" do
      logs = RPC.eth_get_logs!(%{from_block: 20_000_000, to_block: 20_000_000}, rpc_opts())
      assert is_list(logs)
    end
  end

  # --- call (generic JSON-RPC passthrough) ---

  # Aave V3 Pool on mainnet — OpenZeppelin TransparentUpgradeableProxy (EIP-1967).
  # USDC's FiatTokenProxy uses the older zeppelinos slot, NOT EIP-1967, so the
  # EIP-1967 implementation slot legitimately reads zero on it.
  @aave_v3_pool_proxy "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2"
  # EIP-1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
  @eip1967_impl_slot "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"

  describe "call/3" do
    test "eth_getStorageAt returns the EIP-1967 implementation slot for a known proxy" do
      assert {:ok, slot_value} =
               RPC.call(
                 "eth_getStorageAt",
                 [@aave_v3_pool_proxy, @eip1967_impl_slot, "latest"],
                 rpc_opts()
               )

      # Storage slots are 32 bytes → 0x + 64 hex chars.
      assert is_binary(slot_value)
      assert String.starts_with?(slot_value, "0x")
      assert byte_size(slot_value) == 66

      # Lower 20 bytes = implementation address; should be non-zero for a live proxy.
      <<"0x", _padding::binary-size(24), addr_hex::binary-size(40)>> = slot_value
      refute addr_hex == String.duplicate("0", 40)
    end

    test "eth_chainId returns raw 0x-hex string (no decoding applied)" do
      # call/3 deliberately does NOT decode — proves the no-decode semantics by
      # comparing against the typed wrapper which DOES decode to integer.
      assert {:ok, "0x1"} = RPC.call("eth_chainId", [], rpc_opts())
      assert {:ok, 1} = RPC.chain_id(rpc_opts())
    end
  end

  describe "call!/3" do
    test "returns raw result directly" do
      assert "0x1" == RPC.call!("eth_chainId", [], rpc_opts())
    end
  end

  describe "pipeline: ABI.encode_call → RPC.eth_call → ABI.decode_response" do
    test "WETH totalSupply roundtrip returns decoded integer > 0" do
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])
      {:ok, hex_result} = RPC.eth_call(@weth_address, calldata, rpc_opts())
      {:ok, [total_supply]} = ABI.decode_response("(uint256)", hex_result)

      assert is_integer(total_supply)
      assert total_supply > 0
    end
  end

  describe "fee_history/2" do
    test "returns deserialized struct with expected shape" do
      block_count = 5
      percentiles = [25, 50, 75]

      assert {:ok, history} =
               RPC.fee_history(block_count,
                 reward_percentiles: percentiles,
                 rpc_url: Onchain.RPCCase.rpc_url!()
               )

      assert %Cartouche.FeeHistory{} = history
      # base_fee_per_gas has block_count + 1 entries (next-block fee at index 0)
      assert length(history.base_fee_per_gas) == block_count + 1
      assert Enum.all?(history.base_fee_per_gas, &(is_integer(&1) and &1 > 0))

      # gas_used_ratio has block_count entries
      assert length(history.gas_used_ratio) == block_count

      # reward is block_count rows × length(percentiles) cols
      assert length(history.reward) == block_count
      assert Enum.all?(history.reward, fn row -> length(row) == length(percentiles) end)

      assert is_integer(history.oldest_block) and history.oldest_block > 0
    end

    test "default reward_percentiles ([50]) returns single-column reward rows" do
      assert {:ok, history} = RPC.fee_history(3, rpc_opts())
      assert Enum.all?(history.reward, &match?([_], &1))
    end

    test "composes with Onchain.Fees.suggest_fees/2 for end-to-end recommendation" do
      assert {:ok, history} =
               RPC.fee_history(20, reward_percentiles: [50], rpc_url: Onchain.RPCCase.rpc_url!())

      assert {:ok, {base, prio, max_fee}} = Onchain.Fees.suggest_fees(history)

      assert is_integer(base) and base > 0
      assert is_integer(prio) and prio >= 0
      assert is_integer(max_fee) and max_fee >= base + prio
    end
  end

  describe "fee_history!/2" do
    test "returns struct directly on success" do
      assert %Cartouche.FeeHistory{} = RPC.fee_history!(3, rpc_opts())
    end
  end

  # --- get_proof (eth_getProof) ---

  describe "get_proof/3" do
    test "returns account proof with empty storage_keys for an EOA" do
      assert {:ok, proof} = RPC.get_proof(@eoa_address, [], rpc_opts())

      assert is_integer(proof.balance) and proof.balance >= 0
      assert is_integer(proof.nonce) and proof.nonce >= 0
      assert is_binary(proof.code_hash) and String.starts_with?(proof.code_hash, "0x")
      assert is_binary(proof.storage_hash) and String.starts_with?(proof.storage_hash, "0x")
      assert match?([_ | _], proof.account_proof)
      assert Enum.all?(proof.account_proof, &(is_binary(&1) and String.starts_with?(&1, "0x")))
      assert proof.storage_proof == []

      # Address comes back EIP-55 checksummed (parse_address/1)
      assert proof.address == @eoa_address
    end

    test "returns storage_proof entry for a known proxy storage slot" do
      assert {:ok, proof} =
               RPC.get_proof(@aave_v3_pool_proxy, [@eip1967_impl_slot], rpc_opts())

      assert match?([_ | _], proof.account_proof)
      assert [%{key: key, value: value, proof: storage_proof_nodes}] = proof.storage_proof
      assert key == @eip1967_impl_slot
      assert is_binary(value) and String.starts_with?(value, "0x")
      assert is_list(storage_proof_nodes)

      # The Aave V3 Pool proxy is live → its EIP-1967 implementation slot is non-zero
      <<"0x", padded_value::binary>> = value
      refute padded_value == String.duplicate("0", String.length(padded_value))
    end
  end

  describe "get_proof!/3" do
    test "returns proof map directly on success" do
      proof = RPC.get_proof!(@eoa_address, [], rpc_opts())
      assert is_map(proof)
      assert is_integer(proof.balance)
      assert is_list(proof.account_proof)
    end
  end

  describe "base_fee/1" do
    test "returns the next block's base fee per gas in wei" do
      assert {:ok, base_fee} = RPC.base_fee(rpc_opts())
      assert is_integer(base_fee)
      assert base_fee > 0
    end

    test "default block is pending, matching Erigon eth_baseFee's next-block semantics" do
      # Read all three in one batch so the comparison is same-instant and cannot be
      # invalidated by a block landing mid-test.
      assert {:ok, [pending, latest]} =
               RPC.batch(
                 [
                   {"eth_getBlockByNumber", ["pending", false]},
                   {"eth_getBlockByNumber", ["latest", false]}
                 ],
                 rpc_opts()
               )

      {:ok, pending_base_fee} = Onchain.Hex.to_integer(pending["baseFeePerGas"])
      {:ok, latest_base_fee} = Onchain.Hex.to_integer(latest["baseFeePerGas"])

      assert {:ok, ^pending_base_fee} = RPC.base_fee(rpc_opts())
      assert {:ok, ^latest_base_fee} = RPC.base_fee(Keyword.put(rpc_opts(), :block, "latest"))

      # The two differ in normal operation; if they were equal the assertion above
      # would not distinguish the default, so pin that the default tracks pending.
      refute pending_base_fee == latest_base_fee
    end

    test "returns the historical base fee for a numeric block" do
      assert {:ok, base_fee} = RPC.base_fee(Keyword.put(rpc_opts(), :block, 20_000_000))
      assert is_integer(base_fee)
      assert base_fee > 0
    end
  end

  describe "base_fee!/1" do
    test "returns the base fee unwrapped" do
      assert is_integer(RPC.base_fee!(rpc_opts()))
    end
  end

  describe "blob_base_fee/1" do
    test "returns the EIP-4844 base fee per blob gas in wei" do
      assert {:ok, blob_base_fee} = RPC.blob_base_fee(rpc_opts())
      assert is_integer(blob_base_fee)
      assert blob_base_fee >= 1
    end
  end

  describe "blob_base_fee!/1" do
    test "returns the blob base fee unwrapped" do
      assert is_integer(RPC.blob_base_fee!(rpc_opts()))
    end
  end
end
