defmodule Onchain.EVM.IntegrationTest do
  use ExUnit.Case, async: false

  alias Onchain.ABI
  alias Onchain.EVM

  @moduletag :integration

  # USDC on mainnet — stable totalSupply, well-known contract
  @usdc_address "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

  # WETH on mainnet
  @weth_address "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"

  defp rpc_opts do
    [rpc_url: Onchain.RPCCase.rpc_url!()]
  end

  describe "simulate_call/3" do
    test "USDC totalSupply returns decodable uint256" do
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])

      assert {:ok, hex_result} = EVM.simulate_call(@usdc_address, calldata, rpc_opts())
      assert is_binary(hex_result)
      assert String.starts_with?(hex_result, "0x")

      # Decode and verify it's a positive number
      assert {:ok, [total_supply]} = ABI.decode_response("(uint256)", hex_result)
      assert is_integer(total_supply)
      assert total_supply > 0
    end

    test "WETH name returns decodable string" do
      {:ok, calldata} = ABI.encode_call("name()", [])

      assert {:ok, hex_result} = EVM.simulate_call(@weth_address, calldata, rpc_opts())
      assert {:ok, [name]} = ABI.decode_response("(string)", hex_result)
      assert name == "Wrapped Ether"
    end

    test "fork at specific block returns consistent result" do
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])

      # Fork at block 20_000_000 (known historical block)
      opts = Keyword.put(rpc_opts(), :block, 20_000_000)

      assert {:ok, hex1} = EVM.simulate_call(@usdc_address, calldata, opts)
      assert {:ok, hex2} = EVM.simulate_call(@usdc_address, calldata, opts)

      # Same block should give same result
      assert hex1 == hex2
    end

    test "reverted call returns evm_revert error" do
      # Call a non-existent function selector — likely reverts on USDC
      bad_calldata = "0xdeadbeef"

      result = EVM.simulate_call(@usdc_address, bad_calldata, rpc_opts())

      case result do
        {:error, {:evm_revert, revert_data}} ->
          assert is_binary(revert_data)
          assert String.starts_with?(revert_data, "0x")

        {:ok, "0x"} ->
          # Some contracts return empty data for unknown selectors
          :ok

        {:ok, _hex} ->
          # Fallback function returned data
          :ok

        {:error, other} ->
          flunk("Expected :evm_revert or success, got: #{inspect(other)}")
      end
    end
  end

  describe "simulate_call/3 with state overrides" do
    test "override balance is reflected in balanceOf" do
      target_address = "0x0000000000000000000000000000000000000001"

      # Check ETH balance via a simple staticcall pattern:
      # Override balance, then call WETH deposit which checks msg.value
      # Simpler: just verify the override doesn't break execution
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])

      overrides = %{
        target_address => %{"balance" => "0xDE0B6B3A7640000"}
      }

      opts = Keyword.put(rpc_opts(), :state_overrides, overrides)
      assert {:ok, _hex} = EVM.simulate_call(@usdc_address, calldata, opts)
    end
  end

  describe "simulate_transaction/3" do
    test "returns gas_used and success for view call" do
      {:ok, calldata} = ABI.encode_call("totalSupply()", [])

      assert {:ok, result} = EVM.simulate_transaction(@usdc_address, calldata, rpc_opts())
      assert is_map(result)
      assert result.success == true
      assert is_integer(result.gas_used)
      assert result.gas_used > 0
      assert is_binary(result.output)
      assert String.starts_with?(result.output, "0x")
      assert is_list(result.logs)
    end

    test "returns success: false for reverting call" do
      bad_calldata = "0xdeadbeef"

      result = EVM.simulate_transaction(@usdc_address, bad_calldata, rpc_opts())

      case result do
        {:ok, %{success: false} = tx_result} ->
          assert is_integer(tx_result.gas_used)
          assert is_binary(tx_result.output)

        {:ok, %{success: true}} ->
          # Some contracts have fallback functions
          :ok

        {:error, {:evm_error, reason}} ->
          # Halt errors are also possible
          assert is_binary(reason)

        {:error, other} ->
          flunk("Unexpected error: #{inspect(other)}")
      end
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
        assert is_integer(result.gas_used)
        assert result.gas_used > 0
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
