defmodule Onchain.RPC.Differential.CartoucheTest do
  use ExUnit.Case, async: false

  alias Cartouche.Filter.Log
  alias Cartouche.RPC

  # Task 65 requested signet as the first oracle. The project has since migrated
  # from signet to cartouche (see CHANGELOG Task 67), so this uses the current
  # in-tree raw RPC client as the zero-infra oracle.
  #
  # The reference sends raw JSON-RPC and independently decodes the response.
  # If a case fails due to an intentional shape change, document that difference
  # near the case instead of weakening the assertion.
  @moduletag :differential

  @enabled_values ~w(1 true TRUE yes YES)
  @rpc_timeout_ms 30_000
  @hex_base 16
  @test_block 20_000_000
  @test_block_hex "0x1312d00"
  @fee_history_block_count 3
  @fee_history_reward_percentiles [25, 50, 75]
  @zero_address "0x0000000000000000000000000000000000000000"
  @vitalik_address "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
  @weth_address "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
  @usdc_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
  @aave_v3_pool_proxy "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2"
  @eip1967_impl_slot "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc"
  @usdc_transfer_topic "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"

  setup_all do
    require_differential_enabled!()
    rpc_url = require_ethereum_api_url!()
    tx_hash = first_transaction_hash!(rpc_url)

    {:ok, rpc_url: rpc_url, tx_hash: tx_hash}
  end

  test "eth_chainId matches the oracle", %{rpc_url: rpc_url} do
    assert {:ok, actual} = RPC.chain_id(onchain_opts(rpc_url))

    expected =
      "eth_chainId"
      |> reference!([], rpc_url)
      |> hex_to_integer()

    assert actual == expected
  end

  test "eth_getBalance matches the oracle for a historical block", %{rpc_url: rpc_url} do
    opts = onchain_opts(rpc_url, block: @test_block)

    assert {:ok, actual} = RPC.get_balance(@zero_address, opts)

    expected =
      "eth_getBalance"
      |> reference!([String.downcase(@zero_address), @test_block_hex], rpc_url)
      |> hex_to_integer()

    assert actual == expected
  end

  test "eth_getTransactionCount matches the oracle for a historical block", %{rpc_url: rpc_url} do
    opts = onchain_opts(rpc_url, block: @test_block)

    assert {:ok, actual} = RPC.get_transaction_count(@vitalik_address, opts)

    expected =
      "eth_getTransactionCount"
      |> reference!([String.downcase(@vitalik_address), @test_block_hex], rpc_url)
      |> hex_to_integer()

    assert actual == expected
  end

  test "eth_getCode matches the oracle for a historical block", %{rpc_url: rpc_url} do
    opts = onchain_opts(rpc_url, block: @test_block)

    assert {:ok, actual} = RPC.eth_get_code(@weth_address, opts)

    expected =
      reference!(
        "eth_getCode",
        [String.downcase(@weth_address), @test_block_hex],
        rpc_url
      )

    assert actual == expected
  end

  test "eth_call map params and block id match the oracle", %{rpc_url: rpc_url} do
    {:ok, calldata} = ABI.encode_hex_call("totalSupply()", [])
    opts = onchain_opts(rpc_url, block: @test_block)

    assert {:ok, actual} = RPC.eth_call(@weth_address, calldata, opts)

    expected =
      reference!(
        "eth_call",
        [%{"to" => String.downcase(@weth_address), "data" => calldata}, @test_block_hex],
        rpc_url
      )

    assert actual == expected
  end

  test "eth_getBlockByNumber integer block matches the oracle", %{rpc_url: rpc_url} do
    assert {:ok, actual} = RPC.get_block_by_number(@test_block, onchain_opts(rpc_url))

    expected =
      "eth_getBlockByNumber"
      |> reference!([@test_block_hex, false], rpc_url)
      |> expected_block()

    assert actual == expected
  end

  test "eth_getBlockByNumber earliest tag matches the oracle", %{rpc_url: rpc_url} do
    assert {:ok, actual} = RPC.get_block_by_number("earliest", onchain_opts(rpc_url))

    expected =
      "eth_getBlockByNumber"
      |> reference!(["earliest", false], rpc_url)
      |> expected_block()

    assert actual == expected
  end

  test "eth_getBlockByNumber finalized tag matches the oracle", %{rpc_url: rpc_url} do
    assert {:ok, actual} = RPC.get_block_by_number("finalized", onchain_opts(rpc_url))

    expected =
      "eth_getBlockByNumber"
      |> reference!(["finalized", false], rpc_url)
      |> expected_block()

    assert actual == expected
  end

  test "eth_getBlockByNumber safe tag matches the oracle", %{rpc_url: rpc_url} do
    assert {:ok, actual} = RPC.get_block_by_number("safe", onchain_opts(rpc_url))

    expected =
      "eth_getBlockByNumber"
      |> reference!(["safe", false], rpc_url)
      |> expected_block()

    assert actual == expected
  end

  test "eth_getLogs filter map construction matches the oracle", %{rpc_url: rpc_url} do
    filter = %{
      address: @usdc_address,
      topics: [@usdc_transfer_topic],
      from_block: @test_block,
      to_block: @test_block
    }

    assert {:ok, actual} =
             RPC.eth_get_logs(filter, ethereum_node: rpc_url, timeout: @rpc_timeout_ms)

    expected =
      "eth_getLogs"
      |> reference!(
        [
          %{
            "address" => String.downcase(@usdc_address),
            "topics" => [@usdc_transfer_topic],
            "fromBlock" => @test_block_hex,
            "toBlock" => @test_block_hex
          }
        ],
        rpc_url
      )
      |> Enum.map(&Log.deserialize/1)

    assert actual == expected
  end

  # Task 2129: this read returns `%Cartouche.Transaction.Info{}`. Full block
  # transactions still use the sparse map from `expected_transaction/1`.
  test "eth_getTransactionByHash decodes to the same envelope as the oracle JSON", %{
    rpc_url: rpc_url,
    tx_hash: tx_hash
  } do
    assert {:ok, actual} =
             RPC.eth_get_transaction_by_hash(tx_hash, ethereum_node: rpc_url, timeout: @rpc_timeout_ms)

    raw = reference!("eth_getTransactionByHash", [tx_hash], rpc_url)
    assert {:ok, ^actual} = Cartouche.Transaction.Info.decode(raw)
  end

  test "eth_getTransactionReceipt sparse fields match the oracle", %{rpc_url: rpc_url, tx_hash: tx_hash} do
    assert {:ok, actual} = RPC.get_transaction_receipt(tx_hash, onchain_opts(rpc_url))

    expected =
      "eth_getTransactionReceipt"
      |> reference!([tx_hash], rpc_url)
      |> expected_receipt()

    assert actual == expected
  end

  test "eth_feeHistory params and deserialization match the oracle", %{rpc_url: rpc_url} do
    opts =
      onchain_opts(rpc_url,
        newest_block: @test_block,
        reward_percentiles: @fee_history_reward_percentiles
      )

    assert {:ok, actual} = RPC.fee_history(@fee_history_block_count, opts)

    expected =
      "eth_feeHistory"
      |> reference!(
        [
          Cartouche.Hex.from_integer(@fee_history_block_count),
          @test_block_hex,
          @fee_history_reward_percentiles
        ],
        rpc_url
      )
      |> Cartouche.FeeHistory.deserialize()

    assert actual == expected
  end

  # Nodes cap eth_getProof to a recent proof window; use "latest" so both sides succeed.
  test "eth_getProof struct fields match the oracle", %{rpc_url: rpc_url} do
    assert {:ok, actual} =
             RPC.eth_get_proof(@aave_v3_pool_proxy, [@eip1967_impl_slot], onchain_opts(rpc_url))

    expected =
      "eth_getProof"
      |> reference!(
        [String.downcase(@aave_v3_pool_proxy), [@eip1967_impl_slot], "latest"],
        rpc_url
      )
      |> expected_proof()

    assert actual == expected
  end

  test "generic call/3 preserves raw oracle results", %{rpc_url: rpc_url} do
    params = [@aave_v3_pool_proxy, @eip1967_impl_slot, @test_block_hex]

    assert {:ok, actual} = RPC.call("eth_getStorageAt", params, onchain_opts(rpc_url))
    assert actual == reference!("eth_getStorageAt", params, rpc_url)
  end

  defp require_differential_enabled! do
    if System.get_env("ONCHAIN_DIFFERENTIAL_TESTS") not in @enabled_values do
      flunk("""
      Differential RPC tests are disabled.

      To run them, set:
        export ONCHAIN_DIFFERENTIAL_TESTS=1
        export ETHEREUM_API_URL="https://your-mainnet-node"

      Then run:
        mix test --include differential test/onchain/differential
      """)
    end
  end

  defp require_ethereum_api_url! do
    case System.get_env("ETHEREUM_API_URL") do
      nil ->
        flunk_missing_ethereum_api_url()

      "" ->
        flunk_missing_ethereum_api_url()

      rpc_url ->
        rpc_url
    end
  end

  defp flunk_missing_ethereum_api_url do
    flunk("""
    Missing Ethereum RPC URL!

    Set:
      export ETHEREUM_API_URL="https://your-mainnet-node"
    """)
  end

  defp first_transaction_hash!(rpc_url) do
    case reference!("eth_getBlockByNumber", [@test_block_hex, false], rpc_url) do
      %{"transactions" => [tx_hash | _]} when is_binary(tx_hash) ->
        tx_hash

      other ->
        flunk("Expected block #{@test_block} to have transaction hashes, got: #{inspect(other)}")
    end
  end

  defp onchain_opts(rpc_url, extra \\ []), do: Keyword.put(extra, :rpc_url, rpc_url)

  defp reference!(method, params, rpc_url) do
    opts = [ethereum_node: rpc_url, timeout: @rpc_timeout_ms]

    case RPC.send_rpc(method, params, opts) do
      {:ok, result} ->
        result

      {:error, error} ->
        flunk("Oracle RPC #{method} failed: #{inspect(error)}")
    end
  end

  defp decode_bytes(nil), do: nil
  defp decode_bytes("0x" <> hex), do: Base.decode16!(hex, case: :mixed)

  defp hex_to_integer(nil), do: nil
  defp hex_to_integer("0x" <> hex), do: String.to_integer(hex, @hex_base)

  defp checksum(nil), do: nil
  defp checksum(address), do: Onchain.Address.checksum!(address)

  defp expected_block(nil), do: nil

  defp expected_block(raw) do
    %Cartouche.Block{
      number: hex_to_integer(raw["number"]),
      hash: decode_bytes(raw["hash"]),
      parent_hash: decode_bytes(raw["parentHash"]),
      sha3_uncles: decode_bytes(raw["sha3Uncles"]),
      logs_bloom: decode_bytes(raw["logsBloom"]),
      transactions_root: decode_bytes(raw["transactionsRoot"]),
      state_root: decode_bytes(raw["stateRoot"]),
      receipts_root: decode_bytes(raw["receiptsRoot"]),
      miner: decode_bytes(raw["miner"]),
      difficulty: hex_to_integer(raw["difficulty"]),
      total_difficulty: hex_to_integer(raw["totalDifficulty"]),
      extra_data: decode_bytes(raw["extraData"]),
      size: hex_to_integer(raw["size"]),
      gas_limit: hex_to_integer(raw["gasLimit"]),
      gas_used: hex_to_integer(raw["gasUsed"]),
      timestamp: hex_to_integer(raw["timestamp"]),
      transactions: Enum.map(raw["transactions"] || [], &expected_block_transaction/1),
      uncles: Enum.map(raw["uncles"] || [], &decode_bytes/1),
      mix_hash: decode_bytes(raw["mixHash"]),
      nonce: hex_to_integer(raw["nonce"]),
      base_fee_per_gas: hex_to_integer(raw["baseFeePerGas"]),
      withdrawals_root: decode_bytes(raw["withdrawalsRoot"]),
      withdrawals: expected_withdrawals(raw["withdrawals"]),
      blob_gas_used: hex_to_integer(raw["blobGasUsed"]),
      excess_blob_gas: hex_to_integer(raw["excessBlobGas"]),
      parent_beacon_block_root: decode_bytes(raw["parentBeaconBlockRoot"]),
      requests_hash: decode_bytes(raw["requestsHash"])
    }
  end

  defp expected_block_transaction(%{} = tx), do: expected_transaction(tx)
  defp expected_block_transaction(tx_hash) when is_binary(tx_hash), do: tx_hash

  defp expected_withdrawals(nil), do: nil

  defp expected_withdrawals(withdrawals) when is_list(withdrawals) do
    Enum.map(withdrawals, fn withdrawal ->
      %Cartouche.Block.Withdrawal{
        index: hex_to_integer(withdrawal["index"]),
        validator_index: hex_to_integer(withdrawal["validatorIndex"]),
        address: decode_bytes(withdrawal["address"]),
        amount: hex_to_integer(withdrawal["amount"])
      }
    end)
  end

  defp expected_withdrawals(_other), do: nil

  defp expected_transaction(tx) do
    %{
      hash: tx["hash"],
      nonce: hex_to_integer(tx["nonce"]),
      block_hash: tx["blockHash"],
      block_number: hex_to_integer(tx["blockNumber"]),
      transaction_index: hex_to_integer(tx["transactionIndex"]),
      from: checksum(tx["from"]),
      to: checksum(tx["to"]),
      value: hex_to_integer(tx["value"]),
      gas: hex_to_integer(tx["gas"]),
      gas_price: hex_to_integer(tx["gasPrice"]),
      max_fee_per_gas: hex_to_integer(tx["maxFeePerGas"]),
      max_priority_fee_per_gas: hex_to_integer(tx["maxPriorityFeePerGas"]),
      input: tx["input"],
      type: hex_to_integer(tx["type"]),
      chain_id: hex_to_integer(tx["chainId"])
    }
  end

  defp expected_receipt(nil), do: nil

  defp expected_receipt(receipt) do
    %Cartouche.Receipt{
      transaction_hash: decode_bytes(receipt["transactionHash"]),
      transaction_index: hex_to_integer(receipt["transactionIndex"]),
      block_hash: decode_bytes(receipt["blockHash"]),
      block_number: hex_to_integer(receipt["blockNumber"]),
      from: decode_bytes(receipt["from"]),
      to: decode_bytes(receipt["to"]),
      cumulative_gas_used: hex_to_integer(receipt["cumulativeGasUsed"]),
      gas_used: hex_to_integer(receipt["gasUsed"]),
      effective_gas_price: hex_to_integer(receipt["effectiveGasPrice"]),
      status: hex_to_integer(receipt["status"]),
      contract_address: decode_bytes(receipt["contractAddress"]),
      logs: Enum.map(receipt["logs"] || [], &expected_log/1),
      type: hex_to_integer(receipt["type"]),
      logs_bloom: decode_bytes(receipt["logsBloom"]),
      blob_gas_used: hex_to_integer(receipt["blobGasUsed"]),
      blob_gas_price: hex_to_integer(receipt["blobGasPrice"])
    }
  end

  defp expected_log(log) do
    %Log{
      address: decode_bytes(log["address"]),
      topics: Enum.map(log["topics"] || [], &decode_bytes/1),
      data: decode_bytes(log["data"]),
      block_number: hex_to_integer(log["blockNumber"]),
      transaction_hash: decode_bytes(log["transactionHash"]),
      log_index: hex_to_integer(log["logIndex"]),
      transaction_index: hex_to_integer(log["transactionIndex"]),
      block_hash: decode_bytes(log["blockHash"]),
      removed: log["removed"]
    }
  end

  defp expected_proof(proof) do
    %Cartouche.RPC.Proof{
      address: Cartouche.Hex.decode!(proof["address"]),
      balance: hex_to_integer(proof["balance"]),
      nonce: hex_to_integer(proof["nonce"]),
      code_hash: Cartouche.Hex.decode!(proof["codeHash"]),
      storage_hash: Cartouche.Hex.decode!(proof["storageHash"]),
      account_proof: Enum.map(proof["accountProof"], &Cartouche.Hex.decode!/1),
      storage_proof: Enum.map(proof["storageProof"], &expected_storage_proof_entry/1)
    }
  end

  defp expected_storage_proof_entry(entry) do
    %Cartouche.RPC.Proof.StorageProof{
      key: hex_to_integer(entry["key"]),
      value: hex_to_integer(entry["value"]),
      proof: Enum.map(entry["proof"], &Cartouche.Hex.decode!/1)
    }
  end
end
