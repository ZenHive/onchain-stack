defmodule Onchain.EVM.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.ABI
  alias Onchain.EVM

  @moduletag :integration

  # USDC on mainnet — stable totalSupply, well-known contract
  @usdc_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

  # WETH on mainnet
  @weth_address "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

  # Uniswap V2 Router02 on mainnet
  @uniswap_v2_router "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"

  @fork_block 20_000_000
  @expected_usdc_total_supply_at_fork 24_251_286_965_837_135

  @override_contract "0x0000000000000000000000000000000000001000"
  @override_caller "0x0000000000000000000000000000000000002000"

  @balance_reader_runtime "0x4760005260206000f3"
  @storage_reader_runtime "0x60005460005260206000f3"
  @create_child_runtime "0x600060006000f060005260206000f3"

  @word_42 "0x000000000000000000000000000000000000000000000000000000000000002a"
  @word_123 "0x000000000000000000000000000000000000000000000000000000000000007b"
  @created_with_nonce_1 "0x0000000000000000000000005bafcc0c93ecd8022925d7fd89da1c6250850e19"
  @created_with_nonce_2 "0x00000000000000000000000056bf3bd655a1adc56e6d1936eadda051ef3cd330"

  defp rpc_opts do
    [rpc_url: Onchain.RPCCase.rpc_url!(), block: @fork_block]
  end

  defp assert_plausible_gas(gas_used) do
    assert is_integer(gas_used)
    assert gas_used > 0
    assert gas_used < 10_000_000
  end

  defp zero_address_bin do
    Onchain.Hex.decode!("0x0000000000000000000000000000000000000000")
  end

  defp usdc_address_bin do
    Onchain.Hex.decode!(@usdc_address)
  end

  defp weth_address_bin do
    Onchain.Hex.decode!(@weth_address)
  end

  describe "simulate_call/3" do
    test "USDC totalSupply at pinned block returns known uint256" do
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])

      assert {:ok, hex_result} = EVM.simulate_call(@usdc_address, calldata, rpc_opts())
      assert {:ok, [total_supply]} = ABI.decode_response("(uint256)", hex_result)
      assert total_supply == @expected_usdc_total_supply_at_fork
    end

    test "WETH name at pinned block returns known string" do
      {:ok, calldata} = ABI.encode_call("name()", [])

      assert {:ok, hex_result} = EVM.simulate_call(@weth_address, calldata, rpc_opts())
      assert {:ok, [name]} = ABI.decode_response("(string)", hex_result)
      assert name == "Wrapped Ether"
    end

    test "fork at specific block returns consistent result" do
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])

      assert {:ok, hex1} = EVM.simulate_call(@usdc_address, calldata, rpc_opts())
      assert {:ok, hex2} = EVM.simulate_call(@usdc_address, calldata, rpc_opts())

      # Same block should give same result
      assert hex1 == hex2
    end

    test "reverted call returns evm_revert with decoded revert reason" do
      {:ok, calldata} =
        ABI.encode_call("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)", [
          1,
          1,
          [usdc_address_bin(), weth_address_bin()],
          zero_address_bin(),
          1
        ])

      assert {:error, {:evm_revert, revert_data}} =
               EVM.simulate_call(
                 @uniswap_v2_router,
                 calldata,
                 rpc_opts() ++ [from: "0x0000000000000000000000000000000000000001"]
               )

      assert String.starts_with?(revert_data, "0x08c379a0")

      assert {:ok, %{error: "Error", args: ["TransferHelper: TRANSFER_FROM_FAILED"]}} =
               ABI.decode_error(revert_data, ["Error(string)"])
    end
  end

  describe "simulate_call/3 with state overrides" do
    test "balance override changes simulated selfbalance" do
      overrides = %{
        @override_contract => %{"code" => @balance_reader_runtime, "balance" => "0x2a"},
        @override_caller => %{"balance" => "0x0", "nonce" => "0"}
      }

      opts = rpc_opts() ++ [from: @override_caller, state_overrides: overrides]

      assert {:ok, @word_42} = EVM.simulate_call(@override_contract, "0x", opts)
    end

    test "storage override changes simulated sload result" do
      overrides = %{
        @override_contract => %{
          "code" => @storage_reader_runtime,
          "storage" => ~s({"0x0":"#{@word_123}"})
        },
        @override_caller => %{"balance" => "0x0", "nonce" => "0"}
      }

      opts = rpc_opts() ++ [from: @override_caller, state_overrides: overrides]

      assert {:ok, @word_123} = EVM.simulate_call(@override_contract, "0x", opts)
    end

    test "nonce override changes simulated create address" do
      nonce_one_overrides = %{
        @override_contract => %{"code" => @create_child_runtime, "balance" => "0x0", "nonce" => "1"},
        @override_caller => %{"balance" => "0x0", "nonce" => "0"}
      }

      nonce_two_overrides = %{
        @override_contract => %{"code" => @create_child_runtime, "balance" => "0x0", "nonce" => "2"},
        @override_caller => %{"balance" => "0x0", "nonce" => "0"}
      }

      opts = rpc_opts() ++ [from: @override_caller]

      assert {:ok, @created_with_nonce_1} =
               EVM.simulate_call(
                 @override_contract,
                 "0x",
                 Keyword.put(opts, :state_overrides, nonce_one_overrides)
               )

      assert {:ok, @created_with_nonce_2} =
               EVM.simulate_call(
                 @override_contract,
                 "0x",
                 Keyword.put(opts, :state_overrides, nonce_two_overrides)
               )
    end
  end

  describe "simulate_transaction/3" do
    test "returns gas_used and success for view call" do
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])

      assert {:ok, result} = EVM.simulate_transaction(@usdc_address, calldata, rpc_opts())
      assert is_map(result)
      assert result.success == true
      assert_plausible_gas(result.gas_used)
      assert is_binary(result.output)
      assert String.starts_with?(result.output, "0x")
      assert is_list(result.logs)
    end

    test "returns success: false for reverting call" do
      {:ok, calldata} =
        ABI.encode_call("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)", [
          1,
          1,
          [usdc_address_bin(), weth_address_bin()],
          zero_address_bin(),
          1
        ])

      assert {:ok, %{success: false} = tx_result} =
               EVM.simulate_transaction(
                 @uniswap_v2_router,
                 calldata,
                 rpc_opts() ++ [from: "0x0000000000000000000000000000000000000001"]
               )

      assert_plausible_gas(tx_result.gas_used)
      assert String.starts_with?(tx_result.output, "0x08c379a0")

      assert {:ok, %{error: "Error", args: ["TransferHelper: TRANSFER_FROM_FAILED"]}} =
               ABI.decode_error(tx_result.output, ["Error(string)"])
    end

    test "simulates from a high-nonce EOA without NonceTooLow (regression)" do
      # revm 41 made TxEnv.nonce a required u64 with default nonce-checking (revm
      # 19 used Option<u64>, None = skip). Without disable_nonce_check, the single-tx
      # simulate paths regressed to NonceTooLow for any sender with tx history —
      # eth_call semantics never validate nonce. Vitalik's address is a real EOA
      # with many txs, so its nonce is well above 0 at the pinned fork block.
      high_nonce_eoa = "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])

      assert {:ok, result} =
               EVM.simulate_transaction(
                 @usdc_address,
                 calldata,
                 rpc_opts() ++ [from: high_nonce_eoa]
               )

      assert result.success == true
      assert_plausible_gas(result.gas_used)
    end
  end

  describe "simulate_batch/2" do
    test "batch multiple calls on shared fork" do
      {:ok, total_supply_data} = ABI.encode_call("totalSupply()", [])
      {:ok, decimals_data} = ABI.encode_call("decimals()", [])

      calls = [
        {@usdc_address, total_supply_data},
        {@usdc_address, decimals_data},
        {@weth_address, total_supply_data}
      ]

      assert {:ok, results} = EVM.simulate_batch(calls, rpc_opts())
      assert length(results) == 3

      # All should succeed
      Enum.each(results, fn result ->
        assert result.success == true
        assert_plausible_gas(result.gas_used)
        assert String.starts_with?(result.output, "0x")
      end)

      # USDC totalSupply should decode to positive integer
      [usdc_supply_result | _] = results
      assert {:ok, [supply]} = ABI.decode_response("(uint256)", usdc_supply_result.output)
      assert supply > 0

      # USDC decimals should be 6
      [_, decimals_result | _] = results
      assert {:ok, [decimals]} = ABI.decode_response("(uint8)", decimals_result.output)
      assert decimals == 6
    end
  end

  describe "simulate_call/3 error taxonomy" do
    test "returns {:error, {:evm_error, _}} for execution validation errors" do
      {:ok, calldata} = ABI.encode_call("decimals()", [])

      assert {:error, {:evm_error, msg}} =
               EVM.simulate_call(@usdc_address, calldata, rpc_opts() ++ [gas_limit: 1])

      assert is_binary(msg)
    end
  end

  describe "simulate_call/3 :timeout_ms" do
    # 192.0.2.1 is in RFC 5737 TEST-NET-1, guaranteed unrouted on the public
    # Internet — TCP packets are black-holed, so the per-request timeout is the
    # only thing that frees us. (Do not use 10.x — that's RFC1918 private space
    # and dev VPNs often have routes into it.)
    @black_hole_rpc "http://192.0.2.1:8545"

    test "returns {:error, {:timeout, _}} when request exceeds timeout_ms" do
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])

      started = System.monotonic_time(:millisecond)

      result =
        EVM.simulate_call(@usdc_address, calldata,
          rpc_url: @black_hole_rpc,
          timeout_ms: 500
        )

      elapsed = System.monotonic_time(:millisecond) - started

      case result do
        {:error, {:timeout, msg}} ->
          assert is_binary(msg)
          # The reqwest timer should fire ~500ms in; allow generous slack.
          assert elapsed < 5_000,
                 "Expected timeout within 5s, took #{elapsed}ms"

        other ->
          flunk("""
          Expected {:error, {:timeout, _}} from black-hole RPC, got: #{inspect(other)}
          Elapsed: #{elapsed}ms
          """)
      end
    end
  end

  describe "simulate_call/3 connect failures" do
    # Port 1 on loopback is reserved (tcpmux) and practically never listening, so
    # the kernel returns an immediate RST — a connection *refusal*, distinct from
    # the black-hole timeout above. This must classify as :fork_error (retryable
    # infra), not :timeout or :evm_error (Task 49).
    @refused_rpc "http://127.0.0.1:1"

    test "returns {:error, {:fork_error, _}} when the connection is refused" do
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])

      # Generous timeout so the refusal — not the timer — is what fires.
      result =
        EVM.simulate_call(@usdc_address, calldata, rpc_url: @refused_rpc, timeout_ms: 5_000)

      case result do
        {:error, {:fork_error, msg}} ->
          assert is_binary(msg)

        other ->
          flunk("Expected {:error, {:fork_error, _}} from refused connection, got: #{inspect(other)}")
      end
    end
  end

  describe "bang variants with integration" do
    test "simulate_call! returns hex directly" do
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])

      result = EVM.simulate_call!(@usdc_address, calldata, rpc_opts())
      assert is_binary(result)
      assert String.starts_with?(result, "0x")
    end

    test "simulate_transaction! returns result map directly" do
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])

      result = EVM.simulate_transaction!(@usdc_address, calldata, rpc_opts())
      assert is_map(result)
      assert result.success == true
    end

    test "simulate_batch! returns list directly" do
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])
      calls = [{@usdc_address, calldata}]

      results = EVM.simulate_batch!(calls, rpc_opts())
      assert is_list(results)
      assert length(results) == 1
    end
  end
end
